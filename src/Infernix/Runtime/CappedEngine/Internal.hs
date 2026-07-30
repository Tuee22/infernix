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
    NativeArtifactCache,
    NativeArtifactInvocation,
    NativeArtifactLaunchOutcome (..),
    PythonWorkerLaunchOutcome (..),
    nativeArtifactCache,
    nativeArtifactInvocation,
    runExecutableNativeArtifact,
    runExecutablePythonWorker,
    verifyPhysicalFootprintSampler,
    verifyProcessGroupRssSampler,
  )
where

import Control.Concurrent (ThreadId, forkFinally, forkIO, killThread, threadDelay)
import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, readMVar)
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
import Control.Monad (unless, void, when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString8
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Foreign.C.Error (Errno (Errno), ePIPE, eSRCH)
import GHC.IO.Exception (IOErrorType (ResourceVanished), IOException (IOError, ioe_errno, ioe_type))
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.Config (Paths (dataRoot, repoRoot))
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
import Infernix.Runtime.CappedEngine.DarwinObserver qualified as DarwinObserver
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
import System.FilePath (isAbsolute, (</>))
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

data WatchdogSpec
  = AppleFootprintWatchdog Int
  | LinuxProcessGroupRssWatchdog Int

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
  processEnvironment = do
    let installRoot = Artifact.artifactLaunchInstallRoot launchRequest
        entrypoint = Artifact.artifactLaunchEntrypoint launchRequest
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
            (renderNativeArtifactArguments installRoot invocation)
            installRoot
            artifactEnvironment
        )
        ""
    pure
      ( Artifact.ArtifactTerminalProcess
          (artifactProcessOutcome outcome)
          exitCode
          (ByteString8.pack stdoutOutput)
          (ByteString8.pack stderrOutput)
      )

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
  [String]
renderNativeArtifactArguments installRoot invocation =
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
-- grants; until a per-process NVIDIA sampler exists, it fails closed before
-- spawn rather than treating a pod limit or exit code as VRAM enforcement.
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
    (NvidiaVramAccountingEnforcer _, MemoryGrant (MemoryCeiling _)) ->
      Left "NVIDIA per-process VRAM enforcement is unavailable"

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
      sample <- DarwinObserver.processGroupPhysicalFootprintBytes processGroup
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
          pure ()
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
  DarwinObserver.verifyPhysicalFootprintObserver
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

#if !defined(darwin_HOST_OS)

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
              | processState == 'Z' ->
                  foldProcessEntries remaining True totalBytes
              | otherwise -> do
                  statusResult <- readProcFile ("/proc/" <> pidText <> "/status")
                  case statusResult of
                    Left reason -> pure (Left reason)
                    Right Nothing -> foldProcessEntries remaining foundMember totalBytes
                    Right (Just statusContents) ->
                      case parseResidentBytes statusContents of
                        Left reason -> pure (Left (procParseError pidText "status" reason))
                        Right residentBytes ->
                          case checkedAdd totalBytes residentBytes of
                            Nothing -> pure (Left "process-group RSS total overflowed Word64")
                            Just nextTotal ->
                              foldProcessEntries remaining True nextTotal

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

parseResidentBytes :: ByteString -> Either Text Word64
parseResidentBytes contents =
  case
      [ kibibytes
      | line <- ByteString8.lines contents,
        ["VmRSS:", kibibytes, "kB"] <- [words (ByteString8.unpack line)]
      ] of
    [kibibytesText] ->
      case readWord64 kibibytesText of
        Just kibibytes
          | kibibytes <= maxBound `div` bytesPerKib ->
              Right (kibibytes * bytesPerKib)
          | otherwise -> Left "VmRSS byte conversion overflow"
        Nothing -> Left "invalid VmRSS quantity"
    [] -> Left "missing VmRSS"
    _ -> Left "duplicate VmRSS"

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
