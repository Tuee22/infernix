module Infernix.Lint.Files
  ( runFilesLint,
    cabalCppMacroDefinitionViolations,
    cabalCSourcesDeclarationViolations,
    embeddedNativeSourceViolations,
    isGeneratedHaskellProtoTextSnapshot,
    nativeSourcePathViolations,
  )
where

import Control.Monad (forM, unless)
import Data.Char (isAlphaNum, isSpace, toLower)
import Data.List (isInfixOf, isPrefixOf, isSuffixOf)
import Data.List qualified as List
import Infernix.Cluster.Command qualified as Command
import Infernix.Cluster.Invoke qualified as Invoke
import Infernix.Config (Paths (..), discoverPaths)
import Infernix.Lint.Proto qualified as Proto
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (takeExtension, (</>))

checkSuffixes :: [String]
checkSuffixes = [".cabal", ".hs", ".js", ".json", ".md", ".mjs", ".proto", ".purs", ".py", ".sh", ".toml", ".yaml", ".yml"]

checkFiles :: [FilePath]
checkFiles = ["AGENTS.md", "CLAUDE.md", "Dockerfile", "README.md", "cabal.project"]

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
  trackedFileFailures <- listTrackedFileFailures paths
  let failures = List.nub (workingTreeFailures <> trackedFileFailures)
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
          if shouldSkipDirectory childRelative entry
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
    || isCabalPath relativePath
    || isNativeSourcePath relativePath
  where
    fileName = reverse . takeWhile (/= '/') . reverse

shouldSkipDirectory :: FilePath -> FilePath -> Bool
shouldSkipDirectory childRelative entry =
  any (`isSuffixOf` childRelative) skipDirectories
    || entry `elem` skipDirectories
    || "test-results-" `isPrefixOf` entry

checkFile :: FilePath -> FilePath -> IO [String]
checkFile root relativePath = do
  contents <- readFile (root </> relativePath)
  let numberedLines = zip [(1 :: Int) ..] (lines contents)
      lineFailures =
        concatMap
          ( \(lineNumber, lineValue) ->
              [ relativePath <> ":" <> show lineNumber <> ": trailing whitespace" | rstrip lineValue /= lineValue
              ]
                <> [relativePath <> ":" <> show lineNumber <> ": tab character" | '\t' `elem` lineValue]
          )
          numberedLines
      newlineFailure =
        case reverse contents of
          [] -> []
          '\n' : _ -> []
          _ -> [relativePath <> ": missing trailing newline"]
      textHygieneFailures
        | isGeneratedHaskellProtoTextSnapshot relativePath = []
        | otherwise = lineFailures <> newlineFailure
  pure
    ( nativeSourcePathViolations relativePath
        <> cabalCSourcesDeclarationViolations relativePath numberedLines
        <> cabalCppMacroDefinitionViolations relativePath numberedLines
        <> embeddedNativeSourceViolations relativePath numberedLines
        <> textHygieneFailures
        <> envReadFailures relativePath contents
    )

-- | The byte-exact upstream generator snapshot is checked by
-- 'Infernix.Lint.Proto', including exact inventory, SHA-256, and Linux
-- regeneration. Its four outputs retain generator-owned whitespace bytes;
-- similarly named handwritten files remain subject to ordinary text hygiene.
isGeneratedHaskellProtoTextSnapshot :: FilePath -> Bool
isGeneratedHaskellProtoTextSnapshot relativePath =
  relativePath `elem` Proto.generatedHaskellProtoFiles

nativeSourcePathViolations :: FilePath -> [String]
nativeSourcePathViolations relativePath =
  [ relativePath
      <> ": repo-owned native implementation source is forbidden; use a public Haskell package/API behind an internal Haskell module"
  | isNativeSourcePath relativePath
  ]

cabalCSourcesDeclarationViolations :: FilePath -> [(Int, String)] -> [String]
cabalCSourcesDeclarationViolations relativePath numberedLines
  | not (isCabalPath relativePath) = []
  | otherwise =
      [ relativePath
          <> ":"
          <> show lineNumber
          <> ": forbidden Cabal native-source declaration `"
          <> fieldName
          <> ":`; repo-owned native implementation source is not permitted"
      | (lineNumber, lineValue) <- numberedLines,
        Just fieldName <- [nativeSourceDeclarationField lineValue]
      ]

cabalCppMacroDefinitionViolations :: FilePath -> [(Int, String)] -> [String]
cabalCppMacroDefinitionViolations relativePath numberedLines
  | not (isCabalPath relativePath) = []
  | otherwise =
      [ relativePath
          <> ":"
          <> show lineNumber
          <> ": forbidden Cabal CPP macro definition `"
          <> option
          <> "`; native-boundary tokens must remain visible to source lint"
      | (fieldLineNumber, fieldLine) <- numberedLines,
        Just fieldIndent <- [cabalFieldIndent "cpp-options" fieldLine],
        (lineNumber, optionLine) <-
          (fieldLineNumber, cabalFieldValue fieldLine)
            : takeWhile
              (isCabalFieldContinuation fieldIndent . snd)
              (dropWhile ((<= fieldLineNumber) . fst) numberedLines),
        option <- cabalVisibleWords optionLine,
        "-D" `isPrefixOf` option
      ]

cabalFieldIndent :: String -> String -> Maybe Int
cabalFieldIndent expectedField lineValue =
  case break (== ':') (dropWhile isSpace lineValue) of
    (fieldName, ':' : _)
      | map toLower (dropWhileEnd isSpace fieldName) == expectedField ->
          Just (length (takeWhile isSpace lineValue))
    _ -> Nothing
  where
    dropWhileEnd predicate = reverse . dropWhile predicate . reverse

cabalFieldValue :: String -> String
cabalFieldValue lineValue =
  case break (== ':') lineValue of
    (_, ':' : value) -> value
    _ -> ""

isCabalFieldContinuation :: Int -> String -> Bool
isCabalFieldContinuation fieldIndent lineValue =
  null (dropWhile isSpace lineValue)
    || length (takeWhile isSpace lineValue) > fieldIndent

cabalVisibleWords :: String -> [String]
cabalVisibleWords =
  map normalizeCabalOptionToken . takeWhile (/= "--") . words

normalizeCabalOptionToken :: String -> String
normalizeCabalOptionToken =
  dropWhileEnd isTokenDelimiter . dropWhile isTokenDelimiter
  where
    isTokenDelimiter character =
      character == '"' || character == '\'' || character == ','
    dropWhileEnd predicate =
      reverse . dropWhile predicate . reverse

embeddedNativeSourceViolations :: FilePath -> [(Int, String)] -> [String]
embeddedNativeSourceViolations relativePath numberedLines
  | not (isImplementationTextPath relativePath) = []
  | otherwise =
      [ relativePath
          <> ":"
          <> show lineNumber
          <> ": embedded repo-owned native implementation source/compiler marker `"
          <> marker
          <> "` is forbidden; use a public upstream package API"
      | (lineNumber, lineValue) <- numberedLines,
        let normalizedLine = normalizeEmbeddedNativeLine lineValue,
        marker <- embeddedNativeMarkersForLine normalizedLine
      ]

isImplementationTextPath :: FilePath -> Bool
isImplementationTextPath relativePath =
  fileName relativePath == "Dockerfile"
    || normalizedExtension relativePath
      `elem` [".hs", ".js", ".mjs", ".purs", ".py", ".sh", ".toml", ".yaml", ".yml"]
  where
    fileName = reverse . takeWhile (/= '/') . reverse

embeddedNativeSourceMarkers :: [String]
embeddedNativeSourceMarkers =
  map
    concat
    [ ["#inc", "lude<"],
      ["#inc", "lude\""],
      ["#inc", "lude\\\""],
      ["#imp", "ort<"],
      ["#imp", "ort\""],
      ["#imp", "ort\\\""],
      ["@auto", "releasepool"],
      ["@imple", "mentation"],
      ["@inte", "rface"],
      ["extern", "\"c\""],
      ["int", "main("],
      ["newlibrary", "withsource"],
      ["/bin/", "cc"],
      ["/bin/", "c++"],
      ["/bin/", "gcc"],
      ["/bin/", "g++"],
      ["/bin/", "clang"],
      ["/bin/", "clang++"],
      ["xcrun", "clang"],
      ["cc", "-c"],
      ["c++", "-c"],
      ["gcc", "-c"],
      ["g++", "-c"],
      ["clang", "-c"],
      ["clang++", "-c"],
      ["clang", "-fobjc"]
    ]

embeddedNativeMarkersForLine :: String -> [String]
embeddedNativeMarkersForLine normalizedLine =
  filter (`isInfixOf` normalizedLine) embeddedNativeSourceMarkers
    <> filter
      (`hasDelimitedMarker` normalizedLine)
      ["import" <> "metal", "import" <> "coreml"]

-- Swift framework imports are native-source markers, but the Python
-- `coremltools` package is an allowed upstream API. Require a token boundary
-- after the exact Swift framework name so the scanner does not conflate them.
hasDelimitedMarker :: String -> String -> Bool
hasDelimitedMarker marker =
  any startsWithDelimitedMarker . List.tails
  where
    startsWithDelimitedMarker candidate =
      marker `isPrefixOf` candidate
        && case drop (length marker) candidate of
          [] -> True
          next : _ ->
            not
              ( isAlphaNum next
                  || next == '_'
                  || next == '.'
              )

normalizeEmbeddedNativeLine :: String -> String
normalizeEmbeddedNativeLine =
  map toLower . filter (not . isSpace)

isNativeSourcePath :: FilePath -> Bool
isNativeSourcePath relativePath =
  normalizedExtension relativePath
    `elem` [ ".asm",
             ".c",
             ".c++",
             ".cc",
             ".chs",
             ".cmm",
             ".cpp",
             ".cppm",
             ".cu",
             ".cuh",
             ".cxx",
             ".h",
             ".hh",
             ".hpp",
             ".hsc",
             ".hxx",
             ".inc",
             ".inl",
             ".ipp",
             ".ixx",
             ".m",
             ".metal",
             ".mm",
             ".nasm",
             ".s",
             ".swift",
             ".tcc"
           ]

isCabalPath :: FilePath -> Bool
isCabalPath relativePath =
  normalizedExtension relativePath == ".cabal"

normalizedExtension :: FilePath -> String
normalizedExtension = map toLower . takeExtension

nativeSourceDeclarationField :: String -> Maybe String
nativeSourceDeclarationField lineValue =
  case break (== ':') (dropWhile isSpace lineValue) of
    (fieldName, ':' : _) ->
      let normalizedField = map toLower (dropWhileEnd isSpace fieldName)
       in if normalizedField `elem` nativeSourceCabalFields
            then Just normalizedField
            else Nothing
    _ -> Nothing
  where
    dropWhileEnd predicate = reverse . dropWhile predicate . reverse

nativeSourceCabalFields :: [String]
nativeSourceCabalFields =
  [ "asm-sources",
    "c-sources",
    "cmm-sources",
    "cxx-sources"
  ]

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

listTrackedFileFailures :: Paths -> IO [String]
listTrackedFileFailures paths = do
  let root = repoRoot paths
  gitDirectoryPresent <- doesDirectoryExist (root </> ".git")
  if gitDirectoryPresent
    then listTrackedFileFailuresFromGit root
    else listTrackedFileFailuresFromSnapshotManifest root

-- | Enumerate the tracked inventory through the closed bounded-command
-- catalog.
--
-- Phase 6 Sprint 6.44 follow-on removed this module's last raw spawn. The
-- invocation was already fully closed in substance — a registered 'HostGit'
-- tool, a fixed argv, an explicit environment — but it carried no deadline, so
-- a git process wedged on a stuck filesystem or a hung credential helper hung
-- @infernix lint files@ forever. 'Command.gitListTrackedFiles' puts it under
-- the same required timeout and total 'Subprocess.CommandOutcome' as every
-- other external command. @infernix lint files@ runs after configuration
-- exists, so the generated host manifest the bounded-command environment
-- requires is available; when it is not, the outcome is a named fail-closed
-- diagnostic rather than an ambient @\$PATH@ fallback.
listTrackedFileFailuresFromGit :: FilePath -> IO [String]
listTrackedFileFailuresFromGit root = do
  paths <- discoverPaths
  outcome <- Invoke.tryClusterCommand paths (Command.gitListTrackedFiles root)
  case outcome of
    Right stdoutOutput ->
      concat <$> mapM (trackedFilePolicyFailures root) (splitNul stdoutOutput)
    Left failure ->
      ioError
        ( userError
            ( "git ls-files failed during file lint:\n"
                <> failure
            )
        )

splitNul :: String -> [String]
splitNul input =
  case break (== '\0') input of
    ("", "") -> []
    (entry, '\0' : remaining) -> entry : splitNul remaining
    (entry, "") -> [entry | not (null entry)]
    _ -> []

listTrackedFileFailuresFromSnapshotManifest :: FilePath -> IO [String]
listTrackedFileFailuresFromSnapshotManifest root = do
  let manifestPath = sourceSnapshotManifestPath
  manifestPresent <- doesFileExist manifestPath
  if manifestPresent
    then do
      manifestEntries <- lines <$> readFile manifestPath
      concat
        <$> mapM
          (trackedFilePolicyFailures root)
          (filter (not . null) manifestEntries)
    else
      ioError
        ( userError
            ( "infernix lint files requires either a git working tree or a source snapshot manifest at "
                <> manifestPath
            )
        )

trackedFilePolicyFailures :: FilePath -> FilePath -> IO [String]
trackedFilePolicyFailures root relativePath = do
  cabalFailures <-
    if isCabalPath relativePath
      then do
        present <- doesFileExist (root </> relativePath)
        if present
          then do
            contents <- readFile (root </> relativePath)
            pure
              ( cabalCSourcesDeclarationViolations
                  relativePath
                  (zip [(1 :: Int) ..] (lines contents))
                  <> cabalCppMacroDefinitionViolations
                    relativePath
                    (zip [(1 :: Int) ..] (lines contents))
              )
          else pure []
      else pure []
  pure
    ( nativeSourcePathViolations relativePath
        <> [relativePath <> ": tracked generated artifact" | isTrackedGeneratedPath relativePath]
        <> cabalFailures
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
