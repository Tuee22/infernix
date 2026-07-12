module Infernix.ProcessMonitor
  ( CommandMonitor (..),
    tryCommandMonitored,
  )
where

import Control.Concurrent (forkIO, newEmptyMVar, putMVar, threadDelay, tryReadMVar)
import Control.Exception (SomeException, bracket, evaluate, throwIO, try)
import Data.List qualified as List
import Data.Text qualified as Text
import Infernix.Config (Paths (..))
import Infernix.Config qualified as Config
import Infernix.HostConfig qualified as HostConfig
import Infernix.HostTools (HostTool (..))
import Infernix.HostTools qualified as HostTools
import System.Directory (getTemporaryDirectory, removeFile)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath (takeDirectory)
import System.IO (Handle, hClose, openTempFile)
import System.Process
  ( CreateProcess (cwd, env, std_err, std_in, std_out),
    ProcessHandle,
    StdStream (NoStream, UseHandle),
    createProcess,
    proc,
    waitForProcess,
  )

data CommandMonitor = CommandMonitor
  { monitorLabel :: String,
    monitorIntervalMicros :: Int,
    monitorHeartbeat :: Int -> IO ()
  }

-- | Phase 2 Sprint 2.13: @getEnvironment@ whole-env capture retired.
-- Phase 7 Sprint 7.17 Apple cohort closure (2026-05-29): the
-- subprocess PATH is derived from the staged host manifest's
-- @toolPaths@ so nested third-party invocations (most importantly
-- @kind@ shelling out to @docker@) resolve the same absolute binaries
-- the binary itself uses, including Apple Silicon Homebrew's
-- @\/opt\/homebrew\/bin@ prefix. Mirrors
-- 'Infernix.Cluster.clusterSubprocessBaseEnvFor'.
tryCommandMonitored :: Maybe FilePath -> [(String, String)] -> FilePath -> [String] -> Maybe CommandMonitor -> IO (Either String String)
tryCommandMonitored maybeWorkingDirectory envOverrides command args maybeMonitor = do
  paths <- Config.discoverPaths
  temporaryDirectory <- getTemporaryDirectory
  withTempCaptureFile temporaryDirectory "infernix-stdout" $ \stdoutPath stdoutHandle ->
    withTempCaptureFile temporaryDirectory "infernix-stderr" $ \stderrPath stderrHandle -> do
      let mergedEnv = mergeEnvironment (processMonitorBaseEnvFor paths) envOverrides
      processResult <-
        try
          ( do
              (_, _, _, processHandle) <-
                createProcess
                  (proc command args)
                    { cwd = maybeWorkingDirectory,
                      env = Just mergedEnv,
                      std_in = NoStream,
                      std_out = UseHandle stdoutHandle,
                      std_err = UseHandle stderrHandle
                    }
              pure processHandle
          ) ::
          IO (Either SomeException ProcessHandle)
      case processResult of
        Left err -> pure (Left (show err))
        Right processHandle -> do
          exitCode <- waitForMonitoredExit maybeMonitor processHandle
          hClose stdoutHandle
          hClose stderrHandle
          stdoutOutput <- readFileStrict stdoutPath
          stderrOutput <- readFileStrict stderrPath
          pure $
            case exitCode of
              ExitSuccess -> Right stdoutOutput
              _ -> Left (stdoutOutput <> stderrOutput)

withTempCaptureFile :: FilePath -> String -> (FilePath -> Handle -> IO a) -> IO a
withTempCaptureFile temporaryDirectory template action =
  bracket
    (openTempFile temporaryDirectory template)
    (\(path, handle) -> do catchRemoveFailure (hClose handle); catchRemoveFailure (removeFile path))
    (uncurry action)

readFileStrict :: FilePath -> IO String
readFileStrict path = do
  contents <- readFile path
  _ <- evaluate (length contents)
  pure contents

waitForMonitoredExit :: Maybe CommandMonitor -> ProcessHandle -> IO ExitCode
waitForMonitoredExit maybeMonitor processHandle =
  case maybeMonitor of
    Nothing -> waitForProcess processHandle
    Just monitor -> do
      processExit <- newEmptyMVar
      _ <-
        forkIO $
          (try (waitForProcess processHandle) :: IO (Either SomeException ExitCode))
            >>= putMVar processExit
      go processExit 0 0
      where
        intervalMicros = max 1000000 (monitorIntervalMicros monitor)
        pollIntervalMicros = 1000000
        pollIntervalSeconds = pollIntervalMicros `divUp` 1000000
        go processExit elapsedMicros elapsedSeconds = do
          maybeExit <- tryReadMVar processExit
          case maybeExit of
            Just (Right exitCode) -> pure exitCode
            Just (Left err) -> throwIO err
            Nothing -> do
              threadDelay pollIntervalMicros
              let nextElapsedMicros = elapsedMicros + pollIntervalMicros
                  nextElapsedSeconds = elapsedSeconds + pollIntervalSeconds
              if nextElapsedMicros >= intervalMicros
                then do
                  putStrLn (monitorLabel monitor <> ": still running after " <> show nextElapsedSeconds <> "s")
                  monitorHeartbeat monitor nextElapsedSeconds
                  go processExit 0 nextElapsedSeconds
                else
                  go processExit nextElapsedMicros nextElapsedSeconds

mergeEnvironment :: [(String, String)] -> [(String, String)] -> [(String, String)]
mergeEnvironment baseEnv overrides =
  overrides <> filter (\(key, _) -> key `notElem` map fst overrides) baseEnv

-- | The supported base env for monitored subprocesses. Mirrors
-- 'Infernix.Cluster.clusterSubprocessBaseEnvFor': the PATH entry is
-- derived from the staged host manifest's @toolPaths@ parent
-- directories so nested third-party tool invocations (the canonical
-- example is @kind@ shelling out to @docker@ via PATH lookup) find
-- the same absolute binaries the binary itself uses. Falls back to
-- the minimal POSIX search path when the manifest is absent (e.g.
-- unit-test fixtures without a 'HostConfig').
processMonitorBaseEnvFor :: Paths -> [(String, String)]
processMonitorBaseEnvFor paths =
  [ ("PATH", processMonitorSearchPath paths),
    ("LANG", "C.UTF-8"),
    ("LC_ALL", "C.UTF-8")
  ]

processMonitorSearchPath :: Paths -> String
processMonitorSearchPath paths =
  let fallback =
        [ "/usr/local/sbin",
          "/usr/local/bin",
          "/usr/sbin",
          "/usr/bin",
          "/sbin",
          "/bin"
        ]
      manifestDirs = maybe [] processMonitorHostToolDirs (pathsHostConfig paths)
   in List.intercalate ":" (List.nub (manifestDirs <> fallback))

processMonitorHostToolDirs :: HostConfig.HostConfig -> [FilePath]
processMonitorHostToolDirs config =
  let allTools =
        [ HostDocker,
          HostKubectl,
          HostHelm,
          HostKind,
          HostCurl,
          HostTar,
          HostBash,
          HostSkopeo,
          HostHostname,
          HostChown,
          HostNvidiaSmi,
          HostNvkind,
          HostCrictl
        ]
      pathFor tool = Text.unpack (HostTools.hostToolPath config tool)
      absoluteEntries =
        [ takeDirectory entry
        | tool <- allTools,
          let entry = pathFor tool,
          not (null entry)
        ]
   in List.nub absoluteEntries

catchRemoveFailure :: IO () -> IO ()
catchRemoveFailure action = do
  _ <- try action :: IO (Either SomeException ())
  pure ()

divUp :: Int -> Int -> Int
divUp numerator denominator =
  max 1 ((numerator + denominator - 1) `div` denominator)
