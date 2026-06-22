module Infernix.Lint.HaskellStyle
  ( runHaskellStyleLint,
  )
where

import Control.Exception (IOException, try)
import Control.Monad (when)
import Data.Char (isAlphaNum)
import Data.List (intercalate, isInfixOf, sort)
import Data.Maybe (fromMaybe)
import Infernix.Config (Paths (..), discoverPaths)
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    getTemporaryDirectory,
    listDirectory,
    removeFile,
  )
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.IO (hClose, openTempFile)
import System.Process (CreateProcess (cwd), proc, readCreateProcessWithExitCode)

runHaskellStyleLint :: IO ()
runHaskellStyleLint = do
  paths <- discoverPaths
  createDirectoryIfMissing True (buildRoot paths)
  installFormatterTools paths
  let toolsRoot = formatterToolsBinRoot paths
      ormoluPath = toolsRoot </> "ormolu"
      hlintPath = toolsRoot </> "hlint"
  ormoluPresent <- doesFileExist ormoluPath
  hlintPresent <- doesFileExist hlintPath
  when
    (not ormoluPresent || not hlintPresent)
    (ioError (userError "haskell-style-check: formatter bootstrap did not produce ormolu and hlint"))
  sources <- haskellSources (repoRoot paths)
  runCommand (repoRoot paths) ormoluPath (["--mode", "check"] <> sources)
  runCommand (repoRoot paths) hlintPath ["Setup.hs", "app", "src", "test"]
  checkReadabilityRules (repoRoot paths) sources
  checkCabalManifest paths
  putStrLn "haskell-style-check: ok"

installFormatterTools :: Paths -> IO ()
installFormatterTools paths = do
  let toolsRoot = formatterToolsBinRoot paths
      ormoluPath = toolsRoot </> "ormolu"
      hlintPath = toolsRoot </> "hlint"
  ormoluPresent <- doesFileExist ormoluPath
  hlintPresent <- doesFileExist hlintPath
  when (not ormoluPresent || not hlintPresent) $ do
    installResult <- try (installFormatterToolsWithCommand paths "cabal" (formatterInstallArgs paths)) :: IO (Either IOException ())
    case installResult of
      Right () -> pure ()
      Left installErr ->
        ioError
          ( userError
              ( "haskell-style-check: formatter bootstrap failed\nerror:\n"
                  <> show installErr
              )
          )

installFormatterToolsWithCommand :: Paths -> FilePath -> [String] -> IO ()
installFormatterToolsWithCommand paths =
  runCommand (repoRoot paths)

formatterInstallArgs :: Paths -> [String]
formatterInstallArgs paths =
  [ "--builddir=" <> formatterToolsBuildRoot paths,
    "install",
    "--installdir=" <> formatterToolsBinRoot paths,
    "--install-method=copy",
    "--overwrite-policy=always",
    "ormolu",
    "hlint"
  ]

formatterToolsRoot :: Paths -> FilePath
formatterToolsRoot paths = buildRoot paths </> "haskell-style-tools"

formatterToolsBuildRoot :: Paths -> FilePath
formatterToolsBuildRoot paths = formatterToolsRoot paths </> "cabal"

formatterToolsBinRoot :: Paths -> FilePath
formatterToolsBinRoot paths = formatterToolsRoot paths </> "bin"

checkCabalManifest :: Paths -> IO ()
checkCabalManifest paths = do
  let sourcePath = repoRoot paths </> "infernix.cabal"
  tempRoot <- getTemporaryDirectory
  (tempPath, tempHandle) <- openTempFile tempRoot "infernix.cabal"
  hClose tempHandle
  sourceContents <- readFile sourcePath
  writeFile tempPath sourceContents
  runCommand (repoRoot paths) "cabal" ["format", tempPath]
  formattedContents <- readFile tempPath
  removeFile tempPath
  if formattedContents == sourceContents
    then pure ()
    else ioError (userError "haskell-style-check: infernix.cabal is not cabal-format clean")

haskellSources :: FilePath -> IO [FilePath]
haskellSources repoRoot = do
  sourceFiles <- concat <$> mapM (collectHsFiles . (repoRoot </>)) ["app", "src", "test"]
  pure (sort ("Setup.hs" : map (makeRelative repoRoot) sourceFiles))

collectHsFiles :: FilePath -> IO [FilePath]
collectHsFiles directoryPath = do
  exists <- doesDirectoryExist directoryPath
  if not exists
    then pure []
    else do
      children <- listDirectory directoryPath
      concat <$> mapM (collectChild . (directoryPath </>)) children
  where
    collectChild childPath = do
      isDirectory <- doesDirectoryExist childPath
      if isDirectory
        then collectHsFiles childPath
        else do
          isFile <- doesFileExist childPath
          if isFile && hasHsExtension childPath
            then pure [childPath]
            else pure []

hasHsExtension :: FilePath -> Bool
hasHsExtension pathValue =
  reverse (take 3 (reverse pathValue)) == ".hs"

checkReadabilityRules :: FilePath -> [FilePath] -> IO ()
checkReadabilityRules repoRoot sourceFiles = do
  violations <- concat <$> mapM (checkSourceReadability repoRoot) sourceFiles
  case violations of
    [] -> pure ()
    _ ->
      ioError
        ( userError
            ( "haskell-style-check: readability rules failed\n"
                <> intercalate "\n" violations
            )
        )

checkSourceReadability :: FilePath -> FilePath -> IO [String]
checkSourceReadability repoRoot sourceFile = do
  contents <- readFile (repoRoot </> sourceFile)
  let numberedLines = zip [1 :: Int ..] (lines contents)
  pure
    ( hangingCaseViolations sourceFile numberedLines
        <> aliasCommentViolations sourceFile numberedLines
        <> envFunctionViolations sourceFile numberedLines
        <> bareNameProcViolations sourceFile numberedLines
        <> ambientToolLookupViolations sourceFile numberedLines
        <> engineRuntimeBoundaryViolations sourceFile numberedLines
        <> sharedPhase7BoundaryViolations sourceFile numberedLines
    )

-- | Phase 6 Sprint 6.28 (initial landing — May 25, 2026): reject new
-- occurrences of @lookupEnv@ / @getEnv@ / @getEnvironment@ /
-- @setEnv@ / @unsetEnv@ outside the explicit exemption list. The
-- exemption list names the modules whose env retirements are
-- deferred to specific later sprints (Phase 7 Sprint 7.17 for the
-- credential-bearing reads, the Apple validation pass for the
-- Apple-only code paths). As those sprints close, their rows leave
-- this list and the gate tightens automatically.
envFunctionViolations :: FilePath -> [(Int, String)] -> [String]
envFunctionViolations sourceFile numberedLines
  | sourceFile `elem` envFunctionExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden env-IO call `" <> needle <> "`; route through HostConfig or a typed Dhall manifest"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        needle <- forbiddenEnvFunctions,
        containsToken needle lineValue
      ]

forbiddenEnvFunctions :: [String]
forbiddenEnvFunctions =
  [ "lookupEnv",
    "getEnv",
    "getEnvironment",
    "setEnv",
    "unsetEnv"
  ]

envFunctionExemptedFiles :: [FilePath]
envFunctionExemptedFiles =
  [ -- The build setup is genuinely outside the runtime-config
    -- substrate and runs before the binary exists.
    "Setup.hs",
    -- This lint module defines the forbidden tokens as string
    -- literals; it must exempt itself or the check trips on its own
    -- token list.
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

-- | Phase 6 Sprint 6.28 (initial landing — May 25, 2026): reject
-- bare-name @proc "<command>"@ invocations whose name matches a
-- known external tool. The supported flow routes every invocation
-- through `Infernix.HostTools.runHostTool` so the absolute path
-- comes from the typed `HostConfig.toolPaths.*` record.
bareNameProcViolations :: FilePath -> [(Int, String)] -> [String]
bareNameProcViolations sourceFile numberedLines
  | sourceFile `elem` bareNameProcExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden bare-name `proc " <> show toolName <> "`; route through HostTools.runHostTool"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        toolName <- forbiddenBareProcCommands,
        let needle = "proc \"" <> toolName <> "\"",
        needle `isInfixOf` lineValue
      ]

forbiddenBareProcCommands :: [String]
forbiddenBareProcCommands =
  [ "docker",
    "kubectl",
    "helm",
    "kind",
    "cabal",
    "ghc",
    "ghcup",
    "ormolu",
    "hlint",
    "npm",
    "node",
    "python3",
    "poetry",
    "protoc",
    "git",
    "tar",
    "curl",
    "apt-get",
    "brew",
    "colima",
    "skopeo",
    "sudo",
    "systemctl"
  ]

bareNameProcExemptedFiles :: [FilePath]
bareNameProcExemptedFiles =
  [ -- This lint module lists forbidden tokens as literals; exempt it.
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

-- | Phase 6 Sprint 6.28 follow-on: reject ambient executable discovery
-- for registered host tools. Supported invocation paths either read
-- absolute paths from HostConfig.toolPaths or use fixed absolute
-- fallback candidates from Infernix.HostTools.
ambientToolLookupViolations :: FilePath -> [(Int, String)] -> [String]
ambientToolLookupViolations sourceFile numberedLines
  | sourceFile `elem` ambientToolLookupExemptedFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": forbidden ambient host-tool lookup `" <> needle <> "`; route through HostTools and HostConfig.toolPaths"
      | (lineNumber, lineValue) <- numberedLines,
        not (isCommentLine lineValue),
        needle <- forbiddenAmbientToolLookups,
        containsToken needle lineValue
      ]

forbiddenAmbientToolLookups :: [String]
forbiddenAmbientToolLookups =
  [ "findExecutable",
    "findExecutables"
  ]

ambientToolLookupExemptedFiles :: [FilePath]
ambientToolLookupExemptedFiles =
  [ -- This lint module lists forbidden tokens as literals; exempt it.
    "src/Infernix/Lint/HaskellStyle.hs"
  ]

-- | Phase 7 Sprint 7.8: keep the engine runtime surface from
-- importing frontend, coordinator, auth, object-presign, or WebSocket
-- modules. `Runtime.Daemon` owns role orchestration and may wire both
-- coordinator and engine loops, so this gate is scoped to the concrete
-- engine runtime modules.
engineRuntimeBoundaryViolations :: FilePath -> [(Int, String)] -> [String]
engineRuntimeBoundaryViolations sourceFile numberedLines
  | sourceFile `notElem` engineRuntimeBoundaryFiles = []
  | otherwise =
      [ sourceFile <> ":" <> show lineNumber <> ": engine runtime module must not import `" <> forbiddenModule <> "`"
      | (lineNumber, lineValue) <- numberedLines,
        let trimmedLine = trimWhitespace lineValue,
        not (isCommentLine lineValue),
        "import " `isPrefixOfString` trimmedLine,
        forbiddenModule <- forbiddenEngineRuntimeImports,
        forbiddenModule `isInfixOf` trimmedLine
      ]

engineRuntimeBoundaryFiles :: [FilePath]
engineRuntimeBoundaryFiles =
  [ "src/Infernix/Runtime.hs",
    "src/Infernix/Runtime/Cache.hs",
    "src/Infernix/Runtime/KVCache.hs",
    "src/Infernix/Runtime/Worker.hs"
  ]

forbiddenEngineRuntimeImports :: [String]
forbiddenEngineRuntimeImports =
  [ "Infernix.Demo.",
    "Infernix.Auth.Jwt",
    "Infernix.Objects.Presigned",
    "Infernix.Dispatch.SingleFlight",
    "Infernix.Bridge.Result",
    "Infernix.Bootstrap.Models",
    "Network.WebSockets"
  ]

-- | Phase 7 shared-library modules must remain product/runtime agnostic.
-- Conversation primitives are allowed to depend on generated wire contracts,
-- but not on demo application modules. The pure dispatcher/result/bootstrap
-- helpers must also stay out of runtime orchestration, auth, object-presign,
-- and WebSocket concerns.
sharedPhase7BoundaryViolations :: FilePath -> [(Int, String)] -> [String]
sharedPhase7BoundaryViolations sourceFile numberedLines =
  case lookup sourceFile sharedPhase7BoundaryFiles of
    Nothing -> []
    Just forbiddenImports ->
      [ sourceFile <> ":" <> show lineNumber <> ": shared Phase 7 module must not import `" <> forbiddenModule <> "`"
      | (lineNumber, lineValue) <- numberedLines,
        let trimmedLine = trimWhitespace lineValue,
        not (isCommentLine lineValue),
        "import " `isPrefixOfString` trimmedLine,
        forbiddenModule <- forbiddenImports,
        forbiddenModule `isInfixOf` trimmedLine
      ]

sharedPhase7BoundaryFiles :: [(FilePath, [String])]
sharedPhase7BoundaryFiles =
  map conversationBoundaryFile conversationPrimitiveFiles
    <> [ ( "src/Infernix/Dispatch/SingleFlight.hs",
           productAgnosticHelperForbiddenImports
         ),
         ( "src/Infernix/Dispatch/ContextModelMap.hs",
           productAgnosticHelperForbiddenImports
         ),
         ( "src/Infernix/Bridge/Result.hs",
           productAgnosticHelperForbiddenImports
         ),
         ( "src/Infernix/Bootstrap/Models.hs",
           productAgnosticHelperForbiddenImports
         )
       ]

conversationBoundaryFile :: FilePath -> (FilePath, [String])
conversationBoundaryFile sourceFile =
  (sourceFile, conversationForbiddenImports)

conversationPrimitiveFiles :: [FilePath]
conversationPrimitiveFiles =
  [ "src/Infernix/Conversation/Event.hs",
    "src/Infernix/Conversation/Hash.hs",
    "src/Infernix/Conversation/Idempotency.hs",
    "src/Infernix/Conversation/Reducer.hs",
    "src/Infernix/Conversation/Topic.hs"
  ]

conversationForbiddenImports :: [String]
conversationForbiddenImports =
  [ "Infernix.Demo",
    "Infernix.Runtime",
    "Infernix.Auth.Jwt",
    "Infernix.Objects.Presigned",
    "Network.WebSockets"
  ]

productAgnosticHelperForbiddenImports :: [String]
productAgnosticHelperForbiddenImports =
  conversationForbiddenImports
    <> [ "Infernix.Dispatch.SingleFlight",
         "Infernix.Bridge.Result",
         "Infernix.Bootstrap.Models"
       ]

isPrefixOfString :: String -> String -> Bool
isPrefixOfString expected value =
  case stripPrefix expected value of
    Just _ -> True
    Nothing -> False

hangingCaseViolations :: FilePath -> [(Int, String)] -> [String]
hangingCaseViolations sourceFile numberedLines =
  [ sourceFile <> ":" <> show lineNumber <> ": avoid hanging `case`; move it into a named helper or make it the outer expression"
  | (lineNumber, lineValue) <- numberedLines,
    not (isCommentLine lineValue),
    lineHasHangingCase lineValue
  ]

lineHasHangingCase :: String -> Bool
lineHasHangingCase lineValue =
  any
    (`isInfixOf` paddedLine)
    hangingCaseNeedles
  where
    paddedLine = " " <> lineValue <> " "

hangingCaseNeedles :: [String]
hangingCaseNeedles =
  [ "(" <> " case",
    "->" <> " case",
    "then" <> " case",
    "else" <> " case",
    "<-" <> " case",
    " in" <> " case "
  ]

aliasCommentViolations :: FilePath -> [(Int, String)] -> [String]
aliasCommentViolations sourceFile numberedLines =
  concatMap signatureViolations (signatureBlocks numberedLines)
  where
    signatureViolations (lineNumber, signatureLines) =
      [ sourceFile <> ":" <> show lineNumber <> ": aliased type `" <> aliasName <> "` needs comment `" <> requiredComment <> "`"
      | (aliasName, requiredComment) <- aliasedTypeComments,
        containsToken aliasName (unlines signatureLines),
        not (hasRequiredAliasComment requiredComment lineNumber numberedLines)
      ]

aliasedTypeComments :: [(String, String)]
aliasedTypeComments =
  [ ("Application", "-- type Application = Request -> (Response -> IO ResponseReceived) -> IO ResponseReceived"),
    ("HostPreference", "-- type HostPreference = String"),
    ("InferenceResponse", "-- type InferenceResponse = Either (Status, ErrorResponse) InferenceResult"),
    ("PublishedImage", "-- type PublishedImage = (String, String)"),
    ("CommandMonitorFactory", "-- type CommandMonitorFactory = String -> IO (Maybe ProcessMonitor.CommandMonitor)")
  ]

signatureBlocks :: [(Int, String)] -> [(Int, [String])]
signatureBlocks [] = []
signatureBlocks ((lineNumber, lineValue) : remainingLines)
  | isSignatureStart lineValue =
      let (continuation, rest) = span isSignatureContinuation remainingLines
       in (lineNumber, lineValue : map snd continuation) : signatureBlocks rest
  | otherwise = signatureBlocks remainingLines

isSignatureStart :: String -> Bool
isSignatureStart lineValue =
  not (startsWithSpace lineValue)
    && not (isCommentLine lineValue)
    && "::" `isInfixOf` lineValue

isSignatureContinuation :: (Int, String) -> Bool
isSignatureContinuation (_, lineValue) =
  null (trimWhitespace lineValue) || startsWithSpace lineValue || isCommentLine lineValue

startsWithSpace :: String -> Bool
startsWithSpace (' ' : _) = True
startsWithSpace ('\t' : _) = True
startsWithSpace _ = False

hasRequiredAliasComment :: String -> Int -> [(Int, String)] -> Bool
hasRequiredAliasComment requiredComment lineNumber numberedLines =
  requiredComment `elem` precedingNonBlankLines
  where
    precedingNonBlankLines =
      take
        6
        [ trimWhitespace candidateLine
        | (candidateLineNumber, candidateLine) <- reverse numberedLines,
          candidateLineNumber < lineNumber,
          not (null (trimWhitespace candidateLine))
        ]

containsToken :: String -> String -> Bool
containsToken token value =
  token `elem` tokenize value

tokenize :: String -> [String]
tokenize =
  words . map tokenCharacter
  where
    tokenCharacter character
      | isAlphaNum character || character == '_' || character == '\'' = character
      | otherwise = ' '

isCommentLine :: String -> Bool
isCommentLine lineValue =
  case trimWhitespace lineValue of
    '-' : '-' : _ -> True
    _ -> False

trimWhitespace :: String -> String
trimWhitespace =
  reverse . dropWhile (`elem` [' ', '\t']) . reverse . dropWhile (`elem` [' ', '\t'])

makeRelative :: FilePath -> FilePath -> FilePath
makeRelative root fullPath =
  fromMaybe fullPath (stripPrefix (root <> "/") fullPath)

runCommand :: FilePath -> FilePath -> [String] -> IO ()
runCommand workingDirectory command args = do
  (exitCode, stdoutOutput, stderrOutput) <- readCreateProcessWithExitCode (proc command args) {cwd = Just workingDirectory} ""
  case exitCode of
    ExitSuccess -> pure ()
    _ -> ioError (userError ("command failed: " <> command <> " " <> unwords args <> "\n" <> stdoutOutput <> stderrOutput))

stripPrefix :: String -> String -> Maybe String
stripPrefix [] value = Just value
stripPrefix _ [] = Nothing
stripPrefix (expected : expectedRest) (actual : actualRest)
  | expected == actual = stripPrefix expectedRest actualRest
  | otherwise = Nothing
