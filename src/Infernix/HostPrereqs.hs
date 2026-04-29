{-# LANGUAGE LambdaCase #-}

module Infernix.HostPrereqs
  ( appleHostRequirementIds,
    ensureAppleHostPrerequisites,
  )
where

import Control.Monad (unless, void, when)
import Data.List (isInfixOf, nub)
import Infernix.CommandRegistry (Command (..))
import Infernix.Config (controlPlaneContext, discoverPaths, resolveRuntimeMode)
import Infernix.Python (ensurePoetryExecutable)
import Infernix.Types (RuntimeMode (AppleSilicon))
import System.Directory (doesFileExist, findExecutable)
import System.Environment (lookupEnv, setEnv)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.Info (os)
import System.Process (proc, readCreateProcessWithExitCode)

data AppleHostRequirement
  = AppleDockerCli
  | AppleColima
  | AppleKind
  | AppleKubectl
  | AppleHelm
  | AppleNode
  | ApplePoetry
  deriving (Eq, Show)

ensureAppleHostPrerequisites :: Maybe RuntimeMode -> Command -> IO ()
ensureAppleHostPrerequisites maybeRuntimeMode command = do
  paths <- discoverPaths
  when (os == "darwin" && controlPlaneContext paths == "host-native") $ do
    runtimeMode <- resolveRuntimeMode maybeRuntimeMode
    let requirements = appleHostRequirements runtimeMode command
    unless (null requirements) $ do
      brewExecutable <- requireBrewExecutable
      ensureBrewPrefixOnPath brewExecutable
      mapM_ (ensureHomebrewManagedTool brewExecutable) (filter (/= ApplePoetry) requirements)
      when (requiresDockerDaemon requirements) ensureColimaDockerReady
      when (ApplePoetry `elem` requirements) $
        void (ensurePoetryExecutable paths)

appleHostRequirementIds :: RuntimeMode -> Command -> [String]
appleHostRequirementIds runtimeMode command =
  map requirementId (appleHostRequirements runtimeMode command)

appleHostRequirements :: RuntimeMode -> Command -> [AppleHostRequirement]
appleHostRequirements runtimeMode command =
  nub
    ( clusterToolRequirements command
        <> webToolRequirements command
        <> pythonToolRequirements runtimeMode command
    )

clusterToolRequirements :: Command -> [AppleHostRequirement]
clusterToolRequirements = \case
  ClusterUpCommand -> clusterToolchain
  ClusterDownCommand -> clusterToolchain
  ClusterStatusCommand -> clusterToolchain
  KubectlCommand _ -> clusterToolchain
  TestIntegrationCommand -> clusterToolchain
  TestE2ECommand -> clusterToolchain
  TestAllCommand -> clusterToolchain
  InternalPublishChartImagesCommand _ _ -> [AppleDockerCli, AppleColima]
  _ -> []
  where
    clusterToolchain =
      [ AppleDockerCli,
        AppleColima,
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
        ServiceCommand -> [ApplePoetry]
        ClusterUpCommand -> [ApplePoetry]
        TestLintCommand -> [ApplePoetry]
        TestUnitCommand -> [ApplePoetry]
        TestIntegrationCommand -> [ApplePoetry]
        TestE2ECommand -> [ApplePoetry]
        TestAllCommand -> [ApplePoetry]
        _ -> []

requiresDockerDaemon :: [AppleHostRequirement] -> Bool
requiresDockerDaemon requirements =
  any (`elem` requirements) [AppleDockerCli, AppleColima]

requireBrewExecutable :: IO FilePath
requireBrewExecutable = do
  maybeExecutable <- findExecutable "brew"
  case maybeExecutable of
    Just executablePath -> pure executablePath
    Nothing -> do
      let fallbackPaths =
            [ "/opt/homebrew/bin/brew",
              "/usr/local/bin/brew"
            ]
      maybeFallback <- firstExistingPath fallbackPaths
      case maybeFallback of
        Just executablePath -> pure executablePath
        Nothing ->
          ioError
            ( userError
                "Apple host-native prerequisite reconciliation requires Homebrew on PATH before running infernix."
            )

ensureBrewPrefixOnPath :: FilePath -> IO ()
ensureBrewPrefixOnPath brewExecutable = do
  (exitCode, stdoutOutput, stderrOutput) <-
    readCreateProcessWithExitCode (proc brewExecutable ["--prefix"]) ""
  case exitCode of
    ExitSuccess -> do
      let brewPrefix = trimWhitespace stdoutOutput
          brewBin = brewPrefix </> "bin"
          brewSbin = brewPrefix </> "sbin"
      maybePath <- lookupEnv "PATH"
      let pathEntries = maybe [] splitPathList maybePath
          updatedEntries = prependIfMissing brewBin (prependIfMissing brewSbin pathEntries)
      setEnv "PATH" (joinPathList updatedEntries)
    _ ->
      ioError
        ( userError
            ( "failed to resolve the Homebrew prefix via "
                <> brewExecutable
                <> " --prefix\n"
                <> stderrOutput
            )
        )

ensureHomebrewManagedTool :: FilePath -> AppleHostRequirement -> IO ()
ensureHomebrewManagedTool brewExecutable requirement = do
  let commandName = providedCommand requirement
  maybeExecutable <- findExecutable commandName
  case maybeExecutable of
    Just _ -> pure ()
    Nothing -> do
      let formulaName = homebrewFormula requirement
      putStrLn ("reconciling Apple host prerequisite via Homebrew: " <> formulaName)
      (exitCode, _, stderrOutput) <-
        readCreateProcessWithExitCode (proc brewExecutable ["install", formulaName]) ""
      case exitCode of
        ExitSuccess -> do
          maybeInstalledExecutable <- findExecutable commandName
          case maybeInstalledExecutable of
            Just _ -> pure ()
            Nothing ->
              ioError
                ( userError
                    ( "Homebrew installed "
                        <> formulaName
                        <> " but "
                        <> commandName
                        <> " is still not on PATH."
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

ensureColimaDockerReady :: IO ()
ensureColimaDockerReady = do
  dockerReady <- commandSucceeds "docker" ["info"]
  unless dockerReady $ do
    putStrLn "starting Colima for the Apple host-native Docker environment"
    (exitCode, _, stderrOutput) <- readCreateProcessWithExitCode (proc "colima" ["start"]) ""
    case exitCode of
      ExitSuccess -> do
        dockerReadyAfterStart <- commandSucceeds "docker" ["info"]
        unless dockerReadyAfterStart $
          ioError
            ( userError
                "Colima started but `docker info` still failed afterward."
            )
      _ ->
        ioError
          ( userError
              ( "failed to start Colima for the Apple host-native Docker environment\n"
                  <> stderrOutput
              )
          )

commandSucceeds :: FilePath -> [String] -> IO Bool
commandSucceeds commandName args = do
  (exitCode, _, _) <- readCreateProcessWithExitCode (proc commandName args) ""
  pure (exitCode == ExitSuccess)

homebrewFormula :: AppleHostRequirement -> String
homebrewFormula = \case
  AppleDockerCli -> "docker"
  AppleColima -> "colima"
  AppleKind -> "kind"
  AppleKubectl -> "kubernetes-cli"
  AppleHelm -> "helm"
  AppleNode -> "node"
  ApplePoetry -> error "Poetry is not installed through Homebrew on the supported Apple path"

providedCommand :: AppleHostRequirement -> String
providedCommand = \case
  AppleDockerCli -> "docker"
  AppleColima -> "colima"
  AppleKind -> "kind"
  AppleKubectl -> "kubectl"
  AppleHelm -> "helm"
  AppleNode -> "node"
  ApplePoetry -> "poetry"

requirementId :: AppleHostRequirement -> String
requirementId = \case
  AppleDockerCli -> "docker"
  AppleColima -> "colima"
  AppleKind -> "kind"
  AppleKubectl -> "kubectl"
  AppleHelm -> "helm"
  AppleNode -> "node"
  ApplePoetry -> "poetry"

firstExistingPath :: [FilePath] -> IO (Maybe FilePath)
firstExistingPath [] = pure Nothing
firstExistingPath (pathValue : remainingPaths) = do
  exists <- doesFileExist pathValue
  if exists
    then pure (Just pathValue)
    else firstExistingPath remainingPaths

trimWhitespace :: String -> String
trimWhitespace =
  reverse . dropWhile (`elem` [' ', '\n', '\r', '\t']) . reverse

splitPathList :: String -> [String]
splitPathList value =
  case break (== ':') value of
    (entry, ':' : remaining) -> entry : splitPathList remaining
    (entry, _) -> [entry]

joinPathList :: [String] -> String
joinPathList = foldr joinSegment ""
  where
    joinSegment segment "" = segment
    joinSegment segment remaining = segment <> ":" <> remaining

prependIfMissing :: String -> [String] -> [String]
prependIfMissing entry entries
  | any (matchesPath entry) entries = entries
  | otherwise = entry : entries

matchesPath :: String -> String -> Bool
matchesPath expected actual =
  trimWhitespace actual == trimWhitespace expected
    || trimWhitespace actual `isInfixOf` trimWhitespace expected
    || trimWhitespace expected `isInfixOf` trimWhitespace actual
