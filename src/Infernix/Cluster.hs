{-# LANGUAGE OverloadedStrings #-}

module Infernix.Cluster
  ( clusterDown,
    clusterStatus,
    clusterUp,
    kindControlPlaneNodeName,
    linuxGpuSupportedOnHost,
    loadClusterState,
    runKubectlCompat,
    writeGeneratedKindConfig,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (IOException, bracket, try)
import Control.Monad (unless, when)
import Data.Aeson (Value (..), eitherDecode)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy qualified as Lazy
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.Char (isSpace, toLower)
import Data.List qualified as List
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe, mapMaybe)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Data.Vector qualified as Vector
import Infernix.Cluster.Discover
import Infernix.Cluster.PublishImages qualified as PublishImages
import Infernix.Config (Paths (..))
import Infernix.Config qualified as Config
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Engines.AppleSilicon (ensureAppleSiliconRuntimeReady)
import Infernix.Models
import Infernix.Routes (routeHelmValues)
import Infernix.Storage
import Infernix.Types
import Infernix.Workflow (platformCommandsAvailable)
import Network.Socket qualified as Socket
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, findExecutable, listDirectory, removePathForcibly)
import System.Environment (getEnvironment, lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.Process
  ( CreateProcess (cwd, env),
    proc,
    readCreateProcessWithExitCode,
  )
import Text.Read (readMaybe)

clusterStatePath :: Paths -> FilePath
clusterStatePath paths = runtimeRoot paths </> "cluster-state.state"

nodeMountedKindRoot :: FilePath
nodeMountedKindRoot = "/var/infernix-data"

seedClaims :: [PersistentClaim]
seedClaims = platformClaims

helmRepositories :: [(String, String)]
helmRepositories =
  [ ("goharbor", "https://helm.goharbor.io"),
    ("percona", "https://percona.github.io/percona-helm-charts"),
    ("apachepulsar", "https://pulsar.apache.org/charts"),
    ("bitnami", "https://charts.bitnami.com/bitnami"),
    ("nvdp", "https://nvidia.github.io/k8s-device-plugin")
  ]

helmDependencyArchives :: [FilePath]
helmDependencyArchives =
  [ "chart/charts/harbor-1.18.3.tgz",
    "chart/charts/pg-operator-2.9.0.tgz",
    "chart/charts/pg-db-2.9.0.tgz",
    "chart/charts/pulsar-4.5.0.tgz",
    "chart/charts/minio-17.0.21.tgz",
    "chart/charts/gateway-helm-v1.7.2.tgz"
  ]

envoyGatewayDependencyArchive :: FilePath
envoyGatewayDependencyArchive = "chart/charts/gateway-helm-v1.7.2.tgz"

finalPhaseDeployments :: ClusterState -> [String]
finalPhaseDeployments state =
  baseDeployments
    <> [deployment | clusterStateHasDemoUi state, deployment <- ["deployment/infernix-demo"]]
  where
    baseDeployments =
      [ "deployment/infernix-minio-console",
        "deployment/infernix-service"
      ]

finalPhaseStatefulSets :: [String]
finalPhaseStatefulSets =
  [ "statefulset/infernix-infernix-pulsar-bookie",
    "statefulset/infernix-infernix-pulsar-broker",
    "statefulset/infernix-infernix-pulsar-proxy",
    "statefulset/infernix-infernix-pulsar-recovery",
    "statefulset/infernix-infernix-pulsar-toolset",
    "statefulset/infernix-infernix-pulsar-zookeeper",
    "statefulset/infernix-minio"
  ]

harborFinalPhaseDeployments :: [String]
harborFinalPhaseDeployments =
  [ "deployment/infernix-harbor-core",
    "deployment/infernix-harbor-jobservice",
    "deployment/infernix-harbor-nginx",
    "deployment/infernix-harbor-portal",
    "deployment/infernix-harbor-registry"
  ]

harborFinalPhaseStatefulSets :: [String]
harborFinalPhaseStatefulSets =
  [ "statefulset/infernix-harbor-redis",
    "statefulset/infernix-harbor-trivy",
    "statefulset/infernix-minio"
  ]

nvidiaDevicePluginVersion :: String
nvidiaDevicePluginVersion = "0.17.1"

nvidiaCudaContainerImage :: String
nvidiaCudaContainerImage = "nvidia/cuda:12.4.1-base-ubuntu22.04"

kindNodeImage :: String
kindNodeImage = "kindest/node:v1.34.0"

data HelmDeployPhase
  = WarmupPhase
  | BootstrapPhase
  | HarborFinalPhase
  | FinalPhase

data HarborBootstrapOutcome
  = HarborRegistryReady
  | HarborMigrationDirty
  | HarborBootstrapTimedOut String

data OperatorManagedClaim = OperatorManagedClaim
  { operatorClaimNamespace :: String,
    operatorClaimCluster :: String,
    operatorClaimInstanceSet :: String,
    operatorClaimRole :: String,
    operatorClaimDataKind :: String,
    operatorClaimInstance :: String,
    operatorClaimRepository :: String,
    operatorClaimPvcName :: String,
    operatorClaimRequestedStorage :: String
  }

postgresOperatorDeployment :: String
postgresOperatorDeployment = "deployment/infernix-postgres-operator"

harborPostgresClusterName :: String
harborPostgresClusterName = "harbor-postgresql"

harborPostgresExpectedDataClaims :: Int
harborPostgresExpectedDataClaims = 3

harborPostgresStartupRepairGraceAttempts :: Int
harborPostgresStartupRepairGraceAttempts = 18

harborPostgresExpectedOperatorClaims :: Int
harborPostgresExpectedOperatorClaims = 4

harborPostgresPrimarySelector :: String
harborPostgresPrimarySelector =
  "postgres-operator.crunchydata.com/cluster="
    <> harborPostgresClusterName
    <> ",postgres-operator.crunchydata.com/role=primary"

harborPostgresUserName :: String
harborPostgresUserName = "harbor"

harborPostgresUserSecretName :: String
harborPostgresUserSecretName = "infernix-harbor-db-user"

clusterStateHasDemoUi :: ClusterState -> Bool
clusterStateHasDemoUi state =
  any ((`elem` ["/", "/api", "/objects"]) . path) (routes state)

clusterUp :: Maybe RuntimeMode -> IO ()
clusterUp maybeRuntimeMode = do
  paths <- Config.discoverPaths
  Config.ensureRepoLayout paths
  runtimeMode <- Config.resolveRuntimeMode maybeRuntimeMode
  Config.ensureSupportedRuntimeModeForExecutionContext paths runtimeMode
  when (runtimeMode == AppleSilicon) (ensureAppleSiliconRuntimeReady paths)
  commandsAvailable <- platformCommandsAvailable
  unless commandsAvailable $
    ioError
      ( userError
          "cluster up requires Docker, Helm, Kind, and kubectl on the supported path; simulation is no longer available."
      )
  clusterUpWithPlatform paths runtimeMode

clusterUpWithPlatform :: Paths -> RuntimeMode -> IO ()
clusterUpWithPlatform paths runtimeMode = do
  let controlPlane = Config.controlPlaneContext paths
  requestedPort <- chooseEdgePort paths
  generatedConfigPath <- requireGeneratedDemoConfigFile paths runtimeMode
  generatedConfig <- decodeDemoConfigFile generatedConfigPath
  requestedPayload <- Lazy.readFile generatedConfigPath
  let demoUiEnabledValue = demoUiEnabled generatedConfig
  createDirectoryIfMissing True (buildRoot paths)
  claimDiscoveryTime <- getCurrentTime
  let claimDiscoveryState =
        ClusterState
          { clusterPresent = True,
            edgePort = requestedPort,
            routes = routeInventory demoUiEnabledValue,
            storageClass = "infernix-manual",
            claims = seedClaims,
            clusterRuntimeMode = runtimeMode,
            kubeconfigPath = Config.generatedKubeconfigPath paths,
            generatedDemoConfigPath = Config.generatedDemoConfigPath paths,
            publishedDemoConfigPath = Config.publishedConfigMapCatalogPath paths,
            publishedConfigMapManifestPath = Config.publishedConfigMapManifestPath paths,
            mountedDemoConfigPath = Config.watchedDemoConfigPath,
            updatedAt = claimDiscoveryTime
          }
  claimDiscoveryValuesPath <- writeHelmValuesFile paths controlPlane claimDiscoveryState requestedPayload FinalPhase
  claimDiscoveryRenderedChartPath <- renderHelmChart paths runtimeMode [claimDiscoveryValuesPath]
  discoveredClaims <- discoverPersistentClaims paths claimDiscoveryRenderedChartPath
  discoveredRoutes <- discoverChartRoutesFile claimDiscoveryRenderedChartPath
  mapM_ (ensureClaimDirectoryReady paths) discoveredClaims
  (edgePortValue, kubeconfigContents, clusterCreated) <- ensureKindCluster paths runtimeMode requestedPort
  when (clusterCreated && not (kindUsesHostBindMounts paths)) $
    prepareKindNodeRuntimePaths paths runtimeMode
  writeFile (edgePortPath paths) (show edgePortValue)
  writeTextFile (Config.generatedKubeconfigPath paths) (Text.pack kubeconfigContents)
  ensureOuterContainerKindNetworkAccess paths runtimeMode
  waitForKubernetesApi paths runtimeMode
  configureRuntimeModeCluster paths runtimeMode
  let demoConfigPath = generatedConfigPath
      publishedCatalogPath = Config.publishedConfigMapCatalogPath paths
      configMapManifestPath = Config.publishedConfigMapManifestPath paths
      publicationPath = Config.publicationStatePath paths
      mountedCatalogPath = Config.watchedDemoConfigPath
      payload = requestedPayload
  createDirectoryIfMissing True (buildRoot paths)
  createDirectoryIfMissing True (takeDirectory publishedCatalogPath)
  createDirectoryIfMissing True (takeDirectory configMapManifestPath)
  createDirectoryIfMissing True (takeDirectory publicationPath)
  Lazy.writeFile publishedCatalogPath payload
  writeFile configMapManifestPath (renderConfigMapManifest payload)
  now <- getCurrentTime
  let seedState =
        ClusterState
          { clusterPresent = True,
            edgePort = edgePortValue,
            routes = discoveredRoutes,
            storageClass = "infernix-manual",
            claims = seedClaims,
            clusterRuntimeMode = runtimeMode,
            kubeconfigPath = Config.generatedKubeconfigPath paths,
            generatedDemoConfigPath = demoConfigPath,
            publishedDemoConfigPath = publishedCatalogPath,
            publishedConfigMapManifestPath = configMapManifestPath,
            mountedDemoConfigPath = mountedCatalogPath,
            updatedAt = now
          }
  warmupValuesPath <- writeHelmValuesFile paths controlPlane seedState payload WarmupPhase
  bootstrapValuesPath <- writeHelmValuesFile paths controlPlane seedState payload BootstrapPhase
  harborFinalValuesPath <- writeHelmValuesFile paths controlPlane seedState payload HarborFinalPhase
  finalValuesPath <- writeHelmValuesFile paths controlPlane seedState payload FinalPhase
  renderedChartPath <- renderHelmChart paths runtimeMode [finalValuesPath]
  when clusterCreated $
    preloadBootstrapSupportImagesOnKindNodes paths runtimeMode renderedChartPath
  applyBootstrapState paths runtimeMode demoUiEnabledValue discoveredClaims
  let initialState = seedState {claims = discoveredClaims}
  writeFile publicationPath (renderPublicationState controlPlane initialState)
  ensureHelmDependencies paths
  ensureEnvoyGatewayCrdsInstalled paths initialState
  reconcilePersistentVolumes initialState
  deployChart paths initialState [warmupValuesPath] False
  state <- reconcileOperatorManagedPersistentVolumes paths initialState
  repairHarborDatabaseMigrationState state
  bootstrapHarborWithRepair paths state [bootstrapValuesPath]
  buildClusterImages paths runtimeMode
  imageOverridesPath <- publishClusterImages paths renderedChartPath runtimeMode
  deployChart paths state [harborFinalValuesPath, imageOverridesPath] True
  waitForHarborFinalPhaseRollouts state
  waitForGatewayApiCrds state
  preloadHarborBackedImagesOnKindWorker paths runtimeMode imageOverridesPath
  deployChart paths state [finalValuesPath, imageOverridesPath] True
  waitForFinalPhaseRollouts state
  waitForRoutedPublicationSurface paths state
  finalState <- refreshPersistentClaims state
  writeStateFile (clusterStatePath paths) finalState
  putStrLn "cluster up complete"
  putStrLn ("controlPlaneContext: " <> controlPlane)
  putStrLn ("runtimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("edgePort: " <> show edgePortValue)
  putStrLn ("generatedDemoConfigPath: " <> demoConfigPath)
  putStrLn ("publishedDemoConfigPath: " <> publishedCatalogPath)
  putStrLn ("mountedDemoConfigPath: " <> mountedCatalogPath)

requireGeneratedDemoConfigFile :: Paths -> RuntimeMode -> IO FilePath
requireGeneratedDemoConfigFile paths expectedRuntimeMode = do
  let filePath = Config.generatedDemoConfigPath paths
  filePresent <- doesFileExist filePath
  unless filePresent $
    ioError
      ( userError
          ( unlines
              [ "Missing generated substrate file: " <> filePath,
                "Restage it before running cluster operations.",
                "Example: infernix internal materialize-substrate " <> Text.unpack (runtimeModeId expectedRuntimeMode)
              ]
          )
      )
  demoConfig <- decodeDemoConfigFile filePath
  unless (configRuntimeMode demoConfig == expectedRuntimeMode) $
    ioError
      ( userError
          ( unlines
              [ "Generated substrate file runtime mismatch: " <> filePath,
                "expected: " <> Text.unpack (runtimeModeId expectedRuntimeMode),
                "actual: " <> Text.unpack (runtimeModeId (configRuntimeMode demoConfig)),
                "Restage the file for the active substrate before running cluster operations."
              ]
          )
      )
  pure filePath

clusterDown :: Maybe RuntimeMode -> IO ()
clusterDown maybeRuntimeMode = do
  paths <- Config.discoverPaths
  maybeState <- loadClusterState paths
  runtimeMode <-
    case maybeRuntimeMode of
      Just requestedRuntimeMode -> pure requestedRuntimeMode
      Nothing ->
        case maybeState of
          Just state -> pure (clusterRuntimeMode state)
          Nothing -> Config.resolveRuntimeMode Nothing
  clusterExists <- kindClusterExists paths runtimeMode
  when clusterExists $ do
    unless (kindUsesHostBindMounts paths) $
      syncKindNodeRuntimePathsToHost paths runtimeMode maybeState
    deleteKindCluster paths runtimeMode
  case maybeState of
    Nothing -> putStrLn "cluster already absent"
    Just state
      | clusterRuntimeMode state /= runtimeMode -> putStrLn "cluster down complete"
      | otherwise -> do
          now <- getCurrentTime
          let updatedState =
                state
                  { clusterPresent = False,
                    updatedAt = now
                  }
          writeStateFile (clusterStatePath paths) updatedState
          writeFile
            (Config.publicationStatePath paths)
            (renderPublicationState (Config.controlPlaneContext paths) updatedState)
          putStrLn "cluster down complete"

clusterStatus :: Maybe RuntimeMode -> IO ()
clusterStatus maybeRuntimeMode = do
  paths <- Config.discoverPaths
  maybeState <- loadClusterState paths
  case maybeState of
    Nothing -> do
      runtimeMode <- Config.resolveRuntimeMode maybeRuntimeMode
      putStrLn "cluster not yet reconciled"
      putStrLn ("runtimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
      putStrLn ("buildRoot: " <> buildRoot paths)
      putStrLn ("dataRoot: " <> dataRoot paths)
      putStrLn ("expectedDemoConfigPath: " <> Config.generatedDemoConfigPath paths)
      putStrLn ("expectedMountedDemoConfigPath: " <> Config.watchedDemoConfigPath)
    Just state -> do
      actualPresent <- kindClusterExists paths (clusterRuntimeMode state)
      cacheEntries <- countLeafEntries (modelCacheRoot paths)
      resultCount <- countLeafEntries (resultsRoot paths)
      objectCount <- countLeafEntries (objectStoreRoot paths)
      durableManifestCount <- countLeafEntries (objectStoreRoot paths </> "manifests")
      nodeCount <- kubectlLineCountIfReachable state ["get", "nodes", "--no-headers"]
      podCount <- kubectlLineCountIfReachable state ["get", "pods", "-A", "--no-headers"]
      putStrLn ("clusterPresent: " <> show actualPresent)
      putStrLn ("controlPlaneContext: " <> Config.controlPlaneContext paths)
      putStrLn ("runtimeMode: " <> Text.unpack (runtimeModeId (clusterRuntimeMode state)))
      putStrLn ("edgePort: " <> show (edgePort state))
      putStrLn ("storageClass: " <> Text.unpack (storageClass state))
      putStrLn ("buildRoot: " <> buildRoot paths)
      putStrLn ("dataRoot: " <> dataRoot paths)
      putStrLn ("kubeconfigPath: " <> kubeconfigPath state)
      putStrLn ("generatedDemoConfigPath: " <> generatedDemoConfigPath state)
      putStrLn ("publishedDemoConfigPath: " <> publishedDemoConfigPath state)
      putStrLn ("publishedConfigMapManifestPath: " <> publishedConfigMapManifestPath state)
      putStrLn ("mountedDemoConfigPath: " <> mountedDemoConfigPath state)
      putStrLn ("publicationStatePath: " <> Config.publicationStatePath paths)
      putStrLn ("modelCacheRoot: " <> modelCacheRoot paths)
      putStrLn ("durableManifestRoot: " <> objectStoreRoot paths </> "manifests")
      putStrLn ("storageHealth: " <> show (length (claims state)) <> " chart-owned claim roots prepared")
      publicationSummaryLines <- publicationStateSummaryLines (Config.publicationStatePath paths)
      putStrLn ("kubernetesNodeCount: " <> show nodeCount)
      putStrLn ("kubernetesPodCount: " <> show podCount)
      putStrLn ("runtimeResultCount: " <> show resultCount)
      putStrLn ("objectStoreObjectCount: " <> show objectCount)
      putStrLn ("modelCacheEntryCount: " <> show cacheEntries)
      putStrLn ("durableManifestCount: " <> show durableManifestCount)
      mapM_ putStrLn publicationSummaryLines
      mapM_
        (\route -> putStrLn ("route: " <> Text.unpack (path route) <> " -> " <> Text.unpack (purpose route)))
        (routes state)

loadClusterState :: Paths -> IO (Maybe ClusterState)
loadClusterState paths = do
  stateExists <- doesFileExist (clusterStatePath paths)
  if stateExists
    then do
      maybeState <- readStateFileMaybe (clusterStatePath paths)
      case maybeState of
        Just state ->
          pure (Just (normalizeClusterStatePaths paths state))
        Nothing -> pure Nothing
    else pure Nothing

runKubectlCompat :: [String] -> IO ()
runKubectlCompat args = do
  paths <- Config.discoverPaths
  maybeState <- loadClusterState paths
  case maybeState of
    Nothing -> putStrLn "No cluster state is available. Run `infernix cluster up` first."
    Just state
      | not (clusterPresent state) -> putStrLn "Cluster is currently absent."
      | otherwise -> do
          ensureOuterContainerKindNetworkAccess paths (clusterRuntimeMode state)
          ensureClusterKubeconfigPresent paths state
          putStr =<< captureCommand Nothing [] "kubectl" (kubeconfigArgs state <> args)

normalizeClusterStatePaths :: Paths -> ClusterState -> ClusterState
normalizeClusterStatePaths paths state =
  state
    { kubeconfigPath = Config.generatedKubeconfigPath paths
    }

ensureClusterKubeconfigPresent :: Paths -> ClusterState -> IO ()
ensureClusterKubeconfigPresent paths state = do
  let kubeconfigFile = kubeconfigPath state
  kubeconfigExists <- doesFileExist kubeconfigFile
  unless kubeconfigExists $
    writeTextFile kubeconfigFile . Text.pack =<< waitForKindKubeconfigOrFail paths (clusterRuntimeMode state)

publicationStateSummaryLines :: FilePath -> IO [String]
publicationStateSummaryLines publicationPath = do
  publicationExists <- doesFileExist publicationPath
  if not publicationExists
    then pure []
    else do
      contents <- readFile publicationPath
      pure
        ( maybe [] (\mode -> ["publicationApiUpstreamMode: " <> mode]) (publicationApiUpstreamMode contents)
            <> publicationUpstreamLines contents
        )

publicationApiUpstreamMode :: String -> Maybe String
publicationApiUpstreamMode contents =
  firstJsonStringField
    "\"apiUpstream\": {"
    "mode"
    (lines contents)

publicationUpstreamLines :: String -> [String]
publicationUpstreamLines contents =
  foldr collect [] (lines contents)
  where
    collect lineValue acc =
      case publicationUpstreamLine lineValue of
        Just renderedLine -> renderedLine : acc
        Nothing -> acc

publicationUpstreamLine :: String -> Maybe String
publicationUpstreamLine lineValue = do
  upstreamId <- jsonStringField "id" lineValue
  healthStatusValue <- jsonStringField "healthStatus" lineValue
  targetSurfaceValue <- jsonStringField "targetSurface" lineValue
  durableBackendStateValue <- jsonStringField "durableBackendState" lineValue
  pure
    ( "publicationUpstream: "
        <> upstreamId
        <> " -> "
        <> healthStatusValue
        <> " via "
        <> targetSurfaceValue
        <> " ("
        <> durableBackendStateValue
        <> ")"
    )

firstJsonStringField :: String -> String -> [String] -> Maybe String
firstJsonStringField marker fieldName =
  go
  where
    go [] = Nothing
    go (lineValue : remaining)
      | marker `List.isInfixOf` lineValue = jsonStringField fieldName lineValue
      | otherwise = go remaining

jsonStringField :: String -> String -> Maybe String
jsonStringField fieldName lineValue =
  case dropWhile (not . List.isPrefixOf marker) (List.tails lineValue) of
    matched : _ -> readQuotedValue (drop (length marker) matched)
    [] -> Nothing
  where
    marker = "\"" <> fieldName <> "\": "

readQuotedValue :: String -> Maybe String
readQuotedValue value =
  case value of
    '"' : rest -> Just (takeWhile (/= '"') rest)
    _ -> Nothing

chooseEdgePort :: Paths -> IO Int
chooseEdgePort paths = do
  maybeStoredPort <- readEdgePortMaybe paths
  case maybeStoredPort of
    Just storedPort
      | storedPort >= 9090 -> do
          storedPortFree <- portIsFree storedPort
          if storedPortFree
            then pure storedPort
            else firstAvailablePort (storedPort + 1)
    _ -> firstAvailablePort 9090

firstAvailablePort :: Int -> IO Int
firstAvailablePort = go
  where
    go candidatePort = do
      candidateFree <- portIsFree candidatePort
      if candidateFree
        then pure candidatePort
        else go (candidatePort + 1)

portIsFree :: Int -> IO Bool
portIsFree candidatePort = do
  bindResult <-
    try $
      Socket.withSocketsDo $
        bracket
          (Socket.socket Socket.AF_INET Socket.Stream Socket.defaultProtocol)
          Socket.close
          ( \socketHandle -> do
              Socket.setSocketOption socketHandle Socket.ReuseAddr 1
              Socket.bind
                socketHandle
                (Socket.SockAddrInet (fromIntegral candidatePort) (Socket.tupleToHostAddress (127, 0, 0, 1)))
          ) ::
      IO (Either IOException ())
  pure (either (const False) (const True) bindResult)

claimDirectory :: Paths -> PersistentClaim -> FilePath
claimDirectory paths persistentClaim =
  kindRoot paths
    </> Text.unpack (namespace persistentClaim)
    </> Text.unpack (release persistentClaim)
    </> Text.unpack (workload persistentClaim)
    </> show (ordinal persistentClaim)
    </> Text.unpack (claim persistentClaim)

ensureClaimDirectoryReady :: Paths -> PersistentClaim -> IO ()
ensureClaimDirectoryReady paths persistentClaim = do
  let directoryPath = claimDirectory paths persistentClaim
  createDirectoryIfMissing True directoryPath
  -- Harbor and MinIO reuse these persisted hostPath trees as non-root users on Linux.
  runCommand Nothing [] "chmod" ["-R", "a+rwX", directoryPath]
  case claimOwner persistentClaim of
    Nothing -> pure ()
    Just owner -> runCommand Nothing [] "chown" ["-R", owner, directoryPath]

claimOwner :: PersistentClaim -> Maybe String
claimOwner claimSpec
  | workload claimSpec == "minio" && claim claimSpec == "data" = Just "1001:1001"
  | "harbor-postgresql" `List.isPrefixOf` Text.unpack (workload claimSpec) = Just "26:26"
  | otherwise = Nothing

ensureKindCluster :: Paths -> RuntimeMode -> Int -> IO (Int, String, Bool)
ensureKindCluster paths runtimeMode requestedPort = do
  clusterExists <- kindClusterExists paths runtimeMode
  (selectedPort, clusterCreated) <-
    if clusterExists
      then do
        maybeExistingPort <- currentKindEdgePort paths runtimeMode
        pure (fromMaybe requestedPort maybeExistingPort, False)
      else do
        createdPort <- createKindCluster paths runtimeMode requestedPort
        pure (createdPort, True)
  kubeconfigResult <- waitForKindKubeconfig paths runtimeMode
  case kubeconfigResult of
    Right kubeconfigContents ->
      pure (selectedPort, normalizeKubeconfigServer (Config.controlPlaneContext paths) kubeconfigContents, clusterCreated)
    Left err
      | clusterExists -> do
          runCommand Nothing [] "kind" ["delete", "cluster", "--name", kindClusterName paths runtimeMode]
          recreatedPort <- createKindCluster paths runtimeMode requestedPort
          recreatedKubeconfig <- waitForKindKubeconfigOrFail paths runtimeMode
          pure (recreatedPort, normalizeKubeconfigServer (Config.controlPlaneContext paths) recreatedKubeconfig, True)
      | otherwise ->
          ioError
            ( userError
                ( "kind cluster became visible before its kubeconfig was readable for "
                    <> kindClusterName paths runtimeMode
                    <> ":\n"
                    <> err
                )
            )

createKindCluster :: Paths -> RuntimeMode -> Int -> IO Int
createKindCluster paths runtimeMode = case runtimeMode of
  LinuxGpu -> createLinuxGpuCluster paths
  _ -> go
  where
    go candidatePort = do
      configPath <- writeGeneratedKindConfig paths runtimeMode candidatePort
      result <-
        tryCommand
          Nothing
          [("KUBECONFIG", Config.generatedKubeconfigPath paths)]
          "kind"
          ["create", "cluster", "--name", kindClusterName paths runtimeMode, "--config", configPath]
      case result of
        Right _ -> pure candidatePort
        Left err
          | "address already in use" `List.isInfixOf` err ->
              go (candidatePort + 1)
          | otherwise ->
              ioError
                (userError ("kind create cluster failed for " <> kindClusterName paths runtimeMode <> ":\n" <> err))

createLinuxGpuCluster :: Paths -> Int -> IO Int
createLinuxGpuCluster paths = go
  where
    go candidatePort = do
      ensureLinuxGpuHostPrerequisites paths
      nvkindBinary <- ensureNvkindBinary paths
      configPath <- writeGeneratedKindConfig paths LinuxGpu candidatePort
      result <-
        tryCommand
          Nothing
          [("KUBECONFIG", Config.generatedKubeconfigPath paths)]
          nvkindBinary
          [ "cluster",
            "create",
            "--name",
            kindClusterName paths LinuxGpu,
            "--config-template",
            configPath,
            "--kubeconfig",
            Config.generatedKubeconfigPath paths,
            "--wait",
            "5m"
          ]
      case result of
        Right _ -> pure candidatePort
        Left err
          | "address already in use" `List.isInfixOf` err ->
              go (candidatePort + 1)
          | linuxGpuNvkindConfigMapBug err -> do
              clusterCreated <- kindClusterExists paths LinuxGpu
              if clusterCreated
                then do
                  putStrLn "nvkind hit its known configmap persistence bug; continuing with repo-owned linux-gpu node setup"
                  completeLinuxGpuNodeBootstrap paths
                  pure candidatePort
                else
                  ioError
                    (userError ("nvkind cluster create failed for " <> kindClusterName paths LinuxGpu <> ":\n" <> err))
          | otherwise ->
              ioError
                (userError ("nvkind cluster create failed for " <> kindClusterName paths LinuxGpu <> ":\n" <> err))

linuxGpuNvkindConfigMapBug :: String -> Bool
linuxGpuNvkindConfigMapBug err =
  "%!w(<nil>)" `List.isInfixOf` err
    && ( "adding config to cluster" `List.isInfixOf` err
           || "writing configmap" `List.isInfixOf` err
       )

completeLinuxGpuNodeBootstrap :: Paths -> IO ()
completeLinuxGpuNodeBootstrap paths = do
  nodeNames <- kindNodeNames paths LinuxGpu
  let workerNodeNames = filter (/= kindControlPlaneNodeName paths LinuxGpu) nodeNames
  mapM_ bootstrapWorkerNode workerNodeNames
  where
    bootstrapWorkerNode nodeName =
      runDockerNodeScript
        nodeName
        ( unlines
            [ "set -euo pipefail",
              "apt-get update",
              "apt-get install -y gpg curl",
              "curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg",
              "curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list",
              "apt-get update",
              "apt-get install -y nvidia-container-toolkit",
              "nvidia-ctk runtime configure --runtime=containerd --config-source=command",
              "systemctl restart containerd",
              "umount -R /proc/driver/nvidia || true",
              "cp /proc/driver/nvidia/params /root/gpu-params",
              "sed -i 's/^ModifyDeviceFiles: 1$/ModifyDeviceFiles: 0/' /root/gpu-params",
              "mount --bind /root/gpu-params /proc/driver/nvidia/params"
            ]
        )

runDockerNodeScript :: String -> String -> IO ()
runDockerNodeScript nodeName script =
  runCommand Nothing [] "docker" ["exec", nodeName, "bash", "-c", script]

data LinuxGpuProbeResults = LinuxGpuProbeResults
  { hostGpuResult :: Either String String,
    dockerRuntimeResult :: Either String String,
    dockerVolumeMountResult :: Either String String
  }

ensureLinuxGpuHostPrerequisites :: Paths -> IO ()
ensureLinuxGpuHostPrerequisites paths = do
  probeResults <- linuxGpuProbeResults
  unless (linuxGpuPreflightSatisfied (Config.controlPlaneContext paths) probeResults) $ do
    let failureReport = linuxGpuHostFailureReport (Config.controlPlaneContext paths) probeResults
    ioError (userError failureReport)

linuxGpuSupportedOnHost :: IO Bool
linuxGpuSupportedOnHost = do
  paths <- Config.discoverPaths
  linuxGpuPreflightSatisfied (Config.controlPlaneContext paths) <$> linuxGpuProbeResults

linuxGpuProbeResults :: IO LinuxGpuProbeResults
linuxGpuProbeResults = do
  hostGpuResult <- tryCommand Nothing [] "nvidia-smi" ["-L"]
  dockerRuntimeResult <- tryCommand Nothing [] "docker" dockerGpuProbeCommand
  defaultRuntimeVolumeMountResult <- tryCommand Nothing [] "docker" dockerVolumeMountProbeCommand
  gpuVolumeMountResult <- tryCommand Nothing [] "docker" dockerGpuVolumeMountProbeCommand
  let dockerVolumeMountResult =
        firstSuccessfulCommand
          defaultRuntimeVolumeMountResult
          gpuVolumeMountResult
  pure
    LinuxGpuProbeResults
      { hostGpuResult = hostGpuResult,
        dockerRuntimeResult = dockerRuntimeResult,
        dockerVolumeMountResult = dockerVolumeMountResult
      }

linuxGpuPreflightSatisfied :: String -> LinuxGpuProbeResults -> Bool
linuxGpuPreflightSatisfied controlPlane probeResults =
  commandSucceeded (dockerRuntimeResult probeResults)
    && commandSucceeded (dockerVolumeMountResult probeResults)
    && (controlPlane == "outer-container" || commandSucceeded (hostGpuResult probeResults))

commandSucceeded :: Either String String -> Bool
commandSucceeded result = case result of
  Right _ -> True
  Left _ -> False

firstSuccessfulCommand :: Either String String -> Either String String -> Either String String
firstSuccessfulCommand firstResult secondResult =
  case firstResult of
    Right _ -> firstResult
    Left firstErr ->
      case secondResult of
        Right secondOutput ->
          Right ("accepted docker --gpus all + worker-device mount preflight: " <> secondOutput)
        Left secondErr ->
          Left
            ( unlines
                [ "default runtime worker-device mount probe failed:",
                  firstErr,
                  "",
                  "docker --gpus all plus worker-device mount probe failed:",
                  secondErr
                ]
            )

linuxGpuHostFailureReport :: String -> LinuxGpuProbeResults -> String
linuxGpuHostFailureReport controlPlane probeResults =
  unlines
    ( [ "linux-gpu requires a real NVIDIA host plus a Docker engine configured for GPU and the NVIDIA volume-mount worker-device contract that nvkind uses for Kind workers.",
        "",
        "Active control-plane context: " <> controlPlane
      ]
        <> requiredPreflightLines
        <> [ "",
             "If Docker is not configured yet, follow the NVIDIA toolkit setup sequence:",
             "  sudo nvidia-ctk runtime configure --runtime=docker --set-as-default --cdi.enabled",
             "  sudo nvidia-ctk config --set accept-nvidia-visible-devices-as-volume-mounts=true --in-place",
             "  sudo systemctl restart docker",
             "",
             "Observed failures:",
             "launcher-local nvidia-smi:",
             renderCommandOutcome (hostGpuResult probeResults),
             "docker --gpus all:",
             renderCommandOutcome (dockerRuntimeResult probeResults),
             "docker worker-device mount preflight:",
             renderCommandOutcome (dockerVolumeMountResult probeResults)
           ]
    )
  where
    requiredPreflightLines
      | controlPlane == "outer-container" =
          [ "",
            "Required preflight commands for the outer-container launcher:",
            "  docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L",
            "  docker run --rm -v /dev/null:/var/run/nvidia-container-devices/all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L",
            "  or docker run --rm --gpus all -v /dev/null:/var/run/nvidia-container-devices/all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L",
            "",
            "The supported NVIDIA host still needs a working `nvidia-smi -L`, but the launcher container may not ship that binary locally."
          ]
      | otherwise =
          [ "",
            "Required preflight commands:",
            "  nvidia-smi -L",
            "  docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L",
            "  docker run --rm -v /dev/null:/var/run/nvidia-container-devices/all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L",
            "  or docker run --rm --gpus all -v /dev/null:/var/run/nvidia-container-devices/all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi -L"
          ]
    renderCommandOutcome result = case result of
      Right output -> output
      Left err -> err

dockerGpuProbeCommand :: [String]
dockerGpuProbeCommand =
  [ "run",
    "--rm",
    "--gpus",
    "all",
    nvidiaCudaContainerImage,
    "nvidia-smi",
    "-L"
  ]

dockerVolumeMountProbeCommand :: [String]
dockerVolumeMountProbeCommand =
  [ "run",
    "--rm",
    "-v",
    "/dev/null:/var/run/nvidia-container-devices/all",
    nvidiaCudaContainerImage,
    "nvidia-smi",
    "-L"
  ]

dockerGpuVolumeMountProbeCommand :: [String]
dockerGpuVolumeMountProbeCommand =
  [ "run",
    "--rm",
    "--gpus",
    "all",
    "-v",
    "/dev/null:/var/run/nvidia-container-devices/all",
    nvidiaCudaContainerImage,
    "nvidia-smi",
    "-L"
  ]

ensureNvkindBinary :: Paths -> IO FilePath
ensureNvkindBinary _paths = do
  maybeSystemNvkind <- findExecutable "nvkind"
  case maybeSystemNvkind of
    Just executablePath -> pure executablePath
    Nothing ->
      ioError
        ( userError
            "nvkind is not available on PATH. The supported linux-gpu control-plane path runs inside the shared linux substrate image, which supplies nvkind."
        )

waitForKindKubeconfig :: Paths -> RuntimeMode -> IO (Either String String)
waitForKindKubeconfig paths runtimeMode = do
  let internalFlag
        | Config.controlPlaneContext paths == "outer-container" = ["--internal"]
        | otherwise = []
      commandArgs = ["get", "kubeconfig", "--name", kindClusterName paths runtimeMode] <> internalFlag
  retryCommandOutput
    30
    1000000
    ("kind " <> unwords commandArgs)
    (tryCommand Nothing [] "kind" commandArgs)

waitForKindKubeconfigOrFail :: Paths -> RuntimeMode -> IO String
waitForKindKubeconfigOrFail paths runtimeMode = do
  result <- waitForKindKubeconfig paths runtimeMode
  case result of
    Right kubeconfigContents -> pure kubeconfigContents
    Left err ->
      ioError
        ( userError
            ( "kind get kubeconfig never became ready for "
                <> kindClusterName paths runtimeMode
                <> ":\n"
                <> err
            )
        )

waitForKubernetesApi :: Paths -> RuntimeMode -> IO ()
waitForKubernetesApi paths runtimeMode = do
  let kubeconfigFile = Config.generatedKubeconfigPath paths
      commandLabel = "kubectl --kubeconfig " <> kubeconfigFile <> " wait --for=condition=Ready node --all"
      args =
        [ "--kubeconfig",
          kubeconfigFile,
          "wait",
          "--for=condition=Ready",
          "node",
          "--all",
          "--timeout=5s"
        ]
  result <- retryCommandOutput 24 500000 commandLabel (tryCommand Nothing [] "kubectl" args)
  case result of
    Right _ -> pure ()
    Left err ->
      ioError
        ( userError
            ( "Kubernetes never reported ready nodes for "
                <> Text.unpack (runtimeModeId runtimeMode)
                <> ":\n"
                <> err
            )
        )

configureRuntimeModeCluster :: Paths -> RuntimeMode -> IO ()
configureRuntimeModeCluster paths runtimeMode =
  case runtimeMode of
    LinuxGpu -> configureLinuxGpuCluster paths runtimeMode
    _ -> pure ()

configureLinuxGpuCluster :: Paths -> RuntimeMode -> IO ()
configureLinuxGpuCluster paths _runtimeMode = do
  putStrLn "configuring linux-gpu runtime support"
  ensureLinuxGpuRuntimeClass paths
  ensureLinuxGpuNodeUserspace paths
  installLinuxGpuDevicePlugin paths
  waitForLinuxGpuResources paths

ensureLinuxGpuNodeUserspace :: Paths -> IO ()
ensureLinuxGpuNodeUserspace paths = do
  nodeNames <- kindNodeNames paths LinuxGpu
  let workerNodeNames = filter (/= kindControlPlaneNodeName paths LinuxGpu) nodeNames
  mapM_ ensureWorkerUserspace workerNodeNames
  where
    ensureWorkerUserspace nodeName = do
      userspaceReady <- linuxGpuNodeUserspaceReady nodeName
      unless userspaceReady $ do
        putStrLn ("syncing linux-gpu NVIDIA userspace into " <> nodeName)
        syncLinuxGpuNodeUserspace nodeName
        userspaceReadyAfterSync <- linuxGpuNodeUserspaceReady nodeName
        unless userspaceReadyAfterSync $
          ioError
            ( userError
                ( "linux-gpu worker never exposed usable NVIDIA userspace after repo-owned sync: "
                    <> nodeName
                )
            )

linuxGpuNodeUserspaceReady :: String -> IO Bool
linuxGpuNodeUserspaceReady nodeName =
  commandSucceeded
    <$> tryCommand
      Nothing
      []
      "docker"
      ["exec", nodeName, "bash", "-lc", "nvidia-container-cli info >/dev/null 2>&1"]

syncLinuxGpuNodeUserspace :: String -> IO ()
syncLinuxGpuNodeUserspace nodeName =
  runCommand
    Nothing
    []
    "bash"
    [ "-lc",
      unlines
        [ "set -euo pipefail",
          "docker run --rm --gpus all "
            <> nvidiaCudaContainerImage
            <> " bash -lc 'tar -C / -cf - usr/lib/x86_64-linux-gnu/libnvidia* usr/lib/x86_64-linux-gnu/libcuda* usr/bin/nvidia* 2>/dev/null' | docker exec -i "
            <> nodeName
            <> " tar -C / -xf -",
          "docker exec " <> nodeName <> " bash -lc 'ldconfig'"
        ]
    ]

ensureLinuxGpuRuntimeClass :: Paths -> IO ()
ensureLinuxGpuRuntimeClass paths =
  runCommandWithInput
    Nothing
    [("KUBECONFIG", Config.generatedKubeconfigPath paths)]
    "kubectl"
    ["apply", "-f", "-"]
    ( unlines
        [ "apiVersion: node.k8s.io/v1",
          "kind: RuntimeClass",
          "metadata:",
          "  name: nvidia",
          "  annotations:",
          "    meta.helm.sh/release-name: infernix",
          "    meta.helm.sh/release-namespace: platform",
          "  labels:",
          "    app.kubernetes.io/managed-by: Helm",
          "handler: nvidia"
        ]
    )

installLinuxGpuDevicePlugin :: Paths -> IO ()
installLinuxGpuDevicePlugin paths = do
  ensureHelmRepositoryDefinitions paths
  runCommandWithInput
    Nothing
    (("KUBECONFIG", Config.generatedKubeconfigPath paths) : Config.helmEnvironment paths)
    "helm"
    [ "upgrade",
      "-i",
      "nvidia-device-plugin",
      "nvdp/nvidia-device-plugin",
      "--namespace",
      "nvidia",
      "--create-namespace",
      "--version",
      nvidiaDevicePluginVersion,
      "--values",
      "-",
      "--wait",
      "--timeout",
      "10m"
    ]
    linuxGpuDevicePluginValues

linuxGpuDevicePluginValues :: String
linuxGpuDevicePluginValues =
  unlines
    [ "fullnameOverride: nvidia-device-plugin-daemonset",
      "runtimeClassName: nvidia",
      "affinity:",
      "  nodeAffinity:",
      "    requiredDuringSchedulingIgnoredDuringExecution:",
      "      nodeSelectorTerms:",
      "        - matchExpressions:",
      "            - key: infernix.runtime/gpu",
      "              operator: In",
      "              values:",
      "                - \"true\""
    ]

waitForLinuxGpuResources :: Paths -> IO ()
waitForLinuxGpuResources paths = go (30 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 =
          ioError (userError "linux-gpu nodes never reported allocatable nvidia.com/gpu resources")
      | otherwise = do
          allocatableValues <- linuxGpuAllocatableValues paths
          if any isPositiveGpuCount allocatableValues
            then pure ()
            else do
              threadDelay 1000000
              go (remainingAttempts - 1)
    isPositiveGpuCount value =
      case readMaybe value of
        Just parsedCount -> parsedCount > (0 :: Int)
        Nothing -> False

linuxGpuAllocatableValues :: Paths -> IO [String]
linuxGpuAllocatableValues paths =
  filter (not . null) . map trim . lines
    <$> captureCommand
      Nothing
      []
      "kubectl"
      [ "--kubeconfig",
        Config.generatedKubeconfigPath paths,
        "get",
        "nodes",
        "-l",
        "infernix.runtime/gpu=true",
        "-o",
        "jsonpath={range .items[*]}{.status.allocatable.nvidia\\.com/gpu}{\"\\n\"}{end}"
      ]

applyBootstrapState :: Paths -> RuntimeMode -> Bool -> [PersistentClaim] -> IO ()
applyBootstrapState paths runtimeMode demoUiEnabledValue claimInventory = do
  now <- getCurrentTime
  let state =
        ClusterState
          { clusterPresent = True,
            edgePort = 0,
            routes = routeInventory demoUiEnabledValue,
            storageClass = "infernix-manual",
            claims = claimInventory,
            clusterRuntimeMode = runtimeMode,
            kubeconfigPath = Config.generatedKubeconfigPath paths,
            generatedDemoConfigPath = Config.generatedDemoConfigPath paths,
            publishedDemoConfigPath = Config.publishedConfigMapCatalogPath paths,
            publishedConfigMapManifestPath = Config.publishedConfigMapManifestPath paths,
            mountedDemoConfigPath = Config.watchedDemoConfigPath,
            updatedAt = now
          }
  applyNamespace state "platform"
  resetStorageClasses state
  applyStorageClass state

applyNamespace :: ClusterState -> String -> IO ()
applyNamespace state namespaceName =
  runCommandWithInput
    Nothing
    []
    "kubectl"
    (kubeconfigArgs state <> ["apply", "-f", "-"])
    ( unlines
        [ "apiVersion: v1",
          "kind: Namespace",
          "metadata:",
          "  name: " <> namespaceName
        ]
    )

resetStorageClasses :: ClusterState -> IO ()
resetStorageClasses state = do
  existingClasses <- lines <$> kubectlOutput state ["get", "storageclass", "-o", "name"]
  mapM_ (\storageClassName -> runCommand Nothing [] "kubectl" (kubeconfigArgs state <> ["delete", storageClassName])) existingClasses

applyStorageClass :: ClusterState -> IO ()
applyStorageClass state =
  runCommandWithInput
    Nothing
    []
    "kubectl"
    (kubeconfigArgs state <> ["apply", "-f", "-"])
    ( unlines
        [ "apiVersion: storage.k8s.io/v1",
          "kind: StorageClass",
          "metadata:",
          "  name: infernix-manual",
          "provisioner: kubernetes.io/no-provisioner",
          "reclaimPolicy: Retain",
          "volumeBindingMode: WaitForFirstConsumer"
        ]
    )

buildClusterImages :: Paths -> RuntimeMode -> IO ()
buildClusterImages paths runtimeMode = do
  let runtimeModeName = Text.unpack (runtimeModeId (clusterWorkloadRuntimeMode runtimeMode))
      imageRef = clusterWorkloadImageRef runtimeMode
      baseImage =
        case clusterWorkloadRuntimeMode runtimeMode of
          LinuxGpu -> "nvidia/cuda:13.2.1-cudnn-runtime-ubuntu24.04"
          _ -> "ubuntu:24.04"
      dockerBuildArgs targetImageRef =
        [ "build",
          "-f",
          "docker/linux-substrate.Dockerfile",
          "--build-arg",
          "BASE_IMAGE=" <> baseImage,
          "--build-arg",
          "RUNTIME_MODE=" <> runtimeModeName,
          "-t",
          targetImageRef,
          "."
        ]
  imagePresent <- maybeCommand ["docker", "image", "inspect", imageRef]
  if Config.controlPlaneContext paths == "outer-container" && imagePresent
    then putStrLn ("reusing baked cluster image for " <> runtimeModeName <> ": " <> imageRef)
    else do
      putStrLn ("building cluster images for " <> runtimeModeName)
      runCommand
        (Just (repoRoot paths))
        [("DOCKER_BUILDKIT", "1")]
        "docker"
        (dockerBuildArgs imageRef)

preloadBootstrapSupportImagesOnKindNodes :: Paths -> RuntimeMode -> FilePath -> IO ()
preloadBootstrapSupportImagesOnKindNodes paths runtimeMode renderedChartPath = do
  imageRefs <- bootstrapSupportImageRefs paths renderedChartPath
  let uniqueImageRefs = List.nub (filter (not . null) (map trim imageRefs))
  unless (null uniqueImageRefs) $ do
    putStrLn "preloading bootstrap-support images on Kind nodes"
    mapM_ ensureLocalImageRef uniqueImageRefs
    runCommand
      Nothing
      []
      "kind"
      (["load", "docker-image", "--name", kindClusterName paths runtimeMode] <> uniqueImageRefs)

bootstrapSupportImageRefs :: Paths -> FilePath -> IO [String]
bootstrapSupportImageRefs _paths renderedChartPath =
  filter isBootstrapSupportImageRef <$> discoverChartImagesFile renderedChartPath
  where
    isBootstrapSupportImageRef imageRef =
      not (null imageRef)
        && imageRef /= "infernix-linux-cpu:local"
        && imageRef /= "infernix-linux-gpu:local"

ensureLocalImageRef :: String -> IO ()
ensureLocalImageRef imageRef = do
  imagePresent <- maybeCommand ["docker", "image", "inspect", imageRef]
  unless imagePresent $
    runCommand Nothing [] "docker" ["pull", imageRef]

publishClusterImages :: Paths -> FilePath -> RuntimeMode -> IO FilePath
publishClusterImages paths renderedChartPath runtimeMode = do
  let outputPath =
        buildRoot paths
          </> ("harbor-image-overrides-" <> Text.unpack (runtimeModeId runtimeMode) <> ".yaml")
  PublishImages.publishChartImagesFile
    PublishImages.defaultHarborPublishOptions
      { PublishImages.harborApiHost = harborApiHost paths runtimeMode
      }
    renderedChartPath
    outputPath
  pure outputPath

preloadHarborBackedImagesOnKindWorker :: Paths -> RuntimeMode -> FilePath -> IO ()
preloadHarborBackedImagesOnKindWorker paths runtimeMode imageOverridesPath = do
  imageRefs <- harborOverlayImageRefs paths imageOverridesPath
  let workerContainer = kindClusterName paths runtimeMode <> "-worker"
      uniqueImageRefs = List.nub (filter shouldPreloadOnWorker (map trim imageRefs))
  unless (null uniqueImageRefs) $ do
    putStrLn "preloading Harbor-backed final images on the Kind worker"
    mapM_ (preloadHarborImageOnNode workerContainer) uniqueImageRefs
  where
    shouldPreloadOnWorker imageRef = not (null imageRef)

harborOverlayImageRefs :: Paths -> FilePath -> IO [String]
harborOverlayImageRefs _paths imageOverridesPath =
  filter (not . null) <$> discoverHarborOverlayImageRefsFile imageOverridesPath

preloadHarborImageOnNode :: String -> String -> IO ()
preloadHarborImageOnNode nodeContainer imageRef = do
  result <-
    retryCommandOutput
      12
      5000000
      ("preload Harbor image " <> imageRef <> " on " <> nodeContainer)
      ( tryCommand
          Nothing
          []
          "docker"
          [ "exec",
            nodeContainer,
            "crictl",
            "--runtime-endpoint",
            "unix:///run/containerd/containerd.sock",
            "pull",
            "--creds",
            harborAdminUser <> ":" <> harborAdminPassword,
            imageRef
          ]
      )
  case result of
    Right _ -> pure ()
    Left err ->
      ioError
        ( userError
            ( "Kind worker could not preload Harbor-backed image "
                <> imageRef
                <> ":\n"
                <> err
            )
        )

maybeCommand :: [String] -> IO Bool
maybeCommand [] = pure False
maybeCommand (command : arguments) =
  maybeRun command arguments

maybeRun :: String -> [String] -> IO Bool
maybeRun command arguments = do
  result <- tryCommand Nothing [] command arguments
  pure
    ( case result of
        Right _ -> True
        Left _ -> False
    )

waitForHarborRegistry :: Paths -> RuntimeMode -> IO ()
waitForHarborRegistry paths runtimeMode = do
  result <- waitForHarborRegistryResult paths runtimeMode 60 5000000
  case result of
    Right _ -> pure ()
    Left err ->
      ioError
        (userError ("Harbor registry never became ready enough for image publication:\n" <> err))

waitForHarborRegistryResult :: Paths -> RuntimeMode -> Int -> Int -> IO (Either String String)
waitForHarborRegistryResult paths runtimeMode attempts delayMicros = do
  let registryApiUrl = "http://" <> harborApiHost paths runtimeMode <> "/api/v2.0/health"
      probeCommand = do
        response <-
          tryCommand
            Nothing
            []
            "curl"
            ["-sS", "-o", "-", "-w", "\n%{http_code}", registryApiUrl]
        pure $
          response >>= \payload ->
            case parseCurlBodyAndStatus payload of
              Just (responseBody, statusCode)
                | statusCode `elem` ["200", "401", "403"]
                    && let loweredBody = map toLower responseBody
                        in "healthy" `List.isInfixOf` loweredBody || "status" `List.isInfixOf` loweredBody ->
                    Right "ready"
              Just (_, statusCode) ->
                Left ("unexpected Harbor registry status " <> statusCode)
              Nothing ->
                Left "failed to parse Harbor registry probe output"
  retryCommandOutput attempts delayMicros "wait for Harbor registry" probeCommand

bootstrapHarborWithRepair :: Paths -> ClusterState -> [FilePath] -> IO ()
bootstrapHarborWithRepair paths state valuesPaths = go (3 :: Int)
  where
    go remainingAttempts = do
      deployResult <- tryDeployChart paths state valuesPaths False
      case deployResult of
        Right _ -> do
          outcome <- waitForHarborRegistryOrDirty paths state
          case outcome of
            HarborRegistryReady -> pure ()
            HarborMigrationDirty
              | remainingAttempts > 1 -> do
                  repairHarborBootstrapState paths state Nothing
                  go (remainingAttempts - 1)
              | otherwise -> do
                  repairHarborBootstrapState paths state Nothing
                  waitForHarborRegistry paths (clusterRuntimeMode state)
            HarborBootstrapTimedOut err
              | remainingAttempts > 1 -> do
                  repairHarborBootstrapState paths state (Just err)
                  go (remainingAttempts - 1)
              | otherwise ->
                  ioError
                    (userError ("Harbor bootstrap never stabilized after retries:\n" <> err))
        Left err
          | remainingAttempts > 1 -> do
              repairHarborBootstrapState paths state (Just err)
              go (remainingAttempts - 1)
          | otherwise ->
              ioError
                (userError ("Harbor bootstrap Helm reconcile failed after retries:\n" <> err))

repairHarborBootstrapState :: Paths -> ClusterState -> Maybe String -> IO ()
repairHarborBootstrapState _paths state _maybeError = do
  cleanupHarborMigrationJob state
  repairHarborDatabaseMigrationState state

cleanupHarborMigrationJob :: ClusterState -> IO ()
cleanupHarborMigrationJob state = do
  _ <-
    tryCommand
      Nothing
      []
      "kubectl"
      ( kubeconfigArgs state
          <> [ "-n",
               "platform",
               "delete",
               "job",
               "migration-job",
               "--ignore-not-found=true",
               "--wait=true"
             ]
      )
  pure ()

waitForHarborRegistryOrDirty :: Paths -> ClusterState -> IO HarborBootstrapOutcome
waitForHarborRegistryOrDirty paths state = go (24 :: Int) ""
  where
    go remainingAttempts lastError = do
      registryResult <- waitForHarborRegistryResult paths (clusterRuntimeMode state) 1 0
      case registryResult of
        Right _ -> pure HarborRegistryReady
        Left err -> do
          dirty <- harborRegistryMigrationDirty state
          if dirty
            then pure HarborMigrationDirty
            else
              if remainingAttempts <= 1
                then pure (HarborBootstrapTimedOut (if null err then lastError else err))
                else do
                  threadDelay 5000000
                  go (remainingAttempts - 1) (if null err then lastError else err)

harborRegistryMigrationDirty :: ClusterState -> IO Bool
harborRegistryMigrationDirty state = do
  let detectionCommand =
        unlines
          [ "set -eu",
            "dirty_count=$(psql -h 127.0.0.1 -U " <> harborPostgresUserName <> " -d registry -Atqc \"SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'schema_migrations') THEN (SELECT COUNT(*)::text FROM schema_migrations WHERE dirty = TRUE) ELSE '0' END\")",
            "if [ \"$dirty_count\" = \"0\" ]; then",
            "  echo clean",
            "else",
            "  echo dirty",
            "fi"
          ]
  result <- runHarborDatabaseCommand state detectionCommand
  case result of
    Right output -> pure ("dirty" `List.isInfixOf` output)
    Left _ -> pure False

repairHarborDatabaseMigrationState :: ClusterState -> IO ()
repairHarborDatabaseMigrationState state = do
  waitForHarborDatabaseReadyWithRepair state
  let repairCommand =
        unlines
          [ "set -eu",
            "dirty_count=$(psql -h 127.0.0.1 -U " <> harborPostgresUserName <> " -d registry -Atqc \"SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'schema_migrations') THEN (SELECT COUNT(*)::text FROM schema_migrations WHERE dirty = TRUE) ELSE '0' END\")",
            "if [ \"$dirty_count\" != \"0\" ]; then",
            "  psql -h 127.0.0.1 -U " <> harborPostgresUserName <> " -d registry -v ON_ERROR_STOP=1 -c \"DROP SCHEMA public CASCADE;\"",
            "  psql -h 127.0.0.1 -U " <> harborPostgresUserName <> " -d registry -v ON_ERROR_STOP=1 -c \"CREATE SCHEMA public AUTHORIZATION " <> harborPostgresUserName <> ";\"",
            "  psql -h 127.0.0.1 -U " <> harborPostgresUserName <> " -d registry -v ON_ERROR_STOP=1 -c \"GRANT ALL ON SCHEMA public TO " <> harborPostgresUserName <> ";\"",
            "fi"
          ]
  _ <- runHarborDatabaseCommand state repairCommand
  pure ()

waitForHarborDatabaseReadyWithRepair :: ClusterState -> IO ()
waitForHarborDatabaseReadyWithRepair state = do
  waitForWorkloadRollout state 900 postgresOperatorDeployment
  waitForHarborPostgresPodsReady state
  waitForWorkloadRollout state 900 ("deployment/" <> harborPostgresClusterName <> "-pgbouncer")
  primaryPodName <- waitForHarborPostgresPrimaryPod state
  runCommand
    Nothing
    []
    "kubectl"
    ( kubeconfigArgs state
        <> [ "-n",
             "platform",
             "wait",
             "--for=condition=Ready",
             "pod/" <> primaryPodName,
             "--timeout",
             "60s"
           ]
    )

waitForHarborPostgresPodsReady :: ClusterState -> IO ()
waitForHarborPostgresPodsReady state = go totalAttempts False ""
  where
    totalAttempts = 72 :: Int

    go remainingAttempts restartIssued lastError = do
      startupPods <- harborPostgresStartupPods state
      let dataPodCount =
            length
              [ ()
                | startupPod <- startupPods,
                  "harbor-postgresql-instance" `List.isPrefixOf` harborPostgresStartupPodName startupPod
              ]
          repoHostCount =
            length
              [ ()
                | startupPod <- startupPods,
                  "harbor-postgresql-repo-host-" `List.isPrefixOf` harborPostgresStartupPodName startupPod
              ]
          allStartupPodsPresent =
            dataPodCount >= harborPostgresExpectedDataClaims
              && repoHostCount >= 1
          attemptsElapsed = totalAttempts - remainingAttempts
          currentError
            | dataPodCount < harborPostgresExpectedDataClaims =
                "expected "
                  <> show harborPostgresExpectedDataClaims
                  <> " Harbor PostgreSQL data pods but found "
                  <> show dataPodCount
            | repoHostCount < 1 = "expected Harbor PostgreSQL pgBackRest repo host pod but found none"
            | all harborPostgresStartupPodReady startupPods = ""
            | otherwise =
                "Harbor PostgreSQL startup pods are not ready: "
                  <> List.intercalate
                    ", "
                    [ harborPostgresStartupPodName startupPod
                        <> " ["
                        <> harborPostgresStartupPodStatus startupPod
                        <> "]"
                      | startupPod <- startupPods,
                        not (harborPostgresStartupPodReady startupPod)
                    ]
      if null currentError
        then pure ()
        else
          if remainingAttempts <= 1
            then
              ioError
                ( userError
                    ( "Harbor PostgreSQL pods never became ready:\n"
                        <> chooseError currentError lastError
                    )
                )
            else do
              restarted <-
                if restartIssued
                  then pure False
                  else
                    restartHarborPostgresStartupPodsIfStuck
                      state
                      allStartupPodsPresent
                      attemptsElapsed
                      startupPods
              threadDelay 5000000
              go (remainingAttempts - 1) (restartIssued || restarted) (chooseError currentError lastError)

    chooseError current previous
      | null current = previous
      | otherwise = current

data HarborPostgresStartupPod = HarborPostgresStartupPod
  { harborPostgresStartupPodName :: String,
    harborPostgresStartupPodReady :: Bool,
    harborPostgresStartupPodStatus :: String
  }

harborPostgresStartupPods :: ClusterState -> IO [HarborPostgresStartupPod]
harborPostgresStartupPods state =
  mapMaybe parseStartupPodLine . lines
    <$> kubectlOutput
      state
      [ "-n",
        "platform",
        "get",
        "pods",
        "--no-headers"
      ]
  where
    parseStartupPodLine lineValue =
      case words lineValue of
        podNameValue : readyValue : statusValue : _
          | isHarborPostgresStartupPodName podNameValue ->
              Just
                HarborPostgresStartupPod
                  { harborPostgresStartupPodName = podNameValue,
                    harborPostgresStartupPodReady = readyColumnSatisfied readyValue,
                    harborPostgresStartupPodStatus = statusValue
                  }
        _ -> Nothing

    isHarborPostgresStartupPodName podNameValue =
      "harbor-postgresql-instance" `List.isPrefixOf` podNameValue
        || "harbor-postgresql-repo-host-" `List.isPrefixOf` podNameValue

    readyColumnSatisfied readyValue =
      case break (== '/') readyValue of
        (readyCountText, '/' : totalCountText) ->
          case (readMaybe readyCountText :: Maybe Int, readMaybe totalCountText :: Maybe Int) of
            (Just readyCount, Just totalCount) -> totalCount > 0 && readyCount == totalCount
            _ -> False
        _ -> False

restartHarborPostgresStartupPodsIfStuck :: ClusterState -> Bool -> Int -> [HarborPostgresStartupPod] -> IO Bool
restartHarborPostgresStartupPodsIfStuck state allStartupPodsPresent attemptsElapsed startupPods =
  if shouldRestart
    then do
      runCommand
        Nothing
        []
        "kubectl"
        (kubeconfigArgs state <> ["-n", "platform", "delete", "pod"] <> unreadyPodNames)
      pure True
    else pure False
  where
    unreadyPodNames =
      [ harborPostgresStartupPodName startupPod
        | startupPod <- startupPods,
          not (harborPostgresStartupPodReady startupPod)
      ]
    shouldRestart =
      not (null unreadyPodNames)
        && allStartupPodsPresent
        && ( any podLooksStuck startupPods
               || attemptsElapsed >= harborPostgresStartupRepairGraceAttempts
           )
    podLooksStuck startupPod =
      not (harborPostgresStartupPodReady startupPod)
        && ( "CrashLoopBackOff" `List.isInfixOf` harborPostgresStartupPodStatus startupPod
               || harborPostgresStartupPodStatus startupPod == "Error"
               || harborPostgresStartupPodStatus startupPod == "Init:Error"
           )

waitForHarborPostgresPrimaryPod :: ClusterState -> IO String
waitForHarborPostgresPrimaryPod state = go (72 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 =
          ioError (userError "Harbor PostgreSQL primary pod never appeared")
      | otherwise = do
          podName <- harborPostgresPrimaryPodNameMaybe state
          if null podName
            then do
              threadDelay 5000000
              go (remainingAttempts - 1)
            else pure podName

harborPostgresPrimaryPodNameMaybe :: ClusterState -> IO String
harborPostgresPrimaryPodNameMaybe state = do
  podNames <-
    filter (not . null) . map trim . lines
      <$> kubectlOutput
        state
        [ "-n",
          "platform",
          "get",
          "pods",
          "-l",
          harborPostgresPrimarySelector,
          "--no-headers",
          "-o",
          "custom-columns=:metadata.name"
        ]
  pure
    ( case podNames of
        podName : _ -> podName
        [] -> ""
    )

runHarborDatabaseCommand :: ClusterState -> String -> IO (Either String String)
runHarborDatabaseCommand state commandText = do
  password <- harborPostgresPassword state
  primaryPodName <- waitForHarborPostgresPrimaryPod state
  tryCommand
    Nothing
    []
    "kubectl"
    ( kubeconfigArgs state
        <> [ "-n",
             "platform",
             "exec",
             primaryPodName,
             "-c",
             "database",
             "--",
             "sh",
             "-lc",
             unlines
               [ "set -eu",
                 "export PGPASSWORD=" <> shellQuote password,
                 commandText
               ]
           ]
    )

harborPostgresPassword :: ClusterState -> IO String
harborPostgresPassword state = do
  encodedPassword <-
    kubectlOutput
      state
      [ "-n",
        "platform",
        "get",
        "secret",
        harborPostgresUserSecretName,
        "-o",
        "jsonpath={.data.password}"
      ]
  case Base64.decode (ByteString8.pack (trim encodedPassword)) of
    Left err -> ioError (userError ("failed to decode Harbor PostgreSQL password: " <> err))
    Right decodedPassword -> pure (ByteString8.unpack decodedPassword)

shellQuote :: String -> String
shellQuote value =
  "'" <> concatMap escapeCharacter value <> "'"
  where
    escapeCharacter '\'' = "'\"'\"'"
    escapeCharacter character = [character]

deployChart :: Paths -> ClusterState -> [FilePath] -> Bool -> IO ()
deployChart paths state valuesPaths waitForRollout = do
  result <- tryDeployChart paths state valuesPaths waitForRollout
  case result of
    Right _ -> pure ()
    Left err ->
      ioError
        (userError ("command failed: helm upgrade --install infernix chart\n" <> err))

tryDeployChart :: Paths -> ClusterState -> [FilePath] -> Bool -> IO (Either String String)
tryDeployChart paths state valuesPaths waitForRollout = do
  ensureHelmDependencies paths
  tryCommand
    (Just (repoRoot paths))
    (Config.helmEnvironment paths)
    "helm"
    ( [ "upgrade",
        "--install",
        "infernix",
        "chart",
        "--namespace",
        "platform",
        "--create-namespace",
        "--kubeconfig",
        kubeconfigPath state
      ]
        <> timeoutArgs
        <> waitArgs
        <> concatMap (\valuesPath -> ["-f", valuesPath]) valuesPaths
    )
  where
    timeoutArgs = ["--timeout", "30m"]
    waitArgs
      | waitForRollout = ["--wait"]
      | otherwise = []

waitForHarborFinalPhaseRollouts :: ClusterState -> IO ()
waitForHarborFinalPhaseRollouts state = do
  putStrLn "waiting for final Harbor rollouts"
  mapM_ (waitForWorkloadRollout state 1200) harborFinalPhaseStatefulSets
  mapM_ (waitForWorkloadRollout state 900) harborFinalPhaseDeployments
  waitForHarborDatabaseReadyWithRepair state

waitForGatewayApiCrds :: ClusterState -> IO ()
waitForGatewayApiCrds state =
  mapM_
    (waitForGatewayApiCrd state)
    [ "gatewayclasses.gateway.networking.k8s.io",
      "gateways.gateway.networking.k8s.io",
      "httproutes.gateway.networking.k8s.io",
      "referencegrants.gateway.networking.k8s.io"
    ]

waitForGatewayApiCrd :: ClusterState -> String -> IO ()
waitForGatewayApiCrd state crdName = do
  result <-
    retryCommandOutput
      60
      1000000
      ("wait for Gateway API CRD " <> crdName)
      ( tryCommand
          Nothing
          []
          "kubectl"
          (kubeconfigArgs state <> ["get", "crd", crdName])
      )
  case result of
    Right _ -> pure ()
    Left err ->
      ioError
        (userError ("Gateway API CRD never became ready: " <> crdName <> "\n" <> err))

waitForFinalPhaseRollouts :: ClusterState -> IO ()
waitForFinalPhaseRollouts state = do
  putStrLn "waiting for final platform rollouts"
  mapM_ (waitForWorkloadRollout state 1200) finalPhaseStatefulSets
  mapM_ (waitForWorkloadRollout state 900) (finalPhaseDeployments state)
  waitForHarborDatabaseReadyWithRepair state

waitForRoutedPublicationSurface :: Paths -> ClusterState -> IO ()
waitForRoutedPublicationSurface paths state = do
  when (clusterStateHasDemoUi state) $ do
    let publicationUrl = clusterEdgeBaseUrl paths state <> "/api/publication"
        expectedRuntimeMode = clusterRuntimeMode state
    result <-
      retryCommandOutput
        120
        1000000
        ("wait for routed publication surface " <> publicationUrl)
        (probePublicationRoute publicationUrl expectedRuntimeMode)
    case result of
      Right _ -> pure ()
      Left err ->
        ioError
          ( userError
              ( "routed publication surface never became ready for "
                  <> Text.unpack (runtimeModeId expectedRuntimeMode)
                  <> ":\n"
                  <> err
              )
          )

waitForWorkloadRollout :: ClusterState -> Int -> String -> IO ()
waitForWorkloadRollout state timeoutSeconds workload =
  runCommand
    Nothing
    []
    "kubectl"
    ( kubeconfigArgs state
        <> [ "-n",
             "platform",
             "rollout",
             "status",
             workload,
             "--timeout",
             show timeoutSeconds <> "s"
           ]
    )

ensureHelmDependencies :: Paths -> IO ()
ensureHelmDependencies paths = do
  dependenciesPresent <- and <$> mapM (doesFileExist . (repoRoot paths </>)) helmDependencyArchives
  if dependenciesPresent
    then pure ()
    else do
      result <- tryCommand (Just (repoRoot paths)) (Config.helmEnvironment paths) "helm" ["dependency", "build", "--skip-refresh", "chart"]
      case result of
        Right _ -> pure ()
        Left err
          | missingHelmRepoMetadata err ->
              do
                ensureHelmRepositoryDefinitions paths
                runCommand (Just (repoRoot paths)) (Config.helmEnvironment paths) "helm" ["dependency", "build", "chart"]
          | otherwise ->
              ioError (userError ("command failed: helm dependency build --skip-refresh chart\n" <> err))
  where
    missingHelmRepoMetadata err =
      "no repository definition" `List.isInfixOf` err
        || "no cached repository" `List.isInfixOf` err

ensureEnvoyGatewayCrdsInstalled :: Paths -> ClusterState -> IO ()
ensureEnvoyGatewayCrdsInstalled paths state = do
  crdPaths <-
    filter ("gateway-helm/crds/" `List.isPrefixOf`) . lines
      <$> captureCommand
        (Just (repoRoot paths))
        []
        "tar"
        ["-tf", envoyGatewayDependencyArchive]
  when (null crdPaths) $
    ioError
      ( userError
          ( "Envoy Gateway dependency archive did not contain any CRDs:\n"
              <> repoRoot paths
              </> envoyGatewayDependencyArchive
          )
      )
  crdDocuments <-
    mapM
      ( \crdPath ->
          captureCommand
            (Just (repoRoot paths))
            []
            "tar"
            ["-xOf", envoyGatewayDependencyArchive, crdPath]
      )
      crdPaths
  -- Helm does not install CRDs that live under dependency charts, so apply the bundle explicitly.
  runCommandWithInput
    Nothing
    []
    "kubectl"
    (kubeconfigArgs state <> ["apply", "--server-side", "--force-conflicts", "-f", "-"])
    (List.intercalate "\n---\n" crdDocuments)

ensureHelmRepositoryDefinitions :: Paths -> IO ()
ensureHelmRepositoryDefinitions paths =
  mapM_
    (\(repoName, repoUrl) -> runCommand (Just (repoRoot paths)) (Config.helmEnvironment paths) "helm" ["repo", "add", "--force-update", repoName, repoUrl])
    helmRepositories

reconcileOperatorManagedPersistentVolumes :: Paths -> ClusterState -> IO ClusterState
reconcileOperatorManagedPersistentVolumes paths state = do
  waitForWorkloadRollout state 900 postgresOperatorDeployment
  operatorClaims <- waitForOperatorManagedPersistentClaims state harborPostgresExpectedOperatorClaims
  mapM_ (ensureClaimDirectoryReady paths) operatorClaims
  unless (kindUsesHostBindMounts paths) $
    prepareKindNodeClaimDirectories paths (clusterRuntimeMode state) operatorClaims
  let updatedState = state {claims = mergePersistentClaims (claims state) operatorClaims}
  reconcilePersistentVolumes updatedState
  waitForPersistentClaimsBound updatedState operatorClaims
  waitForHarborDatabaseReadyWithRepair updatedState
  pure updatedState

refreshPersistentClaims :: ClusterState -> IO ClusterState
refreshPersistentClaims state = do
  operatorClaims <- discoverOperatorManagedPersistentClaims state
  pure (state {claims = mergePersistentClaims (claims state) operatorClaims})

waitForOperatorManagedPersistentClaims :: ClusterState -> Int -> IO [PersistentClaim]
waitForOperatorManagedPersistentClaims state expectedCount = go (72 :: Int) []
  where
    go remainingAttempts previousClaims = do
      currentClaims <- discoverOperatorManagedPersistentClaims state
      if length currentClaims >= expectedCount
        then pure currentClaims
        else
          if remainingAttempts <= 1
            then
              ioError
                ( userError
                    ( "operator-managed PostgreSQL claims never appeared; expected at least "
                        <> show expectedCount
                        <> " but found "
                        <> show (length currentClaims)
                        <> " after retries"
                    )
                )
            else do
              threadDelay 5000000
              go (remainingAttempts - 1) (if null currentClaims then previousClaims else currentClaims)

discoverOperatorManagedPersistentClaims :: ClusterState -> IO [PersistentClaim]
discoverOperatorManagedPersistentClaims state = do
  pvcPayload <-
    kubectlOutput
      state
      [ "get",
        "pvc",
        "-A",
        "-l",
        "postgres-operator.crunchydata.com/cluster",
        "-o",
        "json"
      ]
  claims <-
    case decodeOperatorManagedClaims pvcPayload of
      Left err -> ioError (userError err)
      Right value -> pure value
  pure (normalizeOperatorManagedClaims claims)

normalizeOperatorManagedClaims :: [OperatorManagedClaim] -> [PersistentClaim]
normalizeOperatorManagedClaims rawClaims =
  concatMap normalizeGroup groupedClaims
  where
    sortedClaims = List.sortOn (\claimValue -> (operatorClaimGroupingKey claimValue, operatorClaimPvcName claimValue)) rawClaims
    groupedClaims = List.groupBy sameGroupingKey sortedClaims
    sameGroupingKey left right = operatorClaimGroupingKey left == operatorClaimGroupingKey right
    normalizeGroup = zipWith operatorClaimToPersistentClaim [0 ..]

operatorClaimGroupingKey :: OperatorManagedClaim -> (String, String, String, String)
operatorClaimGroupingKey claimValue =
  ( operatorClaimNamespace claimValue,
    operatorClaimCluster claimValue,
    operatorManagedWorkloadName claimValue,
    operatorManagedClaimName claimValue
  )

operatorManagedWorkloadName :: OperatorManagedClaim -> String
operatorManagedWorkloadName claimValue =
  case operatorClaimRepository claimValue of
    repositoryValue
      | not (null repositoryValue) ->
          operatorClaimCluster claimValue <> "-pgbackrest"
    _ ->
      operatorClaimCluster claimValue
        <> "-"
        <> groupSuffix
  where
    groupSuffix
      | not (null (operatorClaimInstanceSet claimValue)) = operatorClaimInstanceSet claimValue
      | not (null (operatorClaimDataKind claimValue)) = operatorClaimDataKind claimValue
      | otherwise = operatorClaimRole claimValue

operatorManagedClaimName :: OperatorManagedClaim -> String
operatorManagedClaimName claimValue
  | not (null (operatorClaimRepository claimValue)) = operatorClaimRepository claimValue
  | operatorClaimRole claimValue `elem` ["pgdata", "pgwal"] = operatorClaimRole claimValue
  | not (null (operatorClaimDataKind claimValue)) = operatorClaimDataKind claimValue
  | otherwise = operatorClaimRole claimValue

operatorClaimToPersistentClaim :: Int -> OperatorManagedClaim -> PersistentClaim
operatorClaimToPersistentClaim ordinalValue claimValue =
  PersistentClaim
    { namespace = Text.pack (operatorClaimNamespace claimValue),
      release = "infernix",
      workload = Text.pack (operatorManagedWorkloadName claimValue),
      ordinal = ordinalValue,
      claim = Text.pack (operatorManagedClaimName claimValue),
      pvcName = Text.pack (operatorClaimPvcName claimValue),
      requestedStorage = Text.pack (operatorClaimRequestedStorage claimValue)
    }

decodeOperatorManagedClaims :: String -> Either String [OperatorManagedClaim]
decodeOperatorManagedClaims payload =
  case eitherDecode (LazyChar8.pack payload) of
    Left err -> Left ("failed to decode operator-managed PVC payload: " <> err)
    Right rootValue -> parseOperatorManagedClaims rootValue

parseOperatorManagedClaims :: Value -> Either String [OperatorManagedClaim]
parseOperatorManagedClaims rootValue = do
  items <- requireJsonArrayPath ["items"] rootValue
  maybeClaims <- mapM parseOperatorManagedClaimValue items
  pure
    ( List.sortOn
        (\claimValue -> (operatorClaimGroupingKey claimValue, operatorClaimPvcName claimValue))
        (catMaybes maybeClaims)
    )

parseOperatorManagedClaimValue :: Value -> Either String (Maybe OperatorManagedClaim)
parseOperatorManagedClaimValue itemValue = do
  let maybeClusterValue =
        lookupJsonTextPath ["metadata", "labels", "postgres-operator.crunchydata.com/cluster"] itemValue
  case maybeClusterValue of
    Nothing -> pure Nothing
    Just clusterValue -> do
      let repositoryValue =
            fromMaybe
              ""
              (lookupJsonStringPath ["metadata", "labels", "postgres-operator.crunchydata.com/pgbackrest-repo"] itemValue)
          roleValue =
            fromMaybe
              (if null repositoryValue then "" else "pgbackrest")
              (lookupJsonStringPath ["metadata", "labels", "postgres-operator.crunchydata.com/role"] itemValue)
          storageClassValue =
            lookupJsonStringPath ["spec", "storageClassName"] itemValue
      if roleValue == ""
        then pure Nothing
        else
          if storageClassValue /= Just "infernix-manual"
            then Left ("operator-managed PostgreSQL PVC uses unsupported storageClassName " <> show storageClassValue)
            else
              pure $
                Just
                  OperatorManagedClaim
                    { operatorClaimNamespace =
                        fromMaybe "default" (lookupJsonStringPath ["metadata", "namespace"] itemValue),
                      operatorClaimCluster = Text.unpack clusterValue,
                      operatorClaimInstanceSet =
                        fromMaybe "" (lookupJsonStringPath ["metadata", "labels", "postgres-operator.crunchydata.com/instance-set"] itemValue),
                      operatorClaimRole = roleValue,
                      operatorClaimDataKind =
                        fromMaybe
                          (if null repositoryValue then "" else "pgbackrest")
                          (lookupJsonStringPath ["metadata", "labels", "postgres-operator.crunchydata.com/data"] itemValue),
                      operatorClaimInstance =
                        fromMaybe "" (lookupJsonStringPath ["metadata", "labels", "postgres-operator.crunchydata.com/instance"] itemValue),
                      operatorClaimRepository = repositoryValue,
                      operatorClaimPvcName =
                        fromMaybe "" (lookupJsonStringPath ["metadata", "name"] itemValue),
                      operatorClaimRequestedStorage =
                        fromMaybe "5Gi" (lookupJsonStringPath ["spec", "resources", "requests", "storage"] itemValue)
                    }

mergePersistentClaims :: [PersistentClaim] -> [PersistentClaim] -> [PersistentClaim]
mergePersistentClaims existingClaims newClaims =
  List.sortOn
    persistentVolumeClaimName
    (Map.elems (Map.fromList [(persistentVolumeClaimName persistentClaim, persistentClaim) | persistentClaim <- existingClaims <> newClaims]))

probePublicationRoute :: String -> RuntimeMode -> IO (Either String String)
probePublicationRoute publicationUrl expectedRuntimeMode = do
  response <- tryCommand Nothing [] "curl" ["-fsS", publicationUrl]
  pure $
    response >>= \payload ->
      case eitherDecode (LazyChar8.pack payload) of
        Left err -> Left ("invalid publication payload: " <> err)
        Right publicationPayload ->
          if routedPublicationReady expectedRuntimeMode publicationPayload
            then Right "ready"
            else Left "publication route not ready"

routedPublicationReady :: RuntimeMode -> Value -> Bool
routedPublicationReady expectedRuntimeMode publicationPayload =
  lookupJsonStringPath ["daemonLocation"] publicationPayload
    == Just (Text.unpack (expectedDaemonLocationForRuntime expectedRuntimeMode))
    && lookupJsonStringPath ["apiUpstream", "mode"] publicationPayload == Just "cluster-demo"
    && lookupJsonStringPath ["runtimeMode"] publicationPayload == Just (Text.unpack (runtimeModeId expectedRuntimeMode))

requireJsonArrayPath :: [Text.Text] -> Value -> Either String [Value]
requireJsonArrayPath pathSegments value =
  case lookupJsonValuePath pathSegments value of
    Just (Array values) -> Right (Vector.toList values)
    _ -> Left ("missing JSON array at " <> show (map Text.unpack pathSegments))

lookupJsonValuePath :: [Text.Text] -> Value -> Maybe Value
lookupJsonValuePath [] value = Just value
lookupJsonValuePath (segment : remainingSegments) (Object objectValue) =
  KeyMap.lookup (Key.fromText segment) objectValue >>= lookupJsonValuePath remainingSegments
lookupJsonValuePath _ _ = Nothing

lookupJsonTextPath :: [Text.Text] -> Value -> Maybe Text.Text
lookupJsonTextPath pathSegments value =
  case lookupJsonValuePath pathSegments value of
    Just (String textValue) -> Just textValue
    _ -> Nothing

lookupJsonStringPath :: [Text.Text] -> Value -> Maybe String
lookupJsonStringPath pathSegments value =
  Text.unpack <$> lookupJsonTextPath pathSegments value

parseCurlBodyAndStatus :: String -> Maybe (String, String)
parseCurlBodyAndStatus payload =
  case reverse (lines payload) of
    statusCode : reversedBodyLines ->
      Just (unlines (reverse reversedBodyLines), trim statusCode)
    [] -> Nothing

waitForPersistentClaimsBound :: ClusterState -> [PersistentClaim] -> IO ()
waitForPersistentClaimsBound state = mapM_ waitForPersistentClaimBound
  where
    waitForPersistentClaimBound persistentClaim = go (72 :: Int) ""
      where
        claimNamespace = Text.unpack (namespace persistentClaim)
        pvcNameValue = persistentVolumeClaimName persistentClaim
        go remainingAttempts lastPhase = do
          phaseValue <-
            trim
              <$> kubectlOutput
                state
                [ "-n",
                  claimNamespace,
                  "get",
                  "pvc",
                  pvcNameValue,
                  "-o",
                  "jsonpath={.status.phase}"
                ]
          if phaseValue == "Bound"
            then pure ()
            else
              if remainingAttempts <= 1
                then
                  ioError
                    ( userError
                        ( "persistent claim "
                            <> pvcNameValue
                            <> " never reached Bound phase; last phase was "
                            <> choosePhase phaseValue lastPhase
                        )
                    )
                else do
                  threadDelay 5000000
                  go (remainingAttempts - 1) (choosePhase phaseValue lastPhase)
        choosePhase current previous
          | null current = previous
          | otherwise = current

reconcilePersistentVolumes :: ClusterState -> IO ()
reconcilePersistentVolumes state =
  mapM_ applyClaim (claims state)
  where
    applyClaim persistentClaim =
      runCommandWithInput
        Nothing
        []
        "kubectl"
        (kubeconfigArgs state <> ["apply", "-f", "-"])
        (renderPersistentVolume persistentClaim)
    renderPersistentVolume persistentClaim =
      unlines
        [ "apiVersion: v1",
          "kind: PersistentVolume",
          "metadata:",
          "  name: " <> persistentVolumeName persistentClaim,
          "spec:",
          "  capacity:",
          "    storage: " <> Text.unpack (requestedStorage persistentClaim),
          "  accessModes:",
          "    - ReadWriteOnce",
          "  persistentVolumeReclaimPolicy: Retain",
          "  storageClassName: infernix-manual",
          "  volumeMode: Filesystem",
          "  claimRef:",
          "    namespace: " <> Text.unpack (namespace persistentClaim),
          "    name: " <> persistentVolumeClaimName persistentClaim,
          "  hostPath:",
          "    path: " <> nodeMountedClaimPath persistentClaim
        ]

writeGeneratedKindConfig :: Paths -> RuntimeMode -> Int -> IO FilePath
writeGeneratedKindConfig paths runtimeMode edgePortValue = do
  let outputPath =
        buildRoot paths
          </> "kind"
          </> ("cluster-" <> Text.unpack (runtimeModeId runtimeMode) <> ".generated.yaml")
  hostKindRoot <- resolveHostKindRoot paths
  writeRegistryHostsConfig paths runtimeMode
  hostRegistryHostsDirectory <- resolveHostRegistryHostsRoot paths
  writeTextFile outputPath (Text.pack (renderKindConfig paths runtimeMode edgePortValue hostKindRoot hostRegistryHostsDirectory))
  pure outputPath

writeRegistryHostsConfig :: Paths -> RuntimeMode -> IO ()
writeRegistryHostsConfig paths runtimeMode = do
  let registryRoot = repoRoot paths </> ".build" </> "kind" </> "registry"
  writeRegistryNamespace "localhost:30002" (kindClusterName paths runtimeMode <> "-control-plane:30002") registryRoot
  where
    writeRegistryNamespace registryNamespace reachableRegistryHost registryRoot = do
      let registryDirectory = registryRoot </> registryNamespace
          hostsFile = registryDirectory </> "hosts.toml"
          hostsToml =
            unlines
              [ "server = \"http://" <> reachableRegistryHost <> "\"",
                "",
                "[host.\"http://" <> reachableRegistryHost <> "\"]",
                "  capabilities = [\"pull\", \"resolve\"]",
                "  skip_verify = true"
              ]
      createDirectoryIfMissing True registryDirectory
      writeFile hostsFile hostsToml

resolveHostKindRoot :: Paths -> IO FilePath
resolveHostKindRoot paths = do
  maybeOverride <- lookupEnv "INFERNIX_HOST_KIND_ROOT"
  pure (fromMaybe (kindRoot paths) maybeOverride)

resolveHostRegistryHostsRoot :: Paths -> IO FilePath
resolveHostRegistryHostsRoot paths = do
  maybeHostKindRoot <- lookupEnv "INFERNIX_HOST_KIND_ROOT"
  pure
    ( case maybeHostKindRoot of
        Just hostKindRoot ->
          takeDirectory (takeDirectory hostKindRoot)
            </> ".build"
            </> "kind"
            </> "registry"
        Nothing -> repoRoot paths </> ".build" </> "kind" </> "registry"
    )

renderKindConfig :: Paths -> RuntimeMode -> Int -> FilePath -> FilePath -> String
renderKindConfig paths runtimeMode edgePortValue hostKindRoot registryHostsDirectory =
  unlines (preamble <> ["nodes:"] <> nodeBlock "control-plane" initLabels edgePortLines <> nodeBlock "worker" workerLabels [])
  where
    preamble =
      [ "kind: Cluster",
        "apiVersion: kind.x-k8s.io/v1alpha4",
        "name: " <> kindClusterName paths runtimeMode,
        "networking:",
        "  apiServerAddress: \"127.0.0.1\""
      ]
    initLabels = controlPlaneRuntimeModeLabels runtimeMode
    workerLabels = runtimeModeLabels runtimeMode
    edgePortLines =
      [ "    extraPortMappings:",
        "      - containerPort: 30090",
        "        hostPort: " <> show edgePortValue,
        "        listenAddress: \"127.0.0.1\"",
        "        protocol: TCP",
        "      - containerPort: 30002",
        "        hostPort: 30002",
        "        listenAddress: \"127.0.0.1\"",
        "        protocol: TCP",
        "      - containerPort: 30011",
        "        hostPort: 30011",
        "        listenAddress: \"127.0.0.1\"",
        "        protocol: TCP",
        "      - containerPort: 30080",
        "        hostPort: 30080",
        "        listenAddress: \"127.0.0.1\"",
        "        protocol: TCP",
        "      - containerPort: 30650",
        "        hostPort: 30650",
        "        listenAddress: \"127.0.0.1\"",
        "        protocol: TCP"
      ]
    nodeBlock role labels extraLines =
      [ "  - role: " <> role,
        "    image: " <> kindNodeImage
      ]
        <> extraLines
        <> extraMountLines role
        <> [ "    kubeadmConfigPatches:",
             "      - |",
             "        kind: " <> kubeConfiguration role,
             "        nodeRegistration:",
             "          kubeletExtraArgs:",
             "            node-labels: " <> show labels
           ]
    extraMountLines role
      | null nodeExtraMounts = []
      | otherwise = ["    extraMounts:"] <> nodeExtraMounts
      where
        nodeExtraMounts = linuxGpuMounts role <> hostBindMounts
    hostBindMounts
      | kindUsesHostBindMounts paths =
          [ "      - hostPath: " <> hostKindRoot,
            "        containerPath: " <> nodeMountedKindRoot,
            "      - hostPath: " <> registryHostsDirectory,
            "        containerPath: /etc/containerd/certs.d"
          ]
      | otherwise = []
    linuxGpuMounts role = case (runtimeMode, role) of
      (LinuxGpu, "worker") ->
        [ "      - hostPath: /dev/null",
          "        containerPath: /var/run/nvidia-container-devices/all"
        ]
      _ -> []
    kubeConfiguration role
      | role == "control-plane" = "InitConfiguration"
      | otherwise = "JoinConfiguration"

kindUsesHostBindMounts :: Paths -> Bool
kindUsesHostBindMounts paths =
  Config.controlPlaneContext paths /= "outer-container"

prepareKindNodeRuntimePaths :: Paths -> RuntimeMode -> IO ()
prepareKindNodeRuntimePaths paths runtimeMode = do
  let localKindRoot = kindRoot paths
      localRegistryHostsRoot = repoRoot paths </> ".build" </> "kind" </> "registry"
      registryDirectoryInNode = "/etc/containerd/certs.d/localhost:30002"
      registryHostsPath = localRegistryHostsRoot </> "localhost:30002" </> "hosts.toml"
  createDirectoryIfMissing True localKindRoot
  registryHostsContents <- readFile registryHostsPath
  nodeNames <- kindNodeNames paths runtimeMode
  mapM_ (primeNode localKindRoot registryDirectoryInNode registryHostsContents) nodeNames
  where
    primeNode localKindRoot registryDirectoryInNode registryHostsContents nodeName = do
      runCommand Nothing [] "docker" ["exec", nodeName, "mkdir", "-p", nodeMountedKindRoot]
      copyDirectoryContentsToContainer localKindRoot nodeName nodeMountedKindRoot
      runCommand Nothing [] "docker" ["exec", nodeName, "mkdir", "-p", registryDirectoryInNode]
      runCommandWithInput
        Nothing
        []
        "docker"
        ["exec", "-i", nodeName, "cp", "/dev/stdin", registryDirectoryInNode </> "hosts.toml"]
        registryHostsContents

prepareKindNodeClaimDirectories :: Paths -> RuntimeMode -> [PersistentClaim] -> IO ()
prepareKindNodeClaimDirectories paths runtimeMode persistentClaims = do
  nodeNames <- kindNodeNames paths runtimeMode
  mapM_ (prepareOnNode nodeNames) persistentClaims
  where
    prepareOnNode nodeNames persistentClaim =
      mapM_ (prepareOnSingleNode persistentClaim) nodeNames
    prepareOnSingleNode persistentClaim nodeName = do
      let directoryPath = nodeMountedClaimPath persistentClaim
      runCommand Nothing [] "docker" ["exec", nodeName, "mkdir", "-p", directoryPath]
      runCommand Nothing [] "docker" ["exec", nodeName, "chmod", "-R", "a+rwX", directoryPath]
      case claimOwner persistentClaim of
        Nothing -> pure ()
        Just owner -> runCommand Nothing [] "docker" ["exec", nodeName, "chown", "-R", owner, directoryPath]

syncKindNodeRuntimePathsToHost :: Paths -> RuntimeMode -> Maybe ClusterState -> IO ()
syncKindNodeRuntimePathsToHost paths runtimeMode maybeState = do
  let localKindRoot = kindRoot paths
  createDirectoryIfMissing True localKindRoot
  syncedClaims <- case maybeState of
    Just state | not (null (claims state)) -> syncClaimDirectoriesFromOwningNodes paths state
    _ -> pure False
  unless syncedClaims $ do
    nodeNames <- kindNodeNames paths runtimeMode
    mapM_ (\nodeName -> copyDirectoryContentsFromContainer nodeName nodeMountedKindRoot localKindRoot) nodeNames

syncClaimDirectoriesFromOwningNodes :: Paths -> ClusterState -> IO Bool
syncClaimDirectoriesFromOwningNodes paths state = do
  claimNodeBindings <- discoverClaimNodeBindings state
  claimSyncResults <-
    mapM
      (\persistentClaim -> syncClaimDirectoryFromOwningNode paths persistentClaim claimNodeBindings)
      (claims state)
  pure (or claimSyncResults)

discoverClaimNodeBindings :: ClusterState -> IO (Map.Map String String)
discoverClaimNodeBindings state = do
  result <-
    tryCommand
      Nothing
      []
      "kubectl"
      ( kubeconfigArgs state
          <> [ "get",
               "pods",
               "-A",
               "-o",
               claimNodeBindingsTemplate
             ]
      )
  pure
    ( case result of
        Left _ -> Map.empty
        Right output -> Map.fromList (mapMaybe parseClaimNodeBindingLine (lines output))
    )
  where
    claimNodeBindingsTemplate =
      "go-template={{range .items}}{{ $node := .spec.nodeName }}{{range .spec.volumes}}{{if .persistentVolumeClaim}}{{printf \"%s\\t%s\\n\" .persistentVolumeClaim.claimName $node}}{{end}}{{end}}{{end}}"

syncClaimDirectoryFromOwningNode :: Paths -> PersistentClaim -> Map.Map String String -> IO Bool
syncClaimDirectoryFromOwningNode paths persistentClaim claimNodeBindings =
  case Map.lookup (persistentVolumeClaimName persistentClaim) claimNodeBindings of
    Nothing -> pure False
    Just nodeName -> do
      let containerDirectory = nodeMountedClaimPath persistentClaim
          localDirectory = claimDirectory paths persistentClaim
      containerExists <- containerDirectoryExists nodeName containerDirectory
      if containerExists
        then do
          localDirectoryExists <- doesDirectoryExist localDirectory
          when localDirectoryExists (removePathForcibly localDirectory)
          createDirectoryIfMissing True localDirectory
          copyDirectoryContentsFromContainer nodeName containerDirectory localDirectory
          pure True
        else pure False

parseClaimNodeBindingLine :: String -> Maybe (String, String)
parseClaimNodeBindingLine lineValue =
  case splitTabs lineValue of
    [claimNameValue, nodeNameValue]
      | not (null claimNameValue) && not (null nodeNameValue) ->
          Just (claimNameValue, nodeNameValue)
    _ -> Nothing

kindNodeNames :: Paths -> RuntimeMode -> IO [String]
kindNodeNames paths runtimeMode =
  filter (not . null) . lines
    <$> captureCommand Nothing [] "kind" ["get", "nodes", "--name", kindClusterName paths runtimeMode]

copyDirectoryContentsToContainer :: FilePath -> String -> FilePath -> IO ()
copyDirectoryContentsToContainer localDirectory nodeName containerDirectory = do
  hasEntries <- directoryHasEntries localDirectory
  when hasEntries $
    runCommand
      Nothing
      []
      "docker"
      ["cp", localDirectory </> ".", nodeName <> ":" <> containerDirectory]

copyDirectoryContentsFromContainer :: String -> FilePath -> FilePath -> IO ()
copyDirectoryContentsFromContainer nodeName containerDirectory localDirectory = do
  hasEntries <- containerDirectoryHasEntries nodeName containerDirectory
  when hasEntries $
    runCommand
      Nothing
      []
      "docker"
      ["cp", (nodeName <> ":" <> containerDirectory) </> ".", localDirectory]

directoryHasEntries :: FilePath -> IO Bool
directoryHasEntries directory = do
  exists <- doesDirectoryExist directory
  if exists
    then not . null <$> listDirectory directory
    else pure False

containerDirectoryHasEntries :: String -> FilePath -> IO Bool
containerDirectoryHasEntries nodeName directory = do
  result <- tryCommand Nothing [] "docker" ["exec", nodeName, "sh", "-lc", "ls -A " <> directory]
  pure
    ( case result of
        Left _ -> False
        Right output -> not (all (all isSpace) (lines output))
    )

containerDirectoryExists :: String -> FilePath -> IO Bool
containerDirectoryExists nodeName directory = do
  result <- tryCommand Nothing [] "docker" ["exec", nodeName, "sh", "-lc", "test -d " <> directory]
  pure
    ( case result of
        Left _ -> False
        Right _ -> True
    )

runtimeModeLabels :: RuntimeMode -> String
runtimeModeLabels runtimeMode = case runtimeMode of
  AppleSilicon -> "infernix.runtime/mode=apple-silicon"
  LinuxCpu -> "infernix.runtime/mode=linux-cpu"
  LinuxGpu -> "infernix.runtime/mode=linux-gpu,infernix.runtime/gpu=true"

controlPlaneRuntimeModeLabels :: RuntimeMode -> String
controlPlaneRuntimeModeLabels runtimeMode = case runtimeMode of
  LinuxGpu -> "infernix.runtime/mode=linux-gpu"
  _ -> runtimeModeLabels runtimeMode

kindClusterName :: Paths -> RuntimeMode -> String
kindClusterName paths runtimeMode =
  let baseName = "infernix-" <> Text.unpack (runtimeModeId runtimeMode)
   in if dataRoot paths == repoRoot paths </> ".data"
        then baseName
        else baseName <> "-" <> show (clusterNameHash (dataRoot paths))

kindControlPlaneNodeName :: Paths -> RuntimeMode -> String
kindControlPlaneNodeName paths runtimeMode = kindClusterName paths runtimeMode <> "-control-plane"

clusterNameHash :: FilePath -> Int
clusterNameHash =
  (`mod` 100000) . List.foldl' (\acc character -> (acc * 33) + fromEnum character) 5381

currentKindEdgePort :: Paths -> RuntimeMode -> IO (Maybe Int)
currentKindEdgePort paths runtimeMode = do
  result <- tryCommand Nothing [] "docker" ["port", kindClusterName paths runtimeMode <> "-control-plane", "30090/tcp"]
  case result of
    Left _ -> pure Nothing
    Right output ->
      pure (parsePublishedPort output)
  where
    parsePublishedPort output =
      case lines output of
        firstLine : _ ->
          case reverse (takeWhile (/= ':') (reverse firstLine)) of
            [] -> Nothing
            portText -> readMaybe portText
        [] -> Nothing

writeHelmValuesFile :: Paths -> String -> ClusterState -> Lazy.ByteString -> HelmDeployPhase -> IO FilePath
writeHelmValuesFile paths controlPlane state demoConfigPayload deployPhase = do
  engineCommandOverrides <- engineCommandOverridesFromEnvironment
  let outputPath =
        buildRoot paths
          </> ("helm-values-" <> phaseSuffix deployPhase <> "-" <> Text.unpack (runtimeModeId (clusterRuntimeMode state)) <> ".yaml")
  writeFile outputPath (renderHelmValues controlPlane state demoConfigPayload deployPhase engineCommandOverrides)
  pure outputPath
  where
    phaseSuffix phaseValue = case phaseValue of
      WarmupPhase -> "warmup"
      BootstrapPhase -> "bootstrap"
      HarborFinalPhase -> "harbor-final"
      FinalPhase -> "final"

engineCommandOverridesFromEnvironment :: IO [(String, String)]
engineCommandOverridesFromEnvironment = do
  environment <- getEnvironment
  pure
    ( List.sortOn
        fst
        [ (name, value)
          | (name, value) <- environment,
            "INFERNIX_ENGINE_COMMAND_" `List.isPrefixOf` name,
            not (null value)
        ]
    )

renderHelmChart :: Paths -> RuntimeMode -> [FilePath] -> IO FilePath
renderHelmChart paths runtimeMode valuesPaths = do
  let outputPath =
        buildRoot paths
          </> ("helm-rendered-" <> Text.unpack (runtimeModeId runtimeMode) <> ".yaml")
  ensureHelmDependencies paths
  renderedChart <-
    captureCommand
      (Just (repoRoot paths))
      (Config.helmEnvironment paths)
      "helm"
      (["template", "infernix", "chart", "--namespace", "platform"] <> concatMap (\valuesPath -> ["-f", valuesPath]) valuesPaths)
  writeFile outputPath renderedChart
  pure outputPath

discoverPersistentClaims :: Paths -> FilePath -> IO [PersistentClaim]
discoverPersistentClaims _paths =
  discoverChartClaimsFile

renderHelmValues :: String -> ClusterState -> Lazy.ByteString -> HelmDeployPhase -> [(String, String)] -> String
renderHelmValues controlPlane state demoConfigPayload deployPhase engineCommandOverrides =
  unlines
    ( [ "runtimeMode: " <> Text.unpack (runtimeModeId (clusterRuntimeMode state)),
        "controlPlaneContext: " <> show controlPlane,
        "gateway:",
        "  publishedPort: " <> show (edgePort state),
        "  publishedNodePort: 30090",
        "  listenerPort: 80",
        "demoConfig:",
        "  fileName: infernix-substrate.dhall",
        "  catalogPayload: |",
        indentBlock 4 (LazyChar8.unpack demoConfigPayload),
        "demo:",
        "  enabled: " <> yamlBool (clusterStateHasDemoUi state),
        "  replicaCount: " <> show (repoWorkloadReplicaCount deployPhase),
        "  port: 8080",
        "  image:",
        "    repository: " <> clusterWorkloadImageRepository (clusterRuntimeMode state),
        "    tag: local",
        "    pullPolicy: IfNotPresent",
        "publication:",
        "  payloadJson: |",
        indentBlock 4 (renderPublicationState controlPlane state),
        "service:",
        "  replicaCount: " <> show (repoWorkloadReplicaCount deployPhase),
        "  image:",
        "    repository: " <> clusterWorkloadImageRepository (clusterRuntimeMode state),
        "    tag: local",
        "    pullPolicy: IfNotPresent"
      ]
        <> routeHelmValues (clusterStateHasDemoUi state)
        <> unsupportedMonitoringOverrides
        <> serviceEngineAdapterOverrides
        <> phaseChartOverrides deployPhase
        <> bootstrapHarborOverrides deployPhase
    )
  where
    repoWorkloadReplicaCount :: HelmDeployPhase -> Int
    repoWorkloadReplicaCount phaseValue = case phaseValue of
      WarmupPhase -> 0
      BootstrapPhase -> 0
      HarborFinalPhase -> 0
      FinalPhase -> 1
    yamlBool value
      | value = "true"
      | otherwise = "false"
    serviceEngineAdapterOverrides
      | null engineCommandOverrides = []
      | otherwise =
          ["  engineAdapters:"] <> commandOverrideLines
    commandOverrideLines
      | null engineCommandOverrides = []
      | otherwise =
          ["    commandEnv:"]
            <> map (\(name, value) -> "      " <> name <> ": " <> show value) engineCommandOverrides
    unsupportedMonitoringOverrides =
      [ "pulsar:",
        "  victoria-metrics-k8s-stack:",
        "    enabled: false"
      ]
    phaseChartOverrides phaseValue = case phaseValue of
      WarmupPhase -> preFinalChartOverrides False
      BootstrapPhase -> preFinalChartOverrides False
      HarborFinalPhase -> preFinalChartOverrides True
      FinalPhase -> []
    preFinalChartOverrides envoyGatewayEnabled =
      [ "upstreamCharts:",
        "  harbor:",
        "    enabled: true",
        "  postgresOperator:",
        "    enabled: true",
        "  harborpg:",
        "    enabled: true",
        "  minio:",
        "    enabled: true",
        "  pulsar:",
        "    enabled: false",
        "  envoyGateway:",
        "    enabled: " <> yamlBool envoyGatewayEnabled,
        "repoGateway:",
        "  enabled: false",
        "minio:",
        "  console:",
        "    enabled: false"
      ]
    bootstrapHarborOverrides phaseValue = case phaseValue of
      WarmupPhase ->
        [ "harbor:",
          "  enableMigrateHelmHook: false",
          "  nginx:",
          "    replicas: 0",
          "  portal:",
          "    replicas: 0",
          "  core:",
          "    replicas: 0",
          "  jobservice:",
          "    replicas: 0",
          "  registry:",
          "    replicas: 0",
          "  trivy:",
          "    replicas: 0"
        ]
      BootstrapPhase ->
        [ "harbor:",
          "  enableMigrateHelmHook: true",
          "  portal:",
          "    replicas: 1",
          "  core:",
          "    replicas: 1",
          "  jobservice:",
          "    replicas: 1",
          "  registry:",
          "    replicas: 1",
          "  trivy:",
          "    replicas: 1"
        ]
      HarborFinalPhase ->
        [ "harbor:",
          "  enableMigrateHelmHook: true"
        ]
      FinalPhase ->
        [ "harbor:",
          "  enableMigrateHelmHook: true"
        ]

harborApiHost :: Paths -> RuntimeMode -> String
harborApiHost paths runtimeMode
  | Config.controlPlaneContext paths == "outer-container" = kindControlPlaneNodeName paths runtimeMode <> ":30002"
  | otherwise = "127.0.0.1:30002"

harborAdminUser :: String
harborAdminUser = "admin"

harborAdminPassword :: String
harborAdminPassword = "Harbor12345"

persistentVolumeClaimName :: PersistentClaim -> String
persistentVolumeClaimName persistentClaim =
  Text.unpack (pvcName persistentClaim)

persistentVolumeName :: PersistentClaim -> String
persistentVolumeName persistentClaim =
  Text.unpack (namespace persistentClaim)
    <> "-"
    <> Text.unpack (release persistentClaim)
    <> "-"
    <> Text.unpack (workload persistentClaim)
    <> "-"
    <> show (ordinal persistentClaim)
    <> "-"
    <> Text.unpack (claim persistentClaim)

nodeMountedClaimPath :: PersistentClaim -> String
nodeMountedClaimPath persistentClaim =
  nodeMountedKindRoot
    </> Text.unpack (namespace persistentClaim)
    </> Text.unpack (release persistentClaim)
    </> Text.unpack (workload persistentClaim)
    </> show (ordinal persistentClaim)
    </> Text.unpack (claim persistentClaim)

kindClusterExists :: Paths -> RuntimeMode -> IO Bool
kindClusterExists paths runtimeMode = do
  existingClusters <- lines <$> captureCommand Nothing [] "kind" ["get", "clusters"]
  pure (kindClusterName paths runtimeMode `elem` existingClusters)

clusterEdgeBaseUrl :: Paths -> ClusterState -> String
clusterEdgeBaseUrl paths state =
  "http://"
    <> clusterEdgeHost paths state
    <> ":"
    <> show (clusterEdgePort paths state)

clusterEdgeHost :: Paths -> ClusterState -> String
clusterEdgeHost paths state
  | Config.controlPlaneContext paths == "outer-container" = kindControlPlaneNodeName paths (clusterRuntimeMode state)
  | otherwise = "127.0.0.1"

clusterEdgePort :: Paths -> ClusterState -> Int
clusterEdgePort paths state
  | Config.controlPlaneContext paths == "outer-container" = 30090
  | otherwise = edgePort state

kubectlOutput :: ClusterState -> [String] -> IO String
kubectlOutput state args = captureCommand Nothing [] "kubectl" (kubeconfigArgs state <> args)

kubectlLineCountIfReachable :: ClusterState -> [String] -> IO Int
kubectlLineCountIfReachable state args = do
  result <- tryCommand Nothing [] "kubectl" (kubeconfigArgs state <> args)
  pure $
    case result of
      Right output -> countNonEmptyLines output
      Left _ -> 0

kubeconfigArgs :: ClusterState -> [String]
kubeconfigArgs state = ["--kubeconfig", kubeconfigPath state]

clusterWorkloadRuntimeMode :: RuntimeMode -> RuntimeMode
clusterWorkloadRuntimeMode runtimeMode =
  case runtimeMode of
    LinuxGpu -> LinuxGpu
    _ -> LinuxCpu

clusterWorkloadImageRepository :: RuntimeMode -> String
clusterWorkloadImageRepository runtimeMode =
  case clusterWorkloadRuntimeMode runtimeMode of
    LinuxGpu -> "infernix-linux-gpu"
    _ -> "infernix-linux-cpu"

clusterWorkloadImageRef :: RuntimeMode -> String
clusterWorkloadImageRef runtimeMode =
  clusterWorkloadImageRepository runtimeMode <> ":local"

deleteKindCluster :: Paths -> RuntimeMode -> IO ()
deleteKindCluster paths runtimeMode = go (3 :: Int) ""
  where
    commandArgs = ["delete", "cluster", "--name", kindClusterName paths runtimeMode]
    commandLabel = "kind " <> unwords commandArgs

    go remainingAttempts lastError = do
      result <-
        tryCommand
          Nothing
          [("KUBECONFIG", Config.generatedKubeconfigPath paths)]
          "kind"
          commandArgs
      case result of
        Right _ -> pure ()
        Left err -> do
          clusterDeleted <- waitForKindClusterAbsence paths runtimeMode
          if clusterDeleted
            then pure ()
            else
              if remainingAttempts <= 1
                then ioError (userError ("command failed: " <> commandLabel <> "\n" <> chooseError err lastError))
                else do
                  threadDelay 2000000
                  go (remainingAttempts - 1) (chooseError err lastError)

    chooseError current previous
      | null current = previous
      | otherwise = current

waitForKindClusterAbsence :: Paths -> RuntimeMode -> IO Bool
waitForKindClusterAbsence paths runtimeMode = go (30 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 = pure False
      | otherwise = do
          clusterStillExists <- kindClusterExists paths runtimeMode
          if clusterStillExists
            then do
              threadDelay 1000000
              go (remainingAttempts - 1)
            else pure True

runCommand :: Maybe FilePath -> [(String, String)] -> FilePath -> [String] -> IO ()
runCommand maybeWorkingDirectory envOverrides command args = do
  result <- tryCommand maybeWorkingDirectory envOverrides command args
  case result of
    Right _ -> pure ()
    Left err ->
      ioError (userError ("command failed: " <> command <> " " <> unwords args <> "\n" <> err))

runCommandWithInput :: Maybe FilePath -> [(String, String)] -> FilePath -> [String] -> String -> IO ()
runCommandWithInput maybeWorkingDirectory envOverrides command args inputPayload = do
  baseEnv <- getEnvironment
  let mergedEnv = mergeEnvironment baseEnv envOverrides
  (exitCode, _, stderrOutput) <-
    readCreateProcessWithExitCode
      (proc command args)
        { cwd = maybeWorkingDirectory,
          env = Just mergedEnv
        }
      inputPayload
  case exitCode of
    ExitSuccess -> pure ()
    _ ->
      ioError
        (userError ("command failed: " <> command <> " " <> unwords args <> "\n" <> stderrOutput))

tryCommand :: Maybe FilePath -> [(String, String)] -> FilePath -> [String] -> IO (Either String String)
tryCommand maybeWorkingDirectory envOverrides command args = do
  baseEnv <- getEnvironment
  let mergedEnv = mergeEnvironment baseEnv envOverrides
  processResult <-
    try
      ( readCreateProcessWithExitCode
          (proc command args)
            { cwd = maybeWorkingDirectory,
              env = Just mergedEnv
            }
          ""
      ) ::
      IO (Either IOException (ExitCode, String, String))
  case processResult of
    Left err -> pure (Left (show err))
    Right (exitCode, stdoutOutput, stderrOutput) ->
      case exitCode of
        ExitSuccess -> pure (Right stdoutOutput)
        _ -> pure (Left (stdoutOutput <> stderrOutput))

captureCommand :: Maybe FilePath -> [(String, String)] -> FilePath -> [String] -> IO String
captureCommand maybeWorkingDirectory envOverrides command args = do
  result <- tryCommand maybeWorkingDirectory envOverrides command args
  case result of
    Right stdoutOutput -> pure stdoutOutput
    Left err ->
      ioError (userError ("command failed: " <> command <> " " <> unwords args <> "\n" <> err))

mergeEnvironment :: [(String, String)] -> [(String, String)] -> [(String, String)]
mergeEnvironment baseEnv overrides =
  overrides <> filter (\(key, _) -> key `notElem` map fst overrides) baseEnv

normalizeKubeconfigServer :: String -> String -> String
normalizeKubeconfigServer _controlPlane kubeconfigContents = kubeconfigContents

ensureOuterContainerKindNetworkAccess :: Paths -> RuntimeMode -> IO ()
ensureOuterContainerKindNetworkAccess paths _runtimeMode
  | Config.controlPlaneContext paths /= "outer-container" = pure ()
  | otherwise = do
      launcherContainer <- currentLauncherContainerName
      connectResult <- tryCommand Nothing [] "docker" ["network", "connect", "kind", launcherContainer]
      case connectResult of
        Right _ -> pure ()
        Left err
          | "already exists" `List.isInfixOf` err -> pure ()
          | "endpoint with name" `List.isInfixOf` err -> pure ()
          | otherwise ->
              ioError
                ( userError
                    ( "linux outer-container control plane could not join the private Kind network:\n"
                        <> err
                    )
                )

currentLauncherContainerName :: IO String
currentLauncherContainerName = do
  maybeHostname <- lookupEnv "HOSTNAME"
  let envHostname = maybe "" trim maybeHostname
  if not (null envHostname)
    then pure envHostname
    else do
      hostnameOutput <- captureCommand Nothing [] "hostname" []
      let hostnameValue = trim hostnameOutput
      if null hostnameValue
        then ioError (userError "linux outer-container control plane could not determine its container id")
        else pure hostnameValue

indentBlock :: Int -> String -> String
indentBlock indentWidth contents =
  unlines (map (replicate indentWidth ' ' <>) (lines contents))

countLeafEntries :: FilePath -> IO Int
countLeafEntries root = do
  rootExists <- doesDirectoryExist root
  if not rootExists
    then pure 0
    else do
      children <- listDirectory root
      counts <- mapM countChild children
      pure (sum counts)
  where
    countChild childName = do
      let childPath = root </> childName
      isDirectory <- doesDirectoryExist childPath
      if isDirectory
        then countLeafEntries childPath
        else pure 1

countNonEmptyLines :: String -> Int
countNonEmptyLines =
  length . filter (not . all isSpace) . lines

trim :: String -> String
trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace

splitTabs :: String -> [String]
splitTabs [] = [""]
splitTabs value =
  let (prefix, suffix) = break (== '\t') value
   in case suffix of
        [] -> [prefix]
        _ : rest -> prefix : splitTabs rest

retryCommandOutput :: Int -> Int -> String -> IO (Either String String) -> IO (Either String String)
retryCommandOutput attempts delayMicros commandLabel action = go attempts ""
  where
    go remainingAttempts lastError = do
      result <- action
      case result of
        Right stdoutOutput -> pure (Right stdoutOutput)
        Left err
          | remainingAttempts <= 1 ->
              pure (Left (commandLabel <> "\n" <> chooseError err lastError))
          | otherwise -> do
              threadDelay delayMicros
              go (remainingAttempts - 1) (chooseError err lastError)

    chooseError current previous
      | null current = previous
      | otherwise = current
