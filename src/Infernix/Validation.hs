{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

-- | Source-bound execution accounting. The checkout mount is provided by the
-- launcher independently of the image. Local integrity is not independent
-- attestation against someone controlling both executor and evidence storage.
module Infernix.Validation
  ( ValidationScope (..),
    RequiredCheck (..),
    CheckOutcome (..),
    VerificationContext (..),
    SuiteContext (..),
    selectSuiteContext,
    validateSuiteContext,
    validateHarnessLane,
    requiredChecks,
    validateCheckOutcomes,
    sourceInventoryDigest,
    verifyValidationReceipt,
    verifyStoredReceipt,
    parseValidationScope,
    withValidation,
    withValidationOutcome,
    withFocusedValidation,
    withNvidiaValidation,
    renderImageBuildIdentity,
    beginNativeBuild,
    finishNativeBuild,
    requireNvidiaValidationContext,
  )
where

import Control.Exception (IOException, SomeException, bracket, displayException, evaluate, mask, throwIO, try)
import Control.Monad (unless, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson (FromJSON, ToJSON, eitherDecode, encode, object, withObject, (.:), (.=))
import Data.Aeson.Types (parseEither)
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as Bytes
import Data.ByteString.Lazy qualified as Lazy
import Data.Char (isHexDigit)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.List (isPrefixOf, sort)
import Data.Text qualified as Text
import GHC.Clock (getMonotonicTimeNSec)
import GHC.Generics (Generic)
import GHC.IO.Handle (hDuplicate, hDuplicateTo)
import Infernix.Cluster.Command qualified as Command
import Infernix.Cluster.ImageFingerprint (retainSourceSnapshot, sourceSnapshot)
import Infernix.Cluster.Invoke qualified as Invoke
import Infernix.Config (ControlPlaneContext (..), Paths (..), controlPlaneContext, discoverPaths, runtimeConfigPath, targetRuntimeModeForExecutionContext, testConfigPath)
import Infernix.DemoConfig.Internal (decodeDemoConfigFile)
import Infernix.Error (finallyPreservingPrimary)
import Infernix.Types (DemoConfig (configRuntimeMode), RuntimeMode (..), runtimeModeId)
import System.Directory (copyFile, createDirectoryIfMissing, doesDirectoryExist, doesFileExist, doesPathExist, getCurrentDirectory, removeFile)
import System.Environment (getExecutablePath)
import System.FilePath (isAbsolute, normalise, splitDirectories, takeFileName, (</>))
import System.IO (IOMode (WriteMode), hClose, hFlush, stderr, stdout, withFile)
import System.Info (arch, os)
import System.Posix.Temp (mkdtemp)

data ValidationScope = LintScope | UnitScope | AllScope | GpuUnitScope | GpuAllScope | NvidiaScope | FocusedScope RequiredCheck
  deriving (Eq, Show, Generic)

instance ToJSON ValidationScope

instance FromJSON ValidationScope

parseValidationScope :: String -> Maybe ValidationScope
parseValidationScope name =
  lookup
    name
    [ ("lint", LintScope),
      ("unit", UnitScope),
      ("all", AllScope),
      ("nvidia", NvidiaScope),
      ("files", FocusedScope FilesLint),
      ("docs", FocusedScope DocsLint),
      ("chart", FocusedScope ChartLint),
      ("proto", FocusedScope ProtoLint),
      ("plan", FocusedScope PlanLint),
      ("integration", FocusedScope Integration),
      ("browser", FocusedScope Browser)
    ]

data RequiredCheck
  = HaskellStyle
  | CabalFormat
  | FilesLint
  | ChartLint
  | ProtoLint
  | DocsLint
  | PlanLint
  | PythonQuality
  | BuildAll
  | CompileFail
  | ArtifactTransaction
  | AppleMaterializer
  | CappedEngineObserver
  | ExecutionPlanInternal
  | HaskellUnit
  | WebUnit
  | Integration
  | Browser
  | NvidiaValidation
  | NvidiaWatchdogCheck
  | NvidiaCeilingBreachCheck
  | NvidiaCompetingTenantCheck
  | NvidiaHostCeilingCheck
  deriving (Eq, Ord, Show, Generic)

instance ToJSON RequiredCheck

instance FromJSON RequiredCheck

data CheckOutcome = ExecutedPass | ExecutedFailure String | Skipped String | NotApplicable String
  deriving (Eq, Show, Generic)

instance ToJSON CheckOutcome

instance FromJSON CheckOutcome

-- | These expectations come from the launcher and initialized inputs, not
-- from the receipt being checked.
data VerificationContext = VerificationContext
  { verificationBinary :: String,
    verificationImage :: Maybe String,
    verificationCommit :: String,
    verificationCheckout :: FilePath,
    verificationArchitecture :: String,
    verificationOperatingSystem :: String,
    verificationLane :: String,
    verificationConfiguration :: [(FilePath, String)]
  }
  deriving (Eq, Show)

requiredChecks :: ValidationScope -> [RequiredCheck]
requiredChecks scope =
  case scope of
    LintScope -> [HaskellStyle, CabalFormat, FilesLint, ChartLint, ProtoLint, DocsLint, PlanLint, PythonQuality, BuildAll]
    UnitScope -> [CompileFail, ArtifactTransaction, AppleMaterializer, CappedEngineObserver, ExecutionPlanInternal, HaskellUnit, WebUnit]
    AllScope -> requiredChecks LintScope <> requiredChecks UnitScope <> [Integration, Browser]
    GpuUnitScope -> requiredChecks UnitScope <> [NvidiaValidation]
    GpuAllScope -> requiredChecks AllScope <> [NvidiaValidation]
    NvidiaScope -> [NvidiaWatchdogCheck, NvidiaCeilingBreachCheck, NvidiaCompetingTenantCheck, NvidiaHostCeilingCheck]
    FocusedScope check -> [check]

withFocusedValidation :: RequiredCheck -> IO () -> IO ()
withFocusedValidation required action = withValidation (FocusedScope required) (\check -> check required action)

data SuiteContext = MachineIndependentContext | NvidiaDeviceContext
  deriving (Eq, Show)

selectSuiteContext :: RuntimeMode -> SuiteContext
selectSuiteContext LinuxGpu = NvidiaDeviceContext
selectSuiteContext _ = MachineIndependentContext

validateSuiteContext :: SuiteContext -> Bool -> Either String ()
validateSuiteContext NvidiaDeviceContext False = Left "NVIDIA validation requires an explicitly device-capable context; the device is unavailable"
validateSuiteContext _ _ = Right ()

-- | A harness cannot change lanes after the mandatory inventory is selected.
validateHarnessLane :: RuntimeMode -> RuntimeMode -> Either String ()
validateHarnessLane active harness
  | active == harness = Right ()
  | otherwise =
      Left
        ( "validation runtime and test configurations select different lanes: runtime="
            <> Text.unpack (runtimeModeId active)
            <> ", test="
            <> Text.unpack (runtimeModeId harness)
        )

requireNvidiaValidationContext :: IO ()
requireNvidiaValidationContext = do
  paths <- discoverPaths
  lane <- targetRuntimeModeForExecutionContext paths
  unless (lane == LinuxGpu && os == "linux") $
    ioError (userError "NVIDIA validation requires the native linux-gpu lane")
  device <- doesFileExist "/dev/nvidiactl"
  sampler <- doesFileExist "/usr/bin/nvidia-smi"
  either (ioError . userError) pure (validateSuiteContext NvidiaDeviceContext (device && sampler))

-- | The ordinary launcher owns selection, but only this separate container
-- receives devices. Its image and mount sources are observed from the running
-- outer container, never resolved through a mutable tag or inherited setting.
runDeviceValidationContext :: FilePath -> (RequiredCheck -> IO () -> IO ()) -> IO ()
runDeviceValidationContext receiptRoot check = do
  paths <- discoverPaths
  lane <- targetRuntimeModeForExecutionContext paths
  when (selectSuiteContext lane == NvidiaDeviceContext) $
    check NvidiaValidation $ do
      (identity, checkout) <- observeImageIdentity paths
      image <- maybe (ioError (userError "NVIDIA validation requires an immutable outer image")) pure identity
      container <- filter (`notElem` ['\n', '\r']) <$> readFile "/etc/hostname"
      mountResult <- Invoke.tryClusterCommand paths (Command.dockerInspectContainerField (Command.ContainerName container) (Command.MountSourceAt "/workspace/.data"))
      dataMount <- filter (`notElem` ['\n', '\r']) <$> either (ioError . userError) pure mountResult
      createDirectoryIfMissing True (runtimeRoot paths </> "validation")
      reservation <- mkdtemp (runtimeRoot paths </> "validation" </> "device-")
      let name = Command.ContainerName ("infernix-validation-" <> takeFileName reservation)
          invoke command = Invoke.tryClusterCommand paths command >>= either (ioError . userError) putStr
      invoke (Command.dockerRunNvidiaValidation name (Command.ImageRef image) checkout dataMount (receiptRoot </> "NvidiaValidation" </> "device"))
        `finallyPreservingPrimary` invoke (Command.dockerRemoveValidationContainer name)

-- | These scopes contain only mandatory gates. Device-specific not-applicable
-- assertions belong to their own typed inventory, never to a mandatory suite.
validateCheckOutcomes :: ValidationScope -> [(RequiredCheck, CheckOutcome)] -> Either String ()
validateCheckOutcomes scope outcomes
  | sort (map fst outcomes) /= sort (requiredChecks scope) =
      Left "required-check inventory mismatch: absent, duplicated, or unexpected check"
  | any ((/= ExecutedPass) . snd) outcomes =
      Left "mandatory check did not execute successfully"
  | otherwise = Right ()

withValidation :: ValidationScope -> ((RequiredCheck -> IO () -> IO ()) -> IO ()) -> IO ()
withValidation = withValidationDestination Nothing

withNvidiaValidation :: FilePath -> ((RequiredCheck -> IO () -> IO ()) -> IO ()) -> IO ()
withNvidiaValidation destination = withValidationDestination (Just destination) NvidiaScope

withValidationDestination :: Maybe FilePath -> ValidationScope -> ((RequiredCheck -> IO () -> IO ()) -> IO ()) -> IO ()
withValidationDestination destination requestedScope action = do
  paths <- discoverPaths
  lane <- validationLane paths requestedScope
  let scope = case (lane, requestedScope) of
        (Just LinuxGpu, UnitScope) -> GpuUnitScope
        (Just LinuxGpu, AllScope) -> GpuAllScope
        _ -> requestedScope
      expectedRoot =
        case controlPlaneContext paths of
          HostNative -> repoRoot paths
          OuterContainer -> "/opt/infernix/checkout"
  when (scope `elem` [GpuUnitScope, GpuAllScope, NvidiaScope] && lane /= Just LinuxGpu) $
    ioError (userError "GPU validation scope requires the linux-gpu lane")
  when (scope == NvidiaScope) requireNvidiaValidationContext
  checkoutPresent <- doesDirectoryExist expectedRoot
  unless checkoutPresent $
    ioError (userError "validation expected checkout is unavailable; use the supported bootstrap launcher with its read-only checkout handoff")
  expected <- sourceSnapshot expectedRoot
  actual <- sourceSnapshot (repoRoot paths)
  unless (expected == actual) $
    ioError (userError "validation source mismatch between requested checkout and executable image; rebuild the launcher")
  (verification, executable) <- observeVerificationContext paths lane scope expectedRoot expected
  let binaryDigest = verificationBinary verification
      imageIdentity = verificationImage verification
      checkoutIdentity = verificationCheckout verification
      commit = verificationCommit verification
  createDirectoryIfMissing True (runtimeRoot paths </> "validation")
  receiptRoot <- createReceiptRoot paths destination
  retained <- retainSourceSnapshot expectedRoot (receiptRoot </> "source")
  unless (retained == expected) $
    ioError (userError "validation source changed before execution")
  configuration <- retainConfiguration paths scope receiptRoot
  unless (configuration == verificationConfiguration verification) $
    ioError (userError "validation configuration changed while retaining its input")
  outcomesRef <- newIORef []
  artifactsRef <- newIORef []
  let runCheck check operation = do
        previous <- readIORef outcomesRef
        unless (check `elem` requiredChecks scope && check `notElem` map fst previous) $
          ioError (userError ("unexpected or duplicated required check: " <> show check))
        currentLane <- validationLane paths scope
        unless (currentLane == lane) $
          ioError (userError "validation lane changed after the required checks were selected")
        checkConfiguration <- retainConfiguration paths scope (receiptRoot </> show check)
        putStrLn ("validation executing " <> show check <> "; logs: " <> receiptRoot </> show check)
        started <- getMonotonicTimeNSec
        outcome <- try @SomeException (retainCheckLogs (receiptRoot </> show check) operation)
        finished <- getMonotonicTimeNSec
        logs <- mapM (\name -> (,) name <$> fileDigest (receiptRoot </> show check </> name)) ["stdout.log", "stderr.log"]
        let childPath = receiptRoot </> show check </> "device" </> "receipt.json"
        childPresent <- if check == NvidiaValidation then doesFileExist childPath else pure False
        childDigest <- if childPresent then Just <$> fileDigest childPath else pure Nothing
        let result = either (ExecutedFailure . displayException) (const ExecutedPass) outcome
        Lazy.writeFile
          (receiptRoot </> show check <> ".json")
          (encode (object ["check" .= check, "outcome" .= result, "configuration" .= checkConfiguration, "logs" .= logs, "childReceiptDigest" .= childDigest, "durationNanoseconds" .= (finished - started)]))
        modifyIORef' outcomesRef (<> [(check, result)])
        digest <- fileDigest (receiptRoot </> show check <> ".json")
        modifyIORef' artifactsRef (<> [(show check <> ".json", digest)])
        putStrLn ("validation " <> show check <> ": " <> show result)
        either throwIO pure outcome
      finish actionOutcome = do
        outcomes <- readIORef outcomesRef
        postExpected <- sourceSnapshot expectedRoot
        postActual <- sourceSnapshot (repoRoot paths)
        postRetained <- sourceSnapshot (receiptRoot </> "source")
        postBinary <- fileDigest executable
        postConfigurationPaths <- configurationPaths paths scope
        postConfiguration <- mapM (\path -> (,) (takeFileName path) <$> fileDigest path) postConfigurationPaths
        artifacts <- readIORef artifactsRef
        artifactChecks <- mapM (artifactMatches receiptRoot) artifacts
        configurationChecks <- mapM (artifactMatches (receiptRoot </> "configuration")) configuration
        let stable = expected == postExpected && actual == postActual && retained == postRetained && binaryDigest == postBinary && configuration == postConfiguration && and artifactChecks && and configurationChecks
            gate = validateCheckOutcomes scope outcomes
            writeReceipt succeeded =
              Lazy.writeFile
                (receiptRoot </> "receipt.json")
                ( encode
                    ( object
                        [ "version" .= (1 :: Int),
                          "digestAlgorithm" .= ("sha256-path-type-mode-payload-v1" :: String),
                          "scope" .= scope,
                          "coverageBoundary" .= ("suite terminal outcomes; fixture-level execution requires separate evidence" :: String),
                          "sourceInventory" .= expected,
                          "sourceDigest" .= sourceInventoryDigest expected,
                          "sourceDigestAlgorithm" .= ("sha256-aeson-source-inventory-v1" :: String),
                          "commit" .= filter (`notElem` ['\n', '\r']) commit,
                          "sourceStable" .= stable,
                          "binaryDigest" .= binaryDigest,
                          "imageIdentity" .= imageIdentity,
                          "checkoutIdentity" .= checkoutIdentity,
                          "architecture" .= arch,
                          "operatingSystem" .= os,
                          "lane" .= validationLaneId lane,
                          "deviceContext" .= show (maybe MachineIndependentContext selectSuiteContext lane),
                          "configuration" .= configuration,
                          "requiredChecks" .= requiredChecks scope,
                          "outcomes" .= outcomes,
                          "artifacts" .= artifacts,
                          "actionOutcome" .= actionOutcome,
                          "passed" .= succeeded
                        ]
                    )
                )
        writeReceipt False
        putStrLn ("validation receipt: " <> receiptRoot </> "receipt.json")
        unless stable $ ioError (userError "validation source, executable, or configuration changed during execution")
        when (actionOutcome == ExecutedPass) $ do
          either (ioError . userError) pure gate
          verifyReceiptCandidate False scope verification expected receiptRoot
          writeReceipt True
  withValidationOutcome (action runCheck >> when (NvidiaValidation `elem` requiredChecks scope) (runDeviceValidationContext receiptRoot runCheck)) finish

createReceiptRoot :: Paths -> Maybe FilePath -> IO FilePath
createReceiptRoot paths destination =
  case destination of
    Nothing -> mkdtemp (runtimeRoot paths </> "validation" </> "run-")
    Just target -> do
      unless ((normalise (runtimeRoot paths </> "validation") <> "/") `isPrefixOf` normalise target && isAbsolute target && ".." `notElem` splitDirectories target) $
        ioError (userError "device receipt must remain inside the shared validation root")
      exists <- doesPathExist target
      when exists $ ioError (userError "device receipt destination already exists")
      createDirectoryIfMissing True target
      pure target

-- | Finalization consumes the enclosing execution's outcome, including a
-- failure after the last check. A secondary finalization failure preserves
-- the original exception.
withValidationOutcome :: IO () -> (CheckOutcome -> IO ()) -> IO ()
withValidationOutcome action finish =
  mask $ \restore -> do
    terminal <- try @SomeException (restore action)
    case terminal of
      Right () -> finish ExecutedPass
      Left failure -> throwIO failure `finallyPreservingPrimary` finish (ExecutedFailure (displayException failure))

sourceInventoryDigest :: [(FilePath, String, Int, String)] -> String
sourceInventoryDigest = Bytes.unpack . Base16.encode . SHA256.hashlazy . encode

observeVerificationContext :: Paths -> Maybe RuntimeMode -> ValidationScope -> FilePath -> [(FilePath, String, Int, String)] -> IO (VerificationContext, FilePath)
observeVerificationContext paths lane scope expectedRoot expected = do
  (imageIdentity, checkoutIdentity) <- observeImageIdentity paths
  commitResult <- Invoke.tryClusterCommand paths (Command.gitCheckoutCommit expectedRoot)
  commit <- filter (`notElem` ['\n', '\r']) <$> either (ioError . userError) pure commitResult
  executable <- getExecutablePath
  binary <- fileDigest executable
  case controlPlaneContext paths of
    HostNative -> requireBuildIdentity (repoRoot paths </> ".build" </> "native-build-identity.json") expected binary
    OuterContainer -> requireBuildIdentity "/opt/infernix/build-identity.json" expected binary
  files <- configurationPaths paths scope
  configuration <- mapM (\path -> (,) (takeFileName path) <$> fileDigest path) files
  pure (VerificationContext binary imageIdentity commit checkoutIdentity arch os (validationLaneId lane) configuration, executable)

verifyStoredReceipt :: ValidationScope -> FilePath -> IO ()
verifyStoredReceipt requestedScope receiptRoot = do
  paths <- discoverPaths
  lane <- validationLane paths requestedScope
  let expectedRoot = case controlPlaneContext paths of
        HostNative -> repoRoot paths
        OuterContainer -> "/opt/infernix/checkout"
      scope = case (lane, requestedScope) of
        (Just LinuxGpu, UnitScope) -> GpuUnitScope
        (Just LinuxGpu, AllScope) -> GpuAllScope
        _ -> requestedScope
  when (scope `elem` [GpuUnitScope, GpuAllScope, NvidiaScope] && lane /= Just LinuxGpu) $
    ioError (userError "GPU receipt verification requires the linux-gpu lane")
  expected <- sourceSnapshot expectedRoot
  actual <- sourceSnapshot (repoRoot paths)
  unless (expected == actual) $
    ioError (userError "receipt verification source differs from the requested checkout")
  (verification, _) <- observeVerificationContext paths lane scope expectedRoot expected
  verifyValidationReceipt scope verification expected receiptRoot
  putStrLn ("verified retained validation receipt: " <> receiptRoot </> "receipt.json")

-- | The same handles inherited by Cabal and its children are retained for
-- this check. Bracketed restoration covers failures and cancellation, and
-- digesting happens only after both log handles have closed.
retainCheckLogs :: FilePath -> IO a -> IO a
retainCheckLogs root operation =
  withFile (root </> "stdout.log") WriteMode $ \out ->
    withFile (root </> "stderr.log") WriteMode $ \err ->
      redirect stdout out (redirect stderr err operation)
  where
    redirect target logHandle action =
      bracket
        (hFlush target >> hDuplicate target)
        (\saved -> (hFlush target >> hDuplicateTo saved target) `finallyPreservingPrimary` hClose saved)
        (\_ -> hDuplicateTo logHandle target >> action)

fileDigest :: FilePath -> IO String
fileDigest path = do
  contents <- Lazy.readFile path
  let digest = Bytes.unpack (Base16.encode (SHA256.hashlazy contents))
  _ <- evaluate (length digest)
  pure digest

artifactMatches :: FilePath -> (FilePath, String) -> IO Bool
artifactMatches root (name, digest) = do
  result <- try @IOException (fileDigest (root </> name))
  pure (either (const False) (== digest) result)

observeImageIdentity :: Paths -> IO (Maybe String, FilePath)
observeImageIdentity paths =
  case controlPlaneContext paths of
    HostNative -> pure (Nothing, repoRoot paths)
    OuterContainer -> do
      container <- filter (`notElem` ['\n', '\r']) <$> readFile "/etc/hostname"
      result <- Invoke.tryClusterCommand paths (Command.dockerInspectContainerField (Command.ContainerName container) Command.ContainerImageIdentity)
      identity <- either (ioError . userError) pure result
      let trimmed = filter (`notElem` ['\n', '\r']) identity
      unless ("sha256:" `isPrefixOf` trimmed && length trimmed == 71 && all isHexDigit (drop 7 trimmed)) $
        ioError (userError "validation cannot observe the immutable executing image identity")
      mountResult <- Invoke.tryClusterCommand paths (Command.dockerInspectContainerField (Command.ContainerName container) (Command.ReadOnlyMountSourceAt "/opt/infernix/checkout"))
      mount <- either (ioError . userError) pure mountResult
      let checkout = filter (`notElem` ['\n', '\r']) mount
      unless (isAbsolute checkout && checkout /= "/workspace" && checkout /= "/") $
        ioError (userError "validation requires an independently mounted read-only host checkout")
      pure (Just trimmed, checkout)

-- | Invoked only after the bounded seed compiler has installed the image's
-- executable. The Docker build binds this record to its immutable image id.
renderImageBuildIdentity :: IO Lazy.ByteString
renderImageBuildIdentity = do
  unless (os == "linux") $ ioError (userError "image build identity requires native Linux execution")
  source <- sourceSnapshot "/workspace"
  executable <- getExecutablePath
  binary <- fileDigest executable
  pure (encode (object ["version" .= (1 :: Int), "source" .= source, "binary" .= binary]))

-- | Stage zero first creates a seed executable, then this executable retains
-- the input to a forced, bounded rebuild. The final executable checks that
-- preimage before binding itself to it. Neither command grants build authority.
beginNativeBuild :: IO ()
beginNativeBuild = do
  unless (os == "darwin" && arch == "aarch64") $
    ioError (userError "native build handoff requires Apple Silicon")
  root <- getCurrentDirectory
  let identity = root </> ".build" </> "native-build-identity.json"
  exists <- doesFileExist identity
  when exists (removeFile identity)
  source <- sourceSnapshot root
  Lazy.writeFile (root </> ".build" </> "native-build-start.json") (encode source)

finishNativeBuild :: IO ()
finishNativeBuild = do
  unless (os == "darwin" && arch == "aarch64") $
    ioError (userError "native build handoff requires Apple Silicon")
  root <- getCurrentDirectory
  payload <- Lazy.readFile (root </> ".build" </> "native-build-start.json")
  source <- either (ioError . userError) pure (eitherDecode payload)
  actual <- sourceSnapshot root
  unless (source == actual) $
    ioError (userError "native build source changed during compilation; rebuild the launcher")
  executable <- getExecutablePath
  binary <- fileDigest executable
  Lazy.writeFile (root </> ".build" </> "native-build-identity.json") (encode (object ["version" .= (1 :: Int), "source" .= source, "binary" .= binary]))
  removeFile (root </> ".build" </> "native-build-start.json")

requireBuildIdentity :: FilePath -> [(FilePath, String, Int, String)] -> String -> IO ()
requireBuildIdentity identityPath expected binary = do
  payload <- Lazy.readFile identityPath
  value <- either (ioError . userError) pure (eitherDecode payload)
  (version, builtSource, builtBinary) <-
    either (ioError . userError) pure $
      parseEither
        (withObject "image build identity" $ \record -> (,,) <$> record .: "version" <*> record .: "source" <*> record .: "binary")
        value
  unless ((version :: Int) == 1 && builtSource == expected && builtBinary == binary) $
    ioError (userError "validation source or executable differs from the build identity; rebuild through the supported bootstrap")

retainConfiguration :: Paths -> ValidationScope -> FilePath -> IO [(FilePath, String)]
retainConfiguration paths scope receiptRoot = do
  files <- configurationPaths paths scope
  let targetRoot = receiptRoot </> "configuration"
  createDirectoryIfMissing True targetRoot
  mapM (retain targetRoot) files
  where
    retain targetRoot path = do
      exists <- doesFileExist path
      unless exists $ ioError (userError ("validation configuration is missing: " <> path))
      let target = targetRoot </> takeFileName path
      copyFile path target
      digest <- fileDigest target
      pure (takeFileName path, digest)

configurationPaths :: Paths -> ValidationScope -> IO [FilePath]
configurationPaths paths scope = do
  testPresent <- if runtimeConfigurationRequired scope then doesFileExist (testConfigPath paths) else pure False
  let runtimeFiles = [runtimeConfigPath paths | runtimeConfigurationRequired scope] <> [testConfigPath paths | testPresent]
  pure (runtimeFiles <> maybe [] pure (pathsHostConfigPath paths))

runtimeConfigurationRequired :: ValidationScope -> Bool
runtimeConfigurationRequired (FocusedScope check) = check `notElem` [FilesLint, DocsLint, ChartLint, ProtoLint, PlanLint]
runtimeConfigurationRequired _ = True

validationLane :: Paths -> ValidationScope -> IO (Maybe RuntimeMode)
validationLane paths scope
  | runtimeConfigurationRequired scope = do
      active <- targetRuntimeModeForExecutionContext paths
      when (harnessConfigurationRequired scope) $ do
        let path = testConfigPath paths
        present <- doesFileExist path
        unless present $
          ioError (userError ("validation test configuration is missing: " <> path <> "; run `infernix test init`"))
        harness <- configRuntimeMode <$> decodeDemoConfigFile path
        either (ioError . userError) pure (validateHarnessLane active harness)
      pure (Just active)
  | otherwise = pure Nothing

harnessConfigurationRequired :: ValidationScope -> Bool
harnessConfigurationRequired AllScope = True
harnessConfigurationRequired GpuAllScope = True
harnessConfigurationRequired (FocusedScope check) = check `elem` [Integration, Browser]
harnessConfigurationRequired _ = False

validationLaneId :: Maybe RuntimeMode -> String
validationLaneId = maybe "machine-independent" (Text.unpack . runtimeModeId)

-- | The expected source and inventory are supplied independently by the
-- caller. Receipt-authored success and hashes cannot replace either input.
verifyValidationReceipt :: ValidationScope -> VerificationContext -> [(FilePath, String, Int, String)] -> FilePath -> IO ()
verifyValidationReceipt = verifyReceiptCandidate True

verifyReceiptCandidate :: Bool -> ValidationScope -> VerificationContext -> [(FilePath, String, Int, String)] -> FilePath -> IO ()
verifyReceiptCandidate requireFinal scope verification expected receiptRoot = do
  payload <- Lazy.readFile (receiptRoot </> "receipt.json")
  value <- either (ioError . userError) pure (eitherDecode payload)
  recordedContext <-
    either (ioError . userError) pure $
      parseEither
        (withObject "execution context" $ \record -> VerificationContext <$> record .: "binaryDigest" <*> record .: "imageIdentity" <*> record .: "commit" <*> record .: "checkoutIdentity" <*> record .: "architecture" <*> record .: "operatingSystem" <*> record .: "lane" <*> record .: "configuration")
        value
  unless (recordedContext == verification) $
    ioError (userError "validation receipt differs from the independently expected binary, image, checkout, configuration, or runtime context")
  (passed, actionOutcome, sourceDigest, entryAlgorithm, sourceAlgorithm) <-
    either (ioError . userError) pure $
      parseEither
        (withObject "validation terminal outcome" $ \record -> (,,,,) <$> record .: "passed" <*> record .: "actionOutcome" <*> record .: "sourceDigest" <*> record .: "digestAlgorithm" <*> record .: "sourceDigestAlgorithm")
        value
  unless ((not requireFinal || passed) && actionOutcome == ExecutedPass && sourceDigest == sourceInventoryDigest expected && (entryAlgorithm :: String) == "sha256-path-type-mode-payload-v1" && (sourceAlgorithm :: String) == "sha256-aeson-source-inventory-v1") $
    ioError (userError "validation receipt has no successful terminal execution for the expected source")
  (version, recordedScope, source, stable, inventory, outcomes, artifacts, configuration) <-
    either (ioError . userError) pure $
      parseEither
        ( withObject "validation receipt" $ \record ->
            (,,,,,,,)
              <$> record .: "version"
              <*> record .: "scope"
              <*> record .: "sourceInventory"
              <*> record .: "sourceStable"
              <*> record .: "requiredChecks"
              <*> record .: "outcomes"
              <*> record .: "artifacts"
              <*> record .: "configuration"
        )
        value
  unless ((version :: Int) == 1 && recordedScope == scope && source == expected && stable && inventory == requiredChecks scope) $
    ioError (userError "validation receipt does not match the required execution handoff")
  either (ioError . userError) pure (validateCheckOutcomes scope outcomes)
  unless (sort (map fst artifacts) == sort [show check <> ".json" | check <- requiredChecks scope]) $
    ioError (userError "validation receipt artifact inventory mismatch")
  mapM_ (verifyArtifact receiptRoot) artifacts
  mapM_ verifyCheck outcomes
  mapM_ (verifyArtifact (receiptRoot </> "configuration")) (configuration :: [(FilePath, String)])
  retained <- sourceSnapshot (receiptRoot </> "source")
  unless (retained == expected) $
    ioError (userError "validation retained source preimage is missing or altered")
  where
    verifyCheck :: (RequiredCheck, CheckOutcome) -> IO ()
    verifyCheck (check, outcome) = do
      payload <- Lazy.readFile (receiptRoot </> show check <> ".json")
      value <- either (ioError . userError) pure (eitherDecode payload)
      (recordedCheck, recordedOutcome, configuration, logs, childDigest) <-
        either (ioError . userError) pure $
          parseEither
            (withObject "check execution" $ \record -> (,,,,) <$> record .: "check" <*> record .: "outcome" <*> record .: "configuration" <*> record .: "logs" <*> record .: "childReceiptDigest")
            value
      unless ((recordedCheck, recordedOutcome) == (check, outcome)) $
        ioError (userError "validation artifact contradicts its recorded check outcome")
      mapM_ (verifyArtifact (receiptRoot </> show check </> "configuration")) (configuration :: [(FilePath, String)])
      unless (sort (map fst logs) == ["stderr.log", "stdout.log"]) $
        ioError (userError "validation check log inventory is incomplete")
      mapM_ (verifyArtifact (receiptRoot </> show check)) logs
      case (check, childDigest) of
        (NvidiaValidation, Just digest) -> do
          let child = receiptRoot </> show check </> "device"
          verifyArtifact child ("receipt.json", digest)
          verifyValidationReceipt NvidiaScope (verification {verificationConfiguration = configuration}) expected child
        (NvidiaValidation, Nothing) -> ioError (userError "required NVIDIA child receipt is absent")
        (_, Nothing) -> pure ()
        (_, Just _) -> ioError (userError "unexpected child receipt in a local check")
    verifyArtifact root (name, digest) = do
      unless (takeFileName name == name && name `notElem` ["", ".", ".."]) $
        ioError (userError "validation artifact path escapes its receipt")
      actual <- fileDigest (root </> name)
      unless (actual == digest) $
        ioError (userError ("validation artifact is missing or altered: " <> name))
