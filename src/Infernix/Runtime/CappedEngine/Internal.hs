{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Package-internal engine process kernel. This is the only module that may
-- inspect runtime resource proofs or use raw process-spawn primitives.
module Infernix.Runtime.CappedEngine.Internal
  ( EngineOutputStream (..),
    EngineOutcome (..),
    EngineExecutionAuthority,
    newEngineExecutionAuthority,
    withSerializedEngineExecution,
    NativeArtifactCache,
    NativeArtifactInvocation,
    NativeArtifactLaunchOutcome (..),
    PythonWorkerLaunchOutcome (..),
    nativeArtifactCache,
    nativeArtifactInvocation,
    missingResidentRecheckForTest,
    linuxWatchdogOutcomeForTest,
    nvidiaWatchdogOutcomeForTest,
    observeNvidiaDeviceVramMib,
    probeNvidiaVramSampler,
    parseResidentBytesForTest,
    renderNativeArtifactArgumentsForTest,
    runExecutableNativeArtifact,
    runExecutablePythonWorker,
    verifyNvidiaVramSampler,
    verifyPhysicalFootprintSampler,
    verifyProcessGroupRssSampler,
  )
where

import Control.Concurrent (ThreadId, forkFinally, forkIO, killThread, threadDelay)
import Control.Concurrent.MVar (MVar, newEmptyMVar, newMVar, putMVar, readMVar, withMVar)
import Control.Exception
  ( IOException,
    SomeAsyncException,
    SomeException,
    bracket,
    catch,
    displayException,
    fromException,
    throwIO,
    try,
  )
import Control.Monad (foldM, unless, void, when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString8
import Data.Either (isRight)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Foreign.C.Error (Errno (Errno), ePIPE, eSRCH)
import GHC.IO.Exception (IOErrorType (ResourceVanished), IOException (IOError, ioe_errno, ioe_type))
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.Config (Paths (dataRoot, repoRoot))
import Infernix.DescriptorSpace (requireBoundedDescriptorSpace)
import Infernix.EngineBindings (canonicalEngineBindingForSelectedEngine)
import Infernix.Engines.Artifact qualified as Artifact
import Infernix.ExecutionPlan.Internal
  ( EnforcedGrant (EnforcedGrant),
    Enforcer
      ( HostFootprintWatchdogEnforcer,
        LinuxProcessGroupRssWatchdogEnforcer,
        NvidiaVramAccountingEnforcer
      ),
    ExecutableModel (ExecutableModel),
    MemoryCeiling (MemoryCeiling),
    MemoryGrant (MemoryGrant),
    RuntimeResources
      ( RuntimeGpuResources,
        RuntimeHostResources,
        RuntimePodResources
      ),
  )
import Infernix.Runtime.CappedEngine.Cleanup qualified as CappedCleanup
-- The @\/proc@ resident-set reader is reachable only from the Linux pair, so
-- its imports belong to the branch that uses it. The fixed public-tool
-- observer kernel is reachable from both branches: the Apple footprint pair on
-- Darwin, the NVIDIA VRAM pair elsewhere.
import Infernix.Runtime.CappedEngine.FixedObserver qualified as FixedObserver
import Infernix.Runtime.CappedEngine.OutputCapture qualified as OutputCapture
import Infernix.Types
  ( EngineBinding
      ( engineBindingAdapterId,
        engineBindingAdapterType
      ),
    InferenceRequest (inputObjectRef, inputText, requestModelId),
    ModelDescriptor (family, modelId, runtimeMode, selectedEngine),
    RuntimeMode (AppleSilicon, LinuxCpu, LinuxGpu),
  )
import System.Directory qualified as Directory
import System.Exit (ExitCode (..))
import System.FilePath (isAbsolute, takeExtension, (</>))
import System.IO (Handle, hClose, hPutStr)
import System.Posix.Signals (sigKILL, signalProcessGroup)
import System.Posix.Types (CPid)
import System.Process
  ( CreateProcess (close_fds, create_group, cwd, env, std_err, std_in, std_out),
    ProcessHandle,
    StdStream (CreatePipe),
    createProcess,
    getPid,
    getProcessExitCode,
    proc,
    terminateProcess,
    waitForProcess,
  )
#if !defined(darwin_HOST_OS)
import Data.Char (isDigit)
import Data.List (elemIndices)
import System.IO.Error (isDoesNotExistError)
import System.Posix.Process (getProcessGroupID)
#endif

-- | A process description whose constructor is hidden by the public facade.
-- The worker cannot recover the raw 'CreateProcess' used by the launch kernel.
data EngineCommand
  = DirectEngineCommand FilePath [String] FilePath [(String, String)]
  deriving (Eq, Show)

-- | A total terminal engine outcome. Enforcement unavailability is distinct
-- from a measured ceiling breach: both fail closed, but only a measured breach
-- is reported as 'ModelMemoryLimitExceeded'.
data EngineOutcome
  = EngineExited ExitCode
  | EngineExceededCeiling Int
  | EngineEnforcementUnavailable Text
  | EngineOutputLimitExceeded EngineOutputStream
  | EngineOutputCaptureFailed EngineOutputStream Text
  deriving (Eq, Show)

data EngineOutputStream
  = EngineStandardOutput
  | EngineStandardError
  deriving (Eq, Show)

-- | Non-secret model-cache operands accepted by the fixed native-runner
-- protocol. Credentials remain in the Haskell worker and never enter target
-- argv.
data NativeArtifactCache = NativeArtifactCache
  { nativeCacheRoot :: !FilePath,
    nativeCacheQuotaBytes :: !Word64,
    nativeCacheMinioEndpoint :: !Text,
    nativeCacheModelsBucket :: !Text,
    nativeCacheDemoArtifactsBucket :: !Text,
    nativeCacheRegion :: !Text
  }
  deriving (Eq, Show)

data NativeArtifactInput
  = NativeArtifactText !Text
  | NativeArtifactObjectRef !Text
  deriving (Eq, Show)

-- | A fixed-shape native invocation. Its constructor and argv renderer remain
-- in this kernel, so the worker can supply only typed data operands.
data NativeArtifactInvocation = NativeArtifactInvocation
  { nativeInvocationModelId :: !Text,
    nativeInvocationSelectedEngine :: !Text,
    nativeInvocationFamily :: !Text,
    nativeInvocationAdapterId :: !Text,
    nativeInvocationRuntimeMode :: !RuntimeMode,
    nativeInvocationInput :: !NativeArtifactInput,
    nativeInvocationCache :: !(Maybe NativeArtifactCache),
    nativeInvocationOutputDirectory :: !(Maybe FilePath),
    nativeInvocationInputFile :: !(Maybe FilePath)
  }
  deriving (Eq, Show)

data NativeArtifactLaunchOutcome
  = NativeArtifactUnsupported !Text
  | NativeArtifactUnavailable
  | NativeArtifactRejected
  | NativeArtifactBusy
  | NativeArtifactInvocationRejected !String
  | NativeArtifactUseValidationFailed
  | NativeArtifactLaunched !EngineOutcome !ExitCode !String !String
  deriving (Eq, Show)

data PythonWorkerLaunchOutcome
  = PythonWorkerInvocationRejected !Text
  | PythonWorkerLaunched !EngineOutcome !ExitCode !ByteString !ByteString
  deriving (Eq, Show)

nativeArtifactCache ::
  FilePath ->
  Word64 ->
  Text ->
  Text ->
  Text ->
  Text ->
  NativeArtifactCache
nativeArtifactCache = NativeArtifactCache

nativeArtifactInvocation ::
  ExecutableModel ->
  InferenceRequest ->
  Maybe NativeArtifactCache ->
  Maybe FilePath ->
  Maybe FilePath ->
  Either String NativeArtifactInvocation
nativeArtifactInvocation
  (ExecutableModel descriptor engineBinding _routes _resources)
  request
  maybeCache
  maybeOutputDirectory
  maybeInputFile = do
    unlessEither
      (requestModelId request == modelId descriptor)
      ( "native artifact invocation model mismatch: expected "
          <> Text.unpack (modelId descriptor)
          <> ", observed "
          <> Text.unpack (requestModelId request)
      )
    mapM_
      requireInvocationText
      [ ("model id", modelId descriptor),
        ("selected engine", selectedEngine descriptor),
        ("model family", family descriptor),
        ("adapter id", engineBindingAdapterId engineBinding)
      ]
    mapM_ validateNativeArtifactCache maybeCache
    mapM_ (requireAbsoluteInvocationPath "output directory") maybeOutputDirectory
    mapM_ (requireAbsoluteInvocationPath "input file") maybeInputFile
    let invocationInput =
          case inputObjectRef request of
            Just objectRef -> NativeArtifactObjectRef objectRef
            Nothing -> NativeArtifactText (inputText request)
    validateNativeArtifactInput invocationInput
    pure
      NativeArtifactInvocation
        { nativeInvocationModelId = modelId descriptor,
          nativeInvocationSelectedEngine = selectedEngine descriptor,
          nativeInvocationFamily = family descriptor,
          nativeInvocationAdapterId = engineBindingAdapterId engineBinding,
          nativeInvocationRuntimeMode = runtimeMode descriptor,
          nativeInvocationInput = invocationInput,
          nativeInvocationCache = maybeCache,
          nativeInvocationOutputDirectory = maybeOutputDirectory,
          nativeInvocationInputFile = maybeInputFile
        }

unlessEither :: Bool -> String -> Either String ()
unlessEither condition failure =
  if condition then Right () else Left failure

requireInvocationText :: (String, Text) -> Either String ()
requireInvocationText (label, value) =
  unlessEither
    (not (Text.null value) && not (Text.any (== '\0') value))
    ("native artifact invocation has an invalid " <> label)

requireAbsoluteInvocationPath :: String -> FilePath -> Either String ()
requireAbsoluteInvocationPath label path =
  unlessEither
    (isAbsolute path && '\0' `notElem` path)
    ("native artifact invocation " <> label <> " is not a valid absolute path")

validateNativeArtifactCache :: NativeArtifactCache -> Either String ()
validateNativeArtifactCache cache = do
  requireAbsoluteInvocationPath "model-cache root" (nativeCacheRoot cache)
  unlessEither
    (nativeCacheQuotaBytes cache > 0)
    "native artifact invocation has a non-positive model-cache quota"
  mapM_
    requireInvocationText
    [ ("MinIO endpoint", nativeCacheMinioEndpoint cache),
      ("models bucket", nativeCacheModelsBucket cache),
      ("demo-artifacts bucket", nativeCacheDemoArtifactsBucket cache),
      ("MinIO region", nativeCacheRegion cache)
    ]

validateNativeArtifactInput :: NativeArtifactInput -> Either String ()
validateNativeArtifactInput invocationInput =
  case invocationInput of
    NativeArtifactText value ->
      unlessEither
        (not (Text.any (== '\0') value))
        "native artifact inline input contains NUL"
    NativeArtifactObjectRef value ->
      requireInvocationText ("input object reference", value)

data EnforcementTermination
  = CeilingBreached Int
  | EnforcementUnavailable Text
  | OutputLimitExceeded EngineOutputStream
  | OutputCaptureFailed EngineOutputStream Text

-- | The single-flight authority for engine execution.
--
-- The constructor is hidden and the value is minted once, by
-- 'Infernix.Runtime.Enforcer.refineCompiledRuntimePlan', alongside the
-- 'RuntimePlan' it serializes. A caller therefore cannot mint a second token and
-- obtain concurrent execution of the same refined plan under independent locks,
-- which a bare @MVar ()@ threaded through a public signature could not prevent.
--
-- It is deliberately one authority for the whole plan rather than one per
-- executable. Serialization here is what bounds *total* resident memory to a
-- single admitted grant at a time; per-executable tokens would let two admitted
-- models run concurrently and exceed the host or pod budget the admission
-- decision was made against.
newtype EngineExecutionAuthority = EngineExecutionAuthority (MVar ())

-- | Mint the one authority for one refined plan. Exposed only so the refinement
-- boundary can pair it with the 'RuntimePlan'; every other module receives it.
newEngineExecutionAuthority :: IO EngineExecutionAuthority
newEngineExecutionAuthority = EngineExecutionAuthority <$> newMVar ()

-- | Run one engine execution under the authority. Exceptions propagate with the
-- token released, so a failed execution cannot wedge the daemon.
withSerializedEngineExecution :: EngineExecutionAuthority -> IO a -> IO a
withSerializedEngineExecution (EngineExecutionAuthority token) action =
  withMVar token (const action)

data WatchdogSpec
  = AppleFootprintWatchdog Int
  | LinuxProcessGroupRssWatchdog Int
  | NvidiaVramWatchdog Int

data EngineHandle s = EngineHandle
  { engineStdin :: Maybe Handle,
    engineStdout :: Maybe Handle,
    engineStderr :: Maybe Handle,
    engineProcess :: ProcessHandle,
    engineProcessGroup :: CPid,
    engineTermination :: IORef (Maybe EnforcementTermination),
    engineWatchdogs :: [ThreadId]
  }

-- | Production text-stdio launch. The executable placement supplies every
-- indexed enforcer/grant pair; an unsupported or unavailable enforcer rejects
-- the command before a child is spawned.
runExecutableProcess :: ExecutableModel -> EngineCommand -> String -> IO (EngineOutcome, ExitCode, String, String)
runExecutableProcess executableModel command input =
  case executableWatchdogs executableModel of
    Left reason -> pure (unavailableTextResult reason)
    Right watchdogs ->
      withCappedEngine watchdogs command $ \handle ->
        case (engineStdin handle, engineStdout handle, engineStderr handle) of
          (Just stdinHandle, Just stdoutHandle, Just stderrHandle) -> do
            withEngineOutputCaptures handle stdoutHandle stderrHandle $
              \stdoutCapture stderrCapture -> do
                ignoreSigPipe
                  (unless (null input) (hPutStr stdinHandle input) >> hClose stdinHandle)
                stdoutOutput <- awaitOutputCapture stdoutCapture
                stderrOutput <- awaitOutputCapture stderrCapture
                outcome <- awaitEngineOutcome handle
                pure
                  ( outcome,
                    engineOutcomeExitCode outcome,
                    ByteString8.unpack stdoutOutput,
                    ByteString8.unpack stderrOutput
                  )
          _ -> failMissingPipes

-- | Resolve, validate, launch, and reap one native artifact under a single
-- shared-lock region. Neither the validated capability nor its raw executable
-- path is exposed to the worker.
runExecutableNativeArtifact ::
  Paths ->
  ExecutableModel ->
  NativeArtifactInvocation ->
  Subprocess.SubprocessEnv ->
  IO NativeArtifactLaunchOutcome
runExecutableNativeArtifact
  paths
  executableModel
  invocation
  processEnvironment =
    case validateInvocationBinding executableModel invocation of
      Left failure ->
        pure (NativeArtifactInvocationRejected failure)
      Right () ->
        case nativeArtifactRuntimeContract executableModel of
          Left unsupportedAdapter ->
            pure (NativeArtifactUnsupported unsupportedAdapter)
          Right (identity, runtimeExpectation) -> do
            resolution <-
              Artifact.withFirstValidatedEngineArtifact
                identity
                runtimeExpectation
                (nativeArtifactInstallRoots paths executableModel)
                ( Artifact.artifactLauncher
                    ( \launchRequest ->
                        runArtifactLaunchRequest
                          executableModel
                          launchRequest
                          invocation
                          processEnvironment
                    )
                )
            pure $
              case resolution of
                Artifact.ArtifactResolved terminalOutcome ->
                  nativeArtifactTerminalOutcome terminalOutcome
                Artifact.ArtifactUnavailable _ ->
                  NativeArtifactUnavailable
                Artifact.ArtifactRejected _ _ ->
                  NativeArtifactRejected
                Artifact.ArtifactBusy _ ->
                  NativeArtifactBusy

nativeArtifactInstallRoots :: Paths -> ExecutableModel -> [FilePath]
nativeArtifactInstallRoots
  paths
  (ExecutableModel _descriptor engineBinding _routes _resources) =
    [ dataRoot paths
        </> "engines"
        </> Text.unpack (engineBindingAdapterId engineBinding),
      "/opt/infernix/engines"
        </> Text.unpack (engineBindingAdapterId engineBinding)
    ]

-- | The closed Python-stdio launch. The executable, module/entrypoint, working
-- directory, argument vector, and rendered environment are derived here from
-- the runtime-refined model and repository paths. No caller can provide a raw
-- process specification.
runExecutablePythonWorker ::
  Paths ->
  ExecutableModel ->
  Subprocess.SubprocessEnv ->
  ByteString ->
  IO PythonWorkerLaunchOutcome
runExecutablePythonWorker paths executableModel processEnvironment inputPayload =
  case canonicalPythonWorkerBinding executableModel of
    Left failure ->
      pure (PythonWorkerInvocationRejected failure)
    Right engineBinding -> do
      command <-
        resolvePythonWorkerCommand
          paths
          engineBinding
          processEnvironment
      (outcome, exitCode, stdoutOutput, stderrOutput) <-
        runExecutableStdioEngine
          executableModel
          command
          inputPayload
      pure
        ( PythonWorkerLaunched
            outcome
            exitCode
            stdoutOutput
            stderrOutput
        )

canonicalPythonWorkerBinding ::
  ExecutableModel ->
  Either Text EngineBinding
canonicalPythonWorkerBinding
  (ExecutableModel descriptor engineBinding _routes _resources) =
    case canonicalEngineBindingForSelectedEngine
      (runtimeMode descriptor)
      (selectedEngine descriptor) of
      Just canonicalBinding
        | canonicalBinding == engineBinding
            && engineBindingAdapterType canonicalBinding == "python-stdio" ->
            Right canonicalBinding
      _ ->
        Left
          ( "runtime-refined executable does not carry a canonical Python-stdio binding for "
              <> modelId descriptor
          )

resolvePythonWorkerCommand ::
  Paths ->
  EngineBinding ->
  Subprocess.SubprocessEnv ->
  IO EngineCommand
resolvePythonWorkerCommand paths engineBinding processEnvironment = do
  perEnginePythonPresent <- Directory.doesFileExist perEnginePython
  if perEnginePythonPresent
    then pure command
    else
      ioError
        ( userError
            ( "prepared Python engine interpreter is missing for "
                <> Text.unpack (engineBindingAdapterId engineBinding)
                <> ": "
                <> perEnginePython
            )
        )
  where
    command =
      DirectEngineCommand
        perEnginePython
        ["-m", adapterModule]
        (repoRoot paths)
        renderedEnvironment
    perEnginePython =
      repoRoot paths
        </> "python"
        </> "engines"
        </> perEngineName
        </> ".venv"
        </> "bin"
        </> "python"
    perEngineName =
      Text.unpack
        ( Text.replace
            "-python"
            ""
            (engineBindingAdapterId engineBinding)
        )
    adapterModule =
      "adapters."
        <> Text.unpack
          ( Text.replace
              "-"
              "_"
              (engineBindingAdapterId engineBinding)
          )
    renderedEnvironment =
      Subprocess.renderSubprocessEnv processEnvironment

-- | Interpret one runner-issued launch request. The artifact runner has
-- already revalidated the sealed root under its shared lock; this launcher
-- holds no artifact capability, only the closed request it was handed.
runArtifactLaunchRequest ::
  ExecutableModel ->
  Artifact.ArtifactLaunchRequest ->
  NativeArtifactInvocation ->
  Subprocess.SubprocessEnv ->
  IO Artifact.ArtifactTerminalOutcome
runArtifactLaunchRequest
  executableModel
  launchRequest
  invocation
  processEnvironment =
    case renderNativeArtifactArguments installRoot invocation of
      Left _ -> pure Artifact.ArtifactTerminalRejected
      Right invocationArguments -> do
        artifactEnvironment <-
          closedNativeArtifactEnvironment
            installRoot
            invocation
            processEnvironment
        (outcome, exitCode, stdoutOutput, stderrOutput) <-
          runExecutableProcess
            executableModel
            ( DirectEngineCommand
                entrypoint
                (leadingArguments <> invocationArguments)
                installRoot
                artifactEnvironment
            )
            ""
        finalizedOutput <-
          finalizeNativeArtifactOutput invocation exitCode stdoutOutput
        pure $
          case finalizedOutput of
            Left _ -> Artifact.ArtifactTerminalRejected
            Right finalStdout ->
              Artifact.ArtifactTerminalProcess
                (artifactProcessOutcome outcome)
                exitCode
                (ByteString8.pack finalStdout)
                (ByteString8.pack stderrOutput)
    where
      -- The closed catalog's leading arguments come first. They are what makes a
      -- target complete: Python runners receive their script and fixed protocol
      -- prefix, while the JVM receives its classpath and main class. The sealed
      -- adapter dispatch then appends that target's actual invocation grammar.
      installRoot = Artifact.artifactLaunchInstallRoot launchRequest
      entrypoint = Artifact.artifactLaunchEntrypoint launchRequest
      leadingArguments =
        Artifact.artifactLaunchLeadingArguments launchRequest

finalizeNativeArtifactOutput ::
  NativeArtifactInvocation ->
  ExitCode ->
  String ->
  IO (Either String String)
finalizeNativeArtifactOutput invocation exitCode stdoutOutput =
  case (nativeInvocationAdapterId invocation, exitCode) of
    ("jvm-native", ExitSuccess) ->
      case requireNativeInvocationPath
        "jvm-native output directory"
        (nativeInvocationOutputDirectory invocation) of
        Left failure -> pure (Left failure)
        Right directory -> do
          outputFiles <- collectBoundedArtifactOutputFiles directory
          pure $
            case outputFiles of
              Right [artifactPath] ->
                Right ("infernix-native-artifact-file:" <> artifactPath)
              Right [] ->
                Left "Audiveris completed without a MusicXML output artifact"
              Right _ ->
                Left "Audiveris completed with multiple MusicXML output artifacts"
              Left failure -> Left failure
    _ -> pure (Right stdoutOutput)

collectBoundedArtifactOutputFiles :: FilePath -> IO (Either String [FilePath])
collectBoundedArtifactOutputFiles root = fmap (fmap snd) (walk 0 0 root)
  where
    maximumDepth = 8 :: Int
    maximumEntries = 4096 :: Int
    walk depth observed directory
      | depth > maximumDepth =
          pure (Left "native artifact output exceeded the directory-depth bound")
      | otherwise = do
          entries <- List.sort <$> Directory.listDirectory directory
          if observed + length entries > maximumEntries
            then pure (Left "native artifact output exceeded the entry-count bound")
            else
              foldM
                (visit depth directory)
                (Right (observed + length entries, []))
                entries
    visit _ _ (Left failure) _ = pure (Left failure)
    visit depth directory (Right (observed, files)) entry = do
      let path = directory </> entry
      symbolicLink <- Directory.pathIsSymbolicLink path
      if symbolicLink
        then pure (Left "native artifact output contains a symbolic link")
        else do
          isDirectory <- Directory.doesDirectoryExist path
          if isDirectory
            then do
              descendants <- walk (depth + 1) observed path
              pure (fmap (appendCollectedFiles files) descendants)
            else do
              regularFile <- Directory.doesFileExist path
              let accepted =
                    regularFile
                      && takeExtension path `elem` [".mxl", ".musicxml", ".xml"]
              pure (Right (observed, files <> [path | accepted]))
    appendCollectedFiles existingFiles (count, descendantFiles) =
      (count, existingFiles <> descendantFiles)

closedNativeArtifactEnvironment ::
  FilePath ->
  NativeArtifactInvocation ->
  Subprocess.SubprocessEnv ->
  IO [(String, String)]
closedNativeArtifactEnvironment installRoot invocation processEnvironment =
  case nativeInvocationRuntimeMode invocation of
    AppleSilicon -> do
      unless (isAbsolute installRoot) $
        ioError
          (userError "validated Apple engine artifact has a non-absolute install root")
      pure
        ( appleRuntimeEnvironment installRoot
            <> filter
              ((`notElem` appleRuntimeEnvironmentNames) . fst)
              (Subprocess.renderSubprocessEnv processEnvironment)
        )
    LinuxCpu ->
      pure (Subprocess.renderSubprocessEnv processEnvironment)
    LinuxGpu ->
      pure (Subprocess.renderSubprocessEnv processEnvironment)

appleRuntimeEnvironment :: FilePath -> [(String, String)]
appleRuntimeEnvironment installRoot =
  [ ("PYTHONHOME", installRoot </> "python-home"),
    ("DYLD_FRAMEWORK_PATH", installRoot </> "python-frameworks"),
    ( "DYLD_LIBRARY_PATH",
      (installRoot </> "native" </> "lib")
        <> ":"
        <> (installRoot </> "native" </> "libexec")
    ),
    ("PYTHONNOUSERSITE", "1"),
    ("PYTHONDONTWRITEBYTECODE", "1")
  ]

appleRuntimeEnvironmentNames :: [String]
appleRuntimeEnvironmentNames =
  [ "PYTHONHOME",
    "DYLD_FRAMEWORK_PATH",
    "DYLD_LIBRARY_PATH",
    "PYTHONNOUSERSITE",
    "PYTHONDONTWRITEBYTECODE"
  ]

artifactProcessOutcome :: EngineOutcome -> Artifact.ArtifactProcessOutcome
artifactProcessOutcome outcome =
  case outcome of
    EngineExited exitCode ->
      Artifact.ArtifactProcessExited exitCode
    EngineExceededCeiling observedBytes ->
      Artifact.ArtifactProcessExceededCeiling observedBytes
    EngineEnforcementUnavailable reason ->
      Artifact.ArtifactProcessEnforcementUnavailable reason
    EngineOutputLimitExceeded outputStream ->
      Artifact.ArtifactProcessOutputLimitExceeded
        (artifactOutputStream outputStream)
    EngineOutputCaptureFailed outputStream reason ->
      Artifact.ArtifactProcessOutputCaptureFailed
        (artifactOutputStream outputStream)
        reason

artifactOutputStream ::
  EngineOutputStream ->
  Artifact.ArtifactOutputStream
artifactOutputStream outputStream =
  case outputStream of
    EngineStandardOutput -> Artifact.ArtifactStandardOutput
    EngineStandardError -> Artifact.ArtifactStandardError

nativeArtifactTerminalOutcome ::
  Artifact.ArtifactTerminalOutcome ->
  NativeArtifactLaunchOutcome
nativeArtifactTerminalOutcome terminalOutcome =
  case terminalOutcome of
    Artifact.ArtifactTerminalCompleted ->
      NativeArtifactUseValidationFailed
    Artifact.ArtifactTerminalRejected ->
      NativeArtifactUseValidationFailed
    Artifact.ArtifactTerminalProcess
      processOutcome
      exitCode
      stdoutOutput
      stderrOutput ->
        NativeArtifactLaunched
          (engineOutcomeFromArtifact processOutcome)
          exitCode
          (ByteString8.unpack stdoutOutput)
          (ByteString8.unpack stderrOutput)

engineOutcomeFromArtifact :: Artifact.ArtifactProcessOutcome -> EngineOutcome
engineOutcomeFromArtifact processOutcome =
  case processOutcome of
    Artifact.ArtifactProcessExited exitCode ->
      EngineExited exitCode
    Artifact.ArtifactProcessExceededCeiling observedBytes ->
      EngineExceededCeiling observedBytes
    Artifact.ArtifactProcessEnforcementUnavailable reason ->
      EngineEnforcementUnavailable reason
    Artifact.ArtifactProcessOutputLimitExceeded outputStream ->
      EngineOutputLimitExceeded (engineOutputStream outputStream)
    Artifact.ArtifactProcessOutputCaptureFailed outputStream reason ->
      EngineOutputCaptureFailed
        (engineOutputStream outputStream)
        reason

engineOutputStream ::
  Artifact.ArtifactOutputStream ->
  EngineOutputStream
engineOutputStream outputStream =
  case outputStream of
    Artifact.ArtifactStandardOutput -> EngineStandardOutput
    Artifact.ArtifactStandardError -> EngineStandardError

nativeArtifactRuntimeContract ::
  ExecutableModel ->
  Either
    Text
    (Artifact.NativeArtifactIdentity, Artifact.ArtifactRuntimeExpectation)
nativeArtifactRuntimeContract
  (ExecutableModel descriptor engineBinding _routes _resources) = do
    identity <-
      maybe
        (Left (engineBindingAdapterId engineBinding))
        Right
        ( Artifact.parseNativeArtifactIdentity
            (engineBindingAdapterId engineBinding)
        )
    let runtimeExpectation =
          case runtimeMode descriptor of
            AppleSilicon -> Artifact.appleArtifactRuntimeExpectation
            LinuxCpu -> Artifact.linuxArtifactRuntimeExpectation
            LinuxGpu -> Artifact.linuxArtifactRuntimeExpectation
    pure (identity, runtimeExpectation)

validateInvocationBinding ::
  ExecutableModel ->
  NativeArtifactInvocation ->
  Either String ()
validateInvocationBinding
  (ExecutableModel descriptor engineBinding _routes _resources)
  invocation = do
    unlessEither
      (nativeInvocationModelId invocation == modelId descriptor)
      "native artifact invocation does not belong to the executable model"
    unlessEither
      ( nativeInvocationSelectedEngine invocation
          == selectedEngine descriptor
      )
      "native artifact invocation selected-engine binding changed"
    unlessEither
      (nativeInvocationFamily invocation == family descriptor)
      "native artifact invocation model-family binding changed"
    unlessEither
      ( nativeInvocationAdapterId invocation
          == engineBindingAdapterId engineBinding
      )
      "native artifact invocation adapter binding changed"
    unlessEither
      (nativeInvocationRuntimeMode invocation == runtimeMode descriptor)
      "native artifact invocation runtime binding changed"

renderNativeArtifactArguments ::
  FilePath ->
  NativeArtifactInvocation ->
  Either String [String]
renderNativeArtifactArguments installRoot invocation =
  case nativeInvocationAdapterId invocation of
    "llama-cpp-cli" -> do
      cache <- requireNativeArtifactCache invocation
      prompt <-
        case nativeInvocationInput invocation of
          NativeArtifactText value -> Right value
          NativeArtifactObjectRef _ ->
            Left "llama-cpp-cli requires inline text input"
      pure
        [ "--model",
          nativeModelPayloadPath cache invocation,
          "--prompt",
          Text.unpack prompt,
          "--n-predict",
          "32",
          "--ctx-size",
          "512",
          "--threads",
          "1",
          "--gpu-layers",
          "0",
          "--no-display-prompt",
          "--no-conversation",
          "--single-turn",
          "--simple-io",
          "--log-disable"
        ]
    "whisper-cpp-cli" -> do
      cache <- requireNativeArtifactCache invocation
      inputFile <-
        requireNativeInvocationPath
          "whisper-cpp-cli input file"
          (nativeInvocationInputFile invocation)
      pure
        [ "--model",
          nativeModelPayloadPath cache invocation,
          "--file",
          inputFile,
          "--threads",
          "1",
          "--no-timestamps",
          "--language",
          "en",
          "--no-gpu"
        ]
    "jvm-native" -> do
      inputFile <-
        requireNativeInvocationPath
          "jvm-native input file"
          (nativeInvocationInputFile invocation)
      outputDirectory <-
        requireNativeInvocationPath
          "jvm-native output directory"
          (nativeInvocationOutputDirectory invocation)
      pure
        [ "-batch",
          "-export",
          "-output",
          outputDirectory,
          inputFile
        ]
    adapterId
      | adapterId
          `elem` [ "ctranslate2-native",
                   "onnx-runtime-native",
                   "mlx-native",
                   "coreml-native"
                 ] ->
          Right (renderPythonNativeArtifactArguments installRoot invocation)
    adapterId ->
      Left
        ( "closed native invocation grammar has no entry for adapter "
            <> Text.unpack adapterId
        )

-- | Unit-test view of the closed adapter dispatch. Production callers cannot
-- supply these operands; they receive the opaque invocation minted above.
renderNativeArtifactArgumentsForTest ::
  Text ->
  Maybe FilePath ->
  Maybe FilePath ->
  Either String [String]
renderNativeArtifactArgumentsForTest adapterId maybeOutputDirectory maybeInputFile =
  renderNativeArtifactArguments
    "/opt/infernix/engines/test-adapter"
    NativeArtifactInvocation
      { nativeInvocationModelId = "test-model",
        nativeInvocationSelectedEngine = "test-engine",
        nativeInvocationFamily = "test-family",
        nativeInvocationAdapterId = adapterId,
        nativeInvocationRuntimeMode = LinuxCpu,
        nativeInvocationInput = NativeArtifactText "test prompt",
        nativeInvocationCache =
          Just
            NativeArtifactCache
              { nativeCacheRoot = "/var/lib/infernix/models",
                nativeCacheQuotaBytes = 1,
                nativeCacheMinioEndpoint = "minio",
                nativeCacheModelsBucket = "models",
                nativeCacheDemoArtifactsBucket = "artifacts",
                nativeCacheRegion = "local"
              },
        nativeInvocationOutputDirectory = maybeOutputDirectory,
        nativeInvocationInputFile = maybeInputFile
      }

requireNativeArtifactCache ::
  NativeArtifactInvocation ->
  Either String NativeArtifactCache
requireNativeArtifactCache invocation =
  maybe
    (Left "native invocation requires a populated model cache")
    Right
    (nativeInvocationCache invocation)

requireNativeInvocationPath ::
  String ->
  Maybe FilePath ->
  Either String FilePath
requireNativeInvocationPath label =
  maybe (Left (label <> " is unavailable")) Right

nativeModelPayloadPath ::
  NativeArtifactCache ->
  NativeArtifactInvocation ->
  FilePath
nativeModelPayloadPath cache invocation =
  nativeCacheRoot cache
    </> Text.unpack (nativeInvocationModelId invocation)
    </> "payload"

renderPythonNativeArtifactArguments ::
  FilePath ->
  NativeArtifactInvocation ->
  [String]
renderPythonNativeArtifactArguments installRoot invocation =
  [ "--model",
    Text.unpack (nativeInvocationModelId invocation),
    "--engine",
    Text.unpack (nativeInvocationSelectedEngine invocation),
    "--family",
    Text.unpack (nativeInvocationFamily invocation),
    "--install-root",
    installRoot,
    "--require-native-payload"
  ]
    <> renderNativeArtifactInput (nativeInvocationInput invocation)
    <> maybe [] renderNativeArtifactCache (nativeInvocationCache invocation)
    <> maybe
      []
      (\outputDirectory -> ["--output-dir", outputDirectory])
      (nativeInvocationOutputDirectory invocation)
    <> maybe
      []
      (\inputFile -> ["--input-file", inputFile])
      (nativeInvocationInputFile invocation)

renderNativeArtifactInput :: NativeArtifactInput -> [String]
renderNativeArtifactInput invocationInput =
  case invocationInput of
    NativeArtifactText value ->
      ["--input-text", Text.unpack value]
    NativeArtifactObjectRef value ->
      ["--input-object-ref", Text.unpack value]

renderNativeArtifactCache :: NativeArtifactCache -> [String]
renderNativeArtifactCache cache =
  [ "--model-cache-root",
    nativeCacheRoot cache,
    "--model-cache-quota-bytes",
    show (nativeCacheQuotaBytes cache),
    "--minio-endpoint",
    Text.unpack (nativeCacheMinioEndpoint cache),
    "--minio-models-bucket",
    Text.unpack (nativeCacheModelsBucket cache),
    "--minio-demo-artifacts-bucket",
    Text.unpack (nativeCacheDemoArtifactsBucket cache),
    "--minio-region",
    Text.unpack (nativeCacheRegion cache)
  ]

-- | Production binary-stdio launch for Python adapters.
runExecutableStdioEngine :: ExecutableModel -> EngineCommand -> ByteString -> IO (EngineOutcome, ExitCode, ByteString, ByteString)
runExecutableStdioEngine executableModel command input =
  case executableWatchdogs executableModel of
    Left reason -> pure (unavailableBinaryResult reason)
    Right watchdogs ->
      withCappedEngine watchdogs command $ \handle ->
        case (engineStdin handle, engineStdout handle, engineStderr handle) of
          (Just stdinHandle, Just stdoutHandle, Just stderrHandle) -> do
            withEngineOutputCaptures handle stdoutHandle stderrHandle $
              \stdoutCapture stderrCapture -> do
                ignoreSigPipe (ByteString.hPut stdinHandle input >> hClose stdinHandle)
                stdoutOutput <- awaitOutputCapture stdoutCapture
                stderrOutput <- awaitOutputCapture stderrCapture
                outcome <- awaitEngineOutcome handle
                pure (outcome, engineOutcomeExitCode outcome, stdoutOutput, stderrOutput)
          _ -> failMissingPipes

unavailableTextResult :: Text -> (EngineOutcome, ExitCode, String, String)
unavailableTextResult reason =
  (EngineEnforcementUnavailable reason, ExitFailure enforcementUnavailableExitCode, "", Text.unpack reason)

unavailableBinaryResult :: Text -> (EngineOutcome, ExitCode, ByteString, ByteString)
unavailableBinaryResult reason =
  ( EngineEnforcementUnavailable reason,
    ExitFailure enforcementUnavailableExitCode,
    ByteString.empty,
    ByteString8.pack (Text.unpack reason)
  )

data OutputCapture = OutputCapture
  { outputCaptureThread :: !ThreadId,
    outputCaptureHandle :: !Handle,
    outputCaptureResult :: !(MVar (Either SomeException ByteString))
  }

withEngineOutputCaptures ::
  EngineHandle s ->
  Handle ->
  Handle ->
  (OutputCapture -> OutputCapture -> IO result) ->
  IO result
withEngineOutputCaptures engineHandle stdoutHandle stderrHandle action =
  bracket
    acquire
    release
    (uncurry action)
  where
    acquire = do
      stdoutCapture <-
        startOutputCapture
          engineHandle
          EngineStandardOutput
          stdoutHandle
      stderrCapture <-
        startOutputCapture
          engineHandle
          EngineStandardError
          stderrHandle
      pure (stdoutCapture, stderrCapture)

    release (stdoutCapture, stderrCapture) = do
      stopOutputCapture stdoutCapture
      stopOutputCapture stderrCapture

startOutputCapture ::
  EngineHandle s ->
  EngineOutputStream ->
  Handle ->
  IO OutputCapture
startOutputCapture engineHandle outputStream outputHandle = do
  result <- newEmptyMVar
  worker <-
    forkFinally
      (captureEngineOutput engineHandle outputStream outputHandle)
      (putMVar result)
  pure
    OutputCapture
      { outputCaptureThread = worker,
        outputCaptureHandle = outputHandle,
        outputCaptureResult = result
      }

stopOutputCapture :: OutputCapture -> IO ()
stopOutputCapture capture = do
  killThread (outputCaptureThread capture)
  void (readMVar (outputCaptureResult capture))
  hClose (outputCaptureHandle capture)
    `catch` \(_ :: SomeException) -> pure ()

awaitOutputCapture :: OutputCapture -> IO ByteString
awaitOutputCapture capture = do
  result <- readMVar (outputCaptureResult capture)
  case result of
    Right output -> pure output
    Left failure -> throwIO failure

captureEngineOutput ::
  EngineHandle s ->
  EngineOutputStream ->
  Handle ->
  IO ByteString
captureEngineOutput engineHandle outputStream outputHandle = do
  result <-
    try @SomeException
      ( OutputCapture.readBoundedCapture
          maximumEngineOutputBytes
          ( terminateForWatchdog
              (engineProcess engineHandle)
              (engineProcessGroup engineHandle)
              (engineTermination engineHandle)
              (OutputLimitExceeded outputStream)
          )
          outputHandle
      )
  case result of
    Right boundedCapture ->
      pure $
        case boundedCapture of
          OutputCapture.BoundedCaptureCompleted output -> output
          OutputCapture.BoundedCaptureExceeded output -> output
    Left failure ->
      case fromException failure :: Maybe SomeAsyncException of
        Just _ -> throwIO failure
        Nothing -> do
          terminateForWatchdog
            (engineProcess engineHandle)
            (engineProcessGroup engineHandle)
            (engineTermination engineHandle)
            ( OutputCaptureFailed
                outputStream
                (Text.take maximumEngineOutputFailureChars (Text.pack (displayException failure)))
            )
          pure ByteString.empty

maximumEngineOutputBytes :: Int
maximumEngineOutputBytes = 16 * 1024 * 1024

maximumEngineOutputFailureChars :: Int
maximumEngineOutputFailureChars = 4096

-- | Eliminate the existential executable placement while retaining each
-- enforcer/grant resource index. A GPU placement must satisfy both independent
-- grants: the pod resident-set watchdog and the NVIDIA per-process-group VRAM
-- watchdog each run against their own admitted ceiling, and neither a pod limit
-- nor an exit code is ever accepted as a substitute for the other's evidence.
executableWatchdogs :: ExecutableModel -> Either Text [WatchdogSpec]
executableWatchdogs (ExecutableModel _ _ _ resources) =
  case resources of
    RuntimeHostResources hostGrant ->
      (: []) <$> watchdogForGrant hostGrant
    RuntimePodResources podGrant ->
      (: []) <$> watchdogForGrant podGrant
    RuntimeGpuResources podGrant vramGrant -> do
      podWatchdog <- watchdogForGrant podGrant
      vramWatchdog <- watchdogForGrant vramGrant
      pure [podWatchdog, vramWatchdog]

watchdogForGrant :: EnforcedGrant resource -> Either Text WatchdogSpec
watchdogForGrant (EnforcedGrant enforcer grant) =
  case (enforcer, grant) of
    (HostFootprintWatchdogEnforcer _, MemoryGrant (MemoryCeiling ceilingMib)) ->
      positiveWatchdog ceilingMib AppleFootprintWatchdog
    (LinuxProcessGroupRssWatchdogEnforcer _, MemoryGrant (MemoryCeiling ceilingMib)) ->
      positiveWatchdog ceilingMib LinuxProcessGroupRssWatchdog
    (NvidiaVramAccountingEnforcer _, MemoryGrant (MemoryCeiling ceilingMib)) ->
      positiveWatchdog ceilingMib NvidiaVramWatchdog

positiveWatchdog :: Int -> (Int -> WatchdogSpec) -> Either Text WatchdogSpec
positiveWatchdog ceilingMib constructor
  | ceilingMib <= 0 =
      Left "the executable model carries a non-positive memory ceiling"
  | toInteger ceilingMib * toInteger bytesPerMib > toInteger (maxBound :: Word64) =
      Left "the executable model carries a memory ceiling too large to enforce"
  | otherwise = Right (constructor ceilingMib)

withCappedEngine :: [WatchdogSpec] -> EngineCommand -> (forall s. EngineHandle s -> IO result) -> IO result
withCappedEngine watchdogs command action =
  CappedCleanup.withCappedEngineCleanupBoundary acquire release runInRegion
  where
    -- Keep the rank-2 action monomorphic at the bracketed region's handle.
    runInRegion = action
    acquire = do
      -- 'withStdioPipes' sets close_fds, whose pre-'exec' descriptor walk is
      -- linear in the soft RLIMIT_NOFILE. An engine launch inside a containerd
      -- pod would otherwise spend 313 s before the adapter's first instruction.
      _ <- requireBoundedDescriptorSpace "capped engine launch"
      (maybeIn, maybeOut, maybeErr, processHandle) <-
        createProcess (withStdioPipes (engineCreateProcess command))
      maybeProcessGroup <- getPid processHandle
      processGroup <-
        case maybeProcessGroup of
          Just pid -> pure pid
          Nothing -> do
            terminateProcess processHandle
            void (waitForProcess processHandle)
            ioError (userError "engine process exited before its process-group identity was observed")
      terminationRef <- newIORef Nothing
      watchdogThreads <-
        mapM
          (\watchdog -> forkIO (runCeilingWatchdog watchdog processHandle processGroup terminationRef))
          watchdogs
      pure
        EngineHandle
          { engineStdin = maybeIn,
            engineStdout = maybeOut,
            engineStderr = maybeErr,
            engineProcess = processHandle,
            engineProcessGroup = processGroup,
            engineTermination = terminationRef,
            engineWatchdogs = watchdogThreads
          }
    release handle = do
      CappedCleanup.runCappedEngineCleanup
        [ mapM_ killThread (engineWatchdogs handle),
          killEngineProcessGroup (engineProcessGroup handle),
          mapM_
            closeEnginePipe
            [engineStdin handle, engineStdout handle, engineStderr handle]
        ]
        (waitForProcess (engineProcess handle))

    closeEnginePipe =
      mapM_
        ( \pipeHandle ->
            hClose pipeHandle
              `catch` \(_ :: SomeException) -> pure ()
        )

awaitEngineOutcome :: EngineHandle s -> IO EngineOutcome
awaitEngineOutcome handle = do
  exitCode <- waitForProcess (engineProcess handle)
  termination <- readIORef (engineTermination handle)
  pure $
    case termination of
      Just (CeilingBreached ceilingMib) -> EngineExceededCeiling ceilingMib
      Just (EnforcementUnavailable reason) -> EngineEnforcementUnavailable reason
      Just (OutputLimitExceeded outputStream) ->
        EngineOutputLimitExceeded outputStream
      Just (OutputCaptureFailed outputStream reason) ->
        EngineOutputCaptureFailed outputStream reason
      Nothing -> EngineExited exitCode

engineOutcomeExitCode :: EngineOutcome -> ExitCode
engineOutcomeExitCode outcome =
  case outcome of
    EngineExited exitCode -> exitCode
    EngineExceededCeiling _ -> ExitFailure 137
    EngineEnforcementUnavailable _ -> ExitFailure enforcementUnavailableExitCode
    EngineOutputLimitExceeded _ -> ExitFailure engineOutputFailureExitCode
    EngineOutputCaptureFailed _ _ -> ExitFailure engineOutputFailureExitCode

enforcementUnavailableExitCode :: Int
enforcementUnavailableExitCode = 70

engineOutputFailureExitCode :: Int
engineOutputFailureExitCode = 74

engineCreateProcess :: EngineCommand -> CreateProcess
engineCreateProcess command =
  case command of
    DirectEngineCommand executable arguments workingDirectory processEnvironment ->
      (proc executable arguments)
        { cwd = Just workingDirectory,
          env = Just processEnvironment
        }

withStdioPipes :: CreateProcess -> CreateProcess
withStdioPipes spec =
  spec
    { close_fds = True,
      create_group = True,
      std_in = CreatePipe,
      std_out = CreatePipe,
      std_err = CreatePipe
    }

ignoreSigPipe :: IO () -> IO ()
ignoreSigPipe action = action `catch` sigPipeHandler
  where
    sigPipeHandler :: IOException -> IO ()
    sigPipeHandler ioException =
      case ioException of
        IOError {ioe_type = ResourceVanished, ioe_errno = Just errno}
          | Errno errno == ePIPE -> pure ()
        _ -> throwIO ioException

failMissingPipes :: IO result
failMissingPipes =
  ioError (userError "capped engine subprocess did not expose the requested stdio pipes")

runCeilingWatchdog ::
  WatchdogSpec ->
  ProcessHandle ->
  CPid ->
  IORef (Maybe EnforcementTermination) ->
  IO ()
runCeilingWatchdog watchdog processHandle processGroup terminationRef =
  case watchdog of
    AppleFootprintWatchdog ceilingMib ->
      runAppleWatchdog ceilingMib processHandle processGroup terminationRef
    LinuxProcessGroupRssWatchdog ceilingMib ->
      runLinuxWatchdog ceilingMib processHandle processGroup terminationRef
    NvidiaVramWatchdog ceilingMib ->
      runNvidiaWatchdog ceilingMib processHandle processGroup terminationRef

runAppleWatchdog ::
  Int ->
  ProcessHandle ->
  CPid ->
  IORef (Maybe EnforcementTermination) ->
  IO ()
#if defined(darwin_HOST_OS)
runAppleWatchdog ceilingMib processHandle processGroup terminationRef = loop
  where
    ceilingBytes = mibToBytes ceilingMib
    loop = do
      sample <- FixedObserver.processGroupPhysicalFootprintBytes processGroup
      case sample of
        Right footprint
          | footprint > ceilingBytes ->
              terminateForWatchdog
                processHandle
                processGroup
                terminationRef
                (CeilingBreached ceilingMib)
          | otherwise -> continueIfRunning processHandle loop
        Left reason ->
          failSamplerIfRunning processHandle processGroup terminationRef reason
#else
runAppleWatchdog _ processHandle processGroup terminationRef =
  failSamplerIfRunning
    processHandle
    processGroup
    terminationRef
    "Apple physical-footprint observation is unavailable on this platform"
#endif

runLinuxWatchdog ::
  Int ->
  ProcessHandle ->
  CPid ->
  IORef (Maybe EnforcementTermination) ->
  IO ()
#if defined(darwin_HOST_OS)
runLinuxWatchdog _ processHandle processGroup terminationRef =
  failSamplerIfRunning
    processHandle
    processGroup
    terminationRef
    "Linux /proc process-group RSS enforcement is unavailable on this platform"
#else
runLinuxWatchdog ceilingMib processHandle processGroup terminationRef = loop
  where
    ceilingBytes = mibToBytes ceilingMib
    loop = do
      sample <- processGroupRssBytes processGroup
      case sample of
        Left reason ->
          failSamplerIfRunning processHandle processGroup terminationRef reason
        Right Nothing ->
          -- No live group member was observed. If the engine has actually
          -- exited this is the ordinary end of enforcement and
          -- 'failSamplerIfRunning' returns quietly. If it has *not* exited, the
          -- sampler cannot account for a process that is still running, which is
          -- the same class of loss as a `Left` and must fail closed. Returning
          -- unconditionally here — as this did — silently disabled enforcement
          -- for the rest of an execution that was still going, and the startup
          -- probe already treats the same observation as a failure.
          failSamplerIfRunning
            processHandle
            processGroup
            terminationRef
            "Linux /proc process-group RSS sampler observed no live group member for a running engine"
        Right (Just footprint)
          | footprint > ceilingBytes ->
              terminateForWatchdog
                processHandle
                processGroup
                terminationRef
                (CeilingBreached ceilingMib)
          | otherwise -> do
              threadDelay watchdogIntervalMicros
              loop
#endif

runNvidiaWatchdog ::
  Int ->
  ProcessHandle ->
  CPid ->
  IORef (Maybe EnforcementTermination) ->
  IO ()
#if defined(darwin_HOST_OS)
runNvidiaWatchdog _ processHandle processGroup terminationRef =
  failSamplerIfRunning
    processHandle
    processGroup
    terminationRef
    "NVIDIA per-process-group VRAM enforcement is unavailable on this platform"
#else
runNvidiaWatchdog ceilingMib processHandle processGroup terminationRef = loop
  where
    ceilingBytes = mibToBytes ceilingMib
    loop = do
      sample <- processGroupVramBytes processGroup
      case sample of
        Left reason ->
          failSamplerIfRunning processHandle processGroup terminationRef reason
        Right Nothing ->
          -- No live group member was observed. If the engine has exited this is
          -- the ordinary end of enforcement and 'failSamplerIfRunning' returns
          -- quietly; if it has not, the sampler cannot account for a process
          -- that is still running, which is the same loss class as a 'Left' and
          -- must fail closed rather than silently disable the VRAM ceiling.
          failSamplerIfRunning
            processHandle
            processGroup
            terminationRef
            "NVIDIA VRAM sampler observed no live group member for a running engine"
        Right (Just vramBytes)
          | vramBytes > ceilingBytes ->
              terminateForWatchdog
                processHandle
                processGroup
                terminationRef
                (CeilingBreached ceilingMib)
          | otherwise -> do
              threadDelay watchdogIntervalMicros
              loop
#endif

-- | Package-test seam for the real Linux watchdog. The seam accepts an
-- already-created grouped child, mints no execution authority, and exposes
-- only the typed terminal classification after the production loop returns.
linuxWatchdogOutcomeForTest ::
  Int ->
  ProcessHandle ->
  CPid ->
  IO (Maybe EngineOutcome)
linuxWatchdogOutcomeForTest ceilingMib processHandle processGroup = do
  terminationRef <- newIORef Nothing
  runLinuxWatchdog ceilingMib processHandle processGroup terminationRef
  termination <- readIORef terminationRef
  pure $
    case termination of
      Just (CeilingBreached observedCeilingMib) ->
        Just (EngineExceededCeiling observedCeilingMib)
      Just (EnforcementUnavailable reason) ->
        Just (EngineEnforcementUnavailable reason)
      Just (OutputLimitExceeded outputStream) ->
        Just (EngineOutputLimitExceeded outputStream)
      Just (OutputCaptureFailed outputStream reason) ->
        Just (EngineOutputCaptureFailed outputStream reason)
      Nothing -> Nothing

-- | Package-test seam for the real NVIDIA VRAM watchdog, mirroring
-- 'linuxWatchdogOutcomeForTest': an already-created grouped child in, the typed
-- terminal classification out, no execution authority minted.
nvidiaWatchdogOutcomeForTest ::
  Int ->
  ProcessHandle ->
  CPid ->
  IO (Maybe EngineOutcome)
nvidiaWatchdogOutcomeForTest ceilingMib processHandle processGroup = do
  terminationRef <- newIORef Nothing
  runNvidiaWatchdog ceilingMib processHandle processGroup terminationRef
  termination <- readIORef terminationRef
  pure $
    case termination of
      Just (CeilingBreached observedCeilingMib) ->
        Just (EngineExceededCeiling observedCeilingMib)
      Just (EnforcementUnavailable reason) ->
        Just (EngineEnforcementUnavailable reason)
      Just (OutputLimitExceeded outputStream) ->
        Just (EngineOutputLimitExceeded outputStream)
      Just (OutputCaptureFailed outputStream reason) ->
        Just (EngineOutputCaptureFailed outputStream reason)
      Nothing -> Nothing

#if defined(darwin_HOST_OS)
continueIfRunning :: ProcessHandle -> IO () -> IO ()
continueIfRunning processHandle continue = do
  maybeExitCode <- getProcessExitCode processHandle
  case maybeExitCode of
    Just _ -> pure ()
    Nothing -> do
      threadDelay watchdogIntervalMicros
      continue
#endif

failSamplerIfRunning ::
  ProcessHandle ->
  CPid ->
  IORef (Maybe EnforcementTermination) ->
  Text ->
  IO ()
failSamplerIfRunning processHandle processGroup terminationRef reason = do
  maybeExitCode <- getProcessExitCode processHandle
  case maybeExitCode of
    Just _ -> pure ()
    Nothing ->
      terminateForWatchdog
        processHandle
        processGroup
        terminationRef
        (EnforcementUnavailable reason)

terminateForWatchdog ::
  ProcessHandle ->
  CPid ->
  IORef (Maybe EnforcementTermination) ->
  EnforcementTermination ->
  IO ()
terminateForWatchdog processHandle processGroup terminationRef termination = do
  firstTermination <-
    atomicModifyIORef'
      terminationRef
      ( \current ->
          case current of
            Nothing -> (Just termination, True)
            Just _ -> (current, False)
      )
  when firstTermination $ do
    groupKill <- try (signalProcessGroup sigKILL processGroup)
    case groupKill of
      Right () -> pure ()
      Left (_ :: SomeException) ->
        terminateProcess processHandle `catch` \(_ :: SomeException) -> pure ()

killEngineProcessGroup :: CPid -> IO ()
killEngineProcessGroup processGroup = do
  killResult <-
    try @IOException
      (signalProcessGroup sigKILL processGroup)
  case killResult of
    Right () -> pure ()
    Left failure
      | isMissingProcessGroup failure -> pure ()
      | otherwise -> throwIO failure

isMissingProcessGroup :: IOException -> Bool
isMissingProcessGroup failure =
  let Errno missingProcessErrno = eSRCH
   in ioe_errno failure == Just missingProcessErrno

mibToBytes :: Int -> Word64
mibToBytes mib = fromIntegral mib * bytesPerMib

bytesPerMib :: Word64
bytesPerMib = 1048576

watchdogIntervalMicros :: Int
watchdogIntervalMicros = 50000

-- | Startup probe for the Apple physical-footprint sampler. A later sampling
-- failure is still terminal; this probe is not treated as permanent evidence.
verifyPhysicalFootprintSampler :: IO Bool
#if defined(darwin_HOST_OS)
verifyPhysicalFootprintSampler =
  FixedObserver.verifyPhysicalFootprintObserver
#else
verifyPhysicalFootprintSampler = pure False
#endif

-- | Startup probe for the Linux process-group RSS sampler. The per-execution
-- watchdog still treats every later sampling failure as terminal.
verifyProcessGroupRssSampler :: IO Bool
#if defined(darwin_HOST_OS)
verifyProcessGroupRssSampler = pure False
#else
verifyProcessGroupRssSampler = do
  processGroup <- getProcessGroupID
  sample <- processGroupRssBytes processGroup
  pure $
    case sample of
      Right (Just _) -> True
      Right Nothing -> False
      Left _ -> False
#endif

-- | Startup probe for the NVIDIA per-process-group VRAM sampler: the fixed
-- @nvidia-smi@ device-memory and compute-application queries must both
-- succeed, and the @\/proc@ group enumeration the sampler intersects them with
-- must work for this process's own group. The per-execution watchdog still
-- treats every later sampling failure as terminal.
verifyNvidiaVramSampler :: IO Bool
#if defined(darwin_HOST_OS)
verifyNvidiaVramSampler = pure False
#else
verifyNvidiaVramSampler = isRight <$> probeNvidiaVramSampler
#endif

-- | The same startup probe as 'verifyNvidiaVramSampler', but retaining the
-- reason it failed.
--
-- Sprint 6.44 originally exposed only the @Bool@, and refinement turned that
-- into a bare @NvidiaSamplerUnavailable <modelId>@ carrying no diagnosis. A
-- `linux-gpu` engine then crash-looped on exactly that error while every input
-- measured by hand inside the same pod — tool exit status, empty stderr, 30 ms
-- latency against a 5 s deadline, and a healthy @\/proc@ group walk — said the
-- probe should succeed. An enforcement probe that fails closed without saying
-- why forces a multi-hour cohort cycle per hypothesis, so the reason is now
-- carried and logged at the refinement boundary.
probeNvidiaVramSampler :: IO (Either Text Int)
#if defined(darwin_HOST_OS)
probeNvidiaVramSampler =
  pure (Left "NVIDIA VRAM enforcement is unavailable on this platform")
#else
probeNvidiaVramSampler = do
  observed <- FixedObserver.probeNvidiaVramObserver
  case observed of
    Left reason -> pure (Left ("NVIDIA device observation failed: " <> reason))
    Right totalMib
      | totalMib <= 0 ->
          pure (Left "NVIDIA device reported a non-positive total VRAM")
      | otherwise -> do
          processGroup <- getProcessGroupID
          members <- processGroupMembers processGroup
          pure $
            case members of
              Right (_ : _) -> Right totalMib
              Right [] ->
                Left
                  ( "the /proc process-group walk observed no live member for this daemon's own group ("
                      <> Text.pack (show (fromIntegral processGroup :: Integer))
                      <> ")"
                  )
              Left reason ->
                Left ("the /proc process-group walk failed: " <> reason)
#endif

-- | Observe the installed NVIDIA device's total VRAM (MiB) as the outer
-- envelope a VRAM grant must fit inside — the GPU analogue of the cgroup
-- memory limit read for the resident-set lane. 'Nothing' is an absent
-- observation, which the refinement boundary rejects rather than assumes.
observeNvidiaDeviceVramMib :: IO (Maybe Int)
observeNvidiaDeviceVramMib = do
  observed <- FixedObserver.observeNvidiaDeviceTotalMib
  pure $
    case observed of
      Right totalMib | totalMib > 0 -> Just totalMib
      _ -> Nothing

#if !defined(darwin_HOST_OS)

-- | Sum the device memory NVIDIA attributes to the child process group. NVML
-- resolves each compute context in the reading process's PID namespace and
-- omits the contexts it cannot resolve, so an engine pod observes exactly its
-- own namespace and never another container's. Membership comes from the same
-- @\/proc@ walk the resident-set lane uses, so the NVIDIA lane spawns one fixed
-- command per sample and performs no process discovery of its own.
--
-- 'Nothing' means no live group member was observed at all — the same
-- exit-race signal the resident-set sampler returns. A live member with no
-- compute context is @Just 0@: the child exists but has not allocated device
-- memory yet, which is an ordinary early-execution observation, not a loss.
processGroupVramBytes :: CPid -> IO (Either Text (Maybe Word64))
processGroupVramBytes processGroup = do
  memberResult <- processGroupMembers processGroup
  case memberResult of
    Left reason -> pure (Left reason)
    Right [] -> pure (Right Nothing)
    Right members -> do
      computeAppResult <- FixedObserver.observeNvidiaComputeApps
      pure $
        case computeAppResult of
          Left reason -> Left reason
          Right computeApps ->
            Just <$> FixedObserver.nvidiaComputeAppGroupBytes members computeApps

-- | Enumerate the live members of a process group from @\/proc@. Terminal
-- (zombie or dead) tasks still count as members — the group has not gone away
-- — but they hold no device memory. Enumeration, read, and parse failures are
-- enforcement failures, never an empty result.
processGroupMembers :: CPid -> IO (Either Text [CPid])
processGroupMembers processGroup = do
  procEntriesResult <- try (Directory.listDirectory "/proc")
  case procEntriesResult of
    Left (ioException :: IOException) ->
      pure
        ( Left
            ( "unable to enumerate /proc for VRAM enforcement: "
                <> Text.pack (show ioException)
            )
        )
    Right procEntries ->
      foldProcessEntries (filter (all isDigit) procEntries) []
  where
    targetGroup = fromIntegral processGroup :: Integer

    foldProcessEntries [] members = pure (Right (reverse members))
    foldProcessEntries (pidText : remaining) members = do
      statResult <- readProcFile ("/proc/" <> pidText <> "/stat")
      case statResult of
        Left reason -> pure (Left reason)
        Right Nothing -> foldProcessEntries remaining members
        Right (Just statContents) ->
          case parseProcessStateAndGroup statContents of
            Left reason -> pure (Left (procParseError pidText "stat" reason))
            Right (_, processGroupValue)
              | processGroupValue /= targetGroup ->
                  foldProcessEntries remaining members
              | otherwise ->
                  -- The directory name is only known to be all digits, so an
                  -- out-of-range value would silently truncate through
                  -- 'fromInteger' and could then falsely match a compute
                  -- application's pid. Enforcement fails closed on it instead.
                  case readInteger pidText of
                    Just processId
                      | processId > 0,
                        processId <= toInteger (maxBound :: CPid) ->
                          foldProcessEntries remaining (fromInteger processId : members)
                    _ ->
                      pure (Left (procParseError pidText "stat" "invalid process id"))

-- | Sum resident bytes for every live member of the child process group. A
-- vanished proc entry is an ordinary exit race; permission, enumeration, or
-- parse failures are enforcement failures and terminate the whole group.
processGroupRssBytes :: CPid -> IO (Either Text (Maybe Word64))
processGroupRssBytes processGroup = do
  procEntriesResult <- try (Directory.listDirectory "/proc")
  case procEntriesResult of
    Left (ioException :: IOException) ->
      pure (Left ("unable to enumerate /proc for RSS enforcement: " <> Text.pack (show ioException)))
    Right procEntries ->
      foldProcessEntries (filter (all isDigit) procEntries) False 0
  where
    targetGroup = fromIntegral processGroup :: Integer

    foldProcessEntries [] foundMember totalBytes =
      pure (Right (if foundMember then Just totalBytes else Nothing))
    foldProcessEntries (pidText : remaining) foundMember totalBytes = do
      statResult <- readProcFile ("/proc/" <> pidText <> "/stat")
      case statResult of
        Left reason -> pure (Left reason)
        Right Nothing -> foldProcessEntries remaining foundMember totalBytes
        Right (Just statContents) ->
          case parseProcessStateAndGroup statContents of
            Left reason -> pure (Left (procParseError pidText "stat" reason))
            Right (processState, processGroupValue)
              | processGroupValue /= targetGroup ->
                  foldProcessEntries remaining foundMember totalBytes
              | processStateIsTerminal processState ->
                  foldProcessEntries remaining True totalBytes
              | otherwise -> do
                  statusResult <- readProcFile ("/proc/" <> pidText <> "/status")
                  case statusResult of
                    Left reason -> pure (Left reason)
                    Right Nothing -> foldProcessEntries remaining foundMember totalBytes
                    Right (Just statusContents) -> do
                      residentResult <- readResidentBytes pidText statusContents
                      case residentResult of
                        Left reason -> pure (Left reason)
                        Right residentBytes ->
                          case checkedAdd totalBytes residentBytes of
                            Nothing -> pure (Left "process-group RSS total overflowed Word64")
                            Just nextTotal ->
                              foldProcessEntries remaining True nextTotal

    -- A task can discard its memory map before procfs publishes its terminal
    -- state. In that exit window @status@ legitimately has no @VmRSS@ even
    -- though the earlier @stat@ sample still said live. Re-read both files a
    -- bounded interval and accept zero only after disappearance or explicit
    -- terminal-state evidence. The interval matches the watchdog cadence so a
    -- scheduler-delayed exit gets several ordinary observation opportunities;
    -- a stable live or malformed task still fails closed after 200 ms.
    readResidentBytes pidText = retry 4
      where
        retry :: Int -> ByteString -> IO (Either Text Word64)
        retry retriesRemaining statusContents =
          case parseResidentSample statusContents of
            Left reason -> pure (Left (procParseError pidText "status" reason))
            Right (ResidentBytes residentBytes) -> pure (Right residentBytes)
            Right ResidentTerminal -> pure (Right 0)
            Right ResidentMissing -> do
              statResult <- readProcFile ("/proc/" <> pidText <> "/stat")
              case statResult of
                Left reason -> pure (Left reason)
                Right statContents ->
                  case missingResidentRecheckForTest statContents of
                    Left reason -> pure (Left (procParseError pidText "stat" reason))
                    Right True -> pure (Right 0)
                    Right False
                      | retriesRemaining <= 0 ->
                          pure (Left (procParseError pidText "status" "missing VmRSS"))
                      | otherwise -> do
                          threadDelay watchdogIntervalMicros
                          nextStatusResult <- readProcFile ("/proc/" <> pidText <> "/status")
                          case nextStatusResult of
                            Left reason -> pure (Left reason)
                            Right Nothing -> pure (Right 0)
                            Right (Just nextStatusContents) ->
                              retry (retriesRemaining - 1) nextStatusContents

readProcFile :: FilePath -> IO (Either Text (Maybe ByteString))
readProcFile path = do
  readResult <- try (ByteString.readFile path)
  pure $
    case readResult of
      Right contents -> Right (Just contents)
      Left (ioException :: IOException)
        | isDoesNotExistError ioException -> Right Nothing
        | otherwise ->
            Left
              ( "unable to read "
                  <> Text.pack path
                  <> " for RSS enforcement: "
                  <> Text.pack (show ioException)
              )

parseProcessStateAndGroup :: ByteString -> Either Text (Char, Integer)
parseProcessStateAndGroup contents =
  case elemIndices ')' (ByteString8.unpack contents) of
    [] -> Left "missing command terminator"
    closingParentheses ->
      case words (drop (last closingParentheses + 1) (ByteString8.unpack contents)) of
        stateText : _parentPid : processGroupText : _
          | [processState] <- stateText ->
              case readInteger processGroupText of
                Just processGroup -> Right (processState, processGroup)
                Nothing -> Left "invalid process-group id"
        _ -> Left "missing process state or process-group id"

data ResidentSample
  = ResidentBytes Word64
  | ResidentTerminal
  | ResidentMissing

parseResidentSample :: ByteString -> Either Text ResidentSample
parseResidentSample contents =
  case
      [ kibibytes
      | line <- ByteString8.lines contents,
        ["VmRSS:", kibibytes, "kB"] <- [words (ByteString8.unpack line)]
      ] of
    [kibibytesText] ->
      case readWord64 kibibytesText of
        Just kibibytes
          | kibibytes <= maxBound `div` bytesPerKib ->
              Right (ResidentBytes (kibibytes * bytesPerKib))
          | otherwise -> Left "VmRSS byte conversion overflow"
        Nothing -> Left "invalid VmRSS quantity"
    []
      | processHasTerminalStatus contents -> Right ResidentTerminal
      | otherwise -> Right ResidentMissing
    _ -> Left "duplicate VmRSS"

parseResidentBytes :: ByteString -> Either Text Word64
parseResidentBytes contents =
  case parseResidentSample contents of
    Left reason -> Left reason
    Right (ResidentBytes residentBytes) -> Right residentBytes
    Right ResidentTerminal -> Right 0
    Right ResidentMissing -> Left "missing VmRSS"

-- A process may cross from the live state observed in @stat@ to a zombie or
-- dead state before its @status@ file is read. Linux then legitimately omits
-- @VmRSS@. That terminal transition contributes zero resident bytes; a live
-- or malformed status without @VmRSS@ remains an enforcement failure.
processHasTerminalStatus :: ByteString -> Bool
processHasTerminalStatus contents =
  case
      [ processState
      | line <- ByteString8.lines contents,
        "State:" : [processState] : _ <- [words (ByteString8.unpack line)]
      ] of
    [processState] -> processState == 'Z' || processState == 'X'
    _ -> False

processStateIsTerminal :: Char -> Bool
processStateIsTerminal processState =
  processState == 'Z' || processState == 'X' || processState == 'x'

-- | Pure seam for the bounded exit-race recheck. A vanished task or an
-- explicitly terminal second @stat@ sample permits zero RSS; a still-live
-- task must be sampled again and eventually fails closed if @VmRSS@ remains
-- absent.
missingResidentRecheckForTest :: Maybe ByteString -> Either Text Bool
missingResidentRecheckForTest Nothing = Right True
missingResidentRecheckForTest (Just statContents) =
  processStateIsTerminal . fst <$> parseProcessStateAndGroup statContents

parseResidentBytesForTest :: ByteString -> Either Text Word64
parseResidentBytesForTest = parseResidentBytes

readInteger :: String -> Maybe Integer
readInteger value =
  case reads value of
    [(parsed, "")] -> Just parsed
    _ -> Nothing

readWord64 :: String -> Maybe Word64
readWord64 value =
  case reads value of
    [(parsed, "")] -> Just parsed
    _ -> Nothing

checkedAdd :: Word64 -> Word64 -> Maybe Word64
checkedAdd left right
  | maxBound - left < right = Nothing
  | otherwise = Just (left + right)

procParseError :: String -> Text -> Text -> Text
procParseError pidText fileName reason =
  "unable to parse /proc/"
    <> Text.pack pidText
    <> "/"
    <> fileName
    <> " for RSS enforcement: "
    <> reason

bytesPerKib :: Word64
bytesPerKib = 1024

#endif
