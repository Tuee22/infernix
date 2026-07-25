-- | Phase 1 Sprint 1.16 — the bounded-command kernel of the
-- managed-state-transition doctrine
-- ('documents/architecture/managed_state_transitions.md'). 'SubprocessEnv'
-- carries @HOME@ and @TMPDIR@ as required fields behind a hidden constructor,
-- so a subprocess spawned with an environment missing them is unrepresentable;
-- values come from the typed host manifest and the repo-local data root, never
-- from a process-inherited environment variable. 'runBoundedCommand' takes a
-- required 'Timeout' and returns a total 'CommandOutcome', so an unbounded exec
-- and a success-or-fatal collapse are both unrepresentable. The raw spawn
-- primitive is not exported.
module Infernix.Cluster.Subprocess
  ( SubprocessEnv,
    subprocessEnvSearchPath,
    subprocessEnvHome,
    subprocessEnvTmpdir,
    clusterSubprocessEnv,
    clusterSubprocessEnvWithSearchPath,
    subprocessEnvWithOverrides,
    renderSubprocessEnv,
    Timeout (..),
    RetryPolicy (..),
    FailureClass (..),
    ClusterOperation (..),
    BoundedCommand,
    CommandOutcome (..),
    compileBoundedCommand,
    runBoundedCommand,
  )
where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Monad (void)
import Data.List qualified as List
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Infernix.Config (Paths (..))
import Infernix.HostConfig qualified as HostConfig
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO (hClose, hGetContents, hPutStr)
import System.Process
  ( CreateProcess (..),
    StdStream (CreatePipe),
    proc,
    waitForProcess,
    withCreateProcess,
  )
import System.Timeout (timeout)

-- | A total process environment. The constructor is hidden and
-- 'clusterSubprocessEnv' is the sole builder, so @HOME@ and @TMPDIR@ are
-- always present.
data SubprocessEnv = SubprocessEnv
  { subprocessEnvSearchPath :: !FilePath,
    subprocessEnvHome :: !FilePath,
    subprocessEnvTmpdir :: !FilePath,
    subprocessEnvLang :: !String,
    subprocessEnvExtra :: ![(String, String)]
  }

-- | Build the environment for host subprocesses from the typed host
-- manifest and the repo-local data root. Fails closed when the manifest is
-- absent rather than falling back to an ambient environment.
clusterSubprocessEnv :: Paths -> IO SubprocessEnv
clusterSubprocessEnv paths =
  case pathsHostConfig paths of
    Nothing -> missingManifestError "clusterSubprocessEnv"
    Just config -> clusterSubprocessEnvWithSearchPath paths (searchPathForHost config)

-- | Build the subprocess environment with a caller-supplied @PATH@ (for callers
-- that assemble their own tool-directory search path) while still requiring
-- @HOME@ and @TMPDIR@ from the typed host manifest and the repo-local data root.
-- Fails closed when the manifest is absent rather than falling back to an
-- ambient environment, so a subprocess spawned without @HOME@/@TMPDIR@ is
-- unrepresentable.
clusterSubprocessEnvWithSearchPath :: Paths -> FilePath -> IO SubprocessEnv
clusterSubprocessEnvWithSearchPath paths searchPath =
  case pathsHostConfig paths of
    Nothing -> missingManifestError "clusterSubprocessEnvWithSearchPath"
    Just config -> do
      let home =
            Text.unpack (HostConfig.hostHomeDirectory (HostConfig.hostFilesystem config))
          tmpdir = dataRoot paths </> "tmp"
      createDirectoryIfMissing True tmpdir
      pure
        SubprocessEnv
          { subprocessEnvSearchPath = searchPath,
            subprocessEnvHome = home,
            subprocessEnvTmpdir = tmpdir,
            subprocessEnvLang = "C.UTF-8",
            subprocessEnvExtra = []
          }

missingManifestError :: String -> IO a
missingManifestError caller =
  ioError
    ( userError
        ( caller
            <> ": host manifest is unavailable; run `infernix init` to stage "
            <> "./infernix-host.dhall before invoking external commands"
        )
    )

-- | Compose @PATH@ from the parent directories of the manifest's tool paths
-- plus the fixed fallback system directories, deduplicated in order.
searchPathForHost :: HostConfig.HostConfig -> FilePath
searchPathForHost config =
  List.intercalate ":" (List.nub (toolDirs <> fallbackDirs))
  where
    toolPaths = HostConfig.hostToolPaths config
    toolDirs =
      map
        (takeDirectory . Text.unpack)
        [ HostConfig.hostDocker toolPaths,
          HostConfig.hostKubectl toolPaths,
          HostConfig.hostHelm toolPaths,
          HostConfig.hostKind toolPaths,
          HostConfig.hostCabal toolPaths,
          HostConfig.hostGhc toolPaths,
          HostConfig.hostNpm toolPaths,
          HostConfig.hostNode toolPaths,
          HostConfig.hostPython3 toolPaths,
          HostConfig.hostPoetry toolPaths,
          HostConfig.hostProtoc toolPaths,
          HostConfig.hostGit toolPaths,
          HostConfig.hostTar toolPaths,
          HostConfig.hostCurl toolPaths
        ]
    fallbackDirs =
      [ "/usr/local/sbin",
        "/usr/local/bin",
        "/usr/sbin",
        "/usr/bin",
        "/sbin",
        "/bin"
      ]

-- | Render the environment for a spawn. @HOME@ and @TMPDIR@ are always
-- present because 'SubprocessEnv' cannot be built without them.
renderSubprocessEnv :: SubprocessEnv -> [(String, String)]
renderSubprocessEnv environment =
  [ ("PATH", subprocessEnvSearchPath environment),
    ("HOME", subprocessEnvHome environment),
    ("TMPDIR", subprocessEnvTmpdir environment),
    ("LANG", subprocessEnvLang environment),
    ("LC_ALL", subprocessEnvLang environment)
  ]
    <> subprocessEnvExtra environment

-- | Add command-specific variables without permitting callers to replace the
-- kernel-owned total-environment fields.
subprocessEnvWithOverrides :: [(String, String)] -> SubprocessEnv -> Either String SubprocessEnv
subprocessEnvWithOverrides overrides environment =
  case filter ((`elem` protectedNames) . fst) overrides of
    [] -> Right environment {subprocessEnvExtra = overrides <> subprocessEnvExtra environment}
    protected ->
      Left ("subprocess overrides cannot replace kernel-owned variables: " <> show (map fst protected))
  where
    protectedNames = ["PATH", "HOME", "TMPDIR", "LANG", "LC_ALL"]

-- | A required wall-clock bound for a subprocess, in microseconds.
newtype Timeout = Timeout {timeoutMicros :: Int}
  deriving (Eq, Show)

-- | The total outcome of a bounded command. 'CommandFailedTransient' is
-- assigned by a caller's failure policy reclassifying a 'CommandFailedFatal'
-- (for example an idempotent delete whose target was already gone); the raw
-- primitive itself only produces success, fatal, or timeout.
data CommandOutcome
  = CommandSucceeded !String
  | CommandFailedTransient !String
  | CommandFailedFatal !String
  | CommandTimedOut !Timeout
  deriving (Eq, Show)

data RetryPolicy
  = NeverRetry
  | BoundedRetry !Int !Int
  deriving (Eq, Show)

data FailureClass
  = FatalFailure
  | TransientThenFatal
  | IdempotentAbsence
  deriving (Eq, Show)

data ClusterOperation
  = ClusterLifecycleOperation
  | ImagePublicationOperation
  | LongRunningLifecycleOperation
  deriving (Eq, Show)

data BoundedCommand = BoundedCommand
  { boundedTimeout :: !Timeout,
    boundedEnvironment :: !SubprocessEnv,
    boundedWorkingDirectory :: !(Maybe FilePath),
    boundedExecutable :: !FilePath,
    boundedArguments :: ![String],
    boundedInput :: !String,
    boundedRetryPolicy :: !RetryPolicy,
    boundedFailureClass :: !FailureClass
  }

compileBoundedCommand ::
  ClusterOperation ->
  Timeout ->
  RetryPolicy ->
  FailureClass ->
  SubprocessEnv ->
  Maybe FilePath ->
  FilePath ->
  [String] ->
  String ->
  Either String BoundedCommand
compileBoundedCommand _operation budget retryPolicy failureClass environment workingDirectory command arguments input
  | timeoutMicros budget <= 0 = Left "bounded command timeout must be positive"
  | null command = Left "bounded command executable must be non-empty"
  | BoundedRetry attempts backoffMicros <- retryPolicy,
    attempts <= 0 || backoffMicros < 0 =
      Left "bounded retry requires positive attempts and non-negative backoff"
  | otherwise =
      Right
        BoundedCommand
          { boundedTimeout = budget,
            boundedEnvironment = environment,
            boundedWorkingDirectory = workingDirectory,
            boundedExecutable = command,
            boundedArguments = arguments,
            boundedInput = input,
            boundedRetryPolicy = retryPolicy,
            boundedFailureClass = failureClass
          }

-- | Run a command under a required 'Timeout' with a total 'SubprocessEnv'.
-- On timeout the child is reaped — 'withCreateProcess' terminates it on the
-- async exception raised by 'timeout' — and the result is 'CommandTimedOut'.
runBoundedCommand :: BoundedCommand -> IO CommandOutcome
runBoundedCommand command = runAttempts (retryAttempts (boundedRetryPolicy command))
  where
    runAttempts remaining = do
      outcome <- runRawBoundedCommand command
      case (outcome, boundedRetryPolicy command, remaining) of
        (CommandFailedFatal message, _, _)
          | boundedFailureClass command == IdempotentAbsence,
            any (`List.isInfixOf` message) ["not found", "does not exist", "No such"] ->
              pure (CommandSucceeded message)
        (CommandFailedFatal _, BoundedRetry _ backoffMicros, attemptsLeft)
          | attemptsLeft > 1 && boundedFailureClass command == TransientThenFatal -> do
              delayVar <- newEmptyMVar
              void (timeout backoffMicros (takeMVar delayVar))
              runAttempts (attemptsLeft - 1)
        _ -> pure outcome

retryAttempts :: RetryPolicy -> Int
retryAttempts NeverRetry = 1
retryAttempts (BoundedRetry attempts _) = attempts

runRawBoundedCommand :: BoundedCommand -> IO CommandOutcome
runRawBoundedCommand command = do
  let spec =
        (proc (boundedExecutable command) (boundedArguments command))
          { cwd = boundedWorkingDirectory command,
            env = Just (renderSubprocessEnv (boundedEnvironment command)),
            std_in = CreatePipe,
            std_out = CreatePipe,
            std_err = CreatePipe
          }
  result <-
    timeout (timeoutMicros (boundedTimeout command)) (withCreateProcess spec collect)
  pure (fromMaybe (CommandTimedOut (boundedTimeout command)) result)
  where
    collect maybeIn maybeOut maybeErr processHandle =
      case (maybeIn, maybeOut, maybeErr) of
        (Just stdinHandle, Just stdoutHandle, Just stderrHandle) -> do
          stdoutVar <- newEmptyMVar
          stderrVar <- newEmptyMVar
          void (forkIO (drain stdoutHandle stdoutVar))
          void (forkIO (drain stderrHandle stderrVar))
          hPutStr stdinHandle (boundedInput command)
          hClose stdinHandle
          out <- takeMVar stdoutVar
          err <- takeMVar stderrVar
          code <- waitForProcess processHandle
          pure (classifyExit code out err)
        _ ->
          pure
            (CommandFailedFatal "runBoundedCommand: process pipes were not created")
    drain handle var = do
      contents <- hGetContents handle
      length contents `seq` putMVar var contents

classifyExit :: ExitCode -> String -> String -> CommandOutcome
classifyExit ExitSuccess out _ = CommandSucceeded out
classifyExit (ExitFailure code) out err =
  CommandFailedFatal
    ("exit " <> show code <> "\nstdout:\n" <> out <> "\nstderr:\n" <> err)
