{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

-- | Package-internal kernel for the fixed public-tool memory observers: the
-- Apple @\/usr\/bin\/top@ plus @\/usr\/bin\/footprint@ physical-footprint pair
-- and the NVIDIA @\/usr\/bin\/nvidia-smi@ VRAM pair. Callers cannot supply an
-- executable, arguments, environment, or working directory — the request
-- vocabulary is a closed enum and 'FixedObserverSpec' is unexported. The raw
-- process authority and cleanup operations stay enclosed in this module.
module Infernix.Runtime.CappedEngine.FixedObserver
  ( FixedObserverKernelTest (..),
    NvidiaComputeApp (..),
    nvidiaComputeAppGroupBytes,
    observeNvidiaComputeApps,
    observeNvidiaDeviceFreeMib,
    observeNvidiaDeviceTotalMib,
    parseFootprintPhysicalBytes,
    parseNvidiaComputeApps,
    parseNvidiaDeviceTotalMib,
    parseTopProcessGroupLiveMembersAbsent,
    parseTopProcessGroupMembers,
    parseTopProcessGroupSamplingMembers,
    probeNvidiaVramObserver,
    probePhysicalFootprintObserver,
    processGroupHasNoLiveMembers,
    processGroupMemberCount,
    processGroupPhysicalFootprintBytes,
    runFixedObserverFixtureModeIfRequested,
    runFixedObserverKernelTest,
    verifyNvidiaVramObserver,
    verifyPhysicalFootprintObserver,
  )
where

import Control.Concurrent
  ( ThreadId,
    forkIO,
    forkIOWithUnmask,
    killThread,
    yield,
  )
import Control.Concurrent.MVar
  ( MVar,
    newEmptyMVar,
    putMVar,
    readMVar,
    takeMVar,
  )
import Control.Exception
  ( IOException,
    SomeAsyncException,
    SomeException,
    catch,
    displayException,
    fromException,
    mask,
    throwIO,
    toException,
    try,
  )
import Control.Monad (foldM, unless, void, when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString8
import Data.Char (isDigit)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List qualified as List
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import GHC.Clock (getMonotonicTimeNSec)
import Infernix.DescriptorSpace (requireBoundedDescriptorSpace)
import Infernix.Error
  ( onExceptionPreservingPrimary,
    runCleanupsPreservingFailures,
  )
import Infernix.ProcessIdentity
  ( ProcessBirthIdentity,
    dropInheritedProcessIdentity,
    parseProcessBirthIdentity,
    readProcessBirthIdentity,
    registerCurrentProcessIdentity,
    renderProcessBirthIdentity,
  )
import System.Directory (makeAbsolute)
import System.Environment (getArgs, getExecutablePath)
import System.Exit (ExitCode (..), exitWith)
import System.IO
  ( Handle,
    hClose,
    hFlush,
    hIsClosed,
    hPutStr,
    stderr,
    stdout,
  )
import System.IO.Error (isDoesNotExistError, isPermissionError)
import System.Info (os)
import System.Posix.Process
  ( getProcessGroupID,
    getProcessGroupIDOf,
    getProcessID,
  )
import System.Posix.Signals
  ( nullSignal,
    raiseSignal,
    sigCONT,
    sigKILL,
    sigSTOP,
    signalProcessGroup,
  )
import System.Posix.Types (CPid)
import System.Process
  ( CreateProcess
      ( close_fds,
        create_group,
        cwd,
        env,
        std_err,
        std_in,
        std_out
      ),
    ProcessHandle,
    StdStream (CreatePipe, Inherit),
    -- infernix-lint: non-engine-process-site
    createProcess,
    getPid,
    proc,
    terminateProcess,
    -- infernix-lint: non-engine-process-site
    waitForProcess,
  )
import System.Timeout (timeout)

data FixedObserverKernelTest
  = ObserverNormalCompletion
  | ObserverNonzeroCompletion
  | ObserverTimeoutCleanup
  | ObserverSynchronousExceptionCleanup
  | ObserverAsynchronousCancellationCleanup
  | ObserverStoppedGroupCleanup
  | ObserverDescendantGroupCleanup
  | ObserverOutputBoundsCleanup
  | ObserverMemberTurnoverRestart
  | ObserverLiveMemberFailure
  | ObserverTerminalMemberFailure
  | ObserverMembershipRecheckFailure
  deriving (Bounded, Enum, Eq, Show)

data FixedObserverRequest
  = DiscoverProcessGroup CPid
  | MeasureProcessFootprint CPid
  | QueryNvidiaComputeApps
  | QueryNvidiaDeviceMemory
  | -- | Phase 6 Sprint 6.51: what the card currently has free, as distinct from
    -- what it contains. Admission is against capacity by doctrine, so a
    -- competing tenant changes nothing about what was admitted; what it changes
    -- is whether the admitted arena can actually be taken.
    QueryNvidiaDeviceFreeMemory

-- | The one closed host selection for the fixed observer. Both lanes remain
-- ordinary reachable Haskell values, so every compiler invocation typechecks
-- every fixed request and specification under @-Wall -Werror@. The selection
-- changes only which public-tool family may execute on the current host.
data FixedObserverLane
  = AppleFixedObserverLane
  | NvidiaFixedObserverLane
  deriving (Eq, Show)

currentFixedObserverLane :: FixedObserverLane
currentFixedObserverLane
  | os == "darwin" = AppleFixedObserverLane
  | otherwise = NvidiaFixedObserverLane

data FixedObserverSpec = FixedObserverSpec
  { observerExecutable :: FilePath,
    observerArguments :: [String],
    observerLabel :: String,
    observerStdoutLimit :: Int,
    observerRequiresFixtureGate :: Bool
  }

newtype ObserverDeadline = ObserverDeadline Word64

data DrainCapture = DrainCapture
  { drainBytes :: ByteString,
    drainOverflowed :: Bool
  }

data CapturedStreams = CapturedStreams
  { capturedStdout :: Either SomeException DrainCapture,
    capturedStderr :: Either SomeException DrainCapture
  }

data ObserverRun
  = ObserverCompleted ExitCode CapturedStreams
  | ObserverTimedOut CapturedStreams

-- Possession of this value means the public process API created a fresh group
-- whose leader is still owned by an unreaped ProcessHandle. Keeping the leader
-- unreaped prevents PID and process-group reuse until cleanup is complete.
data OwnedObserverGroup = OwnedObserverGroup
  { ownedObserverProcess :: ProcessHandle,
    ownedObserverProcessGroup :: CPid
  }

data SpawnedObserver = SpawnedObserver
  { spawnedObserverInput :: Handle,
    spawnedObserverOutput :: Handle,
    spawnedObserverError :: Handle,
    spawnedObserverGroup :: OwnedObserverGroup
  }

data ActiveObserver = ActiveObserver
  { activeObserverSpawned :: SpawnedObserver,
    activeObserverStdoutThread :: ThreadId,
    activeObserverStderrThread :: ThreadId,
    activeObserverStdoutResult :: MVar (Either SomeException DrainCapture),
    activeObserverStderrResult :: MVar (Either SomeException DrainCapture)
  }

data ObserverSpawnEvidence = ObserverSpawnEvidence
  { observerSpawnProcessId :: CPid,
    observerSpawnBirthIdentity :: Maybe ProcessBirthIdentity
  }

-- | Prove through the fixed complete @/usr/bin/top@ snapshot that a retained
-- process-group identity has no live members. Darwin omits an unreaped zombie
-- leader from @top@ and answers @kill(-pgid, 0)@ with @EPERM@, so this is the
-- pre-reap live-member proof. The owner then crosses a masked leader-reap
-- transition and must not treat the reusable numeric PGID as evidence.
processGroupHasNoLiveMembers :: CPid -> IO (Either Text Bool)
processGroupHasNoLiveMembers processGroup =
  case currentFixedObserverLane of
    AppleFixedObserverLane ->
      captureSynchronousFailure "Apple process-group live-member observation failed" $ do
        deadline <- deadlineFromNow observerSampleTimeoutMicros
        output <- runFixedObserverRequest deadline (DiscoverProcessGroup processGroup)
        pure (output >>= parseTopProcessGroupLiveMembersAbsent processGroup)
    NvidiaFixedObserverLane ->
      pure (Left "Apple process-group live-member observation is unavailable on this platform")

-- | Phase 4 Sprint 4.40 — how many live members the group holds.
--
-- The shared sampling loop sums a per-process residency field across a group,
-- and that sum is a bounded quantity only against a bounded member count. This
-- is the Apple lane's half of that check; it reuses the same fixed public-tool
-- discovery the footprint sample already performs and adds no caller-supplied
-- command specification.
processGroupMemberCount :: CPid -> IO (Either Text Int)
processGroupMemberCount processGroup =
  case currentFixedObserverLane of
    AppleFixedObserverLane ->
      captureSynchronousFailure "Apple process-group member-count observation failed" $ do
        deadline <- deadlineFromNow observerSampleTimeoutMicros
        discovered <- discoverProcessGroupMembers deadline processGroup
        pure (fmap length discovered)
    NvidiaFixedObserverLane ->
      pure (Left "Apple process-group member-count observation is unavailable on this platform")

processGroupPhysicalFootprintBytes :: CPid -> IO (Either Text Word64)
processGroupPhysicalFootprintBytes processGroup =
  case currentFixedObserverLane of
    AppleFixedObserverLane ->
      captureSynchronousFailure "Apple physical-footprint observation failed" $ do
        deadline <- deadlineFromNow observerSampleTimeoutMicros
        discovered <- discoverProcessGroupMembers deadline processGroup
        case discovered of
          Left reason -> pure (Left reason)
          Right members ->
            sampleCompleteProcessGroupSnapshotWith
              (observeProcessGroupMembers deadline processGroup)
              (measureProcessFootprint deadline)
              members
    NvidiaFixedObserverLane ->
      pure (Left "Apple physical-footprint observation is unavailable on this platform")

-- | Sum one complete process-group membership snapshot. A member can exit
-- after @top@ publishes the snapshot but before @footprint@ opens that PID. A
-- failed member is therefore rechecked through another complete snapshot. If
-- it has gone, every partial byte count is discarded and sampling restarts
-- from the refreshed membership; if it remains live, the observer failure is
-- preserved. Production supplies observations and measurements that all share
-- one fixed 'ObserverDeadline', so repeated turnover cannot extend the sample.
sampleCompleteProcessGroupSnapshotWith ::
  IO (Either Text [CPid]) ->
  (CPid -> IO (Either Text Word64)) ->
  [CPid] ->
  IO (Either Text Word64)
sampleCompleteProcessGroupSnapshotWith observeMembers measureMember initialMembers
  | null initialMembers =
      pure (Left "Apple top output omitted every live process-group member")
  | otherwise = sampleMembers initialMembers 0
  where
    sampleMembers [] total = pure (Right total)
    sampleMembers (processId : remaining) total = do
      sampled <- measureMember processId
      case sampled of
        Left footprintFailure -> do
          refreshed <- observeMembers
          case refreshed of
            Left membershipFailure ->
              pure
                ( Left
                    ( footprintFailure
                        <> "; Apple process-group membership recheck failed: "
                        <> membershipFailure
                    )
                )
            Right refreshedMembers
              | processId `elem` refreshedMembers ->
                  pure (Left footprintFailure)
              | null refreshedMembers ->
                  pure (Left footprintFailure)
              | otherwise ->
                  sampleMembers refreshedMembers 0
        Right physicalBytes ->
          case checkedAddWord64 total physicalBytes of
            Nothing ->
              pure
                (Left "Apple process-group physical-footprint total overflowed Word64")
            Just nextTotal ->
              sampleMembers remaining nextTotal

verifyPhysicalFootprintObserver :: IO Bool
verifyPhysicalFootprintObserver = do
  observed <- probePhysicalFootprintObserver
  pure $
    case observed of
      Right physicalBytes -> physicalBytes > 0
      Left _ -> False

probePhysicalFootprintObserver :: IO (Either Text Word64)
probePhysicalFootprintObserver =
  case currentFixedObserverLane of
    AppleFixedObserverLane ->
      captureSynchronousFailure "Apple physical-footprint startup probe failed" $ do
        processId <- getProcessID
        processGroup <- getProcessGroupID
        deadline <- deadlineFromNow observerSampleTimeoutMicros
        discovered <- discoverProcessGroupMembers deadline processGroup
        case discovered of
          Left reason -> pure (Left reason)
          Right members
            | processId `notElem` members ->
                pure
                  ( Left
                      "Apple process-group discovery omitted the current process"
                  )
            | otherwise -> measureProcessFootprint deadline processId
    NvidiaFixedObserverLane ->
      pure (Left "Apple physical-footprint observation is unavailable on this platform")

-- | One NVIDIA compute application as @nvidia-smi@ attributes it. The process
-- id is reported in the *caller's* PID namespace: NVML resolves each compute
-- context against the reading process's namespace and omits the contexts it
-- cannot resolve, so an engine pod observes exactly its own namespace's
-- compute applications and never another container's.
data NvidiaComputeApp = NvidiaComputeApp
  { nvidiaComputeAppProcessId :: CPid,
    nvidiaComputeAppUsedMib :: Word64
  }
  deriving (Eq, Show)

-- | Observe every NVIDIA compute application visible in this PID namespace.
-- The caller intersects the result with the engine process group it already
-- enumerates from @\/proc@; this observer deliberately performs no group
-- discovery of its own, so the NVIDIA lane spawns one fixed command per sample
-- rather than the Darwin lane's per-member pair.
observeNvidiaComputeApps :: IO (Either Text [NvidiaComputeApp])
observeNvidiaComputeApps =
  case currentFixedObserverLane of
    AppleFixedObserverLane ->
      pure (Left "NVIDIA compute-application observation is unavailable on this platform")
    NvidiaFixedObserverLane -> do
      deadline <- deadlineFromNow observerSampleTimeoutMicros
      output <- runFixedObserverRequest deadline QueryNvidiaComputeApps
      pure (output >>= parseNvidiaComputeApps)

-- | Observe the installed NVIDIA device's total VRAM (MiB). This is the outer
-- envelope a VRAM grant must fit inside, the GPU analogue of the pod cgroup
-- memory limit read for the resident-set lane.
-- | Phase 6 Sprint 6.51 — what the device currently has free.
--
-- Serialization is what makes this observation worth taking: one engine process
-- per machine and one execution at a time means the only claimant that can move
-- the number between the observation and the allocation is one this repository
-- did not start, which is exactly the claimant a refusal must name instead of
-- assuming absent.
observeNvidiaDeviceFreeMib :: IO (Either Text Int)
observeNvidiaDeviceFreeMib =
  case currentFixedObserverLane of
    AppleFixedObserverLane ->
      pure (Left "NVIDIA device free-memory observation is unavailable on this platform")
    NvidiaFixedObserverLane -> do
      deadline <- deadlineFromNow observerSampleTimeoutMicros
      output <- runFixedObserverRequest deadline QueryNvidiaDeviceFreeMemory
      pure (output >>= parseNvidiaDeviceTotalMib)

observeNvidiaDeviceTotalMib :: IO (Either Text Int)
observeNvidiaDeviceTotalMib =
  case currentFixedObserverLane of
    AppleFixedObserverLane ->
      pure (Left "NVIDIA device observation is unavailable on this platform")
    NvidiaFixedObserverLane -> do
      deadline <- deadlineFromNow observerSampleTimeoutMicros
      output <- runFixedObserverRequest deadline QueryNvidiaDeviceMemory
      pure (output >>= parseNvidiaDeviceTotalMib)

-- | Startup probe for the NVIDIA VRAM sampler. Both fixed requests must
-- succeed: the device envelope must be positive and the compute-application
-- query must parse. An empty compute-application list is a valid observation —
-- no compute context exists yet at probe time — so it is not a probe failure.
-- The per-execution watchdog still treats every later sampling failure as
-- terminal; this probe is an observation, not permanent evidence.
probeNvidiaVramObserver :: IO (Either Text Int)
probeNvidiaVramObserver =
  case currentFixedObserverLane of
    AppleFixedObserverLane ->
      pure (Left "NVIDIA VRAM observation is unavailable on this platform")
    NvidiaFixedObserverLane -> do
      observedTotal <- observeNvidiaDeviceTotalMib
      case observedTotal of
        Left reason -> pure (Left reason)
        Right totalMib
          | totalMib <= 0 ->
              pure (Left "NVIDIA device reported a non-positive total VRAM")
          | otherwise -> do
              computeApps <- observeNvidiaComputeApps
              pure (totalMib <$ computeApps)

verifyNvidiaVramObserver :: IO Bool
verifyNvidiaVramObserver = do
  observed <- probeNvidiaVramObserver
  pure $
    case observed of
      Right totalMib -> totalMib > 0
      Left _ -> False

-- | Discover the group's members for a sample.
--
-- An empty snapshot is not absence. @top@ samples over an interval and can
-- publish one that omits a member which is live both before and after it —
-- the same turnover the failed-member recheck already handles from the other
-- direction. Converting that into an unavailable enforcer terminates a healthy
-- inference run, so an empty snapshot asks the authoritative liveness question
-- instead: a group with no live member left is terminal evidence the caller
-- settles, and a group that still has one is resampled inside the same fixed
-- deadline. The deadline is what bounds this, so the refusal still arrives, and
-- it now names an emptiness that outlived the group's own liveness. There is no
-- pause between attempts and none is needed: each attempt is a complete @top@
-- snapshot and a liveness probe, so the loop is paced by the observations it
-- makes rather than by a wait this kernel is not allowed to take.
discoverProcessGroupMembers ::
  ObserverDeadline ->
  CPid ->
  IO (Either Text [CPid])
discoverProcessGroupMembers deadline processGroup = do
  observed <- observeProcessGroupMembers deadline processGroup
  case observed of
    Left reason -> pure (Left reason)
    Right members
      | not (null members) -> pure (Right members)
      | otherwise -> do
          absent <- processGroupHasNoLiveMembers processGroup
          case absent of
            Left reason -> pure (Left reason)
            Right True -> pure (Right members)
            Right False -> do
              remaining <- remainingDeadlineMicros deadline
              if remaining <= 0
                then
                  pure
                    ( Left
                        "Apple top output omitted every live process-group member for the whole observation deadline while the group remained live"
                    )
                else discoverProcessGroupMembers deadline processGroup

-- Keep the empty membership shape available to a failed-member recheck: it is
-- terminal evidence for the caller to settle alongside relay closure, never a
-- fabricated zero-byte sample.
observeProcessGroupMembers ::
  ObserverDeadline ->
  CPid ->
  IO (Either Text [CPid])
observeProcessGroupMembers deadline processGroup = do
  output <- runFixedObserverRequest deadline (DiscoverProcessGroup processGroup)
  pure (output >>= parseTopProcessGroupMemberRows processGroup)

measureProcessFootprint ::
  ObserverDeadline ->
  CPid ->
  IO (Either Text Word64)
measureProcessFootprint deadline processId = do
  output <- runFixedObserverRequest deadline (MeasureProcessFootprint processId)
  pure (output >>= parseFootprintPhysicalBytes)

runFixedObserverRequest ::
  ObserverDeadline ->
  FixedObserverRequest ->
  IO (Either Text ByteString)
runFixedObserverRequest deadline request =
  captureSynchronousFailure
    (Text.pack (observerLabel spec) <> " failed")
    ( do
        observerRun <- runFixedObserver deadline spec (const (pure ()))
        pure (successfulObserverOutput spec observerRun)
    )
  where
    spec = fixedObserverSpec request

-- | The closed command catalog. Every arm hardcodes an absolute public-tool
-- path and a literal argument vector; the only variable text is a process id
-- rendered as a decimal integer. Enforcement must not be redirectable, so the
-- executable is pinned here rather than resolved from the host-tools manifest
-- that the operator-facing prerequisite probes use.
fixedObserverSpec :: FixedObserverRequest -> FixedObserverSpec
fixedObserverSpec request =
  case request of
    DiscoverProcessGroup processGroup ->
      FixedObserverSpec
        { observerExecutable = "/usr/bin/top",
          observerArguments =
            [ "-l",
              "1",
              "-F",
              "-R",
              "-stats",
              "pid,pgrp,mem"
            ],
          observerLabel =
            "fixed /usr/bin/top process-group observer for "
              <> show (fromIntegral processGroup :: Integer),
          observerStdoutLimit = maximumTopOutputBytes,
          observerRequiresFixtureGate = False
        }
    MeasureProcessFootprint processId ->
      FixedObserverSpec
        { observerExecutable = "/usr/bin/footprint",
          observerArguments =
            [ "-f",
              "bytes",
              "--noCategories",
              "-pid",
              show (fromIntegral processId :: Integer)
            ],
          observerLabel =
            "fixed /usr/bin/footprint observer for "
              <> show (fromIntegral processId :: Integer),
          observerStdoutLimit = maximumFootprintOutputBytes,
          observerRequiresFixtureGate = False
        }
    QueryNvidiaComputeApps ->
      FixedObserverSpec
        { observerExecutable = nvidiaSmiExecutable,
          observerArguments =
            [ "--query-compute-apps=pid,used_gpu_memory",
              "--format=csv,noheader,nounits"
            ],
          observerLabel = "fixed " <> nvidiaSmiExecutable <> " compute-application observer",
          observerStdoutLimit = maximumNvidiaOutputBytes,
          observerRequiresFixtureGate = False
        }
    QueryNvidiaDeviceMemory ->
      FixedObserverSpec
        { observerExecutable = nvidiaSmiExecutable,
          observerArguments =
            [ "--query-gpu=memory.total",
              "--format=csv,noheader,nounits"
            ],
          observerLabel = "fixed " <> nvidiaSmiExecutable <> " device-memory observer",
          observerStdoutLimit = maximumNvidiaOutputBytes,
          observerRequiresFixtureGate = False
        }
    QueryNvidiaDeviceFreeMemory ->
      FixedObserverSpec
        { observerExecutable = nvidiaSmiExecutable,
          observerArguments =
            [ "--query-gpu=memory.free",
              "--format=csv,noheader,nounits"
            ],
          observerLabel = "fixed " <> nvidiaSmiExecutable <> " device-free-memory observer",
          observerStdoutLimit = maximumNvidiaOutputBytes,
          observerRequiresFixtureGate = False
        }

successfulObserverOutput ::
  FixedObserverSpec ->
  ObserverRun ->
  Either Text ByteString
successfulObserverOutput spec observerRun =
  case observerRun of
    ObserverTimedOut captured ->
      Left
        ( Text.pack (observerLabel spec)
            <> " exceeded its total monotonic deadline"
            <> renderCapturedDiagnostic captured
        )
    ObserverCompleted exitCode captured -> do
      stdoutCapture <- requireDrainCapture "stdout" (capturedStdout captured)
      stderrCapture <- requireDrainCapture "stderr" (capturedStderr captured)
      when
        (drainOverflowed stdoutCapture)
        ( Left
            ( Text.pack (observerLabel spec)
                <> " exceeded its stdout bound"
            )
        )
      when
        (drainOverflowed stderrCapture)
        ( Left
            ( Text.pack (observerLabel spec)
                <> " exceeded its stderr bound"
            )
        )
      unless
        (ByteString8.all isObserverWhitespace (drainBytes stderrCapture))
        ( Left
            ( Text.pack (observerLabel spec)
                <> " emitted unexpected stderr: "
                <> renderBytes (drainBytes stderrCapture)
            )
        )
      case exitCode of
        ExitSuccess -> Right (drainBytes stdoutCapture)
        ExitFailure status ->
          Left
            ( Text.pack (observerLabel spec)
                <> " exited nonzero with status "
                <> Text.pack (show status)
                <> renderCapturedDiagnostic captured
            )

requireDrainCapture ::
  Text ->
  Either SomeException DrainCapture ->
  Either Text DrainCapture
requireDrainCapture streamName result =
  case result of
    Right capture -> Right capture
    Left failure ->
      Left
        ( "fixed observer "
            <> streamName
            <> " drain failed: "
            <> Text.pack (displayException failure)
        )

renderCapturedDiagnostic :: CapturedStreams -> Text
renderCapturedDiagnostic captured =
  "\nstdout: "
    <> renderDrain (capturedStdout captured)
    <> "\nstderr: "
    <> renderDrain (capturedStderr captured)
  where
    renderDrain result =
      case result of
        Left failure -> "<drain failure: " <> Text.pack (displayException failure) <> ">"
        Right capture -> renderBytes (drainBytes capture)

renderBytes :: ByteString -> Text
renderBytes = Text.pack . ByteString8.unpack

captureSynchronousFailure ::
  Text ->
  IO (Either Text value) ->
  IO (Either Text value)
captureSynchronousFailure label action = do
  result <- try @SomeException action
  case result of
    Right value -> pure value
    Left failure ->
      case fromException failure :: Maybe SomeAsyncException of
        Just _ -> throwIO failure
        Nothing ->
          pure
            ( Left
                ( label
                    <> ": "
                    <> Text.pack (displayException failure)
                )
            )

runFixedObserver ::
  ObserverDeadline ->
  FixedObserverSpec ->
  (ObserverSpawnEvidence -> IO ()) ->
  IO ObserverRun
runFixedObserver deadline spec afterSpawn =
  mask $ \restore -> do
    active <- acquireActiveObserver spec
    maybeCaptured <-
      onExceptionPreservingPrimary
        ( restore $ do
            evidence <- observeSpawnEvidence deadline spec active
            afterSpawn evidence
            releaseObserverInput spec active
            awaitCapturedStreamsBefore deadline active
        )
        (void (finishActiveObserver active Nothing))
    (exitCode, captured) <- finishActiveObserver active maybeCaptured
    pure $
      case maybeCaptured of
        Just _ -> ObserverCompleted exitCode captured
        Nothing -> ObserverTimedOut captured

acquireActiveObserver :: FixedObserverSpec -> IO ActiveObserver
acquireActiveObserver spec = do
  spawned <- spawnFixedObserver spec
  onExceptionPreservingPrimary
    ( do
        stdoutResult <- newEmptyMVar
        stderrResult <- newEmptyMVar
        stdoutThread <-
          forkDrain
            (observerStdoutLimit spec)
            (spawnedObserverOutput spawned)
            stdoutResult
        stderrThread <-
          onExceptionPreservingPrimary
            ( forkDrain
                maximumObserverStderrBytes
                (spawnedObserverError spawned)
                stderrResult
            )
            (killThread stdoutThread)
        pure
          ActiveObserver
            { activeObserverSpawned = spawned,
              activeObserverStdoutThread = stdoutThread,
              activeObserverStderrThread = stderrThread,
              activeObserverStdoutResult = stdoutResult,
              activeObserverStderrResult = stderrResult
            }
    )
    (cleanupSpawnedObserver spawned)

forkDrain ::
  Int ->
  Handle ->
  MVar (Either SomeException DrainCapture) ->
  IO ThreadId
forkDrain byteLimit handleValue resultVariable =
  forkIOWithUnmask $ \restore ->
    try @SomeException (restore (drainHandleBounded byteLimit handleValue))
      >>= putMVar resultVariable

spawnFixedObserver :: FixedObserverSpec -> IO SpawnedObserver
spawnFixedObserver spec = do
  -- The observer samples on a 50 ms cadence against a bounded total deadline,
  -- so it is the kernel an unbounded descriptor space starves first: the
  -- pre-'exec' walk 'close_fds' performs is linear in the soft RLIMIT_NOFILE,
  -- which is 1073741816 in a containerd pod. Fail closed and name the kernel
  -- rather than time out with two empty captured streams.
  _ <- requireBoundedDescriptorSpace (observerLabel spec)
  created <-
    -- infernix-lint: non-engine-process-site
    createProcess
      (proc (observerExecutable spec) (observerArguments spec))
        { cwd = Just observerWorkingDirectory,
          env = Just observerEnvironment,
          std_in = CreatePipe,
          std_out = CreatePipe,
          std_err = CreatePipe,
          close_fds = True,
          create_group = True
        }
  let (maybeInput, maybeOutput, maybeError, processHandle) = created
      existingHandles = [maybeInput, maybeOutput, maybeError]
      cleanupWithoutGroup =
        runCleanupsPreservingFailures
          [ ignoreMissingProcess (terminateProcess processHandle),
            void (waitForProcessWithinCleanupDeadline processHandle),
            closeMaybeHandles existingHandles
          ]
  maybeProcessId <-
    onExceptionPreservingPrimary
      (getPid processHandle)
      cleanupWithoutGroup
  processId <-
    case maybeProcessId of
      Just value -> pure value
      Nothing ->
        onExceptionPreservingPrimary
          ( ioError
              ( userError
                  ( observerLabel spec
                      <> " exited before its process-group authority was observed"
                  )
              )
          )
          cleanupWithoutGroup
  let ownedGroup =
        OwnedObserverGroup
          { ownedObserverProcess = processHandle,
            ownedObserverProcessGroup = processId
          }
      cleanupWithGroup =
        runCleanupsPreservingFailures
          [ terminateOwnedObserverGroup ownedGroup,
            closeMaybeHandles existingHandles
          ]
  onExceptionPreservingPrimary
    (validateFreshProcessGroup processId)
    cleanupWithGroup
  case (maybeInput, maybeOutput, maybeError) of
    (Just inputHandle, Just outputHandle, Just errorHandle) ->
      pure
        SpawnedObserver
          { spawnedObserverInput = inputHandle,
            spawnedObserverOutput = outputHandle,
            spawnedObserverError = errorHandle,
            spawnedObserverGroup = ownedGroup
          }
    _ ->
      onExceptionPreservingPrimary
        ( ioError
            ( userError
                (observerLabel spec <> " did not expose all standard-stream pipes")
            )
        )
        cleanupWithGroup

validateFreshProcessGroup :: CPid -> IO ()
validateFreshProcessGroup processId = do
  processGroup <- getProcessGroupIDOf processId
  unless
    (processGroup == processId)
    ( ioError
        ( userError
            "Apple observer was not isolated in its requested fresh process group"
        )
    )

cleanupSpawnedObserver :: SpawnedObserver -> IO ()
cleanupSpawnedObserver spawned =
  runCleanupsPreservingFailures
    [ terminateOwnedObserverGroup (spawnedObserverGroup spawned),
      closeSpawnedObserverHandles spawned
    ]

observeSpawnEvidence ::
  ObserverDeadline ->
  FixedObserverSpec ->
  ActiveObserver ->
  IO ObserverSpawnEvidence
observeSpawnEvidence deadline spec active =
  if observerRequiresFixtureGate spec
    then do
      birthIdentity <-
        awaitProcessBirthIdentityBefore deadline processId
      pure
        ObserverSpawnEvidence
          { observerSpawnProcessId = processId,
            observerSpawnBirthIdentity = Just birthIdentity
          }
    else
      pure
        ObserverSpawnEvidence
          { observerSpawnProcessId = processId,
            observerSpawnBirthIdentity = Nothing
          }
  where
    processId =
      ownedObserverProcessGroup
        (spawnedObserverGroup (activeObserverSpawned active))

awaitProcessBirthIdentityBefore ::
  ObserverDeadline ->
  CPid ->
  IO ProcessBirthIdentity
awaitProcessBirthIdentityBefore deadline processId = loop
  where
    loop = do
      observed <- readProcessBirthIdentity (fromIntegral processId)
      case observed of
        Just identity -> pure identity
        Nothing -> do
          remaining <- remainingDeadlineMicros deadline
          if remaining <= 0
            then
              ioError
                ( userError
                    "closed observer fixture did not publish a process birth identity before its deadline"
                )
            else yield >> loop

releaseObserverInput :: FixedObserverSpec -> ActiveObserver -> IO ()
releaseObserverInput spec active = do
  let inputHandle =
        spawnedObserverInput (activeObserverSpawned active)
  when (observerRequiresFixtureGate spec) $ do
    hPutStr inputHandle observerFixtureGate
    hFlush inputHandle
  hClose inputHandle

awaitCapturedStreamsBefore ::
  ObserverDeadline ->
  ActiveObserver ->
  IO (Maybe CapturedStreams)
awaitCapturedStreamsBefore deadline active =
  runMaybeBeforeDeadline
    deadline
    (readCapturedStreams active)

readCapturedStreams :: ActiveObserver -> IO CapturedStreams
readCapturedStreams active =
  CapturedStreams
    <$> readMVar (activeObserverStdoutResult active)
    <*> readMVar (activeObserverStderrResult active)

finishActiveObserver ::
  ActiveObserver ->
  Maybe CapturedStreams ->
  IO (ExitCode, CapturedStreams)
finishActiveObserver active preobservedCapture = do
  cleanupDeadline <- deadlineFromNow observerCleanupTimeoutMicros
  exitCodeRef <- newIORef Nothing
  captureRef <- newIORef preobservedCapture
  runCleanupsPreservingFailures
    [ do
        exitCode <- terminateAndReapOwnedObserverGroup cleanupDeadline ownedGroup
        writeIORef exitCodeRef (Just exitCode),
      do
        currentCapture <- readIORef captureRef
        case currentCapture of
          Just _ -> pure ()
          Nothing -> do
            capture <-
              runBeforeDeadline
                cleanupDeadline
                "Apple observer stream drains exceeded their cleanup deadline"
                (readCapturedStreams active)
            writeIORef captureRef (Just capture),
      closeSpawnedObserverHandles (activeObserverSpawned active),
      killThread (activeObserverStdoutThread active),
      killThread (activeObserverStderrThread active)
    ]
  maybeExitCode <- readIORef exitCodeRef
  maybeCapture <- readIORef captureRef
  case (maybeExitCode, maybeCapture) of
    (Just exitCode, Just capture) -> pure (exitCode, capture)
    _ ->
      ioError
        ( userError
            "Apple observer cleanup completed without terminal process and stream evidence"
        )
  where
    ownedGroup =
      spawnedObserverGroup (activeObserverSpawned active)

terminateOwnedObserverGroup :: OwnedObserverGroup -> IO ()
terminateOwnedObserverGroup ownedGroup = do
  cleanupDeadline <- deadlineFromNow observerCleanupTimeoutMicros
  void (terminateAndReapOwnedObserverGroup cleanupDeadline ownedGroup)

terminateAndReapOwnedObserverGroup ::
  ObserverDeadline ->
  OwnedObserverGroup ->
  IO ExitCode
terminateAndReapOwnedObserverGroup cleanupDeadline ownedGroup = do
  continueResult <-
    try @IOException
      (signalProcessGroup sigCONT processGroup)
  killResult <-
    try @IOException
      (signalProcessGroup sigKILL processGroup)
  reapResult <-
    try @SomeException
      ( runBeforeDeadline
          cleanupDeadline
          "Apple observer reap exceeded its cleanup deadline"
          -- infernix-lint: non-engine-process-site
          (waitForProcess (ownedObserverProcess ownedGroup))
      )
  absenceResult <-
    try @SomeException
      ( runBeforeDeadline
          cleanupDeadline
          "Apple observer group-absence proof exceeded its cleanup deadline"
          (proveNumericProcessGroupAbsent processGroup)
      )
  let failures =
        signalFailures continueResult
          <> signalFailures killResult
          <> either (: []) (const []) reapResult
          <> either (: []) (const []) absenceResult
  unless (null failures) $
    runCleanupsPreservingFailures (map throwIO failures)
  case reapResult of
    Right exitCode -> pure exitCode
    Left failure -> throwIO failure
  where
    processGroup = ownedObserverProcessGroup ownedGroup

-- Darwin may report EPERM when only an unreaped zombie leader remains. Treat
-- ESRCH and EPERM as provisional signal results only: the designated wait must
-- succeed and the subsequent null-signal probe must prove the numeric group
-- absent before either result is discharged.
signalFailures :: Either IOException () -> [SomeException]
signalFailures result =
  case result of
    Right () -> []
    Left failure
      | isDoesNotExistError failure || isPermissionError failure -> []
      | otherwise -> [toException failure]

proveNumericProcessGroupAbsent :: CPid -> IO ()
proveNumericProcessGroupAbsent processGroup = loop
  where
    -- Every caller encloses this proof in an absolute monotonic deadline.
    -- A killed descendant may remain observable until its system parent reaps
    -- it, so keep probing without a timing sleep and accept only ESRCH.
    loop = do
      probeResult <-
        try @IOException
          (signalProcessGroup nullSignal processGroup)
      case probeResult of
        Left failure
          | isDoesNotExistError failure -> pure ()
          | isPermissionError failure -> yield >> loop
          | otherwise -> throwIO failure
        Right () -> yield >> loop

waitForProcessWithinCleanupDeadline :: ProcessHandle -> IO ExitCode
waitForProcessWithinCleanupDeadline processHandle = do
  cleanupDeadline <- deadlineFromNow observerCleanupTimeoutMicros
  runBeforeDeadline
    cleanupDeadline
    "Apple observer reap exceeded its cleanup deadline"
    -- infernix-lint: non-engine-process-site
    (waitForProcess processHandle)

closeSpawnedObserverHandles :: SpawnedObserver -> IO ()
closeSpawnedObserverHandles spawned =
  runCleanupsPreservingFailures
    ( map
        closeHandleIfOpen
        [ spawnedObserverInput spawned,
          spawnedObserverOutput spawned,
          spawnedObserverError spawned
        ]
    )

closeMaybeHandles :: [Maybe Handle] -> IO ()
closeMaybeHandles =
  runCleanupsPreservingFailures
    . map (maybe (pure ()) closeHandleIfOpen)

closeHandleIfOpen :: Handle -> IO ()
closeHandleIfOpen handleValue = do
  closed <- hIsClosed handleValue
  unless closed (hClose handleValue)

ignoreMissingProcess :: IO () -> IO ()
ignoreMissingProcess action =
  action `catch` \(failure :: IOException) ->
    unless (isDoesNotExistError failure) (throwIO failure)

drainHandleBounded :: Int -> Handle -> IO DrainCapture
drainHandleBounded byteLimit handleValue =
  go byteLimit [] False
  where
    go remainingBytes chunks overflowed = do
      chunk <- ByteString.hGetSome handleValue observerDrainChunkBytes
      if ByteString.null chunk
        then
          pure
            DrainCapture
              { drainBytes = ByteString.concat (reverse chunks),
                drainOverflowed = overflowed
              }
        else do
          let retained = ByteString.take remainingBytes chunk
              nextRemaining = remainingBytes - ByteString.length retained
              nextOverflow =
                overflowed || ByteString.length chunk > remainingBytes
              nextChunks =
                if ByteString.null retained
                  then chunks
                  else retained : chunks
          go nextRemaining nextChunks nextOverflow

deadlineFromNow :: Int -> IO ObserverDeadline
deadlineFromNow microseconds = do
  startedAt <- getMonotonicTimeNSec
  pure
    ( ObserverDeadline
        (deadlineAfterMicros startedAt microseconds)
    )

deadlineAfterMicros :: Word64 -> Int -> Word64
deadlineAfterMicros startedAt microseconds =
  fromInteger
    ( min
        (toInteger (maxBound :: Word64))
        (toInteger startedAt + toInteger microseconds * 1000)
    )

remainingDeadlineMicros :: ObserverDeadline -> IO Int
remainingDeadlineMicros (ObserverDeadline deadline) = do
  now <- getMonotonicTimeNSec
  pure
    ( if now >= deadline
        then 0
        else
          fromIntegral
            ( min
                (fromIntegral (maxBound :: Int))
                ((deadline - now) `div` 1000)
            )
    )

runMaybeBeforeDeadline ::
  ObserverDeadline ->
  IO value ->
  IO (Maybe value)
runMaybeBeforeDeadline deadline action = do
  remaining <- remainingDeadlineMicros deadline
  if remaining <= 0
    then pure Nothing
    else timeout remaining action

runBeforeDeadline ::
  ObserverDeadline ->
  String ->
  IO value ->
  IO value
runBeforeDeadline deadline failureMessage action =
  runMaybeBeforeDeadline deadline action
    >>= maybe (ioError (userError failureMessage)) pure

parseTopProcessGroupMembers ::
  CPid ->
  ByteString ->
  Either Text [CPid]
parseTopProcessGroupMembers processGroup contents = do
  members <- parseTopProcessGroupMemberRows processGroup contents
  unless
    (processGroup `elem` members)
    (Left "Apple top output omitted the exact process-group leader")
  pure members

-- | Members that remain sampleable while the caller retains the unreaped
-- process-group leader's numeric identity. Darwin omits a zombie leader from
-- @top@, so requiring the leader row here would discard the footprint of live
-- descendants. An empty group is terminal, not a zero-byte sample.
parseTopProcessGroupSamplingMembers ::
  CPid ->
  ByteString ->
  Either Text [CPid]
parseTopProcessGroupSamplingMembers processGroup contents = do
  members <- parseTopProcessGroupMemberRows processGroup contents
  requireProcessGroupSamplingMembers members

requireProcessGroupSamplingMembers :: [CPid] -> Either Text [CPid]
requireProcessGroupSamplingMembers members = do
  when
    (null members)
    (Left "Apple top output omitted every live process-group member")
  pure members

-- | Whether the fixed complete top snapshot contains no live member of the
-- requested process group. Unlike 'parseTopProcessGroupMembers', this accepts
-- the ordinary terminal Darwin shape in which the unreaped zombie leader is
-- absent from @top@; every row and bound is still validated identically.
parseTopProcessGroupLiveMembersAbsent ::
  CPid ->
  ByteString ->
  Either Text Bool
parseTopProcessGroupLiveMembersAbsent processGroup contents =
  null <$> parseTopProcessGroupMemberRows processGroup contents

parseTopProcessGroupMemberRows ::
  CPid ->
  ByteString ->
  Either Text [CPid]
parseTopProcessGroupMemberRows processGroup contents
  | not (validProcessId processGroup) =
      Left "Apple process-group observer received an invalid process-group id"
  | ByteString.length contents > maximumTopOutputBytes =
      Left "Apple top output exceeded its parser bound"
  | length outputLines > maximumTopOutputLines =
      Left "Apple top output exceeded its line-count bound"
  | any ((> maximumObserverLineBytes) . ByteString.length) outputLines =
      Left "Apple top output contained an overlong line"
  | otherwise =
      case headerIndices of
        [headerIndex] ->
          parseRows (drop (headerIndex + 1) outputLines)
        [] -> Left "Apple top output omitted the exact PID PGRP MEM header"
        _ -> Left "Apple top output repeated the PID PGRP MEM header"
  where
    outputLines = ByteString8.lines contents
    headerIndices =
      [ index
      | (index, lineValue) <- zip [0 ..] outputLines,
        ByteString8.words lineValue == ["PID", "PGRP", "MEM"]
      ]
    parseRows rows
      | null rows = Left "Apple top output contained no process rows"
      | length rows > maximumTopProcessRows =
          Left "Apple top output exceeded its process-row bound"
      | otherwise = do
          (_, members) <- foldM parseRow (Set.empty, Set.empty) rows
          unless
            (Set.size members <= maximumObservedGroupMembers)
            ( Left
                "Apple process group exceeded its member-count enforcement bound"
            )
          pure (Set.toAscList members)
    parseRow (seenProcessIds, members) lineValue =
      case ByteString8.words lineValue of
        [processIdToken, processGroupToken, memoryToken] -> do
          processId <- parseTopProcessId "PID" processIdToken
          rowProcessGroup <- parseTopProcessId "PGRP" processGroupToken
          unless
            (validTopMemoryToken memoryToken)
            (Left "Apple top output contained a malformed MEM value")
          when
            (rowProcessGroup == processGroup && processId == 0)
            ( Left
                "Apple top output assigned kernel PID zero to the requested process group"
            )
          when
            (Set.member processId seenProcessIds)
            (Left "Apple top output repeated a process id")
          pure
            ( Set.insert processId seenProcessIds,
              if rowProcessGroup == processGroup
                then Set.insert processId members
                else members
            )
        _ -> Left "Apple top output contained a malformed process row"

parseFootprintPhysicalBytes :: ByteString -> Either Text Word64
parseFootprintPhysicalBytes contents
  | ByteString.length contents > maximumFootprintOutputBytes =
      Left "Apple footprint output exceeded its parser bound"
  | length outputLines > maximumFootprintOutputLines =
      Left "Apple footprint output exceeded its line-count bound"
  | any ((> maximumObserverLineBytes) . ByteString.length) outputLines =
      Left "Apple footprint output contained an overlong line"
  | otherwise =
      case physicalFootprintFields of
        [[_, byteCountToken, "B"]] -> do
          byteCount <- parseDecimalWord64 byteCountToken
          if byteCount > 0
            then Right byteCount
            else Left "Apple footprint reported a non-positive phys_footprint"
        [] -> Left "Apple footprint output omitted phys_footprint"
        _ -> Left "Apple footprint output repeated or malformed phys_footprint"
  where
    outputLines = ByteString8.lines contents
    physicalFootprintFields =
      [ fields
      | lineValue <- outputLines,
        let fields = ByteString8.words lineValue,
        case fields of
          fieldName : _ -> fieldName == "phys_footprint:"
          [] -> False
      ]

parsePositiveProcessId :: Text -> ByteString -> Either Text CPid
parsePositiveProcessId fieldName token = do
  processId <- parseDecimalWord64 token
  if processId > 0 && processId <= maximumPosixProcessId
    then pure (fromIntegral processId)
    else
      Left
        ( "Apple top output contained an out-of-range "
            <> fieldName
        )

-- Darwin top includes the kernel task as PID/PGRP zero. Zero is valid only as
-- an unrelated table row; requested observer groups and fixture identities
-- still go through the positive parser.
parseTopProcessId :: Text -> ByteString -> Either Text CPid
parseTopProcessId fieldName token = do
  processId <- parseDecimalWord64 token
  if processId <= maximumPosixProcessId
    then pure (fromIntegral processId)
    else
      Left
        ( "Apple top output contained an out-of-range "
            <> fieldName
        )

parseDecimalWord64 :: ByteString -> Either Text Word64
parseDecimalWord64 token
  | ByteString.null token =
      Left "Apple observer output contained an empty decimal value"
  | ByteString.length token > maximumWord64DecimalDigits =
      Left "Apple observer output contained an overlong decimal value"
  | otherwise =
      foldM appendDigit 0 (ByteString8.unpack token)
  where
    appendDigit current character
      | not (isAsciiDecimalDigit character) =
          Left "Apple observer output contained a non-decimal value"
      | otherwise =
          let digit = fromIntegral (fromEnum character - fromEnum '0')
           in if current > (maxBound - digit) `div` 10
                then Left "Apple observer decimal value overflowed Word64"
                else Right (current * 10 + digit)

validTopMemoryToken :: ByteString -> Bool
validTopMemoryToken token =
  not (null digits)
    && all isAsciiDecimalDigit digits
    && suffix `elem` ["B", "K", "M", "G", "T", "P"]
  where
    (digits, suffix) = span isAsciiDecimalDigit (ByteString8.unpack token)

isAsciiDecimalDigit :: Char -> Bool
isAsciiDecimalDigit = isDigit

validProcessId :: CPid -> Bool
validProcessId processId =
  let value = fromIntegral processId :: Integer
   in value > 0 && value <= toInteger maximumPosixProcessId

-- | Sum, in bytes, the device memory NVIDIA attributes to the given process
-- group members. Compute applications outside the member list belong to other
-- processes in this PID namespace and are deliberately not attributed here;
-- the caller supplies the membership it observed from @\/proc@. Every MiB
-- conversion and accumulation is overflow-checked, so an implausible sample is
-- a diagnosed rejection rather than a wrapped-around under-count that would
-- silently disable the ceiling.
nvidiaComputeAppGroupBytes ::
  [CPid] ->
  [NvidiaComputeApp] ->
  Either Text Word64
nvidiaComputeAppGroupBytes members = foldM accumulate 0
  where
    memberSet = Set.fromList members
    accumulate total computeApp
      | nvidiaComputeAppProcessId computeApp `Set.notMember` memberSet = Right total
      | nvidiaComputeAppUsedMib computeApp > maxBound `div` bytesPerObserverMib =
          Left "NVIDIA compute-application byte conversion overflowed Word64"
      | otherwise =
          case checkedAddWord64 total (nvidiaComputeAppUsedMib computeApp * bytesPerObserverMib) of
            Nothing -> Left "NVIDIA process-group VRAM total overflowed Word64"
            Just nextTotal -> Right nextTotal

bytesPerObserverMib :: Word64
bytesPerObserverMib = 1048576

checkedAddWord64 :: Word64 -> Word64 -> Maybe Word64
checkedAddWord64 left right
  | maxBound - left < right = Nothing
  | otherwise = Just (left + right)

isObserverWhitespace :: Char -> Bool
isObserverWhitespace character =
  character `elem` (" \t\r\n" :: String)

-- | Parse @nvidia-smi --query-compute-apps=pid,used_gpu_memory@ in
-- @csv,noheader,nounits@ form. Each retained row is @\<pid\>, \<mib\>@. An
-- empty payload is a valid observation of "no compute application", which is
-- what a freshly started device reports; every other shape — a malformed row,
-- a non-decimal field, a duplicate pid, an out-of-range pid, or a row count
-- past the bound — is a rejection, never a silently dropped sample.
parseNvidiaComputeApps :: ByteString -> Either Text [NvidiaComputeApp]
parseNvidiaComputeApps contents
  | ByteString.length contents > maximumNvidiaOutputBytes =
      Left "NVIDIA compute-application output exceeded its byte bound"
  | length outputLines > maximumNvidiaOutputLines =
      Left "NVIDIA compute-application output exceeded its line bound"
  | any ((> maximumObserverLineBytes) . ByteString.length) outputLines =
      Left "NVIDIA compute-application output contained an oversized line"
  | length rows > maximumNvidiaProcessRows =
      Left "NVIDIA compute-application output exceeded its row bound"
  | otherwise = do
      parsedRows <- traverse parseRow rows
      let processIds = map nvidiaComputeAppProcessId parsedRows
      if length (List.nub processIds) /= length processIds
        then Left "NVIDIA compute-application output repeated a process id"
        else Right parsedRows
  where
    outputLines = ByteString8.lines contents
    rows =
      [ trimmed
      | lineValue <- outputLines,
        let trimmed = trimObserverBytes lineValue,
        not (ByteString.null trimmed)
      ]
    parseRow row =
      case map trimObserverBytes (ByteString8.split ',' row) of
        [processIdToken, usedMibToken] -> do
          processId <- parsePositiveProcessId "NVIDIA compute-application" processIdToken
          usedMib <- parseDecimalWord64 usedMibToken
          pure
            NvidiaComputeApp
              { nvidiaComputeAppProcessId = processId,
                nvidiaComputeAppUsedMib = usedMib
              }
        _ ->
          Left
            ( "NVIDIA compute-application output row was not a pid,used_gpu_memory pair: "
                <> renderBytes row
            )

-- | Parse @nvidia-smi --query-gpu=memory.total@ in @csv,noheader,nounits@
-- form. Exactly one positive device row is required: a host with no device, a
-- host whose device reports nothing, and a multi-device host are all
-- rejections rather than an assumed envelope.
parseNvidiaDeviceTotalMib :: ByteString -> Either Text Int
parseNvidiaDeviceTotalMib contents
  | ByteString.length contents > maximumNvidiaOutputBytes =
      Left "NVIDIA device-memory output exceeded its byte bound"
  | otherwise =
      case rows of
        [] -> Left "NVIDIA device-memory output named no device"
        [row] -> do
          totalMib <- parseDecimalWord64 row
          if totalMib == 0
            then Left "NVIDIA device reported a non-positive total VRAM"
            else
              if totalMib > fromIntegral (maxBound :: Int)
                then Left "NVIDIA device-memory total exceeded the representable range"
                else Right (fromIntegral totalMib)
        _ ->
          Left
            "NVIDIA device-memory output named more than one device; per-device VRAM enforcement requires exactly one"
  where
    rows =
      [ trimmed
      | lineValue <- ByteString8.lines contents,
        let trimmed = trimObserverBytes lineValue,
        not (ByteString.null trimmed)
      ]

trimObserverBytes :: ByteString -> ByteString
trimObserverBytes =
  ByteString8.dropWhile isObserverWhitespace
    . ByteString8.reverse
    . ByteString8.dropWhile isObserverWhitespace
    . ByteString8.reverse

runFixedObserverKernelTest ::
  FixedObserverKernelTest ->
  IO (Either Text ())
runFixedObserverKernelTest testCase = do
  result <- try @SomeException (runKernelTest testCase)
  case result of
    Right () -> pure (Right ())
    Left failure ->
      case fromException failure :: Maybe SomeAsyncException of
        Just _ -> throwIO failure
        Nothing -> pure (Left (Text.pack (displayException failure)))

runKernelTest :: FixedObserverKernelTest -> IO ()
runKernelTest testCase =
  case testCase of
    ObserverNormalCompletion ->
      testTerminalFixture FixtureNormal ExitSuccess
    ObserverNonzeroCompletion ->
      testTerminalFixture FixtureNonzero (ExitFailure fixtureNonzeroExitCode)
    ObserverTimeoutCleanup ->
      testTimedOutFixture FixtureHang
    ObserverSynchronousExceptionCleanup ->
      testSynchronousExceptionCleanup
    ObserverAsynchronousCancellationCleanup ->
      testAsynchronousCancellationCleanup
    ObserverStoppedGroupCleanup ->
      testTimedOutFixture FixtureStopped
    ObserverDescendantGroupCleanup ->
      testDescendantGroupCleanup
    ObserverOutputBoundsCleanup ->
      testOutputBoundsCleanup
    ObserverMemberTurnoverRestart ->
      testMemberTurnoverRestart
    ObserverLiveMemberFailure ->
      testLiveMemberFailure
    ObserverTerminalMemberFailure ->
      testTerminalMemberFailure
    ObserverMembershipRecheckFailure ->
      testMembershipRecheckFailure

data ObserverFixture
  = FixtureNormal
  | FixtureNonzero
  | FixtureHang
  | FixtureStopped
  | FixtureDescendantOwner
  | FixtureDescendant
  | FixtureOutputOverflow

testTerminalFixture :: ObserverFixture -> ExitCode -> IO ()
testTerminalFixture fixture expectedExitCode = do
  (observerRun, evidence) <- runClosedFixture fixture fixtureCompletionTimeoutMicros
  case observerRun of
    ObserverCompleted actualExitCode _
      | actualExitCode == expectedExitCode -> pure ()
      | otherwise ->
          kernelTestFailure
            ( "closed observer fixture exited "
                <> show actualExitCode
                <> " instead of "
                <> show expectedExitCode
            )
    ObserverTimedOut _ ->
      kernelTestFailure "closed observer fixture timed out unexpectedly"
  requireExactFixtureAbsence evidence

testTimedOutFixture :: ObserverFixture -> IO ()
testTimedOutFixture fixture = do
  (observerRun, evidence) <- runClosedFixture fixture fixtureTimeoutMicros
  case observerRun of
    ObserverTimedOut _ -> pure ()
    ObserverCompleted exitCode _ ->
      kernelTestFailure
        ( "closed observer timeout fixture completed unexpectedly with "
            <> show exitCode
        )
  requireExactFixtureAbsence evidence

testSynchronousExceptionCleanup :: IO ()
testSynchronousExceptionCleanup = do
  deadline <- deadlineFromNow fixtureCompletionTimeoutMicros
  evidenceRef <- newIORef Nothing
  spec <- fixtureSpec FixtureHang
  result <-
    try @SomeException
      ( runFixedObserver
          deadline
          spec
          ( \evidence -> do
              writeIORef evidenceRef (Just evidence)
              ioError (userError synchronousFixtureFailureMarker)
          )
      )
  case result of
    Left failure
      | synchronousFixtureFailureMarker
          `List.isInfixOf` displayException failure ->
          pure ()
      | otherwise ->
          kernelTestFailure
            ( "synchronous fixture preserved the wrong primary failure: "
                <> displayException failure
            )
    Right _ ->
      kernelTestFailure "synchronous fixture injection did not fail"
  evidence <- requireRecordedEvidence evidenceRef
  requireExactFixtureAbsence evidence

testAsynchronousCancellationCleanup :: IO ()
testAsynchronousCancellationCleanup = do
  deadline <- deadlineFromNow fixtureLongRunningTimeoutMicros
  evidenceVariable <- newEmptyMVar
  resultVariable <- newEmptyMVar
  blocker <- newEmptyMVar
  spec <- fixtureSpec FixtureHang
  workerThread <-
    forkIO
      ( try @SomeException
          ( runFixedObserver
              deadline
              spec
              ( \evidence -> do
                  putMVar evidenceVariable evidence
                  takeMVar blocker
              )
          )
          >>= putMVar resultVariable
      )
  evidence <-
    runBeforeTestDeadline
      "asynchronous observer fixture did not publish spawn evidence"
      (takeMVar evidenceVariable)
  killThread workerThread
  result <-
    runBeforeTestDeadline
      "asynchronous observer fixture did not finish cleanup"
      (takeMVar resultVariable)
  case result of
    Left failure ->
      case fromException failure :: Maybe SomeAsyncException of
        Just _ -> pure ()
        Nothing ->
          kernelTestFailure
            ( "observer cancellation lost asynchronous classification: "
                <> displayException failure
            )
    Right _ ->
      kernelTestFailure "observer cancellation unexpectedly returned normally"
  requireExactFixtureAbsence evidence

testDescendantGroupCleanup :: IO ()
testDescendantGroupCleanup = do
  (observerRun, ownerEvidence) <-
    runClosedFixture FixtureDescendantOwner fixtureTimeoutMicros
  captured <-
    case observerRun of
      ObserverTimedOut streams -> pure streams
      ObserverCompleted exitCode _ ->
        kernelTestFailure
          ( "descendant fixture completed unexpectedly with "
              <> show exitCode
          )
  descendantEvidence <-
    case requireDrainCapture "fixture stdout" (capturedStdout captured)
      >>= requireUnboundedDrain of
      Left reason -> kernelTestFailure (Text.unpack reason)
      Right output ->
        either (kernelTestFailure . Text.unpack) pure (parseDescendantEvidence output)
  requireExactFixtureAbsence ownerEvidence
  requireExactProcessAbsence descendantEvidence

testOutputBoundsCleanup :: IO ()
testOutputBoundsCleanup = do
  (observerRun, evidence) <-
    runClosedFixture FixtureOutputOverflow fixtureCompletionTimeoutMicros
  captured <-
    case observerRun of
      ObserverCompleted ExitSuccess streams -> pure streams
      ObserverCompleted exitCode _ ->
        kernelTestFailure
          ( "output-bound fixture exited unexpectedly with "
              <> show exitCode
          )
      ObserverTimedOut _ ->
        kernelTestFailure "output-bound fixture timed out unexpectedly"
  stdoutCapture <-
    either
      (kernelTestFailure . Text.unpack)
      pure
      (requireDrainCapture "fixture stdout" (capturedStdout captured))
  stderrCapture <-
    either
      (kernelTestFailure . Text.unpack)
      pure
      (requireDrainCapture "fixture stderr" (capturedStderr captured))
  unless
    ( drainOverflowed stdoutCapture
        && ByteString.length (drainBytes stdoutCapture)
          == maximumFixtureOutputBytes
        && drainOverflowed stderrCapture
        && ByteString.length (drainBytes stderrCapture)
          == maximumObserverStderrBytes
    )
    (kernelTestFailure "observer drains did not retain exactly their configured bounds")
  requireExactFixtureAbsence evidence

data MemberSamplingFixtureStep
  = FixtureObserveMembers (Either Text [CPid])
  | FixtureMeasureMember CPid (Either Text Word64)
  deriving (Eq, Show)

testMemberTurnoverRestart :: IO ()
testMemberTurnoverRestart =
  testMemberSamplingFixture
    "departed member restarts the complete refreshed snapshot from zero"
    [fixtureProcessId42, fixtureProcessId43]
    [ FixtureMeasureMember fixtureProcessId42 (Right 100),
      FixtureMeasureMember fixtureProcessId43 (Left fixtureFootprintFailure),
      FixtureObserveMembers (Right [fixtureProcessId42, fixtureProcessId44]),
      FixtureMeasureMember fixtureProcessId42 (Right 100),
      FixtureMeasureMember fixtureProcessId44 (Right 200)
    ]
    (Right 300)

testLiveMemberFailure :: IO ()
testLiveMemberFailure =
  testMemberSamplingFixture
    "a still-live failed member preserves the footprint failure"
    [fixtureProcessId42]
    [ FixtureMeasureMember fixtureProcessId42 (Left fixtureFootprintFailure),
      FixtureObserveMembers (Right [fixtureProcessId42])
    ]
    (Left fixtureFootprintFailure)

testTerminalMemberFailure :: IO ()
testTerminalMemberFailure =
  testMemberSamplingFixture
    "an empty refreshed group preserves the failure for terminal settlement"
    [fixtureProcessId42]
    [ FixtureMeasureMember fixtureProcessId42 (Left fixtureFootprintFailure),
      FixtureObserveMembers (Right [])
    ]
    (Left fixtureFootprintFailure)

testMembershipRecheckFailure :: IO ()
testMembershipRecheckFailure =
  testMemberSamplingFixture
    "a failed membership recheck fails closed with both diagnostics"
    [fixtureProcessId42]
    [ FixtureMeasureMember fixtureProcessId42 (Left fixtureFootprintFailure),
      FixtureObserveMembers (Left fixtureMembershipFailure)
    ]
    ( Left
        "injected footprint failure; Apple process-group membership recheck failed: injected membership failure"
    )

testMemberSamplingFixture ::
  String ->
  [CPid] ->
  [MemberSamplingFixtureStep] ->
  Either Text Word64 ->
  IO ()
testMemberSamplingFixture label initialMembers steps expected = do
  stepsRef <- newIORef steps
  actual <-
    sampleCompleteProcessGroupSnapshotWith
      (fixtureObserveMembers stepsRef)
      (fixtureMeasureMember stepsRef)
      initialMembers
  unless (actual == expected) $
    kernelTestFailure
      ( label
          <> ": returned "
          <> show actual
          <> " instead of "
          <> show expected
      )
  remaining <- readIORef stepsRef
  unless (null remaining) $
    kernelTestFailure
      ( label
          <> ": left unconsumed scripted operations "
          <> show remaining
      )

fixtureObserveMembers ::
  IORef [MemberSamplingFixtureStep] ->
  IO (Either Text [CPid])
fixtureObserveMembers stepsRef = do
  step <- takeMemberSamplingFixtureStep stepsRef
  case step of
    FixtureObserveMembers observed -> pure observed
    FixtureMeasureMember processId _ ->
      kernelTestFailure
        ( "member-sampling fixture observed membership before measuring PID "
            <> show processId
        )

fixtureMeasureMember ::
  IORef [MemberSamplingFixtureStep] ->
  CPid ->
  IO (Either Text Word64)
fixtureMeasureMember stepsRef processId = do
  step <- takeMemberSamplingFixtureStep stepsRef
  case step of
    FixtureMeasureMember expectedProcessId observed
      | processId == expectedProcessId -> pure observed
      | otherwise ->
          kernelTestFailure
            ( "member-sampling fixture measured PID "
                <> show processId
                <> " instead of "
                <> show expectedProcessId
            )
    FixtureObserveMembers _ ->
      kernelTestFailure
        ( "member-sampling fixture measured PID "
            <> show processId
            <> " before refreshing membership"
        )

takeMemberSamplingFixtureStep ::
  IORef [MemberSamplingFixtureStep] ->
  IO MemberSamplingFixtureStep
takeMemberSamplingFixtureStep stepsRef = do
  steps <- readIORef stepsRef
  case steps of
    [] -> kernelTestFailure "member-sampling fixture exhausted its scripted operations"
    step : remaining -> do
      writeIORef stepsRef remaining
      pure step

fixtureProcessId42 :: CPid
fixtureProcessId42 = 42

fixtureProcessId43 :: CPid
fixtureProcessId43 = 43

fixtureProcessId44 :: CPid
fixtureProcessId44 = 44

fixtureFootprintFailure :: Text
fixtureFootprintFailure = "injected footprint failure"

fixtureMembershipFailure :: Text
fixtureMembershipFailure = "injected membership failure"

requireUnboundedDrain :: DrainCapture -> Either Text ByteString
requireUnboundedDrain capture
  | drainOverflowed capture =
      Left "closed observer fixture stdout exceeded its bound"
  | otherwise = Right (drainBytes capture)

runClosedFixture ::
  ObserverFixture ->
  Int ->
  IO (ObserverRun, ObserverSpawnEvidence)
runClosedFixture fixture timeoutMicros = do
  deadline <- deadlineFromNow timeoutMicros
  evidenceRef <- newIORef Nothing
  spec <- fixtureSpec fixture
  observerRun <-
    runFixedObserver
      deadline
      spec
      (writeIORef evidenceRef . Just)
  evidence <- requireRecordedEvidence evidenceRef
  pure (observerRun, evidence)

requireRecordedEvidence ::
  IORef (Maybe ObserverSpawnEvidence) ->
  IO ObserverSpawnEvidence
requireRecordedEvidence evidenceRef =
  readIORef evidenceRef
    >>= maybe
      (kernelTestFailure "closed observer fixture omitted spawn evidence")
      pure

requireExactFixtureAbsence :: ObserverSpawnEvidence -> IO ()
requireExactFixtureAbsence evidence = do
  requireExactProcessAbsence evidence
  deadline <- deadlineFromNow fixtureAbsenceTimeoutMicros
  runBeforeDeadline
    deadline
    "closed observer fixture group-absence proof exceeded its deadline"
    (proveNumericProcessGroupAbsent (observerSpawnProcessId evidence))

requireExactProcessAbsence :: ObserverSpawnEvidence -> IO ()
requireExactProcessAbsence evidence =
  case observerSpawnBirthIdentity evidence of
    Nothing ->
      kernelTestFailure
        "closed observer fixture omitted its exact process birth identity"
    Just expectedIdentity -> do
      deadline <- deadlineFromNow fixtureAbsenceTimeoutMicros
      awaitAbsence deadline expectedIdentity
  where
    processId = fromIntegral (observerSpawnProcessId evidence)
    awaitAbsence deadline expectedIdentity = do
      observed <- readProcessBirthIdentity processId
      if observed /= Just expectedIdentity
        then pure ()
        else do
          remaining <- remainingDeadlineMicros deadline
          if remaining <= 0
            then
              kernelTestFailure
                ( "closed observer fixture remained live after cleanup: "
                    <> show processId
                )
            else yield >> awaitAbsence deadline expectedIdentity

parseDescendantEvidence ::
  ByteString ->
  Either Text ObserverSpawnEvidence
parseDescendantEvidence contents =
  case [ fields
       | lineValue <- ByteString8.lines contents,
         let fields = ByteString8.words lineValue,
         case fields of
           "DESCENDANT" : _ -> True
           _ -> False
       ] of
    [["DESCENDANT", processIdToken, birthIdentityToken]] -> do
      processId <- parsePositiveProcessId "descendant PID" processIdToken
      birthIdentity <-
        maybe
          (Left "closed observer descendant emitted an invalid birth identity")
          Right
          (parseProcessBirthIdentity (ByteString8.unpack birthIdentityToken))
      pure
        ObserverSpawnEvidence
          { observerSpawnProcessId = processId,
            observerSpawnBirthIdentity = Just birthIdentity
          }
    [] -> Left "closed observer fixture omitted descendant identity evidence"
    _ -> Left "closed observer fixture emitted malformed descendant identity evidence"

runBeforeTestDeadline :: String -> IO value -> IO value
runBeforeTestDeadline failureMessage action = do
  deadline <- deadlineFromNow fixtureCompletionTimeoutMicros
  runBeforeDeadline deadline failureMessage action

kernelTestFailure :: String -> IO value
kernelTestFailure = ioError . userError

fixtureSpec :: ObserverFixture -> IO FixedObserverSpec
fixtureSpec fixture = do
  executable <- getExecutablePath >>= makeAbsolute
  pure
    FixedObserverSpec
      { observerExecutable = executable,
        observerArguments =
          [ observerFixtureModeArgument,
            renderFixture fixture
          ],
        observerLabel = "closed Darwin observer kernel fixture " <> renderFixture fixture,
        observerStdoutLimit = maximumFixtureOutputBytes,
        observerRequiresFixtureGate = True
      }

renderFixture :: ObserverFixture -> String
renderFixture fixture =
  case fixture of
    FixtureNormal -> "normal"
    FixtureNonzero -> "nonzero"
    FixtureHang -> "hang"
    FixtureStopped -> "stopped"
    FixtureDescendantOwner -> "descendant-owner"
    FixtureDescendant -> "descendant"
    FixtureOutputOverflow -> "output-overflow"

parseFixture :: String -> Maybe ObserverFixture
parseFixture value =
  case value of
    "normal" -> Just FixtureNormal
    "nonzero" -> Just FixtureNonzero
    "hang" -> Just FixtureHang
    "stopped" -> Just FixtureStopped
    "descendant-owner" -> Just FixtureDescendantOwner
    "descendant" -> Just FixtureDescendant
    "output-overflow" -> Just FixtureOutputOverflow
    _ -> Nothing

runFixedObserverFixtureModeIfRequested :: IO Bool
runFixedObserverFixtureModeIfRequested = do
  arguments <- getArgs
  case arguments of
    [modeArgument, fixtureArgument]
      | modeArgument == observerFixtureModeArgument,
        Just fixture <- parseFixture fixtureArgument -> do
          runObserverFixtureProcess fixture
          pure True
    _ -> pure False

runObserverFixtureProcess :: ObserverFixture -> IO ()
runObserverFixtureProcess fixture = do
  dropInheritedProcessIdentity
  identity <- registerCurrentProcessIdentity
  _ <- getLine
  case fixture of
    FixtureNormal -> putStrLn "observer-ok"
    FixtureNonzero -> exitWith (ExitFailure fixtureNonzeroExitCode)
    FixtureHang -> blockForever
    FixtureStopped -> raiseSignal sigSTOP >> blockForever
    FixtureDescendantOwner -> runDescendantOwner
    FixtureDescendant -> do
      processId <- getProcessID
      putStrLn
        ( "DESCENDANT "
            <> show (fromIntegral processId :: Integer)
            <> " "
            <> renderProcessBirthIdentity identity
        )
      hFlush stdout
      blockForever
    FixtureOutputOverflow -> do
      putStr (replicate (maximumFixtureOutputBytes + 1) 'o')
      hFlush stdout
      hPutStr stderr (replicate (maximumObserverStderrBytes + 1) 'e')
      hFlush stderr

runDescendantOwner :: IO ()
runDescendantOwner = do
  executable <- getExecutablePath
  (maybeInput, _, _, processHandle) <-
    -- infernix-lint: non-engine-process-site
    createProcess
      (proc executable [observerFixtureModeArgument, renderFixture FixtureDescendant])
        { cwd = Just observerWorkingDirectory,
          env = Just observerEnvironment,
          std_in = CreatePipe,
          std_out = Inherit,
          std_err = Inherit,
          close_fds = True,
          create_group = False
        }
  case maybeInput of
    Just inputHandle -> do
      hPutStr inputHandle observerFixtureGate
      hFlush inputHandle
      hClose inputHandle
      -- infernix-lint: non-engine-process-site
      exitCode <- waitForProcess processHandle
      exitWith exitCode
    Nothing -> do
      ignoreMissingProcess (terminateProcess processHandle)
      void (waitForProcessWithinCleanupDeadline processHandle)
      kernelTestFailure "closed descendant fixture omitted its input gate"

-- | Block until the observer's cleanup terminates this fixture.
--
-- The obvious spelling, @newEmptyMVar >>= takeMVar@, is not a hang. Nothing
-- else can ever reference that 'MVar', so the RTS deadlock detector delivers
-- @BlockedIndefinitelyOnMVar@ at the first idle GC and the fixture exits 1
-- long before its observer's deadline — which reads as a completed run rather
-- than the timeout the fixture exists to produce.
--
-- Wrapping the same wait in 'timeout' removes that: the pending timer is
-- another way for the thread to become runnable, so the wait is not indefinite
-- and the detector does not fire. The interval is re-armed rather than made
-- unbounded, which is also what keeps this a bounded wait rather than the raw
-- indefinite sleep the readiness kernel exists to forbid.
blockForever :: IO value
blockForever = do
  blocker <- newEmptyMVar
  void (timeout fixtureBlockingIntervalMicros (takeMVar blocker))
  blockForever

observerEnvironment :: [(String, String)]
observerEnvironment =
  [ ("LANG", "C"),
    ("LC_ALL", "C"),
    ("PATH", "/usr/bin:/bin"),
    ("TMPDIR", "/tmp")
  ]

-- process-1.6.26.1 on the supported Apple host reports ENOENT from its child
-- chdir path for @cwd = Just "/"@, even with an absolute executable. The fixed
-- /tmp directory exercises the same public close_fds/create_group path without
-- making the working directory caller-controlled.
observerWorkingDirectory :: FilePath
observerWorkingDirectory = "/tmp"

observerFixtureGate :: String
observerFixtureGate = "start\n"

observerFixtureModeArgument :: String
observerFixtureModeArgument =
  "__infernix-internal-fixed-observer-fixture-v1"

synchronousFixtureFailureMarker :: String
synchronousFixtureFailureMarker =
  "injected synchronous fixed observer fixture failure"

fixtureNonzeroExitCode :: Int
fixtureNonzeroExitCode = 23

-- | One re-armed blocking interval for a fixture that must outlive its
-- observer's deadline. Any bound far above every fixture deadline below works.
fixtureBlockingIntervalMicros :: Int
fixtureBlockingIntervalMicros = 60000000

-- The full-host Darwin @top@ snapshot has a wider bound than the fixed NVIDIA
-- query. The selected Apple cohort measured a healthy @top@ invocation exceed
-- the former five-second total budget while the first real model was loading;
-- killing that model converted scheduler pressure into enforcement loss. The
-- Apple lane is detection-only already, so the honest contract is a still-total
-- fifteen-second sample bound. Linux keeps the five-second NVIDIA bound whose
-- healthy query is measured in tens of milliseconds.
observerSampleTimeoutMicros :: Int
observerSampleTimeoutMicros =
  case currentFixedObserverLane of
    AppleFixedObserverLane -> 15000000
    NvidiaFixedObserverLane -> 5000000

observerCleanupTimeoutMicros :: Int
observerCleanupTimeoutMicros = 2000000

fixtureCompletionTimeoutMicros :: Int
fixtureCompletionTimeoutMicros = 3000000

fixtureLongRunningTimeoutMicros :: Int
fixtureLongRunningTimeoutMicros = 10000000

fixtureTimeoutMicros :: Int
fixtureTimeoutMicros = 1000000

fixtureAbsenceTimeoutMicros :: Int
fixtureAbsenceTimeoutMicros = 3000000

maximumTopOutputBytes :: Int
maximumTopOutputBytes = 8 * 1024 * 1024

maximumFootprintOutputBytes :: Int
maximumFootprintOutputBytes = 256 * 1024

-- | @nvidia-smi@ emits one short CSV row per compute application or device, so
-- its bounds are far tighter than the Darwin @top@ full-process-table dump.
maximumNvidiaOutputBytes :: Int
maximumNvidiaOutputBytes = 256 * 1024

maximumNvidiaOutputLines :: Int
maximumNvidiaOutputLines = 4096

maximumNvidiaProcessRows :: Int
maximumNvidiaProcessRows = 1024

-- | The fixed NVIDIA observation tool. Pinned as an absolute path for the same
-- reason as @\/usr\/bin\/top@: enforcement must not follow a caller-supplied,
-- manifest-supplied, or @PATH@-resolved executable.
nvidiaSmiExecutable :: FilePath
nvidiaSmiExecutable = "/usr/bin/nvidia-smi"

maximumFixtureOutputBytes :: Int
maximumFixtureOutputBytes = 64 * 1024

maximumObserverStderrBytes :: Int
maximumObserverStderrBytes = 64 * 1024

observerDrainChunkBytes :: Int
observerDrainChunkBytes = 32768

maximumObserverLineBytes :: Int
maximumObserverLineBytes = 4096

maximumTopOutputLines :: Int
maximumTopOutputLines = 65536

maximumTopProcessRows :: Int
maximumTopProcessRows = 65535

maximumFootprintOutputLines :: Int
maximumFootprintOutputLines = 4096

maximumObservedGroupMembers :: Int
maximumObservedGroupMembers = 256

maximumWord64DecimalDigits :: Int
maximumWord64DecimalDigits = 20

maximumPosixProcessId :: Word64
maximumPosixProcessId = 2147483647
