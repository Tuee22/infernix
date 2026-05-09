{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Infernix.HostPrereqs
  ( appleHostRequirementIds,
    ensureAppleHostPrerequisites,
  )
where

import Control.Monad (unless, void, when)
import Data.Aeson (FromJSON (parseJSON), eitherDecode, withObject, (.:))
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
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
  | ApplePython
  | ApplePoetry
  deriving (Eq, Show)

data ColimaProfile = ColimaProfile
  { colimaStatus :: String,
    colimaCpus :: Int,
    colimaMemoryBytes :: Integer
  }

instance FromJSON ColimaProfile where
  parseJSON =
    withObject "ColimaProfile" $ \objectValue ->
      ColimaProfile
        <$> objectValue .: "status"
        <*> objectValue .: "cpus"
        <*> objectValue .: "memory"

supportedColimaCpuCount :: Int
supportedColimaCpuCount = 8

supportedColimaMemoryGiB :: Int
supportedColimaMemoryGiB = 16

gibibyte :: Integer
gibibyte = 1024 * 1024 * 1024

supportedColimaMemoryBytes :: Integer
supportedColimaMemoryBytes =
  fromIntegral supportedColimaMemoryGiB * gibibyte

ensureAppleHostPrerequisites :: Maybe RuntimeMode -> Command -> IO ()
ensureAppleHostPrerequisites maybeRuntimeMode command = do
  paths <- discoverPaths
  when (os == "darwin" && controlPlaneContext paths == "host-native") $ do
    resolvedRuntimeMode <- runtimeModeForApplePrereqs maybeRuntimeMode command
    let requirements = appleHostRequirements resolvedRuntimeMode command
    unless (null requirements) $ do
      brewExecutable <- requireBrewExecutable
      ensureBrewPrefixOnPath brewExecutable
      mapM_ (ensureHomebrewManagedTool brewExecutable) (filter (/= ApplePoetry) requirements)
      when (requiresDockerDaemon requirements) ensureColimaDockerReady
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
        Nothing -> Just <$> resolveRuntimeMode Nothing
  | otherwise = pure maybeRuntimeMode

commandNeedsPythonPrereqs :: Command -> Bool
commandNeedsPythonPrereqs = \case
  ServiceCommand -> True
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
        ServiceCommand -> [ApplePython, ApplePoetry]
        ClusterUpCommand -> [ApplePython, ApplePoetry]
        TestLintCommand -> [ApplePython, ApplePoetry]
        TestUnitCommand -> [ApplePython, ApplePoetry]
        TestIntegrationCommand -> [ApplePython, ApplePoetry]
        TestE2ECommand -> [ApplePython, ApplePoetry]
        TestAllCommand -> [ApplePython, ApplePoetry]
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
  profile <- readColimaProfile
  dockerReady <- commandSucceeds "docker" ["info"]
  case (colimaProfileRunning profile, colimaProfileSatisfiesMinimums profile, dockerReady) of
    (True, True, True) -> pure ()
    (True, True, False) -> do
      putStrLn "restarting Colima because the Docker daemon is not reachable through the supported Apple host-native environment"
      stopColima
      startSupportedColima
    (True, False, _) -> do
      putStrLn
        ( "restarting Colima with the supported Apple profile ("
            <> supportedColimaProfileSummary
            <> "); current profile is "
            <> colimaProfileSummary profile
        )
      stopColima
      startSupportedColima
    (False, _, _) -> do
      putStrLn
        ( "starting Colima for the Apple host-native Docker environment with the supported profile ("
            <> supportedColimaProfileSummary
            <> ")"
        )
      startSupportedColima
  dockerReadyAfterStart <- commandSucceeds "docker" ["info"]
  unless dockerReadyAfterStart $
    ioError
      ( userError
          "Colima is running but `docker info` still failed afterward."
      )
  updatedProfile <- readColimaProfile
  unless (colimaProfileRunning updatedProfile && colimaProfileSatisfiesMinimums updatedProfile) $
    ioError
      ( userError
          ( "Colima did not reach the supported Apple profile after reconciliation. "
              <> "Expected at least "
              <> supportedColimaProfileSummary
              <> " but found "
              <> colimaProfileSummary updatedProfile
              <> "."
          )
      )

readColimaProfile :: IO ColimaProfile
readColimaProfile = do
  (exitCode, stdoutOutput, stderrOutput) <-
    readCreateProcessWithExitCode (proc "colima" ["list", "--json"]) ""
  case exitCode of
    ExitSuccess ->
      case eitherDecode (LazyChar8.pack stdoutOutput) of
        Right profile -> pure profile
        Left decodeError ->
          ioError
            ( userError
                ( "failed to parse `colima list --json`\n"
                    <> decodeError
                )
            )
    _ ->
      ioError
        ( userError
            ( "failed to inspect the Colima profile for the Apple host-native Docker environment\n"
                <> stderrOutput
            )
        )

colimaProfileRunning :: ColimaProfile -> Bool
colimaProfileRunning profile =
  colimaStatus profile == "Running"

colimaProfileSatisfiesMinimums :: ColimaProfile -> Bool
colimaProfileSatisfiesMinimums profile =
  colimaCpus profile >= supportedColimaCpuCount
    && colimaMemoryBytes profile >= supportedColimaMemoryBytes

colimaProfileSummary :: ColimaProfile -> String
colimaProfileSummary profile =
  show (colimaCpus profile)
    <> " CPU / "
    <> show (colimaMemoryBytes profile `div` gibibyte)
    <> " GiB memory"

supportedColimaProfileSummary :: String
supportedColimaProfileSummary =
  show supportedColimaCpuCount
    <> " CPU / "
    <> show supportedColimaMemoryGiB
    <> " GiB memory"

stopColima :: IO ()
stopColima = do
  (exitCode, _, stderrOutput) <- readCreateProcessWithExitCode (proc "colima" ["stop"]) ""
  case exitCode of
    ExitSuccess -> pure ()
    _ ->
      ioError
        ( userError
            ( "failed to stop Colima for Apple host-native Docker reconciliation\n"
                <> stderrOutput
            )
        )

startSupportedColima :: IO ()
startSupportedColima = do
  (exitCode, _, stderrOutput) <-
    readCreateProcessWithExitCode
      (proc "colima" ["start", "--cpu", show supportedColimaCpuCount, "--memory", show supportedColimaMemoryGiB])
      ""
  case exitCode of
    ExitSuccess -> pure ()
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
  ApplePython -> "python@3.12"
  ApplePoetry -> error "Poetry is not installed through Homebrew on the supported Apple path"

providedCommand :: AppleHostRequirement -> String
providedCommand = \case
  AppleDockerCli -> "docker"
  AppleColima -> "colima"
  AppleKind -> "kind"
  AppleKubectl -> "kubectl"
  AppleHelm -> "helm"
  AppleNode -> "node"
  ApplePython -> "python3.12"
  ApplePoetry -> "poetry"

requirementId :: AppleHostRequirement -> String
requirementId = \case
  AppleDockerCli -> "docker"
  AppleColima -> "colima"
  AppleKind -> "kind"
  AppleKubectl -> "kubectl"
  AppleHelm -> "helm"
  AppleNode -> "node"
  ApplePython -> "python"
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
