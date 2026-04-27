module Infernix.Lint.Files
  ( runFilesLint,
  )
where

import Control.Monad (forM, unless)
import Data.List (isInfixOf, isPrefixOf, isSuffixOf)
import Infernix.Config (Paths (..), discoverPaths)
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.Process (CreateProcess (cwd), proc, readCreateProcessWithExitCode)

checkSuffixes :: [String]
checkSuffixes = [".cabal", ".hs", ".js", ".json", ".md", ".mjs", ".proto", ".purs", ".py", ".sh", ".yaml", ".yml"]

checkFiles :: [FilePath]
checkFiles = ["AGENTS.md", "CLAUDE.md", "README.md", "cabal.project"]

skipDirectories :: [FilePath]
skipDirectories =
  [ ".build",
    ".data",
    ".git",
    ".spago",
    ".tmp",
    ".venv",
    "__pycache__",
    "dist",
    "dist-newstyle",
    "node_modules",
    "output",
    "playwright-report",
    "test-results"
  ]

runFilesLint :: IO ()
runFilesLint = do
  paths <- discoverPaths
  workingTreeFailures <- concat <$> walkDirectory (repoRoot paths) ""
  trackedGeneratedFailures <- listTrackedGeneratedFailures (repoRoot paths)
  let failures = workingTreeFailures <> trackedGeneratedFailures
  unless (null failures) $
    ioError (userError (unlines failures))

walkDirectory :: FilePath -> FilePath -> IO [[String]]
walkDirectory root relativePath = do
  let currentPath =
        if null relativePath
          then root
          else root </> relativePath
  entries <- listDirectory currentPath
  fmap concat $
    forM entries $ \entry -> do
      let childRelative =
            if null relativePath
              then entry
              else relativePath </> entry
          childPath = root </> childRelative
      isDirectory <- doesDirectoryExist childPath
      if isDirectory
        then
          if any (`isSuffixOf` childRelative) skipDirectories || entry `elem` skipDirectories
            then pure []
            else walkDirectory root childRelative
        else do
          isRegularFile <- doesFileExist childPath
          if isRegularFile && shouldCheck childRelative
            then (: []) <$> checkFile root childRelative
            else pure []

shouldCheck :: FilePath -> Bool
shouldCheck relativePath =
  fileName relativePath `elem` checkFiles
    || any (`isSuffixOf` relativePath) checkSuffixes
  where
    fileName = reverse . takeWhile (/= '/') . reverse

checkFile :: FilePath -> FilePath -> IO [String]
checkFile root relativePath = do
  contents <- readFile (root </> relativePath)
  let lineFailures =
        concatMap
          ( \(lineNumber, lineValue) ->
              [ relativePath <> ":" <> show lineNumber <> ": trailing whitespace" | rstrip lineValue /= lineValue
              ]
                <> [relativePath <> ":" <> show lineNumber <> ": tab character" | '\t' `elem` lineValue]
          )
          (zip [(1 :: Int) ..] (lines contents))
      newlineFailure =
        [relativePath <> ": missing trailing newline" | not (null contents) && last contents /= '\n']
  pure (lineFailures <> newlineFailure)

rstrip :: String -> String
rstrip = reverse . dropWhile (`elem` [' ', '\t']) . reverse

listTrackedGeneratedFailures :: FilePath -> IO [String]
listTrackedGeneratedFailures root = do
  (exitCode, stdoutOutput, stderrOutput) <-
    readCreateProcessWithExitCode ((proc "git" ["ls-files"]) {cwd = Just root}) ""
  case exitCode of
    ExitSuccess ->
      pure
        [ relativePath <> ": tracked generated artifact"
          | relativePath <- lines stdoutOutput,
            isTrackedGeneratedPath relativePath
        ]
    _ ->
      ioError
        ( userError
            ( "git ls-files failed during file lint:\n"
                <> stderrOutput
            )
        )

isTrackedGeneratedPath :: FilePath -> Bool
isTrackedGeneratedPath relativePath =
  or
    [ "/__pycache__/" `isInfixOf` relativePath,
      "__pycache__" `isSuffixOf` relativePath,
      ".pyc" `isSuffixOf` relativePath,
      relativePath == "poetry.lock",
      "/poetry.lock" `isSuffixOf` relativePath,
      relativePath == "spago.lock",
      "/spago.lock" `isSuffixOf` relativePath,
      "tools/generated_proto/" `isPrefixOf` relativePath,
      "web/src/Generated/" `isPrefixOf` relativePath,
      "/.mypy_cache/" `isInfixOf` relativePath,
      "/.mypy_cache" `isSuffixOf` relativePath,
      "/.ruff_cache/" `isInfixOf` relativePath,
      "/.ruff_cache" `isSuffixOf` relativePath
    ]
