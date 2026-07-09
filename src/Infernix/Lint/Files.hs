module Infernix.Lint.Files
  ( runFilesLint,
  )
where

import Control.Monad (forM, unless)
import Data.List (isInfixOf, isPrefixOf, isSuffixOf)
import Data.List qualified as List
import Data.Text qualified as Text
import Infernix.Config (Paths (..), discoverPaths)
import Infernix.HostConfig qualified as HostConfig
import Infernix.HostTools (HostTool (..))
import Infernix.HostTools qualified as HostTools
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath (takeDirectory, (</>))
import System.Process (CreateProcess (cwd, env), proc, readCreateProcessWithExitCode)

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
  trackedGeneratedFailures <- listTrackedGeneratedFailures paths
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
        case reverse contents of
          [] -> []
          '\n' : _ -> []
          _ -> [relativePath <> ": missing trailing newline"]
  pure (lineFailures <> newlineFailure <> envReadFailures relativePath contents)

-- | Reject environment reads in web/Python product code: no `os.environ` /
-- `os.getenv` under `python/`, and no `process.env` under `web/`. The supported
-- configuration substrate is typed input, not the process environment
-- (documents/architecture/configuration_doctrine.md); comment-only mentions are
-- allowed so the rule can be documented in source.
envReadFailures :: FilePath -> String -> [String]
envReadFailures relativePath contents =
  concatMap check (zip [(1 :: Int) ..] (lines contents))
  where
    isPython = "python/" `isPrefixOf` relativePath && ".py" `isSuffixOf` relativePath
    isWeb =
      "web/" `isPrefixOf` relativePath
        && any (`isSuffixOf` relativePath) [".js", ".mjs", ".purs"]
    check (lineNumber, lineValue)
      | isPython && not (lineIsComment "#" lineValue) =
          [ relativePath <> ":" <> show lineNumber <> ": forbidden environment read `" <> token <> "`; Python config must come from typed inputs, not the process environment"
          | token <- ["os.environ", "os.getenv"],
            token `isInfixOf` lineValue
          ]
      | isWeb && not (lineIsComment "//" lineValue) =
          [ relativePath <> ":" <> show lineNumber <> ": forbidden environment read `process.env`; web config must come from typed inputs, not the process environment"
          | "process.env" `isInfixOf` lineValue
          ]
      | otherwise = []
    lineIsComment marker lineValue =
      marker `isPrefixOf` dropWhile (`elem` [' ', '\t']) lineValue

rstrip :: String -> String
rstrip = reverse . dropWhile (`elem` [' ', '\t']) . reverse

listTrackedGeneratedFailures :: Paths -> IO [String]
listTrackedGeneratedFailures paths = do
  let root = repoRoot paths
  gitDirectoryPresent <- doesDirectoryExist (root </> ".git")
  if gitDirectoryPresent
    then listTrackedGeneratedFailuresFromGit root
    else listTrackedGeneratedFailuresFromSnapshotManifest

listTrackedGeneratedFailuresFromGit :: FilePath -> IO [String]
listTrackedGeneratedFailuresFromGit root = do
  paths <- discoverPaths
  gitCommand <- requireFilesLintHostTool paths HostGit
  (exitCode, stdoutOutput, stderrOutput) <-
    readCreateProcessWithExitCode
      (proc gitCommand ["-c", "safe.directory=" <> root, "ls-files"])
        { cwd = Just root,
          env = Just (filesLintSubprocessBaseEnvFor paths)
        }
      ""
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

listTrackedGeneratedFailuresFromSnapshotManifest :: IO [String]
listTrackedGeneratedFailuresFromSnapshotManifest = do
  let manifestPath = sourceSnapshotManifestPath
  manifestPresent <- doesFileExist manifestPath
  if manifestPresent
    then do
      manifestEntries <- lines <$> readFile manifestPath
      pure
        [ relativePath <> ": tracked generated artifact"
        | relativePath <- manifestEntries,
          not (null relativePath),
          isTrackedGeneratedPath relativePath
        ]
    else
      ioError
        ( userError
            ( "infernix lint files requires either a git working tree or a source snapshot manifest at "
                <> manifestPath
            )
        )

sourceSnapshotManifestPath :: FilePath
sourceSnapshotManifestPath = "/opt/infernix/source-snapshot-files.txt"

isTrackedGeneratedPath :: FilePath -> Bool
isTrackedGeneratedPath relativePath =
  or
    [ -- Zero version-controlled `.dhall`: the `infernix` binary is the sole
      -- generator of every `.dhall` (configuration_doctrine.md), so any tracked
      -- `.dhall` is a forbidden generated artifact.
      ".dhall" `isSuffixOf` relativePath,
      "/__pycache__/" `isInfixOf` relativePath,
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

requireFilesLintHostTool :: Paths -> HostTool -> IO FilePath
requireFilesLintHostTool paths tool = do
  maybePath <- filesLintHostToolPath paths tool
  case maybePath of
    Just path -> pure path
    Nothing ->
      ioError
        ( userError
            ( "required host tool is unavailable during file lint: "
                <> Text.unpack (HostTools.hostToolName tool)
            )
        )

filesLintHostToolPath :: Paths -> HostTool -> IO (Maybe FilePath)
filesLintHostToolPath paths tool =
  case pathsHostConfig paths of
    Just hostConfig ->
      let configured = HostTools.hostToolPath hostConfig tool
       in pure $
            if Text.null configured
              then Nothing
              else Just (Text.unpack configured)
    Nothing -> firstExistingPath (HostTools.hostToolFallbackCandidates tool)

firstExistingPath :: [FilePath] -> IO (Maybe FilePath)
firstExistingPath [] = pure Nothing
firstExistingPath (candidate : rest) = do
  present <- doesFileExist candidate
  if present
    then pure (Just candidate)
    else firstExistingPath rest

filesLintSubprocessBaseEnvFor :: Paths -> [(String, String)]
filesLintSubprocessBaseEnvFor paths =
  maybe [] hostHomeEnv (pathsHostConfig paths)
    <> [ ("PATH", filesLintSearchPath paths),
         ("LANG", "C.UTF-8"),
         ("LC_ALL", "C.UTF-8")
       ]

hostHomeEnv :: HostConfig.HostConfig -> [(String, String)]
hostHomeEnv hostConfig =
  let home = Text.unpack (HostConfig.hostHomeDirectory (HostConfig.hostFilesystem hostConfig))
   in [("HOME", home) | not (null home)]

filesLintSearchPath :: Paths -> String
filesLintSearchPath paths =
  let fallback =
        [ "/opt/homebrew/bin",
          "/usr/bin",
          "/bin"
        ]
      manifestDirs =
        maybe [] hostToolParentDirs (pathsHostConfig paths)
   in List.intercalate ":" (List.nub (manifestDirs <> fallback))

hostToolParentDirs :: HostConfig.HostConfig -> [FilePath]
hostToolParentDirs hostConfig =
  List.nub
    [ takeDirectory path
    | tool <- [HostGit],
      let path = Text.unpack (HostTools.hostToolPath hostConfig tool),
      not (null path)
    ]
