{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Infernix.HostPrereqs
  ( appleHostRequirementIds,
    appleDockerBoundaryError,
    decodeDockerInfoArchitecture,
    ensureAppleHostPrerequisites,
  )
where

import Control.Monad (unless, void, when)
import Data.Aeson (FromJSON (parseJSON), eitherDecode, withObject, (.:))
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.Char (toLower)
import Data.List (nub)
import Infernix.CommandRegistry (Command (..))
import Infernix.Config (ControlPlaneContext (HostNative), controlPlaneContext, discoverPaths, targetRuntimeModeForExecutionContext)
import Infernix.Python (ensurePoetryExecutable)
import Infernix.Types (RuntimeMode (AppleSilicon))
import System.Directory (doesFileExist)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.Info (os)
import System.Process (proc, readCreateProcessWithExitCode)

data AppleHostRequirement
  = AppleDockerCli
  | AppleKind
  | AppleKubectl
  | AppleHelm
  | AppleNode
  | ApplePython
  | ApplePoetry
  deriving (Eq, Show)

newtype DockerInfo = DockerInfo String

instance FromJSON DockerInfo where
  parseJSON =
    withObject "DockerInfo" $ \objectValue ->
      DockerInfo <$> objectValue .: "Architecture"

ensureAppleHostPrerequisites :: Maybe RuntimeMode -> Command -> IO ()
ensureAppleHostPrerequisites maybeRuntimeMode command = do
  paths <- discoverPaths
  when (os == "darwin" && controlPlaneContext paths == HostNative) $ do
    resolvedRuntimeMode <- runtimeModeForApplePrereqs maybeRuntimeMode command
    let requirements = appleHostRequirements resolvedRuntimeMode command
    unless (null requirements) $ do
      let brewExecutable = "/opt/homebrew/bin/brew"
      requireBrewExecutable brewExecutable
      mapM_ (ensureHomebrewManagedTool brewExecutable) (filter (/= ApplePoetry) requirements)
      when (requiresDockerDaemon requirements) ensureSelectedDockerDaemonReady
      when (ApplePoetry `elem` requirements) $
        void (ensurePoetryExecutable paths)

appleHostRequirementIds :: RuntimeMode -> Command -> [String]
appleHostRequirementIds runtimeMode command =
  map requirementId (appleHostRequirements (Just runtimeMode) command)

appleHostRequirements :: Maybe RuntimeMode -> Command -> [AppleHostRequirement]
appleHostRequirements maybeRuntimeMode command =
  nub
    ( clusterToolRequirements command
        <> webToolRequirements command
        <> maybe [] (`pythonToolRequirements` command) maybeRuntimeMode
    )

runtimeModeForApplePrereqs :: Maybe RuntimeMode -> Command -> IO (Maybe RuntimeMode)
runtimeModeForApplePrereqs maybeRuntimeMode command
  | commandNeedsPythonPrereqs command =
      case maybeRuntimeMode of
        Just runtimeMode -> pure (Just runtimeMode)
        Nothing -> do
          paths <- discoverPaths
          Just <$> targetRuntimeModeForExecutionContext paths
  | otherwise = pure maybeRuntimeMode

commandNeedsPythonPrereqs :: Command -> Bool
commandNeedsPythonPrereqs = \case
  ServiceCommand _ -> True
  ClusterUpCommand -> True
  TestLintCommand -> True
  TestUnitCommand -> True
  TestIntegrationCommand -> True
  TestE2ECommand -> True
  TestAllCommand -> True
  _ -> False

clusterToolRequirements :: Command -> [AppleHostRequirement]
clusterToolRequirements = \case
  ClusterUpCommand -> clusterToolchain
  ClusterDownCommand -> clusterToolchain
  ClusterStatusCommand -> clusterToolchain
  KubectlCommand _ -> clusterToolchain
  TestIntegrationCommand -> clusterToolchain
  TestE2ECommand -> clusterToolchain
  TestAllCommand -> clusterToolchain
  InternalPublishChartImagesCommand _ _ -> [AppleDockerCli]
  _ -> []
  where
    clusterToolchain =
      [ AppleDockerCli,
        AppleKind,
        AppleKubectl,
        AppleHelm
      ]

webToolRequirements :: Command -> [AppleHostRequirement]
webToolRequirements = \case
  ClusterUpCommand -> [AppleNode]
  TestUnitCommand -> [AppleNode]
  TestIntegrationCommand -> [AppleNode]
  TestE2ECommand -> [AppleNode]
  TestAllCommand -> [AppleNode]
  _ -> []

pythonToolRequirements :: RuntimeMode -> Command -> [AppleHostRequirement]
pythonToolRequirements runtimeMode command
  | runtimeMode /= AppleSilicon = []
  | otherwise =
      case command of
        ServiceCommand _ -> [ApplePython, ApplePoetry]
        ClusterUpCommand -> [ApplePython, ApplePoetry]
        TestLintCommand -> [ApplePython, ApplePoetry]
        TestUnitCommand -> [ApplePython, ApplePoetry]
        TestIntegrationCommand -> [ApplePython, ApplePoetry]
        TestE2ECommand -> [ApplePython, ApplePoetry]
        TestAllCommand -> [ApplePython, ApplePoetry]
        _ -> []

requiresDockerDaemon :: [AppleHostRequirement] -> Bool
requiresDockerDaemon requirements =
  AppleDockerCli `elem` requirements

requireBrewExecutable :: FilePath -> IO ()
requireBrewExecutable brewExecutable = do
  present <- doesFileExist brewExecutable
  unless present $
    ioError
      ( userError
          ( "Apple host-native prerequisite reconciliation requires native arm64 Homebrew at "
              <> brewExecutable
              <> ". Install Homebrew for Apple Silicon and rerun the same command."
          )
      )

ensureHomebrewManagedTool :: FilePath -> AppleHostRequirement -> IO ()
ensureHomebrewManagedTool brewExecutable requirement = do
  let commandName = providedCommand requirement
      commandPath = homebrewCommandPath commandName
  executablePresent <- doesFileExist commandPath
  unless executablePresent $ do
    let formulaName = homebrewFormula requirement
    putStrLn ("reconciling Apple host prerequisite via Homebrew: " <> formulaName)
    (exitCode, _, stderrOutput) <-
      readCreateProcessWithExitCode (proc brewExecutable ["install", formulaName]) ""
    case exitCode of
      ExitSuccess -> do
        installed <- doesFileExist commandPath
        unless installed $
          ioError
            ( userError
                ( "Homebrew installed "
                    <> formulaName
                    <> " but "
                    <> commandPath
                    <> " is still missing."
                )
            )
      _ ->
        ioError
          ( userError
              ( "failed to install "
                  <> formulaName
                  <> " with Homebrew\n"
                  <> stderrOutput
              )
          )

ensureSelectedDockerDaemonReady :: IO ()
ensureSelectedDockerDaemonReady = do
  let dockerExecutable = homebrewCommandPath "docker"
  contextName <- readDockerContext dockerExecutable
  architecture <- readDockerDaemonArchitecture dockerExecutable contextName
  putStrLn
    ( "Apple Docker context: "
        <> contextName
        <> "; daemon architecture: "
        <> architecture
    )
  case appleDockerBoundaryError contextName architecture of
    Nothing -> pure ()
    Just message -> ioError (userError message)

readDockerContext :: FilePath -> IO String
readDockerContext dockerExecutable = do
  (exitCode, stdoutOutput, stderrOutput) <-
    readCreateProcessWithExitCode (proc dockerExecutable ["context", "show"]) ""
  case exitCode of
    ExitSuccess -> pure (trimWhitespace stdoutOutput)
    _ ->
      ioError
        ( userError
            ( "failed to inspect the selected Docker context with "
                <> dockerExecutable
                <> " context show\n"
                <> stderrOutput
            )
        )

readDockerDaemonArchitecture :: FilePath -> String -> IO String
readDockerDaemonArchitecture dockerExecutable contextName = do
  (exitCode, stdoutOutput, stderrOutput) <-
    readCreateProcessWithExitCode
      (proc dockerExecutable ["info", "--format", "{{json .}}"])
      ""
  case exitCode of
    ExitSuccess ->
      case decodeDockerInfoArchitecture stdoutOutput of
        Right architecture -> pure architecture
        Left decodeError ->
          ioError
            ( userError
                ( "failed to parse Docker daemon architecture for context "
                    <> contextName
                    <> "\n"
                    <> decodeError
                )
            )
    _ ->
      ioError
        ( userError
            ( "Docker-backed Apple work requires the currently selected Docker context to point at an already running native arm64 daemon. "
                <> "The selected context is "
                <> contextName
                <> ", but `docker info` failed. Infernix will not create or switch Docker contexts or create a Docker VM.\n"
                <> stderrOutput
            )
        )

decodeDockerInfoArchitecture :: String -> Either String String
decodeDockerInfoArchitecture stdoutOutput = do
  DockerInfo architecture <- eitherDecode (LazyChar8.pack stdoutOutput)
  pure architecture

appleDockerBoundaryError :: String -> String -> Maybe String
appleDockerBoundaryError contextName architecture
  | nativeArm64Architecture architecture = Nothing
  | otherwise =
      Just
        ( "Docker-backed Apple work requires the selected Docker context to use a native arm64 daemon. "
            <> "Current context: "
            <> contextName
            <> "; daemon architecture: "
            <> architecture
            <> ". Infernix will not create or switch Docker contexts, create a Docker VM, or use cross-architecture emulation."
        )

nativeArm64Architecture :: String -> Bool
nativeArm64Architecture architecture =
  normalizeArchitecture architecture `elem` ["arm64", "aarch64"]

normalizeArchitecture :: String -> String
normalizeArchitecture = map toLower . trimWhitespace

homebrewFormula :: AppleHostRequirement -> String
homebrewFormula = \case
  AppleDockerCli -> "docker"
  AppleKind -> "kind"
  AppleKubectl -> "kubernetes-cli"
  AppleHelm -> "helm"
  AppleNode -> "node"
  ApplePython -> "python@3.12"
  ApplePoetry -> error "Poetry is not installed through Homebrew on the supported Apple path"

providedCommand :: AppleHostRequirement -> String
providedCommand = \case
  AppleDockerCli -> "docker"
  AppleKind -> "kind"
  AppleKubectl -> "kubectl"
  AppleHelm -> "helm"
  AppleNode -> "node"
  ApplePython -> "python3.12"
  ApplePoetry -> "poetry"

requirementId :: AppleHostRequirement -> String
requirementId = \case
  AppleDockerCli -> "docker"
  AppleKind -> "kind"
  AppleKubectl -> "kubectl"
  AppleHelm -> "helm"
  AppleNode -> "node"
  ApplePython -> "python"
  ApplePoetry -> "poetry"

trimWhitespace :: String -> String
trimWhitespace =
  reverse . dropWhile (`elem` [' ', '\n', '\r', '\t']) . reverse

homebrewCommandPath :: String -> FilePath
homebrewCommandPath commandName =
  "/opt/homebrew/bin" </> commandName
