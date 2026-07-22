{-# LANGUAGE CPP #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Phase 4 Sprint 4.30 — the capped-engine kernel: the memory analog of the
-- bounded-command kernel ('Infernix.Cluster.Subprocess.runBoundedCommand' under a
-- required 'Timeout'). An inference engine subprocess runs only through
-- 'withCappedEngine', which requires a 'MemoryGrant' minted by
-- 'Infernix.Types.admitModelMemory' and bounds the subprocess's actual resident
-- memory to the admitted 'MemoryCeiling'. The raw process-spawn primitives
-- ('createProcess' / 'waitForProcess') are imported here but deliberately NOT
-- re-exported, so an engine spawn without a grant — or one whose resident memory
-- is not bounded to its grant — is not a constructible term for the rest of the
-- runtime. On @apple-silicon@ (host-native, no cgroups) a watchdog samples the
-- child's physical footprint via @proc_pid_rusage@ and @SIGKILL@s its process
-- group on breach; on @linux-cpu@ / @linux-gpu@ the pod cgroup / CUDA allocator
-- already bound the process, and the kernel classifies the OOM exit. Every
-- substrate returns the one total 'EngineOutcome' whose 'EngineExceededCeiling'
-- arm maps to a clean @status=failed@ 'Infernix.Types.ModelMemoryLimitExceeded'
-- rather than a host OOM-kill. Canonical doctrine:
-- 'documents/architecture/bounded_inference_memory.md'.
module Infernix.Runtime.CappedEngine
  ( EngineHandle,
    EngineOutcome (..),
    engineStdin,
    engineStdout,
    engineStderr,
    withCappedEngine,
    awaitEngineOutcome,
    engineOutcomeExitCode,
    runCappedProcess,
    runCappedStdioEngine,
  )
where

import Control.Concurrent (ThreadId, forkIO, killThread, threadDelay)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (SomeException, bracket, catch, evaluate, throwIO)
import Control.Monad (unless, void)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Word (Word64)
import Foreign.C.Error (Errno (Errno), ePIPE)
import GHC.IO.Exception (IOErrorType (ResourceVanished), IOException (IOError, ioe_errno, ioe_type))
import Infernix.Types (MemoryCeiling, MemoryGrant, grantMemoryCeiling, memoryCeilingMib)
import System.Exit (ExitCode (..))
import System.IO (Handle, hClose, hGetContents, hPutStr)
import System.Posix.Signals (sigKILL, signalProcessGroup)
import System.Posix.Types (CPid)
import System.Process
  ( CreateProcess (create_group, std_err, std_in, std_out),
    ProcessHandle,
    StdStream (CreatePipe),
    createProcess,
    getPid,
    waitForProcess,
  )
#if defined(darwin_HOST_OS)
import Foreign.C.Types (CInt (..))
import Foreign.Marshal.Alloc (allocaBytes)
import Foreign.Ptr (Ptr, castPtr)
import Foreign.Storable (peekByteOff)
#endif

-- | The total terminal outcome of a capped-engine subprocess. 'EngineExited'
-- carries the process exit code (which may itself be a non-memory failure the
-- realness contract maps to @status=failed@). 'EngineExceededCeiling' is the
-- memory-safety terminal: the resident footprint breached the admitted ceiling
-- and the kernel killed the process group (@apple-silicon@ watchdog) or the pod
-- cgroup OOM-killed it (@linux-*@); it maps to
-- 'Infernix.Types.ModelMemoryLimitExceeded', never a host OOM.
data EngineOutcome
  = EngineExited ExitCode
  | EngineExceededCeiling MemoryCeiling
  deriving (Eq, Show)

-- | A live capped-engine subprocess. The phantom @s@ plus the rank-2 scope of
-- 'withCappedEngine' keep the handle from escaping the region in which the
-- ceiling is actively enforced. The stdio handles are exposed for the caller's
-- request/response protocol; the raw 'ProcessHandle', the breach flag, and the
-- watchdog thread are hidden so the only way to a terminal result is
-- 'awaitEngineOutcome'.
data EngineHandle s = EngineHandle
  { engineStdin :: Maybe Handle,
    engineStdout :: Maybe Handle,
    engineStderr :: Maybe Handle,
    engineProcess :: ProcessHandle,
    engineCeiling :: MemoryCeiling,
    engineBreach :: IORef Bool,
    engineWatchdog :: ThreadId
  }

-- | The sole engine-spawn path. Requires a 'MemoryGrant', launches the
-- subprocess as its own process-group leader, arms the physical-footprint
-- watchdog, and guarantees — via 'bracket' — that the watchdog is torn down and
-- the process group is killed on every exit path, including exception. The
-- rank-2 @forall s.@ prevents the 'EngineHandle' from escaping the enforced
-- region.
withCappedEngine :: MemoryGrant -> CreateProcess -> (forall s. EngineHandle s -> IO r) -> IO r
withCappedEngine grant spec action = bracket acquire release runInRegion
  where
    -- Bound (rather than eta-reduced) because the rank-2 @action@ cannot be
    -- eta-reduced past 'bracket' without impredicative polymorphism; the
    -- monomorphism restriction fixes @runInRegion@ at the region's handle type.
    runInRegion = action
    ceilingValue = grantMemoryCeiling grant
    acquire = do
      (maybeIn, maybeOut, maybeErr, processHandle) <-
        createProcess spec {create_group = True}
      breachRef <- newIORef False
      watchdog <- forkIO (runCeilingWatchdog processHandle ceilingValue breachRef)
      pure
        EngineHandle
          { engineStdin = maybeIn,
            engineStdout = maybeOut,
            engineStderr = maybeErr,
            engineProcess = processHandle,
            engineCeiling = ceilingValue,
            engineBreach = breachRef,
            engineWatchdog = watchdog
          }
    release handle = do
      killThread (engineWatchdog handle)
      killEngineProcessGroup (engineProcess handle)
      void (waitForProcess (engineProcess handle))
        `catch` \(_ :: SomeException) -> pure ()

-- | Reap the subprocess and classify its terminal outcome. A ceiling breach —
-- either the @apple-silicon@ watchdog set the breach flag before killing the
-- group, or the process exited with the OOM-kill signature the pod cgroup
-- produces on @linux-*@ — becomes 'EngineExceededCeiling'; anything else is the
-- raw 'EngineExited' code.
awaitEngineOutcome :: EngineHandle s -> IO EngineOutcome
awaitEngineOutcome handle = do
  exitCode <- waitForProcess (engineProcess handle)
  breached <- readIORef (engineBreach handle)
  pure $
    if breached || exitCodeIndicatesOom exitCode
      then EngineExceededCeiling (engineCeiling handle)
      else EngineExited exitCode

-- | The exit code a caller that only needs an exit status should see. A ceiling
-- breach surfaces as an OOM-style failure exit so a downstream that ignores the
-- 'EngineOutcome' still fails closed.
engineOutcomeExitCode :: EngineOutcome -> ExitCode
engineOutcomeExitCode outcome = case outcome of
  EngineExited exitCode -> exitCode
  EngineExceededCeiling _ -> ExitFailure 137

-- | Run an engine subprocess to completion under its ceiling, mirroring
-- @readCreateProcessWithExitCode@ (text stdin/stdout/stderr) for the native
-- runner path. Streams are drained concurrently so a full pipe cannot deadlock
-- the wait.
runCappedProcess :: MemoryGrant -> CreateProcess -> String -> IO (EngineOutcome, ExitCode, String, String)
runCappedProcess grant spec input =
  withCappedEngine grant (withStdioPipes spec) $ \handle ->
    case (engineStdin handle, engineStdout handle, engineStderr handle) of
      (Just stdinHandle, Just stdoutHandle, Just stderrHandle) -> do
        stderrVar <- newEmptyMVar
        _ <- forkIO (readAllText stderrHandle >>= putMVar stderrVar)
        ignoreSigPipe (unless (null input) (hPutStr stdinHandle input) >> hClose stdinHandle)
        stdoutOutput <- readAllText stdoutHandle
        stderrOutput <- takeMVar stderrVar
        outcome <- awaitEngineOutcome handle
        pure (outcome, engineOutcomeExitCode outcome, stdoutOutput, stderrOutput)
      _ -> failMissingPipes

-- | Run an engine subprocess to completion under its ceiling for the Python
-- stdio protocol (binary stdin payload, binary stdout/stderr capture). Streams
-- are drained concurrently so a full pipe cannot deadlock the wait.
runCappedStdioEngine :: MemoryGrant -> CreateProcess -> ByteString -> IO (EngineOutcome, ExitCode, ByteString, ByteString)
runCappedStdioEngine grant spec input =
  withCappedEngine grant (withStdioPipes spec) $ \handle ->
    case (engineStdin handle, engineStdout handle, engineStderr handle) of
      (Just stdinHandle, Just stdoutHandle, Just stderrHandle) -> do
        stderrVar <- newEmptyMVar
        _ <- forkIO (ByteString.hGetContents stderrHandle >>= putMVar stderrVar)
        ignoreSigPipe (ByteString.hPut stdinHandle input >> hClose stdinHandle)
        stdoutOutput <- ByteString.hGetContents stdoutHandle
        stderrOutput <- takeMVar stderrVar
        outcome <- awaitEngineOutcome handle
        pure (outcome, engineOutcomeExitCode outcome, stdoutOutput, stderrOutput)
      _ -> failMissingPipes

withStdioPipes :: CreateProcess -> CreateProcess
withStdioPipes spec =
  spec
    { std_in = CreatePipe,
      std_out = CreatePipe,
      std_err = CreatePipe
    }

readAllText :: Handle -> IO String
readAllText handleValue = do
  contents <- hGetContents handleValue
  _ <- evaluate (length contents)
  pure contents

-- | Swallow the @EPIPE@ (`ResourceVanished`) that a stdin write raises when the
-- engine subprocess has already closed its read end — e.g. it exited early or
-- the watchdog SIGKILLed it mid-transfer of a payload larger than the pipe
-- buffer. GHC ignores @SIGPIPE@ and surfaces it as an 'IOException', which would
-- otherwise escape the capped region before 'awaitEngineOutcome' can classify
-- the terminal outcome; swallowing it lets the drain-and-classify path complete
-- (mirroring @System.Process@'s own @ignoreSigPipe@ around its stdin write).
ignoreSigPipe :: IO () -> IO ()
ignoreSigPipe action = action `catch` sigPipeHandler
  where
    sigPipeHandler :: IOException -> IO ()
    sigPipeHandler ioException = case ioException of
      IOError {ioe_type = ResourceVanished, ioe_errno = Just errno}
        | Errno errno == ePIPE -> pure ()
      _ -> throwIO ioException

failMissingPipes :: IO a
failMissingPipes = ioError (userError "capped engine subprocess did not expose the requested stdio pipes")

-- | Send SIGKILL to the subprocess's process group (it was launched as a group
-- leader), reaping the whole engine subtree. Best-effort: a process already
-- reaped has no pid and the signal to a dead group is ignored.
killEngineProcessGroup :: ProcessHandle -> IO ()
killEngineProcessGroup processHandle = do
  maybePid <- getPid processHandle
  case maybePid of
    Nothing -> pure ()
    Just pid -> signalProcessGroup sigKILL pid `catch` \(_ :: SomeException) -> pure ()

-- | The watchdog loop: sample the child's physical footprint; on breach, record
-- it and SIGKILL the process group; otherwise sleep one interval and repeat. On
-- @linux-*@ 'physicalFootprintBytes' returns @0@ (the pod cgroup enforces), so
-- the loop simply idles until the process exits.
runCeilingWatchdog :: ProcessHandle -> MemoryCeiling -> IORef Bool -> IO ()
runCeilingWatchdog processHandle ceilingValue breachRef = loop
  where
    ceilingBytes = fromIntegral (memoryCeilingMib ceilingValue) * bytesPerMib
    loop = do
      maybePid <- getPid processHandle
      case maybePid of
        Nothing -> pure ()
        Just pid -> do
          footprint <- physicalFootprintBytes pid
          if footprint > 0 && footprint > ceilingBytes
            then do
              writeIORef breachRef True
              signalProcessGroup sigKILL pid `catch` \(_ :: SomeException) -> pure ()
            else do
              threadDelay watchdogIntervalMicros
              loop

bytesPerMib :: Word64
bytesPerMib = 1048576

watchdogIntervalMicros :: Int
watchdogIntervalMicros = 250000

#if defined(darwin_HOST_OS)

-- | @proc_pid_rusage(pid, RUSAGE_INFO_V2, &info)@ from @libproc@ (part of the
-- system @libSystem@, no extra link flag). The physical-footprint field
-- @ri_phys_footprint@ measures resident + compressed memory the way Activity
-- Monitor does — the honest number to bound against, unlike an address-space
-- rlimit that Metal / Python virtual reservations would blow through.
foreign import ccall unsafe "proc_pid_rusage"
  c_proc_pid_rusage :: CInt -> CInt -> Ptr () -> IO CInt

rusageInfoV2Flavor :: CInt
rusageInfoV2Flavor = 2

-- | Byte offset of @ri_phys_footprint@ inside @struct rusage_info_v2@:
-- @ri_uuid[16]@ (16 bytes) followed by seven @uint64_t@ fields.
physFootprintByteOffset :: Int
physFootprintByteOffset = 72

-- | @struct rusage_info_v2@ is under 200 bytes; over-allocate for headroom.
rusageInfoV2Bytes :: Int
rusageInfoV2Bytes = 256

physicalFootprintBytes :: CPid -> IO Word64
physicalFootprintBytes pid =
  allocaBytes rusageInfoV2Bytes $ \buffer -> do
    result <- c_proc_pid_rusage (fromIntegral pid) rusageInfoV2Flavor (castPtr buffer)
    if result == 0
      then peekByteOff buffer physFootprintByteOffset
      else pure 0

exitCodeIndicatesOom :: ExitCode -> Bool
exitCodeIndicatesOom _ = False

#else

-- | On Linux the pod cgroup / CUDA allocator bound the process; the host cannot
-- OOM. The watchdog therefore does not sample (returns @0@), and a breach is
-- recognized only after the fact by the cgroup OOM-kill exit signature.
physicalFootprintBytes :: CPid -> IO Word64
physicalFootprintBytes _ = pure 0

-- | The pod cgroup OOM killer delivers SIGKILL, which surfaces as
-- @ExitFailure (-9)@ (killed by signal 9) or @ExitFailure 137@ (128 + 9).
exitCodeIndicatesOom :: ExitCode -> Bool
exitCodeIndicatesOom exitCode = case exitCode of
  ExitFailure code -> code == 137 || code == (-9)
  ExitSuccess -> False

#endif
