module Infernix.Workflow
  ( demoConfigGeneratedBanner,
    demoConfigGeneratedBannerLine,
    ensureWebDependencies,
    platformCommandsAvailable,
    resolveWebNpmInvocation,
  )
where

import Data.Char (isDigit)
import Data.List qualified as List
import Data.Maybe (isJust)
import Data.Text qualified as Text
import Infernix.Config (Paths (pathsHostConfig, repoRoot), discoverPaths)
import Infernix.HostConfig qualified as HostConfig
import Infernix.HostTools (HostTool (..))
import Infernix.HostTools qualified as HostTools
import Infernix.Substrate (demoConfigGeneratedBanner, demoConfigGeneratedBannerLine)
import System.Directory (doesDirectoryExist, doesFileExist)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath (takeDirectory, (</>))
import System.Process (CreateProcess (cwd, env), proc, readCreateProcessWithExitCode)

ensureWebDependencies :: IO ()
ensureWebDependencies = do
  paths <- discoverPaths
  let webRoot = repoRoot paths </> "web"
  depsDirectoryPresent <- doesDirectoryExist (webRoot </> "node_modules")
  toolchainPresent <- webToolchainPresent webRoot
  hostNodeReady <- hostNodeSupportsWebToolchain paths
  if depsDirectoryPresent && toolchainPresent && hostNodeReady
    then pure ()
    else do
      (command, args) <-
        resolveWebNpmInvocationWithPaths paths ["--prefix", "web", "install", "--no-audit", "--no-fund"]
      runWorkflowCommand paths (repoRoot paths) command args

platformCommandsAvailable :: IO Bool
platformCommandsAvailable = do
  paths <- discoverPaths
  allM
    (hostToolExecutablePresent paths)
    [HostDocker, HostHelm, HostKind, HostKubectl]

webToolchainPresent :: FilePath -> IO Bool
webToolchainPresent webRoot =
  and
    <$> mapM
      doesFileExist
      [ webRoot </> "node_modules" </> "playwright" </> "package.json",
        webRoot </> "node_modules" </> ".bin" </> "purs",
        webRoot </> "node_modules" </> "spago" </> "package.json",
        webRoot </> "node_modules" </> "esbuild" </> "package.json"
      ]

resolveWebNpmInvocation :: [String] -> IO (FilePath, [String])
resolveWebNpmInvocation npmArgs = do
  paths <- discoverPaths
  resolveWebNpmInvocationWithPaths paths npmArgs

resolveWebNpmInvocationWithPaths :: Paths -> [String] -> IO (FilePath, [String])
resolveWebNpmInvocationWithPaths paths npmArgs = do
  supported <- hostNodeSupportsWebToolchain paths
  npmCommand <- requireWorkflowHostTool paths HostNpm
  pure $
    if supported
      then (npmCommand, npmArgs)
      else
        ( npmCommand,
          [ "exec",
            "--package=node@22",
            "--package=npm@10",
            "--",
            "sh",
            "-lc",
            "npm " <> unwords (map shellQuote npmArgs)
          ]
        )

hostNodeSupportsWebToolchain :: Paths -> IO Bool
hostNodeSupportsWebToolchain paths = do
  maybeNode <- hostToolExecutablePath paths HostNode
  maybeNpm <- hostToolExecutablePath paths HostNpm
  case (maybeNode, maybeNpm) of
    (Just nodeCommand, Just _) -> do
      (exitCode, stdoutOutput, _) <-
        readCreateProcessWithExitCode
          (proc nodeCommand ["--version"])
            { env = Just (workflowSubprocessBaseEnvFor paths)
            }
          ""
      pure $
        case exitCode of
          ExitSuccess -> nodeVersionSatisfiesMinimum stdoutOutput
          _ -> False
    _ -> pure False

nodeVersionSatisfiesMinimum :: String -> Bool
nodeVersionSatisfiesMinimum stdoutOutput =
  case parseNodeVersion stdoutOutput of
    Just (majorVersion, minorVersion) ->
      majorVersion > 22 || (majorVersion == 22 && minorVersion >= 5)
    Nothing -> False

parseNodeVersion :: String -> Maybe (Int, Int)
parseNodeVersion rawVersion =
  case dropWhile (not . isDigit) rawVersion of
    [] -> Nothing
    digits -> parseVersionDigits digits

parseVersionDigits :: String -> Maybe (Int, Int)
parseVersionDigits digits =
  case span isDigit digits of
    (majorDigits, '.' : minorAndRest)
      | not (null majorDigits) ->
          parseMinorVersion majorDigits minorAndRest
    (majorDigits, _) | not (null majorDigits) -> Just (read majorDigits, 0)
    _ -> Nothing

parseMinorVersion :: String -> String -> Maybe (Int, Int)
parseMinorVersion majorDigits minorAndRest =
  case span isDigit minorAndRest of
    (minorDigits, _) | not (null minorDigits) -> Just (read majorDigits, read minorDigits)
    _ -> Nothing

shellQuote :: String -> String
shellQuote rawValue =
  "'" <> concatMap escapeCharacter rawValue <> "'"
  where
    escapeCharacter '\'' = "'\\''"
    escapeCharacter character = [character]

runWorkflowCommand :: Paths -> FilePath -> FilePath -> [String] -> IO ()
runWorkflowCommand paths workingDirectory command args = do
  (exitCode, _, stderrOutput) <-
    readCreateProcessWithExitCode
      (proc command args)
        { cwd = Just workingDirectory,
          env = Just (workflowSubprocessBaseEnvFor paths)
        }
      ""
  case exitCode of
    ExitSuccess -> pure ()
    _ -> ioError (userError ("workflow command failed: " <> command <> " " <> unwords args <> "\n" <> stderrOutput))

hostToolExecutablePresent :: Paths -> HostTool -> IO Bool
hostToolExecutablePresent paths tool = do
  maybePath <- hostToolExecutablePath paths tool
  pure (isJust maybePath)

hostToolExecutablePath :: Paths -> HostTool -> IO (Maybe FilePath)
hostToolExecutablePath paths tool =
  case pathsHostConfig paths of
    Just hostConfig -> do
      let configured = HostTools.hostToolPath hostConfig tool
      if Text.null configured
        then pure Nothing
        else do
          present <- doesFileExist (Text.unpack configured)
          pure (if present then Just (Text.unpack configured) else Nothing)
    Nothing -> firstExistingPath (HostTools.hostToolFallbackCandidates tool)

requireWorkflowHostTool :: Paths -> HostTool -> IO FilePath
requireWorkflowHostTool paths tool = do
  maybePath <- hostToolExecutablePath paths tool
  case maybePath of
    Just path -> pure path
    Nothing ->
      ioError
        ( userError
            ( "required host tool is unavailable: "
                <> Text.unpack (HostTools.hostToolName tool)
            )
        )

firstExistingPath :: [FilePath] -> IO (Maybe FilePath)
firstExistingPath [] = pure Nothing
firstExistingPath (candidate : rest) = do
  present <- doesFileExist candidate
  if present
    then pure (Just candidate)
    else firstExistingPath rest

workflowSubprocessBaseEnvFor :: Paths -> [(String, String)]
workflowSubprocessBaseEnvFor paths =
  maybe [] hostHomeEnv (pathsHostConfig paths)
    <> [ ("PATH", workflowSearchPath paths),
         ("LANG", "C.UTF-8"),
         ("LC_ALL", "C.UTF-8")
       ]

hostHomeEnv :: HostConfig.HostConfig -> [(String, String)]
hostHomeEnv hostConfig =
  let home = Text.unpack (HostConfig.hostHomeDirectory (HostConfig.hostFilesystem hostConfig))
   in [("HOME", home) | not (null home)]

workflowSearchPath :: Paths -> String
workflowSearchPath paths =
  let fallback =
        [ "/opt/homebrew/bin",
          "/usr/local/bin",
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
    | tool <- [HostNpm, HostNode],
      let path = Text.unpack (HostTools.hostToolPath hostConfig tool),
      not (null path)
    ]

allM :: (a -> IO Bool) -> [a] -> IO Bool
allM predicate values = and <$> mapM predicate values
