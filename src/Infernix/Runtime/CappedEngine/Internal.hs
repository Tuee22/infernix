{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Package-internal engine process kernel. This is the only module that may
-- inspect runtime resource proofs or use raw process-spawn primitives.
module Infernix.Runtime.CappedEngine.Internal
  ( EngineOutputStream (..),
    EngineOutcome (..),
    EngineExecutionPlan,
    newEngineExecutionPlan,
    engineExecutionRuntimePlan,
    withEngineExecutionPlan,
    NativeArtifactCache,
    NativeArtifactInvocation,
    NativeArtifactLaunchOutcome (..),
    PythonWorkerLaunchOutcome (..),
    BoundedEngineLaunch,
    boundedEngineLaunchCeiling,
    executableEngineCeiling,
    withEngineCeilingInstalled,
    appleRuntimeEnvironmentForTest,
    appleRuntimeEnvironmentNamesForTest,
    nativeArtifactCache,
    nativeArtifactInvocation,
    missingProcessGroupSettlementForTest,
    missingResidentRecheckForTest,
    appleWatchdogOutcomeForTest,
    linuxWatchdogOutcomeForTest,
    nvidiaWatchdogOutcomeForTest,
    scriptedWatchdogOutcomeForTest,
    scriptedWatchdogPeakForTest,
    unreportedEngineExitForTest,
    executableWatchdogCeilingsForTest,
    observeDeviceArenaAvailability,
    observeNvidiaDeviceFreeMibForTest,
    observeNvidiaDeviceVramMib,
    probeNvidiaVramSampler,
    parseResidentBytesForTest,
    llamaLaneSpecificArguments,
    renderNativeArtifactArgumentsForTest,
    renderNativeArtifactArgumentsForShapeForTest,
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
import Data.Char (isDigit)
import Data.Either (isRight)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef, writeIORef)
import Data.List (elemIndices)
import Data.List qualified as List
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe qualified as Maybe
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Foreign.C.Error (Errno (Errno), ePIPE, eSRCH)
import GHC.IO.Exception (IOErrorType (ResourceVanished), IOException (IOError, ioe_errno, ioe_type))
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.Config (Paths (dataRoot, repoRoot))
import Infernix.DescriptorSpace (requireBoundedDescriptorSpace)
import Infernix.DescriptorSpace qualified as DescriptorSpace
import Infernix.EngineBindings (canonicalEngineBindingForSelectedEngine)
import Infernix.Engines.Artifact qualified as Artifact
import Infernix.ExecutionPlan (RuntimePlan, executableModelGpuVramArenaMib)
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
    enforcerBudgetMib,
  )
-- The @\/proc@ resident-set reader is reachable only from the Linux pair, so
-- its imports belong to the branch that uses it. The fixed public-tool
-- observer kernel is reachable from both branches: the Apple footprint pair on
-- Darwin, the NVIDIA VRAM pair elsewhere.

import Infernix.Python qualified as Python
import Infernix.Runtime.CappedEngine.Ceiling qualified as Ceiling
import Infernix.Runtime.CappedEngine.Cleanup qualified as CappedCleanup
import Infernix.Runtime.CappedEngine.FixedObserver qualified as FixedObserver
import Infernix.Runtime.CappedEngine.OutputCapture qualified as OutputCapture
import Infernix.Runtime.CappedEngine.Projection qualified as Projection
import Infernix.Types
  ( EngineAdapterType (..),
    EngineBinding
      ( engineBindingAdapterId,
        engineBindingAdapterType
      ),
    InferenceRequest (inputObjectRef, inputText, requestModelId),
    ModelDescriptor
      ( family,
        modelExecutionShape,
        modelId,
        runtimeMode,
        selectedEngine
      ),
    ModelExecutionShape (..),
    ModelLoadStrategy (LoadResidentHost),
    Resource (..),
    RuntimeMode (AppleSilicon, LinuxCpu, LinuxGpu),
    resourceText,
  )
import System.Directory qualified as Directory
import System.Exit (ExitCode (..))
import System.FilePath (isAbsolute, takeDirectory, takeExtension, (</>))
import System.IO (Handle, hClose, hPutStr)
import System.IO.Error (isDoesNotExistError)
import System.Info (os)
import System.Posix.Process (getProcessGroupID)
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

-- | A process description whose constructor is hidden by the public facade.
-- The worker cannot recover the raw 'CreateProcess' used by the launch kernel.
data EngineCommand
  = DirectEngineCommand FilePath [String] FilePath [(String, String)]
  deriving (Eq, Show)

-- | Phase 4 Sprint 4.41 — an engine launch that has passed through the ceiling
-- installation region.
--
-- The constructor is hidden and 'withEngineCeilingInstalled' is the only mint,
-- so an engine that never passed through the region is not a term. This is the
-- same move the repository already makes for grants: the authority to start
-- something is a value someone had to mint, not a convention someone had to
-- follow.
data BoundedEngineLaunch = BoundedEngineLaunch EngineCommand Ceiling.InstalledCeiling
  deriving (Eq, Show)

-- | The installation region.
--
-- The operations are ordered, and the order is the point. The descriptor-space
-- bound is established first, because every spawn kernel sets @close_fds@ and
-- the pre-@exec@ descriptor walk is linear in the soft descriptor limit; then
-- the ceiling is rendered from the admitted grant; then the launch prefix lowers
-- both the soft and the hard data-segment limit and replaces itself with the
-- engine image. The limit is in force before the engine's first instruction and
-- cannot be raised back by the process it binds.
withEngineCeilingInstalled ::
  Ceiling.InstalledCeiling ->
  EngineCommand ->
  (BoundedEngineLaunch -> IO result) ->
  IO result
withEngineCeilingInstalled installed command action = do
  _ <- DescriptorSpace.requireBoundedDescriptorSpace "capped engine ceiling installation"
  action (BoundedEngineLaunch (applyCeilingPrefix installed command) installed)

-- | Prepend the launch prefix. A detection-only lane has none, so its command is
-- unchanged and its strength says so.
applyCeilingPrefix :: Ceiling.InstalledCeiling -> EngineCommand -> EngineCommand
applyCeilingPrefix installed command =
  case (Ceiling.installedCeilingArgumentPrefix installed, command) of
    ([], _) -> command
    (tool : leadingArguments, DirectEngineCommand executable arguments workingDirectory processEnvironment) ->
      DirectEngineCommand
        tool
        (leadingArguments <> (executable : arguments))
        workingDirectory
        processEnvironment

-- | The ceiling this launch installed, for the read-back comparison.
boundedEngineLaunchCeiling :: BoundedEngineLaunch -> Ceiling.InstalledCeiling
boundedEngineLaunchCeiling (BoundedEngineLaunch _ installed) = installed

-- | A total terminal engine outcome. Enforcement unavailability is distinct
-- from a measured ceiling breach: both fail closed, but only a measured breach
-- is reported as 'ModelMemoryLimitExceeded'.
data EngineOutcome
  = EngineExited ExitCode
  | -- | Phase 4 Sprint 4.37: the resource that breached, the ceiling installed
    -- for it, and the footprint observed above it. The resource is decided at
    -- grant-mint time from a nominal role that cannot be relabelled, so it is
    -- known statically at every breach site and is carried rather than
    -- re-derived one frame up.
    EngineExceededCeiling Resource Int Int
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
    nativeInvocationExecutionShape :: !ModelExecutionShape,
    nativeInvocationInput :: !NativeArtifactInput,
    nativeInvocationCache :: !(Maybe NativeArtifactCache),
    nativeInvocationOutputDirectory :: !(Maybe FilePath),
    nativeInvocationInputFile :: !(Maybe FilePath)
  }
  deriving (Eq, Show)

data NativeArtifactLaunchOutcome
  = NativeArtifactUnsupported !Text
  | NativeArtifactUnavailable
  | -- | Phase 6 Sprint 6.50: the rejection carries the install root and the
    -- validator's own reason. Discarding them cost a whole @linux-gpu@ cohort
    -- cycle: the daemon reported only that validation failed, so the reason
    -- had to be rediscovered by hand from the image, exactly as the
    -- reason-less @NvidiaSamplerUnavailable@ did in Sprint 6.44.
    NativeArtifactRejected !FilePath !String
  | NativeArtifactBusy
  | NativeArtifactInvocationRejected !String
  | NativeArtifactUseValidationFailed
  | -- | Phase 4 Sprint 4.43: the engine's own projection could not be obtained,
    -- so no ceiling was installed and no engine was started. It is a distinct
    -- outcome from a limit being exceeded for the same reason
    -- 'ModelRequirementUnderivable' is: the quantity is exactly what could not
    -- be established, so there is none to report.
    NativeArtifactProjectionRefused !Text
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
          nativeInvocationExecutionShape = modelExecutionShape descriptor,
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
  = -- | Phase 6 Sprint 6.50: the ceiling that was breached __and the footprint
    -- actually observed__. The observed value was measured at every breach site
    -- and then discarded, so a breach reported @required == available ==
    -- ceiling@ and said nothing about how far over the engine went — which is
    -- exactly the number needed to calibrate a declared footprint from a cohort
    -- rather than from a guess.
    --
    -- Phase 4 Sprint 4.37: the leading 'Resource' is what makes
    -- one shared termination slot attributable. 'withCappedEngine' forks every
    -- watchdog against a single 'IORef', and a @RuntimeGpuResources@ placement
    -- forks two; the single slot is correct — 'recordFirstTermination' is
    -- first-writer-wins, so the recorded value is the breach that actually
    -- terminated the group — but without a tag the value cannot say which loop
    -- wrote it.
    CeilingBreached Resource Int Int
  | EnforcementUnavailable Text
  | OutputLimitExceeded EngineOutputStream
  | OutputCaptureFailed EngineOutputStream Text

-- | A live refined plan together with its single-flight execution authority.
--
-- The constructor is hidden and the value is minted once, by
-- 'Infernix.Runtime.Enforcer.refineCompiledRuntimePlan'. The refined plan never
-- leaves that boundary beside a separable token, so a caller cannot mint or
-- substitute a second lock and obtain concurrent execution of the same plan
-- under independent authorities.
--
-- It is deliberately one lock for the whole plan rather than one per
-- executable. Serialization here is what bounds *total* resident memory to a
-- single admitted grant at a time; per-executable tokens would let two admitted
-- models run concurrently and exceed the host or pod budget the admission
-- decision was made against.
data EngineExecutionPlan = EngineExecutionPlan RuntimePlan (MVar ())

-- | Package-internal mint used only by the live refinement boundary (and the
-- property module that exercises the capability graph without host probes).
newEngineExecutionPlan :: RuntimePlan -> IO EngineExecutionPlan
newEngineExecutionPlan runtimePlan =
  EngineExecutionPlan runtimePlan <$> newMVar ()

-- | Read the immutable refined plan. The execution lock remains enclosed in the
-- same value and cannot be recovered or replaced.
engineExecutionRuntimePlan :: EngineExecutionPlan -> RuntimePlan
engineExecutionRuntimePlan (EngineExecutionPlan runtimePlan _) = runtimePlan

-- | Run one engine execution under its plan's enclosed authority. Exceptions
-- propagate with the token released, so a failed execution cannot wedge the
-- daemon.
withEngineExecutionPlan :: EngineExecutionPlan -> IO a -> IO a
withEngineExecutionPlan (EngineExecutionPlan _ token) action =
  withMVar token (const action)

-- | Phase 6 Sprint 6.51 — whether the admitted device arena can actually be
-- taken right now.
--
-- Admission is against capacity by doctrine: a competing tenant on the same
-- device reduces what is free without changing what is total, so it changes
-- nothing about what was admitted. What it changes is whether the arena can be
-- taken, and that difference is observed rather than assumed away. The reading
-- is taken inside the serialized execution region, immediately before the engine
-- starts, so a shortfall is a named refusal carrying the free bytes observed and
-- the arena required rather than a device allocation failure surfacing later as
-- an engine crash with two empty captured streams.
--
-- This is admission-adjacent rather than a second ceiling: it decides whether to
-- start, never how much the engine may take.
observeDeviceArenaAvailability :: Int -> IO (Either Text ())
observeDeviceArenaAvailability requiredMib = do
  observed <- FixedObserver.observeNvidiaDeviceFreeMib
  pure $
    case observed of
      Left reason ->
        Left ("the device's free memory could not be observed before launch: " <> reason)
      Right freeMib
        | freeMib >= requiredMib -> Right ()
        | otherwise ->
            Left
              ( "the device has "
                  <> Text.pack (show freeMib)
                  <> " MiB free against the "
                  <> Text.pack (show requiredMib)
                  <> " MiB arena this model was admitted for; a claimant this "
                  <> "machine did not start holds the difference"
              )

-- | Package-test seam retaining the exact free-device reading consumed by
-- 'observeDeviceArenaAvailability'. Cohort validation uses it to prove that a
-- real out-of-group allocation changed availability before checking that the
-- production refusal reports the same quantity. The observer remains the
-- fixed, closed @nvidia-smi@ specification; callers gain no command surface.
observeNvidiaDeviceFreeMibForTest :: IO (Either Text Int)
observeNvidiaDeviceFreeMibForTest = FixedObserver.observeNvidiaDeviceFreeMib

-- | Phase 4 Sprint 4.40 — the watchdog specification is indexed by the same
-- 'Resource' kind the grant is.
--
-- 'watchdogForGrant' matches an @EnforcedGrant resource@ — the resource is right
-- there in the type — and the retired flat specification then re-encoded by hand
-- what the index already said, at which point the loop had to be selected by
-- matching on the re-encoding. Here the sampler is chosen by the index, and a
-- breach carries the resource it breached because it never stopped carrying it.
data WatchdogSpec (resource :: Resource) where
  AppleFootprintWatchdog :: Int -> Int -> WatchdogSpec 'HostRam
  LinuxProcessGroupRssWatchdog :: Int -> Int -> WatchdogSpec 'PodRam
  NvidiaVramWatchdog :: Int -> Int -> WatchdogSpec 'NvidiaVram

-- | The heterogeneous list a placement's watchdogs form. A device placement runs
-- two loops over two different resources, so the list is existential in the
-- index while each element keeps its own.
data SomeWatchdogSpec where
  SomeWatchdogSpec :: WatchdogSpec resource -> SomeWatchdogSpec

-- | Runtime host selection for the sampler family. Keeping both constructors
-- reachable makes every watchdog, sampler, probe, and test seam typecheck on
-- every lane; the selected constructor only decides which family may execute.
data WatchdogHostLane
  = AppleWatchdogHostLane
  | LinuxWatchdogHostLane
  deriving (Eq, Show)

currentWatchdogHostLane :: WatchdogHostLane
currentWatchdogHostLane
  | os == "darwin" = AppleWatchdogHostLane
  | otherwise = LinuxWatchdogHostLane

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
runExecutableProcess ::
  ExecutableModel ->
  Ceiling.EngineCeilingProjection ->
  EngineCommand ->
  String ->
  IO (EngineOutcome, ExitCode, String, String)
runExecutableProcess executableModel projection command input = do
  arenaAvailable <- requireDeviceArenaAvailable executableModel
  let installed = executableEngineCeiling projection executableModel
  case (arenaAvailable, executableWatchdogs installed executableModel) of
    (Left reason, _) -> pure (unavailableTextResult reason)
    (_, Left reason) -> pure (unavailableTextResult reason)
    (Right (), Right watchdogs) ->
      withEngineCeilingInstalled installed command $ \launch ->
        withCappedEngine watchdogs launch $ \handle ->
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
                Artifact.ArtifactRejected rejectedRoot rejectionReason ->
                  NativeArtifactRejected rejectedRoot rejectionReason
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
  Python.PreparedPythonEnvironmentReadAuthority s ->
  Paths ->
  ExecutableModel ->
  Subprocess.SubprocessEnv ->
  ByteString ->
  IO PythonWorkerLaunchOutcome
runExecutablePythonWorker authority paths executableModel processEnvironment inputPayload =
  case canonicalPythonWorkerBinding executableModel of
    Left failure ->
      pure (PythonWorkerInvocationRejected failure)
    Right engineBinding -> do
      command <-
        resolvePythonWorkerCommand
          authority
          paths
          (executableModelRuntimeMode executableModel)
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
            && engineBindingAdapterType canonicalBinding == PythonStdio ->
            Right canonicalBinding
      _ ->
        Left
          ( "runtime-refined executable does not carry a canonical Python-stdio binding for "
              <> modelId descriptor
          )

executableModelRuntimeMode :: ExecutableModel -> RuntimeMode
executableModelRuntimeMode (ExecutableModel descriptor _engineBinding _routes _resources) =
  runtimeMode descriptor

resolvePythonWorkerCommand ::
  Python.PreparedPythonEnvironmentReadAuthority s ->
  Paths ->
  RuntimeMode ->
  EngineBinding ->
  Subprocess.SubprocessEnv ->
  IO EngineCommand
resolvePythonWorkerCommand authority paths requestedRuntime engineBinding processEnvironment = do
  perEnginePython <-
    either
      (ioError . userError)
      pure
      ( Python.preparedPythonEnvironmentReadInterpreter
          authority
          requestedRuntime
          engineBinding
      )
  pure
    ( DirectEngineCommand
        perEnginePython
        ["-m", adapterModule]
        (repoRoot paths)
        renderedEnvironment
    )
  where
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
        -- Phase 4 Sprint 4.43: the projection is taken before the ceiling is
        -- installed, because the ceiling is what it decides. A refusal here
        -- starts no engine at all.
        projectionOutcome <-
          resolveNativeEngineProjection
            executableModel
            invocation
            entrypoint
            installRoot
            artifactEnvironment
        case projectionOutcome of
          Left refusal ->
            pure (Artifact.ArtifactTerminalProjectionRefused refusal)
          Right projection -> do
            (outcome, exitCode, stdoutOutput, stderrOutput) <-
              runExecutableProcess
                executableModel
                projection
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

-- | Phase 4 Sprint 4.43 — ask the engine what it projects it needs.
--
-- The probe executable is resolved as a sibling of the validated entry object,
-- inside the same sealed immutable closure root the artifact's own evidence
-- binds, so the probe cannot be pointed anywhere the engine itself is not. It
-- runs through the ordinary engine launch with no per-execution ceiling: the
-- quantity it exists to correct cannot soundly bound the probe before the probe
-- reports its correction. The enclosing pod envelope, bounded output capture,
-- closed argument grammar, and sealed artifact closure bound this surface.
--
-- A refusal is fail-closed by construction: it does not fall back to the derived
-- quantity and does not launch unbounded, because the caller turns it into a
-- terminal outcome that starts no engine.
resolveNativeEngineProjection ::
  ExecutableModel ->
  NativeArtifactInvocation ->
  FilePath ->
  FilePath ->
  [(String, String)] ->
  IO (Either Text Ceiling.EngineCeilingProjection)
resolveNativeEngineProjection
  executableModel
  invocation
  entrypoint
  installRoot
  artifactEnvironment =
    case requireNativeArtifactCache invocation of
      _
        -- A projection only ever changes an /installed/ quantity: it widens the
        -- launch prefix and the read-back it is compared against, and it reaches
        -- nothing else. On a lane whose arm is detection-only there is no prefix
        -- and no read-back, so probing there would spend a process to change
        -- nothing — and would turn an engine payload that happens not to ship
        -- the projection tool into a refused row for no gain. The question is
        -- therefore asked exactly where its answer is used.
        | Ceiling.installedCeilingStrength unprojectedCeiling
            == Ceiling.CeilingDetectionOnly ->
            pure (Right Ceiling.NoEngineProjection)
      -- An adapter with no model cache has no checkpoint to project against.
      -- Every family that declares a projection is a checkpoint runner whose
      -- own invocation grammar already required that cache, so this arm is
      -- reached only by the families that declare none.
      Left _ -> pure (Right Ceiling.NoEngineProjection)
      Right cache ->
        case Projection.engineProjectionRequest
          (nativeInvocationAdapterId invocation)
          (nativeModelPayloadPath cache invocation)
          nativeExecution of
          Nothing -> pure (Right Ceiling.NoEngineProjection)
          Just request -> do
            let probeExecutable =
                  takeDirectory entrypoint
                    </> Projection.projectionExecutableName request
            probePresent <- Directory.doesFileExist probeExecutable
            if not probePresent
              then
                pure
                  ( Left
                      ( "the engine's projection tool is absent from the sealed "
                          <> "artifact closure at "
                          <> Text.pack probeExecutable
                      )
                  )
              else do
                (outcome, _probeExitCode, stdoutOutput, stderrOutput) <-
                  runProjectionProbeProcess
                    unprojectedCeiling
                    ( DirectEngineCommand
                        probeExecutable
                        (Projection.projectionArguments request)
                        installRoot
                        artifactEnvironment
                    )
                pure
                  ( classifyEngineProjection
                      outcome
                      stdoutOutput
                      stderrOutput
                  )
    where
      nativeExecution = llamaNativeExecution invocation
      unprojectedCeiling =
        executableEngineCeiling Ceiling.NoEngineProjection executableModel

-- | Phase 4 Sprint 4.43 — run one projection probe.
--
-- The probe passes through the installation region like every other engine
-- spawn, so the capability-gating lint sees what it expects, and the value it
-- passes through says plainly that nothing was installed. It runs no watchdog
-- for the same reason it installs no ceiling: both would be the model's own
-- derived quantity, and the probe exists precisely because that quantity may be
-- too small for the execution that runs. See 'Ceiling.projectionProbeCeiling'
-- for what bounds it instead.
runProjectionProbeProcess ::
  Ceiling.InstalledCeiling ->
  EngineCommand ->
  IO (EngineOutcome, ExitCode, String, String)
runProjectionProbeProcess unprojected command =
  withEngineCeilingInstalled probeCeiling command $ \launch ->
    withCappedEngine [] launch $ \handle ->
      case (engineStdin handle, engineStdout handle, engineStderr handle) of
        (Just stdinHandle, Just stdoutHandle, Just stderrHandle) ->
          withEngineOutputCaptures handle stdoutHandle stderrHandle $
            \stdoutCapture stderrCapture -> do
              ignoreSigPipe (hClose stdinHandle)
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
  where
    probeCeiling =
      Ceiling.projectionProbeCeiling
        (Ceiling.installedCeilingResource unprojected)
        (Ceiling.installedCeilingMib unprojected)

-- | Turn one probe run into a projection or a reason.
classifyEngineProjection ::
  EngineOutcome ->
  String ->
  String ->
  Either Text Ceiling.EngineCeilingProjection
classifyEngineProjection outcome stdoutOutput stderrOutput =
  case outcome of
    EngineExited ExitSuccess ->
      Ceiling.EngineProjectedMib
        <$> Projection.parseEngineProjectionMib (Text.pack stdoutOutput)
    EngineExited (ExitFailure code) ->
      Left
        ( "the engine's projection probe exited "
            <> Text.pack (show code)
            <> boundedProbeStandardError stderrOutput
        )
    EngineExceededCeiling resource ceilingMib observedMib ->
      Left
        ( "the engine's projection probe exceeded the "
            <> Text.pack (show ceilingMib)
            <> " MiB "
            <> resourceText resource
            <> " ceiling it ran under, holding "
            <> Text.pack (show observedMib)
            <> " MiB"
        )
    EngineEnforcementUnavailable reason ->
      Left ("the engine's projection probe could not be enforced: " <> reason)
    EngineOutputLimitExceeded _ ->
      Left "the engine's projection probe exceeded its bounded output capture"
    EngineOutputCaptureFailed _ reason ->
      Left
        ( "the engine's projection probe output could not be captured: "
            <> reason
        )

-- | A bounded slice of a failed probe's standard error, so a refusal names what
-- the tool said without carrying an unbounded upstream stream into a result.
boundedProbeStandardError :: String -> Text
boundedProbeStandardError captured
  | Text.null trimmed = ""
  | otherwise = ": " <> Text.take maximumProbeStandardErrorChars trimmed
  where
    trimmed = Text.strip (Text.pack captured)

maximumProbeStandardErrorChars :: Int
maximumProbeStandardErrorChars = 512

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
      let inherited = Subprocess.renderSubprocessEnv processEnvironment
      scratchRoot <-
        case lookup "TMPDIR" inherited of
          Just value | isAbsolute value -> pure value
          _ ->
            ioError
              ( userError
                  "the capped engine environment requires an absolute TMPDIR to hold a runtime cache outside the sealed artifact"
              )
      pure
        ( appleRuntimeEnvironment installRoot scratchRoot
            <> filter
              ((`notElem` appleRuntimeEnvironmentNames) . fst)
              inherited
        )
    LinuxCpu ->
      pure (Subprocess.renderSubprocessEnv processEnvironment)
    LinuxGpu ->
      pure (Subprocess.renderSubprocessEnv processEnvironment)

-- | The closed environment a validated Apple engine artifact runs under.
--
-- @PYTHONDONTWRITEBYTECODE@ stops the interpreter writing @.pyc@ files into the
-- sealed payload, but it does not stop every cache a real library keeps: numba,
-- which librosa imports, writes its compiled-function index and object files
-- into a @__pycache__@ directory beside the source it compiled, and honours only
-- its own cache-directory setting. Those writes land inside the generation, so
-- the payload digest stops matching the manifest and the artifact that served
-- one request is rejected on the next. The cache is therefore pointed outside
-- the generation, at the governed scratch root this run already carries, which
-- keeps the seal exact and still lets the cache do its job across runs.
appleRuntimeEnvironment :: FilePath -> FilePath -> [(String, String)]
appleRuntimeEnvironment installRoot scratchRoot =
  [ ("PYTHONHOME", installRoot </> "python-home"),
    ("DYLD_FRAMEWORK_PATH", installRoot </> "python-frameworks"),
    ( "DYLD_LIBRARY_PATH",
      (installRoot </> "native" </> "lib")
        <> ":"
        <> (installRoot </> "native" </> "libexec")
    ),
    ("PYTHONNOUSERSITE", "1"),
    ("PYTHONDONTWRITEBYTECODE", "1"),
    ("NUMBA_CACHE_DIR", scratchRoot </> "infernix-numba-cache")
  ]

-- | Test seams. The environment a sealed Apple artifact runs under is pure in
-- its two roots, and the pair of lists below must agree: a name this renders
-- that the filter does not know is a name the ambient environment can supply.
appleRuntimeEnvironmentForTest :: FilePath -> FilePath -> [(String, String)]
appleRuntimeEnvironmentForTest = appleRuntimeEnvironment

appleRuntimeEnvironmentNamesForTest :: [String]
appleRuntimeEnvironmentNamesForTest = appleRuntimeEnvironmentNames

appleRuntimeEnvironmentNames :: [String]
appleRuntimeEnvironmentNames =
  [ "PYTHONHOME",
    "DYLD_FRAMEWORK_PATH",
    "DYLD_LIBRARY_PATH",
    "PYTHONNOUSERSITE",
    "PYTHONDONTWRITEBYTECODE",
    "NUMBA_CACHE_DIR"
  ]

artifactProcessOutcome :: EngineOutcome -> Artifact.ArtifactProcessOutcome
artifactProcessOutcome outcome =
  case outcome of
    EngineExited exitCode ->
      Artifact.ArtifactProcessExited exitCode
    EngineExceededCeiling resource ceilingMib observedMib ->
      Artifact.ArtifactProcessExceededCeiling resource ceilingMib observedMib
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
    Artifact.ArtifactTerminalProjectionRefused reason ->
      NativeArtifactProjectionRefused reason
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
    Artifact.ArtifactProcessExceededCeiling resource ceilingMib observedMib ->
      EngineExceededCeiling resource ceilingMib observedMib
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

-- | The two llama.cpp flags whose correctness was lane-specific, retained as a
-- total function so a new lane cannot be added without deciding the question
-- for it.
--
-- Both flags are retired on every lane, each for a measured reason. The two
-- lanes run different llama.cpp builds from different sources — Linux the
-- image-pinned b9704 payload, Apple the Homebrew @llama.cpp@ formula that
-- @materialize-metal-engines@ seals under @native/bin@ — so each measurement
-- was taken against the binary that lane actually runs rather than inferred
-- from the other.
--
-- @--log-disable@ silences the runner's only failure channel: a failed model
-- load produces 0 bytes on both streams with it, and names the exact GGUF path
-- without it. That blindness is what made the first @linux-cpu@ cohort failure
-- undiagnosable. @--no-conversation@ is rejected outright by the post-split
-- @llama-cli@ and, under the @llama-completion@ front-end both targets now
-- name, would leak the chat-template marker into published output.
--
-- Apple was measured against Homebrew @llama.cpp@ build 9870 — well past the
-- b9704 split, and shipping @llama-completion@ in the same formula. The retired
-- Apple argv reproduced the Linux defect exactly: @llama-cli@ with
-- @--no-conversation --log-disable@ against a missing model exits 1 having
-- written 128 bytes of front-end complaint to *stdout*
-- (@--no-conversation is not supported by llama-cli / please use
-- llama-completion instead@) and 0 bytes to stderr, so a failure carried one
-- bit and a success would have published chat chrome as the model's answer.
-- Dropping @--log-disable@ restores 905 bytes naming the GGUF path, and
-- @llama-completion@ under the corrected argv exits 1 with 1019 bytes of
-- diagnostics and no unsupported-flag complaint.
-- | Phase 4 Sprint 4.43 — the execution literals the llama native lane runs
-- under, in one value.
--
-- The engine invocation and its projection probe both render from here, so the
-- projection is a statement about exactly the execution that runs. Two matching
-- literals would have been the same program with one extra way to be wrong: a
-- probe asked about a different context length reports a number about work the
-- machine will not do.
--
-- The cache-bearing operands come from the descriptor's carried execution
-- shape. The engine invocation and its pre-flight projection both consume this
-- one value, so admission, projection, and execution cannot silently choose
-- different context or generation bounds. Thread count and device-layer count
-- remain properties of this sealed CPU-native artifact binding; neither is a
-- second spelling of a field carried by 'ModelExecutionShape'.
llamaNativeExecution ::
  NativeArtifactInvocation ->
  Projection.LlamaNativeExecution
llamaNativeExecution invocation =
  Projection.LlamaNativeExecution
    { Projection.llamaExecutionContextLength = executionContextLength shape,
      Projection.llamaExecutionGenerationBound = executionGenerationBound shape,
      Projection.llamaExecutionThreads = 1,
      Projection.llamaExecutionGpuLayers = 0
    }
  where
    shape = nativeInvocationExecutionShape invocation

llamaLaneSpecificArguments :: RuntimeMode -> [String]
llamaLaneSpecificArguments runtimeModeValue =
  case runtimeModeValue of
    AppleSilicon -> []
    LinuxCpu -> []
    LinuxGpu -> []

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
        ( Projection.llamaNativeExecutionArguments
            (nativeModelPayloadPath cache invocation)
            (llamaNativeExecution invocation)
            <> [ "--prompt",
                 Text.unpack prompt,
                 "--no-display-prompt",
                 "--single-turn",
                 "--simple-io"
               ]
            <> llamaLaneSpecificArguments (nativeInvocationRuntimeMode invocation)
        )
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
renderNativeArtifactArgumentsForTest adapterId =
  renderNativeArtifactArgumentsForShapeForTest
    adapterId
    testNativeExecutionShape

renderNativeArtifactArgumentsForShapeForTest ::
  Text ->
  ModelExecutionShape ->
  Maybe FilePath ->
  Maybe FilePath ->
  Either String [String]
renderNativeArtifactArgumentsForShapeForTest
  adapterId
  executionShape
  maybeOutputDirectory
  maybeInputFile =
    renderNativeArtifactArguments
      "/opt/infernix/engines/test-adapter"
      NativeArtifactInvocation
        { nativeInvocationModelId = "test-model",
          nativeInvocationSelectedEngine = "test-engine",
          nativeInvocationFamily = "test-family",
          nativeInvocationAdapterId = adapterId,
          nativeInvocationRuntimeMode = LinuxCpu,
          nativeInvocationExecutionShape = executionShape,
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

testNativeExecutionShape :: ModelExecutionShape
testNativeExecutionShape =
  ModelExecutionShape
    { executionContextLength = 512,
      executionBatchSize = 1,
      executionGenerationBound = 32,
      executionCacheElementWidth = 2,
      executionLoadStrategy = LoadResidentHost
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
    "--generation-bound",
    show (executionGenerationBound (nativeInvocationExecutionShape invocation)),
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
-- | The Python-stdio launch. Phase 4 Sprint 4.43: this lane declares no
-- projection, because no supported Python engine family ships a tool that
-- reports what it will need before it allocates. Artifact derivation therefore
-- remains its admission quantity, while the admitted lane budget is the
-- installed execution bound and the provenance records both facts rather than
-- implying a projection was consulted.
runExecutableStdioEngine :: ExecutableModel -> EngineCommand -> ByteString -> IO (EngineOutcome, ExitCode, ByteString, ByteString)
runExecutableStdioEngine executableModel command input = do
  arenaAvailable <- requireDeviceArenaAvailable executableModel
  let installed = executableEngineCeiling Ceiling.NoEngineProjection executableModel
  case (arenaAvailable, executableWatchdogs installed executableModel) of
    (Left reason, _) -> pure (unavailableBinaryResult reason)
    (_, Left reason) -> pure (unavailableBinaryResult reason)
    (Right (), Right watchdogs) ->
      withEngineCeilingInstalled installed command $ \launch ->
        withCappedEngine watchdogs launch $ \handle ->
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

-- | Phase 4 Sprint 4.43 — the sampled backstop watches the quantity that was
-- actually installed.
--
-- Prevention and detection have to agree. Sprint 4.40 moved the Linux sampler to
-- the field the kernel limit charges for exactly that reason; a ceiling widened
-- by the engine's own projection while the sampler kept watching the narrower
-- artifact-derived quantity reopens the same disagreement from the other side,
-- and it does so in the direction that terminates a model the ceiling permits.
-- Measured on the cohort lane before this correction: an engine launched under a
-- 507 MiB installed ceiling was terminated at 54 MiB by a sampler still watching
-- 52 MiB. The resource the ceiling binds takes the installed quantity; every
-- other resource keeps its own grant, because no ceiling was installed for it.
executableWatchdogs ::
  Ceiling.InstalledCeiling ->
  ExecutableModel ->
  Either Text [SomeWatchdogSpec]
executableWatchdogs installed executable@(ExecutableModel _ _ _ resources) =
  case resources of
    RuntimeHostResources hostGrant ->
      (: []) <$> watchdogForGrant declaredMembers effectiveCeiling hostGrant
    RuntimePodResources podGrant ->
      (: []) <$> watchdogForGrant declaredMembers effectiveCeiling podGrant
    RuntimeGpuResources podGrant vramGrant -> do
      deviceArenaMib <- executableDeviceArenaMib executable
      podWatchdog <- watchdogForGrant declaredMembers effectiveCeiling podGrant
      vramWatchdog <- watchdogForDeviceArena declaredMembers deviceArenaMib vramGrant
      pure [podWatchdog, vramWatchdog]
  where
    declaredMembers = executableEngineMemberBound executable
    effectiveCeiling resource grantCeilingMib
      | Ceiling.installedCeilingResource installed == resource =
          max grantCeilingMib (Ceiling.installedCeilingMib installed)
      | otherwise = grantCeilingMib

-- | Phase 4 Sprint 4.40 — how many processes a placement's engine may run.
--
-- It is derived from the engine binding rather than authored beside it: a native
-- runner is one process image, and a Python stdio adapter is the interpreter
-- plus the bounded set of workers a framework starts under it. The number exists
-- so the loop's tree arithmetic states its premise; without it the sum has a
-- premise nobody wrote down.
executableEngineMemberBound :: ExecutableModel -> Int
executableEngineMemberBound (ExecutableModel _ binding _ _) =
  case engineBindingAdapterType binding of
    NativeProcessRunner -> nativeEngineMemberBound
    PythonStdio -> pythonEngineMemberBound

nativeEngineMemberBound :: Int
nativeEngineMemberBound = 1

-- | A Python adapter is the interpreter plus the workers a framework's own
-- dataloader or tokenizer pool starts under it. The bound is deliberately small:
-- a group that grows past it is an enforcement failure naming both numbers, not
-- a larger sum quietly accepted.
pythonEngineMemberBound :: Int
pythonEngineMemberBound = 8

-- | The bound the per-lane test seams use when they drive a production loop
-- against a fixture group they created themselves.
defaultEngineMemberBound :: Int
defaultEngineMemberBound = pythonEngineMemberBound

-- | Phase 4 Sprint 4.41 — the ceiling this placement's lane can install, over
-- the resident quantity it admitted.
--
-- A device grant is deliberately not a candidate: no kernel mechanism bounds
-- device memory on any supported lane, so the device column is admission, arena
-- sizing, and a sampled backstop, and never a ceiling.
executableEngineCeiling ::
  Ceiling.EngineCeilingProjection ->
  ExecutableModel ->
  Ceiling.InstalledCeiling
executableEngineCeiling projection executable@(ExecutableModel descriptor _binding _ resources) =
  case resources of
    RuntimeHostResources grant ->
      resolve HostRam grant
    RuntimePodResources grant ->
      resolve PodRam grant
    RuntimeGpuResources grant _ ->
      resolve PodRam grant
  where
    resolve :: forall resource. Resource -> EnforcedGrant resource -> Ceiling.InstalledCeiling
    resolve resource grant =
      case projection of
        Ceiling.NoEngineProjection ->
          Ceiling.resolveBudgetedEngineCeiling
            runtimeModeValue
            resource
            (enforcedGrantCeiling grant)
            (enforcedGrantBudget grant)
        Ceiling.EngineProjectedMib _ ->
          Ceiling.resolveEngineCeiling
            runtimeModeValue
            resource
            (enforcedGrantCeiling grant)
            projection

    -- Phase 4 Sprint 4.43 — which quantity this binding can actually be bounded
    -- at.
    --
    -- A checkpoint accounts for weights and a model cache, not the engine's
    -- runtime. That missing term is not peculiar to Python: measured on the
    -- pinned whisper.cpp small row, a 465 MiB legacy GGML object reaches roughly
    -- 748 MiB resident and a still larger data-segment extent. Where an upstream
    -- projection exists, its model-specific quantity widens the artifact grant.
    -- Where none exists, the already-admitted per-execution lane budget is the
    -- only constructed bound covering interpreter/runtime residency, compute
    -- graphs, allocator arenas, and input decoding. Admission still compares
    -- the artifact-derived requirement against observed machine capacity; only
    -- the installed/detected execution bound uses the lane budget, and its
    -- provenance says so explicitly.

    runtimeModeValue = runtimeMode descriptor
    _unusedExecutable = executable

enforcedGrantCeiling :: EnforcedGrant resource -> Int
enforcedGrantCeiling (EnforcedGrant _ (MemoryGrant (MemoryCeiling ceilingMib))) = ceilingMib

-- | The lane's own per-execution budget behind this grant's enforcer.
enforcedGrantBudget :: EnforcedGrant resource -> Int
enforcedGrantBudget (EnforcedGrant enforcer _) = enforcerBudgetMib enforcer

-- | Phase 6 Sprint 6.51 — a device-using placement observes the card's free
-- memory immediately before its engine starts; a placement with no device grant
-- observes nothing, because it takes no device arena.
requireDeviceArenaAvailable :: ExecutableModel -> IO (Either Text ())
requireDeviceArenaAvailable executable@(ExecutableModel _ _ _ resources) =
  case resources of
    RuntimeGpuResources _ _ ->
      case executableDeviceArenaMib executable of
        Left reason -> pure (Left reason)
        Right arenaMib -> observeDeviceArenaAvailability arenaMib
    _ -> pure (Right ())

-- | Phase 6 Sprint 6.51 — one device-sizing quantity for every consumer.
--
-- The worker request, the free-memory observation, and the namespace-local
-- sampled backstop must all name the arena the engine is actually sized by.
-- Retaining the artifact-derived grant for the latter two made a framework
-- engine correctly sized to the lane's per-execution budget fail its own
-- backstop at the smaller admission requirement. A GPU placement without an
-- arena is a construction defect and fails closed rather than falling back to
-- the grant.
executableDeviceArenaMib :: ExecutableModel -> Either Text Int
executableDeviceArenaMib executable =
  case executableModelGpuVramArenaMib executable of
    Nothing -> Left "a device-using executable carries no device arena"
    Just arenaMib
      | arenaMib <= 0 -> Left "the executable model carries a non-positive device arena"
      | otherwise -> Right arenaMib

watchdogForGrant ::
  Int ->
  (Resource -> Int -> Int) ->
  EnforcedGrant resource ->
  Either Text SomeWatchdogSpec
watchdogForGrant declaredMembers effectiveCeiling (EnforcedGrant enforcer grant) =
  case (enforcer, grant) of
    (HostFootprintWatchdogEnforcer _, MemoryGrant (MemoryCeiling ceilingMib)) ->
      positiveWatchdog
        (effectiveCeiling HostRam ceilingMib)
        (`AppleFootprintWatchdog` declaredMembers)
    (LinuxProcessGroupRssWatchdogEnforcer _, MemoryGrant (MemoryCeiling ceilingMib)) ->
      positiveWatchdog
        (effectiveCeiling PodRam ceilingMib)
        (`LinuxProcessGroupRssWatchdog` declaredMembers)
    (NvidiaVramAccountingEnforcer _, MemoryGrant (MemoryCeiling ceilingMib)) ->
      positiveWatchdog
        (effectiveCeiling NvidiaVram ceilingMib)
        (`NvidiaVramWatchdog` declaredMembers)

-- | The NVIDIA backstop watches the arena the engine receives, not the
-- artifact-derived requirement that admission compared with capacity. The
-- resource index makes this function device-only, so no host grant can be
-- substituted for the arena quantity.
watchdogForDeviceArena ::
  Int ->
  Int ->
  EnforcedGrant 'NvidiaVram ->
  Either Text SomeWatchdogSpec
watchdogForDeviceArena declaredMembers arenaMib (EnforcedGrant (NvidiaVramAccountingEnforcer _) _) =
  positiveWatchdog arenaMib (`NvidiaVramWatchdog` declaredMembers)

positiveWatchdog ::
  Int ->
  (Int -> WatchdogSpec resource) ->
  Either Text SomeWatchdogSpec
positiveWatchdog ceilingMib constructor
  | ceilingMib <= 0 =
      Left "the executable model carries a non-positive memory ceiling"
  | toInteger ceilingMib * toInteger bytesPerMib > toInteger (maxBound :: Word64) =
      Left "the executable model carries a memory ceiling too large to enforce"
  | otherwise = Right (SomeWatchdogSpec (constructor ceilingMib))

withCappedEngine :: [SomeWatchdogSpec] -> BoundedEngineLaunch -> (forall s. EngineHandle s -> IO result) -> IO result
withCappedEngine watchdogs (BoundedEngineLaunch command _) action =
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
      peakRef <- newIORef Map.empty
      watchdogThreads <-
        mapM
          ( \watchdog ->
              forkIO
                ( runCeilingWatchdog
                    watchdog
                    processHandle
                    processGroup
                    terminationRef
                    peakRef
                )
          )
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
  pure (engineOutcomeFromTermination exitCode termination)

-- | A non-zero exit has no memory classification unless a watchdog produced
-- explicit enforcement evidence. In particular, sampled proximity to an
-- installed ceiling is not an input: an ordinary engine fault after weights
-- are resident can produce the same peak as an allocation refusal.
engineOutcomeFromTermination :: ExitCode -> Maybe EnforcementTermination -> EngineOutcome
engineOutcomeFromTermination exitCode termination =
  case termination of
    Just (CeilingBreached resource ceilingMib observedMib) ->
      EngineExceededCeiling resource ceilingMib observedMib
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
    EngineExceededCeiling {} -> ExitFailure 137
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

-- | Phase 4 Sprint 4.40 — one sample, however it is taken.
--
-- The three retired loops were the same program written three times: sample,
-- compare against a ceiling, terminate the group on a breach, settle an exit
-- window on an absent group, fail closed on unreadable evidence. They differed
-- only in which quantity the sample reported, and each copy lived behind its own
-- conditional-compilation wall, so no gate on either platform could see two of
-- them at once. This record is what the one remaining loop takes instead.
data WatchdogSampler = WatchdogSampler
  { -- | The group's total for this resource, or 'Nothing' when a complete
    -- observation saw no live member.
    samplerObserveBytes :: CPid -> IO (Either Text (Maybe Word64)),
    -- | Whether the group still has a live member, for settling the exit
    -- window without re-taking the full measurement.
    samplerObservePresence :: CPid -> IO (Either Text Bool),
    -- | How many live members the group holds, so the tree arithmetic states
    -- its own premise instead of assuming it.
    samplerObserveMemberCount :: CPid -> IO (Either Text Int),
    samplerAbsentGroupReason :: Text
  }

-- | Phase 4 Sprint 4.44 — the highest complete observation each resource's loop
-- made, whether or not it ever breached.
--
-- A kernel-refused allocation is never resident, so the sampled backstop has
-- nothing above the ceiling to see and the loop's own peak is the only
-- observation that exists. Retaining it costs one 'IORef' write per sample and
-- is the difference between a diagnosis and a bare non-zero exit.
type EnginePeakObservations = IORef (Map Resource Int)

-- | Merge one observation into the peak record, keeping the larger.
recordPeakObservation :: EnginePeakObservations -> Resource -> Int -> IO ()
recordPeakObservation peakRef resource observedMib =
  atomicModifyIORef'
    peakRef
    (\peaks -> (Map.insertWith max resource observedMib peaks, ()))

-- | What the loop acts on: the group it watches, whether the engine has already
-- terminated, and how to terminate it.
data WatchdogTarget = WatchdogTarget
  { targetProcessGroup :: CPid,
    -- | Terminal evidence for the engine, which the two lanes read
    -- differently: the Apple loop asks the process handle it owns, and the
    -- Linux lanes read procfs, because the engine action is the sole reaper and
    -- a watchdog that also called @getProcessExitCode@ would contend with
    -- @waitForProcess@ exactly while the leader is a zombie.
    targetHasTerminated :: IO (Either Text Bool),
    targetTerminate :: EnforcementTermination -> IO (),
    targetFailEnforcement :: Text -> IO ()
  }

-- | The one ceiling loop. Every decision is kept once.
--
-- Breach above the ceiling, continue at or below it, settle the exit window
-- across four fresh observations at the sampling interval, resume on a member
-- reappearing, complete on a terminal or absent leader, and fail closed on a
-- stable live leader, on unreadable evidence, or on a group holding more
-- members than the placement declared.
runCeilingWatchdogLoop ::
  Resource ->
  Int ->
  Int ->
  EnginePeakObservations ->
  WatchdogSampler ->
  WatchdogTarget ->
  IO ()
runCeilingWatchdogLoop resource ceilingMib declaredMembers peakRef sampler target = loop
  where
    ceilingBytes = mibToBytes ceilingMib
    processGroup = targetProcessGroup target

    loop = do
      sample <- samplerObserveBytes sampler processGroup
      case sample of
        Left reason -> targetFailEnforcement target reason
        Right Nothing ->
          settleMissingProcessGroupWith
            (threadDelay watchdogIntervalMicros)
            missingProcessGroupSettlementRetries
            (samplerObservePresence sampler processGroup)
            (targetHasTerminated target)
            loop
            (targetFailEnforcement target)
            (samplerAbsentGroupReason sampler)
        Right (Just observedBytes) -> do
          -- Summing a residency field across a process group is sound only
          -- against a bounded member count. The bound exists in the placement;
          -- checking it here converts a silent premise into a fail-closed check.
          memberCount <- samplerObserveMemberCount sampler processGroup
          case memberCount of
            Left reason -> targetFailEnforcement target reason
            Right observedMembers -> do
              -- Phase 4 Sprint 4.44: every complete observation updates the
              -- peak, including the ones that neither breach nor fail. A
              -- kernel-refused allocation is never resident, so these are the
              -- only observations a refusal at the ceiling leaves behind.
              recordPeakObservation peakRef resource (bytesToMibCeiling observedBytes)
              classify observedMembers observedBytes

    classify observedMembers observedBytes
      | observedMembers > declaredMembers =
          targetFailEnforcement
            target
            ( "the engine process group holds "
                <> Text.pack (show observedMembers)
                <> " live members against the "
                <> Text.pack (show declaredMembers)
                <> " its placement declares, so the group total is not a bounded sum"
            )
      | observedBytes > ceilingBytes =
          targetTerminate
            target
            (CeilingBreached resource ceilingMib (bytesToMibCeiling observedBytes))
      | otherwise = do
          terminated <- targetHasTerminated target
          case terminated of
            Left reason -> targetFailEnforcement target reason
            Right True -> pure ()
            Right False -> do
              threadDelay watchdogIntervalMicros
              loop

runCeilingWatchdog ::
  SomeWatchdogSpec ->
  ProcessHandle ->
  CPid ->
  IORef (Maybe EnforcementTermination) ->
  EnginePeakObservations ->
  IO ()
runCeilingWatchdog (SomeWatchdogSpec watchdog) processHandle processGroup terminationRef peakRef =
  case watchdog of
    AppleFootprintWatchdog ceilingMib declaredMembers ->
      runAppleWatchdog ceilingMib declaredMembers processHandle processGroup terminationRef peakRef
    LinuxProcessGroupRssWatchdog ceilingMib declaredMembers ->
      runLinuxWatchdog ceilingMib declaredMembers processHandle processGroup terminationRef peakRef
    NvidiaVramWatchdog ceilingMib declaredMembers ->
      runNvidiaWatchdog ceilingMib declaredMembers processHandle processGroup terminationRef peakRef

-- | The Apple lane's target: the process handle is how this loop learns the
-- engine exited, because the fixed public-tool observer reports a footprint
-- rather than group membership.
appleWatchdogTarget ::
  ProcessHandle ->
  CPid ->
  IORef (Maybe EnforcementTermination) ->
  WatchdogTarget
appleWatchdogTarget processHandle processGroup terminationRef =
  WatchdogTarget
    { targetProcessGroup = processGroup,
      targetHasTerminated = Right . Maybe.isJust <$> getProcessExitCode processHandle,
      targetTerminate = terminateForWatchdog processHandle processGroup terminationRef,
      targetFailEnforcement = failSamplerIfRunning processHandle processGroup terminationRef
    }

runAppleWatchdog ::
  Int ->
  Int ->
  ProcessHandle ->
  CPid ->
  IORef (Maybe EnforcementTermination) ->
  EnginePeakObservations ->
  IO ()
runAppleWatchdog ceilingMib declaredMembers processHandle processGroup terminationRef peakRef =
  case currentWatchdogHostLane of
    AppleWatchdogHostLane ->
      runCeilingWatchdogLoop
        HostRam
        ceilingMib
        declaredMembers
        peakRef
        appleFootprintSampler
        (appleWatchdogTarget processHandle processGroup terminationRef)
    LinuxWatchdogHostLane ->
      failSamplerIfRunning
        processHandle
        processGroup
        terminationRef
        "Apple physical-footprint observation is unavailable on this platform"

runLinuxWatchdog ::
  Int ->
  Int ->
  ProcessHandle ->
  CPid ->
  IORef (Maybe EnforcementTermination) ->
  EnginePeakObservations ->
  IO ()
runLinuxWatchdog ceilingMib declaredMembers processHandle processGroup terminationRef peakRef =
  case currentWatchdogHostLane of
    AppleWatchdogHostLane ->
      failSamplerIfRunning
        processHandle
        processGroup
        terminationRef
        "Linux /proc process-group anonymous-residency enforcement is unavailable on this platform"
    LinuxWatchdogHostLane ->
      runLinuxWatchdogForGroup
        ceilingMib
        declaredMembers
        processGroup
        terminationRef
        peakRef

runLinuxWatchdogForGroup ::
  Int ->
  Int ->
  CPid ->
  IORef (Maybe EnforcementTermination) ->
  EnginePeakObservations ->
  IO ()
runLinuxWatchdogForGroup ceilingMib declaredMembers processGroup terminationRef peakRef =
  runCeilingWatchdogLoop
    PodRam
    ceilingMib
    declaredMembers
    peakRef
    linuxAnonymousResidencySampler
    (linuxWatchdogTarget processGroup terminationRef)

runNvidiaWatchdog ::
  Int ->
  Int ->
  ProcessHandle ->
  CPid ->
  IORef (Maybe EnforcementTermination) ->
  EnginePeakObservations ->
  IO ()
runNvidiaWatchdog ceilingMib declaredMembers processHandle processGroup terminationRef peakRef =
  case currentWatchdogHostLane of
    AppleWatchdogHostLane ->
      failSamplerIfRunning
        processHandle
        processGroup
        terminationRef
        "NVIDIA per-process-group VRAM enforcement is unavailable on this platform"
    LinuxWatchdogHostLane ->
      runNvidiaWatchdogForGroup
        ceilingMib
        declaredMembers
        processGroup
        terminationRef
        peakRef

runNvidiaWatchdogForGroup ::
  Int ->
  Int ->
  CPid ->
  IORef (Maybe EnforcementTermination) ->
  EnginePeakObservations ->
  IO ()
runNvidiaWatchdogForGroup ceilingMib declaredMembers processGroup terminationRef peakRef =
  runCeilingWatchdogLoop
    NvidiaVram
    ceilingMib
    declaredMembers
    peakRef
    nvidiaVramSampler
    (linuxWatchdogTarget processGroup terminationRef)

-- | Package-test seam for the shared loop, driven over a scripted sequence of
-- samples with no platform branch, so both lanes' gate sets run the same
-- assertions.
scriptedWatchdogOutcomeForTest ::
  Resource ->
  Int ->
  Int ->
  [Either Text (Maybe Word64)] ->
  [Either Text Int] ->
  IO (Maybe EngineOutcome)
scriptedWatchdogOutcomeForTest resource ceilingMib declaredMembers samples memberCounts =
  fst
    <$> runScriptedWatchdog resource ceilingMib declaredMembers samples memberCounts

-- | Phase 4 Sprint 4.44 — the same scripted loop, read for the peak it
-- recorded rather than for the outcome it reached.
--
-- The peak is what a kernel-refused allocation leaves behind, so a loop that
-- observed samples and retained none of them would make that refusal
-- undiagnosable. This is the assertion that keeps the recording alive.
scriptedWatchdogPeakForTest ::
  Resource ->
  Int ->
  Int ->
  [Either Text (Maybe Word64)] ->
  [Either Text Int] ->
  IO (Maybe Int)
scriptedWatchdogPeakForTest resource ceilingMib declaredMembers samples memberCounts =
  Map.lookup resource . snd
    <$> runScriptedWatchdog resource ceilingMib declaredMembers samples memberCounts

runScriptedWatchdog ::
  Resource ->
  Int ->
  Int ->
  [Either Text (Maybe Word64)] ->
  [Either Text Int] ->
  IO (Maybe EngineOutcome, Map Resource Int)
runScriptedWatchdog resource ceilingMib declaredMembers samples memberCounts = do
  terminationRef <- newIORef Nothing
  sampleQueue <- newIORef samples
  memberQueue <- newIORef memberCounts
  terminatedRef <- newIORef False
  let sampler =
        WatchdogSampler
          { samplerObserveBytes = \_ -> popScriptedValue sampleQueue (Right Nothing),
            samplerObservePresence = \_ -> pure (Right False),
            samplerObserveMemberCount = \_ -> popScriptedValue memberQueue (Right declaredMembers),
            samplerAbsentGroupReason = "scripted sampler observed no live group member"
          }
      target =
        WatchdogTarget
          { targetProcessGroup = 0,
            targetHasTerminated = Right <$> readIORef terminatedRef,
            targetTerminate = \termination -> do
              _ <- recordFirstTermination terminationRef termination
              writeIORef terminatedRef True,
            targetFailEnforcement = \reason -> do
              _ <- recordFirstTermination terminationRef (EnforcementUnavailable reason)
              writeIORef terminatedRef True
          }
  peakRef <- newIORef Map.empty
  runCeilingWatchdogLoop resource ceilingMib declaredMembers peakRef sampler target
  outcome <- classifyWatchdogTermination <$> readIORef terminationRef
  peaks <- readIORef peakRef
  pure (outcome, peaks)

-- | Package-test seam over the ceilings this placement's watchdogs are minted
-- with, so the agreement between what is installed and what is sampled is a
-- checked property rather than an inspected one.
executableWatchdogCeilingsForTest ::
  Ceiling.InstalledCeiling ->
  ExecutableModel ->
  Either Text [(Resource, Int)]
executableWatchdogCeilingsForTest installed executable =
  map watchdogResourceCeiling <$> executableWatchdogs installed executable

watchdogResourceCeiling :: SomeWatchdogSpec -> (Resource, Int)
watchdogResourceCeiling (SomeWatchdogSpec watchdog) =
  case watchdog of
    AppleFootprintWatchdog ceilingMib _ -> (HostRam, ceilingMib)
    LinuxProcessGroupRssWatchdog ceilingMib _ -> (PodRam, ceilingMib)
    NvidiaVramWatchdog ceilingMib _ -> (NvidiaVram, ceilingMib)

-- | Package-test seam for the no-evidence path. A plain exit carries its own
-- code and cannot be promoted to a typed memory failure by an observed peak.
unreportedEngineExitForTest :: ExitCode -> EngineOutcome
unreportedEngineExitForTest exitCode = engineOutcomeFromTermination exitCode Nothing

popScriptedValue :: IORef [a] -> a -> IO a
popScriptedValue queueRef exhausted =
  atomicModifyIORef' queueRef $ \case
    [] -> ([], exhausted)
    value : remaining -> (remaining, value)

-- | Package-test seam for the real Apple footprint watchdog.
--
-- Phase 4 Sprint 4.32. The Linux and NVIDIA seams take a group alone because
-- their production loops ignore the 'ProcessHandle'; the Apple loop does not —
-- the exit check is how it stops when the engine exits, and dropping it here
-- would exercise a different loop than production runs. The caller therefore
-- supplies the handle it already owns, and remains the process's single waiter:
-- the breach path signals the group and never reaps, so the fixture's own
-- @waitForProcess@ is the only reaper.
appleWatchdogOutcomeForTest ::
  Int ->
  ProcessHandle ->
  CPid ->
  IO (Maybe EngineOutcome)
appleWatchdogOutcomeForTest ceilingMib processHandle processGroup =
  case currentWatchdogHostLane of
    AppleWatchdogHostLane -> do
      terminationRef <- newIORef Nothing
      peakRef <- newIORef Map.empty
      runAppleWatchdog
        ceilingMib
        defaultEngineMemberBound
        processHandle
        processGroup
        terminationRef
        peakRef
      classifyWatchdogTermination <$> readIORef terminationRef
    LinuxWatchdogHostLane ->
      pure
        ( Just
            ( EngineEnforcementUnavailable
                "Apple physical-footprint observation is unavailable on this platform"
            )
        )

-- | The one translation from a recorded watchdog termination to the typed
-- terminal engine outcome, shared by every per-lane test seam.
classifyWatchdogTermination :: Maybe EnforcementTermination -> Maybe EngineOutcome
classifyWatchdogTermination termination =
  case termination of
    Just (CeilingBreached resource observedCeilingMib observedMib) ->
      Just (EngineExceededCeiling resource observedCeilingMib observedMib)
    Just (EnforcementUnavailable reason) ->
      Just (EngineEnforcementUnavailable reason)
    Just (OutputLimitExceeded outputStream) ->
      Just (EngineOutputLimitExceeded outputStream)
    Just (OutputCaptureFailed outputStream reason) ->
      Just (EngineOutputCaptureFailed outputStream reason)
    Nothing -> Nothing

linuxWatchdogOutcomeForTest ::
  Int ->
  CPid ->
  IO (Maybe EngineOutcome)
linuxWatchdogOutcomeForTest ceilingMib processGroup =
  case currentWatchdogHostLane of
    AppleWatchdogHostLane ->
      pure
        ( Just
            ( EngineEnforcementUnavailable
                "Linux /proc process-group anonymous-residency enforcement is unavailable on this platform"
            )
        )
    LinuxWatchdogHostLane -> do
      terminationRef <- newIORef Nothing
      peakRef <- newIORef Map.empty
      runLinuxWatchdogForGroup
        ceilingMib
        defaultEngineMemberBound
        processGroup
        terminationRef
        peakRef
      classifyWatchdogTermination <$> readIORef terminationRef

-- | Package-test seam for the real NVIDIA VRAM watchdog, mirroring
-- 'linuxWatchdogOutcomeForTest': an already-created grouped child in, the typed
-- terminal classification out, no execution authority minted.
nvidiaWatchdogOutcomeForTest ::
  Int ->
  CPid ->
  IO (Maybe EngineOutcome)
nvidiaWatchdogOutcomeForTest ceilingMib processGroup =
  case currentWatchdogHostLane of
    AppleWatchdogHostLane ->
      pure
        ( Just
            ( EngineEnforcementUnavailable
                "NVIDIA per-process-group VRAM enforcement is unavailable on this platform"
            )
        )
    LinuxWatchdogHostLane -> do
      terminationRef <- newIORef Nothing
      peakRef <- newIORef Map.empty
      runNvidiaWatchdogForGroup
        ceilingMib
        defaultEngineMemberBound
        processGroup
        terminationRef
        peakRef
      classifyWatchdogTermination <$> readIORef terminationRef

-- | The Apple lane's sampler: the fixed public-tool observer reports the
-- process group's physical footprint, and it reports no absence of its own, so
-- an absent group is inferred from the engine having exited.
appleFootprintSampler :: WatchdogSampler
appleFootprintSampler =
  WatchdogSampler
    { samplerObserveBytes = fmap (fmap Just) . FixedObserver.processGroupPhysicalFootprintBytes,
      samplerObservePresence = const (pure (Right False)),
      samplerObserveMemberCount = FixedObserver.processGroupMemberCount,
      samplerAbsentGroupReason =
        "Apple physical-footprint sampler observed no live group member for a running engine"
    }

-- | The Linux lane's sampler: anonymous residency from @\/proc@, which is the
-- quantity the installed data-segment ceiling charges.
linuxAnonymousResidencySampler :: WatchdogSampler
linuxAnonymousResidencySampler =
  WatchdogSampler
    { samplerObserveBytes = processGroupAnonymousResidencyBytes,
      samplerObservePresence = fmap (fmap (not . null)) . processGroupMembers,
      samplerObserveMemberCount = fmap (fmap length) . processGroupMembers,
      samplerAbsentGroupReason =
        "Linux /proc process-group anonymous-residency sampler observed no live group member for a running engine"
    }

-- | The device lane's sampler. Membership comes from the same @\/proc@ walk the
-- resident-set lane already uses, so the device lane spawns one fixed command
-- per sample and performs no process discovery of its own.
nvidiaVramSampler :: WatchdogSampler
nvidiaVramSampler =
  WatchdogSampler
    { samplerObserveBytes = processGroupVramBytes,
      samplerObservePresence = fmap (fmap (not . null)) . processGroupMembers,
      samplerObserveMemberCount = fmap (fmap length) . processGroupMembers,
      samplerAbsentGroupReason =
        "NVIDIA VRAM sampler observed no live group member for a running engine"
    }

-- | The Linux lanes' target: absence is observed from the group itself, so the
-- process handle plays no part.
linuxWatchdogTarget ::
  CPid ->
  IORef (Maybe EnforcementTermination) ->
  WatchdogTarget
linuxWatchdogTarget processGroup terminationRef =
  WatchdogTarget
    { targetProcessGroup = processGroup,
      targetHasTerminated = processLeaderIsTerminal processGroup,
      targetTerminate = terminateForLinuxWatchdog processGroup terminationRef,
      targetFailEnforcement = failLinuxSamplerIfTargetLive processGroup terminationRef
    }

-- | Observe the process-group leader without touching its 'ProcessHandle'.
-- The engine action is the sole process reaper; a watchdog that also calls
-- 'getProcessExitCode' can contend with 'waitForProcess' exactly while the
-- leader is a zombie. Procfs terminal state or disappearance is sufficient
-- evidence that memory enforcement no longer has a live target.
processLeaderIsTerminal :: CPid -> IO (Either Text Bool)
processLeaderIsTerminal processGroup = do
  let leaderPath = "/proc/" <> show (fromIntegral processGroup :: Integer) <> "/stat"
  statResult <- readProcFile leaderPath
  pure $
    case statResult of
      Left reason -> Left reason
      Right Nothing -> Right True
      Right (Just statContents) ->
        processStateIsTerminal . fst <$> parseProcessStateAndGroup statContents

-- | Shared bounded settlement state machine. Production supplies the real
-- watchdog delay, process-group observation, leader-terminal evidence, and
-- terminal callbacks; the package-test seam below supplies deterministic
-- sequences to cover every branch without racing two waiters on one
-- 'ProcessHandle'.
settleMissingProcessGroupWith ::
  IO () ->
  Int ->
  IO (Either Text Bool) ->
  IO (Either Text Bool) ->
  IO () ->
  (Text -> IO ()) ->
  Text ->
  IO ()
settleMissingProcessGroupWith delay retries observePresence processTerminated continue failWith reason =
  recheck retries
  where
    recheck retriesRemaining = do
      delay
      observed <- observePresence
      case observed of
        Left observationFailure -> failWith observationFailure
        Right True -> continue
        Right False
          | retriesRemaining > 1 -> recheck (retriesRemaining - 1)
          | otherwise -> do
              terminalEvidence <- processTerminated
              case terminalEvidence of
                Left terminalObservationFailure -> failWith terminalObservationFailure
                Right True -> pure ()
                Right False -> failWith reason

missingProcessGroupSettlementRetries :: Int
missingProcessGroupSettlementRetries = 4

-- | Deterministic seam over the production settlement state machine. @Right
-- True@ means the group reappeared and measurement resumed; @Right False@
-- means the process exit became visible; @Left reason@ is the exact terminal
-- enforcement failure.
missingProcessGroupSettlementForTest ::
  [Either Text Bool] ->
  [Either Text Bool] ->
  IO (Either Text Bool)
missingProcessGroupSettlementForTest observations exitStates = do
  observationsRef <- newIORef observations
  exitStatesRef <- newIORef exitStates
  outcomeRef <- newIORef Nothing
  settleMissingProcessGroupWith
    (pure ())
    missingProcessGroupSettlementRetries
    ( atomicModifyIORef' observationsRef $ \case
        [] -> ([], Left "test observation sequence exhausted")
        observation : rest -> (rest, observation)
    )
    ( atomicModifyIORef' exitStatesRef $ \case
        [] -> ([], Right False)
        terminalEvidence : rest -> (rest, terminalEvidence)
    )
    (atomicModifyIORef' outcomeRef (const (Just (Right True), ())))
    (\failure -> atomicModifyIORef' outcomeRef (const (Just (Left failure), ())))
    "process group remained absent while the engine handle remained live"
  Maybe.fromMaybe (Right False) <$> readIORef outcomeRef

-- | Fail closed without consulting the concurrently reaped 'ProcessHandle'.
-- A terminal or absent leader means there is no live target. Otherwise the
-- package-owned group is terminated without racing the action's handle reaper.
failLinuxSamplerIfTargetLive ::
  CPid ->
  IORef (Maybe EnforcementTermination) ->
  Text ->
  IO ()
failLinuxSamplerIfTargetLive processGroup terminationRef reason = do
  terminalResult <- processLeaderIsTerminal processGroup
  case terminalResult of
    Right True -> pure ()
    Right False ->
      terminateForLinuxWatchdog
        processGroup
        terminationRef
        (EnforcementUnavailable reason)
    Left terminalObservationFailure ->
      terminateForLinuxWatchdog
        processGroup
        terminationRef
        ( EnforcementUnavailable
            (reason <> "; leader observation failed: " <> terminalObservationFailure)
        )

terminateForLinuxWatchdog ::
  CPid ->
  IORef (Maybe EnforcementTermination) ->
  EnforcementTermination ->
  IO ()
terminateForLinuxWatchdog processGroup terminationRef termination = do
  firstTermination <- recordFirstTermination terminationRef termination
  when firstTermination $ do
    groupKill <- try @IOException (signalProcessGroup sigKILL processGroup)
    case groupKill of
      Right () -> pure ()
      Left failure
        | isMissingProcessGroup failure -> pure ()
        | otherwise -> throwIO failure

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
  firstTermination <- recordFirstTermination terminationRef termination
  when firstTermination $ do
    groupKill <- try (signalProcessGroup sigKILL processGroup)
    case groupKill of
      Right () -> pure ()
      Left (_ :: SomeException) ->
        terminateProcess processHandle `catch` \(_ :: SomeException) -> pure ()

recordFirstTermination ::
  IORef (Maybe EnforcementTermination) ->
  EnforcementTermination ->
  IO Bool
recordFirstTermination terminationRef termination =
  atomicModifyIORef'
    terminationRef
    ( \current ->
        case current of
          Nothing -> (Just termination, True)
          Just _ -> (current, False)
    )

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

-- | Phase 6 Sprint 6.50: report an observed footprint in the same unit the
-- ceiling is declared in. Rounded __up__, so a reported observation never
-- understates what was measured and a breach never reads as equal to the
-- ceiling it exceeded.
bytesToMibCeiling :: Word64 -> Int
bytesToMibCeiling bytes =
  fromIntegral ((bytes + bytesPerMib - 1) `div` bytesPerMib)

bytesPerMib :: Word64
bytesPerMib = 1048576

watchdogIntervalMicros :: Int
watchdogIntervalMicros = 50000

-- | Startup probe for the Apple physical-footprint sampler. A later sampling
-- failure is still terminal; this probe is not treated as permanent evidence.
verifyPhysicalFootprintSampler :: IO Bool
verifyPhysicalFootprintSampler =
  case currentWatchdogHostLane of
    AppleWatchdogHostLane -> FixedObserver.verifyPhysicalFootprintObserver
    LinuxWatchdogHostLane -> pure False

-- | Startup probe for the Linux process-group RSS sampler. The per-execution
-- watchdog still treats every later sampling failure as terminal.
verifyProcessGroupRssSampler :: IO Bool
verifyProcessGroupRssSampler =
  case currentWatchdogHostLane of
    AppleWatchdogHostLane -> pure False
    LinuxWatchdogHostLane -> do
      processGroup <- getProcessGroupID
      sample <- processGroupAnonymousResidencyBytes processGroup
      pure $
        case sample of
          Right (Just _) -> True
          Right Nothing -> False
          Left _ -> False

-- | Startup probe for the NVIDIA per-process-group VRAM sampler: the fixed
-- @nvidia-smi@ device-memory and compute-application queries must both
-- succeed, and the @\/proc@ group enumeration the sampler intersects them with
-- must work for this process's own group. The per-execution watchdog still
-- treats every later sampling failure as terminal.
verifyNvidiaVramSampler :: IO Bool
verifyNvidiaVramSampler =
  case currentWatchdogHostLane of
    AppleWatchdogHostLane -> pure False
    LinuxWatchdogHostLane -> isRight <$> probeNvidiaVramSampler

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
probeNvidiaVramSampler =
  case currentWatchdogHostLane of
    AppleWatchdogHostLane ->
      pure (Left "NVIDIA VRAM enforcement is unavailable on this platform")
    LinuxWatchdogHostLane -> do
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
-- (zombie or dead) tasks are completion evidence, not enforceable members.
-- Enumeration, read, and parse failures are enforcement failures, never an
-- empty result.
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
            Right (processState, processGroupValue)
              | processGroupValue /= targetGroup ->
                  foldProcessEntries remaining members
              | processStateIsTerminal processState ->
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
processGroupAnonymousResidencyBytes :: CPid -> IO (Either Text (Maybe Word64))
processGroupAnonymousResidencyBytes processGroup = do
  procEntriesResult <- try (Directory.listDirectory "/proc")
  case procEntriesResult of
    Left (ioException :: IOException) ->
      pure (Left ("unable to enumerate /proc for RSS enforcement: " <> Text.pack (show ioException)))
    Right procEntries ->
      foldProcessEntries (filter (all isDigit) procEntries) False 0
  where
    targetGroup = fromIntegral processGroup :: Integer

    foldProcessEntries [] foundLiveMember totalBytes =
      pure (Right (if foundLiveMember then Just totalBytes else Nothing))
    foldProcessEntries (pidText : remaining) foundLiveMember totalBytes = do
      statResult <- readProcFile ("/proc/" <> pidText <> "/stat")
      case statResult of
        Left reason -> pure (Left reason)
        Right Nothing -> foldProcessEntries remaining foundLiveMember totalBytes
        Right (Just statContents) ->
          case parseProcessStateAndGroup statContents of
            Left reason -> pure (Left (procParseError pidText "stat" reason))
            Right (processState, processGroupValue)
              | processGroupValue /= targetGroup ->
                  foldProcessEntries remaining foundLiveMember totalBytes
              | processStateIsTerminal processState ->
                  foldProcessEntries remaining foundLiveMember totalBytes
              | otherwise -> do
                  statusResult <- readProcFile ("/proc/" <> pidText <> "/status")
                  case statusResult of
                    Left reason -> pure (Left reason)
                    Right Nothing -> foldProcessEntries remaining foundLiveMember totalBytes
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
    -- state. In that exit window @status@ legitimately has no @RssAnon@ even
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
                          pure (Left (procParseError pidText "status" "missing RssAnon"))
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

-- The @\/proc@ sampling kernel above executes only on Linux, but it is compiled
-- unconditionally so every lane typechecks the sampler implementation. The
-- parsers below are pure text functions over its formats and the unit suite
-- exercises them on either host.

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

-- | Phase 4 Sprint 4.40 — the sampled field is @RssAnon@, the anonymous
-- residency the installed data-segment ceiling charges.
--
-- The retired sampler read @VmRSS@, which counts file-backed and shared
-- resident pages that the ceiling charges for none of. Kernel and sampler were
-- therefore bounding two different quantities and agreeing only because the
-- difference was usually small; the mapped weight file is exactly the case where
-- it is not small, and streaming a model from a mapped artifact is exactly what
-- this lane does. A @status@ block carrying @VmRSS@ but no @RssAnon@ is an
-- enforcement failure, not a reason to fall back to the old field.
parseResidentSample :: ByteString -> Either Text ResidentSample
parseResidentSample contents =
  case [ kibibytes
       | line <- ByteString8.lines contents,
         ["RssAnon:", kibibytes, "kB"] <- [words (ByteString8.unpack line)]
       ] of
    [kibibytesText] ->
      case readWord64 kibibytesText of
        Just kibibytes
          | kibibytes <= maxBound `div` bytesPerKib ->
              Right (ResidentBytes (kibibytes * bytesPerKib))
          | otherwise -> Left "RssAnon byte conversion overflow"
        Nothing -> Left "invalid RssAnon quantity"
    []
      | processHasTerminalStatus contents -> Right ResidentTerminal
      | otherwise -> Right ResidentMissing
    _ -> Left "duplicate RssAnon"

parseResidentBytes :: ByteString -> Either Text Word64
parseResidentBytes contents =
  case parseResidentSample contents of
    Left reason -> Left reason
    Right (ResidentBytes residentBytes) -> Right residentBytes
    Right ResidentTerminal -> Right 0
    Right ResidentMissing -> Left "missing RssAnon"

-- A process may cross from the live state observed in @stat@ to a zombie or
-- dead state before its @status@ file is read. Linux then legitimately omits
-- @RssAnon@. That terminal transition contributes zero resident bytes; a live
-- or malformed status without @RssAnon@ remains an enforcement failure.
processHasTerminalStatus :: ByteString -> Bool
processHasTerminalStatus contents =
  case [ processState
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
-- task must be sampled again and eventually fails closed if @RssAnon@ remains
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
