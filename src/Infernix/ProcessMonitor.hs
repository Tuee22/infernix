module Infernix.ProcessMonitor
  ( CommandMonitor (..),
    tryCommandMonitored,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, bracket, evaluate, try)
import System.Directory (getTemporaryDirectory, removeFile)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (ExitSuccess))
import System.IO (Handle, hClose, openTempFile)
import System.Process
  ( CreateProcess (cwd, env, std_err, std_in, std_out),
    ProcessHandle,
    StdStream (NoStream, UseHandle),
    createProcess,
    getProcessExitCode,
    proc,
    waitForProcess,
  )

data CommandMonitor = CommandMonitor
  { monitorLabel :: String,
    monitorIntervalMicros :: Int,
    monitorHeartbeat :: Int -> IO ()
  }

tryCommandMonitored :: Maybe FilePath -> [(String, String)] -> FilePath -> [String] -> Maybe CommandMonitor -> IO (Either String String)
tryCommandMonitored maybeWorkingDirectory envOverrides command args maybeMonitor = do
  temporaryDirectory <- getTemporaryDirectory
  withTempCaptureFile temporaryDirectory "infernix-stdout" $ \stdoutPath stdoutHandle ->
    withTempCaptureFile temporaryDirectory "infernix-stderr" $ \stderrPath stderrHandle -> do
      baseEnv <- getEnvironment
      let mergedEnv = mergeEnvironment baseEnv envOverrides
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
    Just monitor -> go 0 0
      where
        intervalMicros = max 1000000 (monitorIntervalMicros monitor)
        pollIntervalMicros = 1000000
        pollIntervalSeconds = pollIntervalMicros `divUp` 1000000
        go elapsedMicros elapsedSeconds = do
          threadDelay pollIntervalMicros
          let nextElapsedMicros = elapsedMicros + pollIntervalMicros
              nextElapsedSeconds = elapsedSeconds + pollIntervalSeconds
          maybeExitCode <- getProcessExitCode processHandle
          case maybeExitCode of
            Just exitCode -> pure exitCode
            Nothing -> do
              if nextElapsedMicros >= intervalMicros
                then do
                  putStrLn (monitorLabel monitor <> ": still running after " <> show nextElapsedSeconds <> "s")
                  monitorHeartbeat monitor nextElapsedSeconds
                  go 0 nextElapsedSeconds
                else
                  go nextElapsedMicros nextElapsedSeconds

mergeEnvironment :: [(String, String)] -> [(String, String)] -> [(String, String)]
mergeEnvironment baseEnv overrides =
  overrides <> filter (\(key, _) -> key `notElem` map fst overrides) baseEnv

catchRemoveFailure :: IO () -> IO ()
catchRemoveFailure action = do
  _ <- try action :: IO (Either SomeException ())
  pure ()

divUp :: Int -> Int -> Int
divUp numerator denominator =
  max 1 ((numerator + denominator - 1) `div` denominator)
