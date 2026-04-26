module Infernix.Lint.Files
  ( runFilesLint,
  )
where

import Control.Monad (forM, unless)
import Data.List (isSuffixOf)
import Infernix.Config (Paths (..), discoverPaths)
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>))

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
  failures <- concat <$> walkDirectory (repoRoot paths) ""
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
