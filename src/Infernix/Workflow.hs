-- | Developer workflow tooling.
--
-- Phase 6 Sprint 6.44 follow-on removed this module's two raw spawns. The
-- @node --version@ probe was already fixed in substance and is now the closed
-- 'Command.nodeVersionProbe'. The workspace dependency install went through a
-- generic @runWorkflowCommand@ that took a caller-supplied executable and
-- argv, but its only caller passed one fixed argument vector selected between
-- two fixed shapes by that same node-version observation; the genericity was
-- an artifact, not a requirement, so it is now the closed
-- 'Command.npmInstallWebDependencies' indexed by
-- 'Command.WebDependencyToolchain'. Both are reached from
-- @infernix test unit@ / @infernix test all@, which run after configuration
-- exists, so the bounded-command environment's required host manifest is
-- available.
module Infernix.Workflow
  ( demoConfigGeneratedBanner,
    demoConfigGeneratedBannerLine,
    ensureWebDependencies,
    platformCommandsAvailable,
    resolveWebNpmInvocation,
  )
where

import Data.Char (isDigit)
import Data.Maybe (isJust)
import Data.Text qualified as Text
import Infernix.Cluster.Command qualified as Command
import Infernix.Cluster.Invoke qualified as Invoke
import Infernix.Config (Paths (pathsHostConfig, repoRoot), discoverPaths)
import Infernix.HostTools (HostTool (..))
import Infernix.HostTools qualified as HostTools
import Infernix.Substrate (demoConfigGeneratedBanner, demoConfigGeneratedBannerLine)
import System.Directory (doesDirectoryExist, doesFileExist)
import System.FilePath ((</>))

ensureWebDependencies :: IO ()
ensureWebDependencies = do
  paths <- discoverPaths
  let webRoot = repoRoot paths </> "web"
  depsDirectoryPresent <- doesDirectoryExist (webRoot </> "node_modules")
  toolchainPresent <- webToolchainPresent webRoot
  hostNodeReady <- hostNodeSupportsWebToolchain paths
  if depsDirectoryPresent && toolchainPresent && hostNodeReady
    then pure ()
    else installWebDependencies paths (webDependencyToolchainFor hostNodeReady)

-- | The closed toolchain index is exactly the host-node observation: a host
-- whose @node@ satisfies the web toolchain minimum installs directly, and one
-- that does not has npm provision a pinned pair for the install.
webDependencyToolchainFor :: Bool -> Command.WebDependencyToolchain
webDependencyToolchainFor hostNodeReady =
  if hostNodeReady
    then Command.HostNodeToolchain
    else Command.PinnedNodeToolchain

installWebDependencies :: Paths -> Command.WebDependencyToolchain -> IO ()
installWebDependencies paths toolchain = do
  outcome <-
    Invoke.tryClusterCommand
      paths
      (Command.npmInstallWebDependencies toolchain)
  case outcome of
    Right _ -> pure ()
    Left failure ->
      ioError
        ( userError
            ("web dependency install failed:\n" <> failure)
        )

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

-- | Observe whether the host's own @node@ satisfies the web toolchain
-- minimum. Both executables must be present before the probe runs, so an
-- absent toolchain is reported as unsupported rather than as a command
-- failure; a probe that fails or times out is also unsupported, which is the
-- fail-closed direction (it selects the pinned toolchain).
hostNodeSupportsWebToolchain :: Paths -> IO Bool
hostNodeSupportsWebToolchain paths = do
  maybeNode <- hostToolExecutablePath paths HostNode
  maybeNpm <- hostToolExecutablePath paths HostNpm
  case (maybeNode, maybeNpm) of
    (Just _, Just _) -> probeHostNodeVersion paths
    _ -> pure False

probeHostNodeVersion :: Paths -> IO Bool
probeHostNodeVersion paths = do
  outcome <- Invoke.tryClusterCommand paths Command.nodeVersionProbe
  case outcome of
    Right stdoutOutput -> pure (nodeVersionSatisfiesMinimum stdoutOutput)
    Left _ -> pure False

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

allM :: (a -> IO Bool) -> [a] -> IO Bool
allM predicate values = and <$> mapM predicate values
