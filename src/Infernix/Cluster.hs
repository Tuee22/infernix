{-# LANGUAGE OverloadedStrings #-}

module Infernix.Cluster
  ( clusterWorkloadArchitectureForHostArchitecture,
    clusterDown,
    clusterStatus,
    clusterUp,
    kindControlPlaneNodeName,
    linuxGpuNvkindConfigMapBug,
    linuxGpuSupportedOnHost,
    loadClusterState,
    runKubectlCompat,
    writeGeneratedKindConfig,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (IOException, SomeException, bracket, displayException, finally, try)
import Control.Monad (forM_, unless, when)
import Data.Aeson (FromJSON (parseJSON), Value (..), eitherDecode, encode, object, withObject, (.:), (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy qualified as Lazy
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.Char (isSpace, toLower)
import Data.List qualified as List
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe, mapMaybe, maybeToList)
import Data.Text qualified as Text
import Data.Time (UTCTime, diffUTCTime, getCurrentTime)
import Data.Vector qualified as Vector
import Infernix.Cluster.Discover
import Infernix.Cluster.PublishImages qualified as PublishImages
import Infernix.Config (ControlPlaneContext (..), Paths (..), controlPlaneContextId)
import Infernix.Config qualified as Config
import Infernix.DemoConfig (decodeDemoConfigFile, ensureGeneratedDemoConfigFile, materializeHostManifestFile, renderGeneratedDemoConfigPayload)
import Infernix.Engines.AppleSilicon (ensureAppleSiliconRuntimeReady)
import Infernix.HostConfig qualified as HostConfig
import Infernix.HostTools (HostTool (..))
import Infernix.HostTools qualified as HostTools
import Infernix.Models
import Infernix.ProcessMonitor qualified as ProcessMonitor
import Infernix.Routes (routeHelmValues)
import Infernix.Storage
import Infernix.Types
import Infernix.Workflow (platformCommandsAvailable)
import Network.HTTP.Client
  ( Manager,
    RequestBody (RequestBodyLBS),
    defaultManagerSettings,
    httpLbs,
    method,
    newManager,
    parseRequest,
    requestBody,
    requestHeaders,
    responseBody,
    responseStatus,
    urlEncodedBody,
  )
import Network.HTTP.Types.Header (Header)
import Network.HTTP.Types.Status (statusCode)
import Network.HTTP.Types.URI (urlEncode)
import Network.Socket qualified as Socket
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, findExecutable, getTemporaryDirectory, listDirectory, removeFile, removePathForcibly, renameFile)
import System.Exit (ExitCode (..))
import System.FilePath (addTrailingPathSeparator, normalise, takeDirectory, takeFileName, (</>))
import System.Info qualified
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

data ClusterUpInputs = ClusterUpInputs
  { clusterUpControlPlane :: ControlPlaneContext,
    clusterUpRequestedEdgePort :: Int,
    clusterUpRequestedHarborPort :: Int,
    clusterUpRequestedPulsarHttpPort :: Int,
    clusterUpDemoUiEnabled :: Bool,
    clusterUpDemoConfigPath :: FilePath,
    clusterUpKubeconfigPath :: FilePath,
    clusterUpPublishedCatalogPath :: FilePath,
    clusterUpConfigMapManifestPath :: FilePath,
    clusterUpMountedCatalogPath :: FilePath,
    clusterUpPayload :: Lazy.ByteString
  }

-- | Phase 7 Sprint 7.7: the supported three-role daemon split retired
-- the fused @infernix-service@ Deployment. The supported finalisation
-- waits on the new @infernix-coordinator@ + @infernix-engine@ rollouts
-- (see 'finalPhaseDeployments'), so this gate is now @False@ across
-- every substrate. Kept as a one-shot constant so a future re-introduction
-- of a single-role fused deployment can flip it back without rewriting
-- every reference.
clusterServiceEnabled :: RuntimeMode -> Bool
clusterServiceEnabled _runtimeMode = False

helmRepositories :: [(String, String)]
helmRepositories =
  [ ("goharbor", "https://helm.goharbor.io"),
    ("percona", "https://percona.github.io/percona-helm-charts"),
    ("apachepulsar", "https://pulsar.apache.org/charts"),
    ("bitnami", "https://charts.bitnami.com/bitnami"),
    ("nvdp", "https://nvidia.github.io/k8s-device-plugin")
  ]

-- | Phase 3 Sprint 3.11 (2026-05-29): the bitnami minio sub-chart is
-- retired in favor of the hand-authored MinIO StatefulSet under
-- `chart/templates/minio/`, so the Helm dependency closure no longer
-- includes `chart/charts/minio-17.0.21.tgz`.
helmDependencyArchives :: [FilePath]
helmDependencyArchives =
  [ "chart/charts/harbor-1.18.3.tgz",
    "chart/charts/pg-operator-2.9.0.tgz",
    "chart/charts/pg-db-2.9.0.tgz",
    "chart/charts/pulsar-4.5.0.tgz",
    "chart/charts/gateway-helm-v1.7.2.tgz"
  ]

envoyGatewayDependencyArchive :: FilePath
envoyGatewayDependencyArchive = "chart/charts/gateway-helm-v1.7.2.tgz"

helmDependencyArchivesDirectory :: Paths -> FilePath
helmDependencyArchivesDirectory paths = repoRoot paths </> "chart/charts"

-- | Phase 7 Sprint 7.7: the supported daemon-split wait list. The
-- production-shaped @demo_ui = false@ topology brings up only the
-- engine role; the coordinator, Keycloak, and browser demo Deployments
-- are demo-gated. The retired @infernix-service@ Deployment is no
-- longer part of the chart.
finalPhaseDeployments :: ClusterState -> [String]
finalPhaseDeployments state =
  baseDeployments
    <> [deployment | clusterStateHasDemoUi state, deployment <- demoDeployments]
  where
    baseDeployments =
      [ "deployment/infernix-engine"
      ]
        <> map (("deployment/infernix-engine-" <>) . Text.unpack) (perEngineDeploymentNames (clusterRuntimeMode state))
        <> [deployment | clusterServiceEnabled (clusterRuntimeMode state), deployment <- ["deployment/infernix-service"]]
    demoDeployments =
      [ "deployment/infernix-coordinator",
        "deployment/infernix-demo",
        "deployment/infernix-keycloak"
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

harborBootstrapHelmTimeout :: String
harborBootstrapHelmTimeout = "5m"

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

harborPostgresPatroniClusterName :: String
harborPostgresPatroniClusterName = "harbor-postgresql-ha"

harborPostgresExpectedDataClaims :: Int
harborPostgresExpectedDataClaims = 3

harborPostgresStartupRepairGraceAttempts :: Int
harborPostgresStartupRepairGraceAttempts = 18

harborPostgresReplicaReinitGraceAttempts :: Int
harborPostgresReplicaReinitGraceAttempts = harborPostgresStartupRepairGraceAttempts + 6

harborPostgresExpectedOperatorClaims :: Int
harborPostgresExpectedOperatorClaims = 4

-- | Phase 7 Sprint 7.1: keycloak-postgresql is a second Patroni Postgres
-- cluster (operator-managed) that lands in FinalPhase, after Harbor.
-- It contributes 4 operator-managed PVCs (3 data + 1 pgbackrest repo),
-- so the FinalPhase reconcile waits for the combined Harbor + Keycloak
-- total before declaring the PV side ready.
keycloakPostgresExpectedOperatorClaims :: Int
keycloakPostgresExpectedOperatorClaims = 4

finalPhaseExpectedOperatorClaims :: Int
finalPhaseExpectedOperatorClaims =
  harborPostgresExpectedOperatorClaims + keycloakPostgresExpectedOperatorClaims

harborPostgresPrimarySelector :: String
harborPostgresPrimarySelector =
  "postgres-operator.crunchydata.com/cluster="
    <> harborPostgresClusterName
    <> ",postgres-operator.crunchydata.com/role=primary"

harborPostgresUserName :: String
harborPostgresUserName = "harbor"

harborPostgresUserSecretName :: String
harborPostgresUserSecretName = "infernix-harbor-db-user"

harborPostgresSchemaName :: String
harborPostgresSchemaName = "harbor"

keycloakRealmName :: String
keycloakRealmName = "infernix"

keycloakSpaClientId :: String
keycloakSpaClientId = "infernix-spa"

keycloakLoginThemeName :: String
keycloakLoginThemeName = "infernix"

keycloakAdminSecretName :: String
keycloakAdminSecretName = "infernix-keycloak-admin"

data KeycloakAdminCredentials = KeycloakAdminCredentials
  { keycloakAdminUsername :: String,
    keycloakAdminPassword :: String
  }

newtype KeycloakAdminToken = KeycloakAdminToken
  { keycloakAdminAccessToken :: Text.Text
  }

instance FromJSON KeycloakAdminToken where
  parseJSON = withObject "KeycloakAdminToken" $ \value ->
    KeycloakAdminToken <$> value .: "access_token"

pulsarZookeeperPodNames :: [String]
pulsarZookeeperPodNames =
  [ "infernix-infernix-pulsar-zookeeper-0",
    "infernix-infernix-pulsar-zookeeper-1",
    "infernix-infernix-pulsar-zookeeper-2"
  ]

pulsarBootstrapDirtyLogMarkers :: [String]
pulsarBootstrapDirtyLogMarkers =
  [ "The current epoch",
    "Got zxid",
    "older than the last zxid",
    "Unable to load database on disk"
  ]

clusterStateHasDemoUi :: ClusterState -> Bool
clusterStateHasDemoUi state =
  any ((`elem` ["/", "/api"]) . path) (routes state)

persistClusterState :: Paths -> ClusterState -> IO ()
persistClusterState paths state = do
  let publicationPath = Config.publicationStatePath paths
  createDirectoryIfMissing True (takeDirectory publicationPath)
  writeStateFile (clusterStatePath paths) state
  writeFile publicationPath (renderPublicationState (Config.controlPlaneContext paths) state)

setLifecycleProgress :: Paths -> ClusterState -> String -> String -> String -> Bool -> IO ClusterState
setLifecycleProgress paths state action phase detail emitMarker = do
  now <- getCurrentTime
  let updatedState =
        state
          { lifecycleProgress =
              Just
                LifecycleProgress
                  { lifecycleAction = action,
                    lifecyclePhase = phase,
                    lifecycleDetail = detail,
                    lifecycleHeartbeatAt = now
                  },
            updatedAt = now
          }
  persistClusterState paths updatedState
  when emitMarker $
    putStrLn (action <> " phase: " <> phase <> " - " <> detail)
  pure updatedState

startLifecyclePhase :: Paths -> ClusterState -> String -> String -> String -> IO ClusterState
startLifecyclePhase paths state action phase detail =
  setLifecycleProgress paths state action phase detail True

touchLifecycleProgress :: Paths -> ClusterState -> IO ()
touchLifecycleProgress paths state =
  case lifecycleProgress state of
    Nothing -> pure ()
    Just progress -> do
      _ <-
        setLifecycleProgress
          paths
          state
          (lifecycleAction progress)
          (lifecyclePhase progress)
          (lifecycleDetail progress)
          False
      pure ()

clearLifecycleProgress :: Paths -> ClusterState -> IO ClusterState
clearLifecycleProgress paths state = do
  now <- getCurrentTime
  let updatedState =
        state
          { lifecycleProgress = Nothing,
            updatedAt = now
          }
  persistClusterState paths updatedState
  pure updatedState

lifecycleMonitorLabel :: ClusterState -> String
lifecycleMonitorLabel state =
  case lifecycleProgress state of
    Just progress ->
      lifecycleAction progress <> " phase " <> lifecyclePhase progress <> ": " <> lifecycleDetail progress
    Nothing -> "long-running lifecycle command"

lifecycleCommandMonitor :: Paths -> ClusterState -> ProcessMonitor.CommandMonitor
lifecycleCommandMonitor paths state =
  ProcessMonitor.CommandMonitor
    { ProcessMonitor.monitorLabel = lifecycleMonitorLabel state,
      ProcessMonitor.monitorIntervalMicros = 30000000,
      ProcessMonitor.monitorHeartbeat = \_elapsedSeconds -> touchLifecycleProgress paths state
    }

runCommandMonitored :: Paths -> ClusterState -> Maybe FilePath -> [(String, String)] -> FilePath -> [String] -> IO ()
runCommandMonitored paths state maybeWorkingDirectory envOverrides command args = do
  let resolvedCommand = resolveClusterCommandWithPaths paths command
  result <-
    ProcessMonitor.tryCommandMonitored
      maybeWorkingDirectory
      envOverrides
      resolvedCommand
      args
      (Just (lifecycleCommandMonitor paths state))
  case result of
    Right _ -> pure ()
    Left err ->
      ioError (userError ("command failed: " <> command <> " " <> unwords args <> "\n" <> err))

clusterUp :: Maybe RuntimeMode -> IO ()
clusterUp maybeRuntimeMode = do
  paths <- discoverClusterCommandPaths
  Config.ensureRepoLayout paths
  runtimeMode <- resolveClusterRuntimeMode paths maybeRuntimeMode
  Config.ensureSupportedRuntimeModeForExecutionContext paths runtimeMode
  when (runtimeMode == AppleSilicon) (ensureAppleSiliconRuntimeReady paths)
  commandsAvailable <- platformCommandsAvailable
  unless commandsAvailable $
    ioError
      ( userError
          "cluster up requires Docker, Helm, Kind, and kubectl on the supported path; simulation is no longer available."
      )
  clusterUpWithPulsarBootstrapRepair paths runtimeMode

clusterUpWithPulsarBootstrapRepair :: Paths -> RuntimeMode -> IO ()
clusterUpWithPulsarBootstrapRepair paths runtimeMode = go False
  where
    go repairAttempted = do
      repairAttempted' <-
        if repairAttempted
          then pure True
          else do
            repaired <- repairInterruptedDirtyPulsarBootstrapState
            pure (repairAttempted || repaired)
      result <- try (clusterUpWithPlatform paths runtimeMode)
      case result of
        Right _ -> pure ()
        Left err
          | repairAttempted' -> ioError err
          | otherwise -> do
              maybeRepairReason <- detectDirtyPulsarBootstrapState paths runtimeMode
              case maybeRepairReason of
                Nothing -> ioError err
                Just repairReason -> do
                  putStrLn ("cluster up detected inconsistent retained Pulsar state: " <> repairReason)
                  clusterDown (Just runtimeMode)
                  resetPulsarClaimDirectories paths runtimeMode
                  putStrLn "retrying cluster up after resetting retained Pulsar claim roots"
                  go True
    repairInterruptedDirtyPulsarBootstrapState = do
      maybeState <- loadClusterState paths
      case matchingClusterState runtimeMode maybeState >>= lifecycleProgress of
        Just progress
          | lifecycleAction progress == "cluster-up" -> do
              maybeRepairReason <- detectDirtyPulsarBootstrapState paths runtimeMode
              case maybeRepairReason of
                Nothing -> pure False
                Just repairReason -> do
                  putStrLn ("cluster up detected interrupted inconsistent retained Pulsar state: " <> repairReason)
                  clusterDown (Just runtimeMode)
                  resetPulsarClaimDirectories paths runtimeMode
                  putStrLn "retrying cluster up after resetting retained Pulsar claim roots"
                  pure True
        _ -> pure False

clusterUpWithPlatform :: Paths -> RuntimeMode -> IO ()
clusterUpWithPlatform paths runtimeMode = do
  inputs <- prepareClusterUpInputs paths runtimeMode
  claimDiscoveryTime <- getCurrentTime
  let provisionalState0 =
        clusterUpState
          inputs
          runtimeMode
          False
          (clusterUpRequestedEdgePort inputs)
          (clusterUpRequestedHarborPort inputs)
          (routeInventory (clusterUpDemoUiEnabled inputs))
          (platformClaimsForRuntime runtimeMode)
          claimDiscoveryTime
  provisionalState <-
    startLifecyclePhase
      paths
      provisionalState0
      "cluster-up"
      "discover-persistent-claims"
      "rendering Helm inputs and discovering durable claim roots"
  claimDiscoveryValuesPath <- writeHelmValuesFile paths (clusterUpControlPlane inputs) provisionalState (clusterUpPayload inputs) FinalPhase
  claimDiscoveryRenderedChartPath <- renderHelmChart paths runtimeMode [claimDiscoveryValuesPath]
  discoveredClaims <- discoverPersistentClaims paths claimDiscoveryRenderedChartPath
  discoveredRoutes <- discoverChartRoutesFile claimDiscoveryRenderedChartPath
  scrubNonRetainedClusterDirectories paths runtimeMode
  mapM_ (ensureClaimDirectoryReady paths runtimeMode) discoveredClaims
  clusterPrepareState <-
    startLifecyclePhase
      paths
      provisionalState
      "cluster-up"
      "prepare-kind-cluster"
      "creating or reusing the Kind cluster and preparing retained runtime data"
  (edgePortValue, harborPortValue, pulsarHttpPortValue, kubeconfigContents, clusterCreated) <-
    ensureKindCluster paths runtimeMode (clusterUpRequestedEdgePort inputs) (clusterUpRequestedHarborPort inputs) (clusterUpRequestedPulsarHttpPort inputs)
  writeRegistryHostsConfig paths runtimeMode harborPortValue
  primeKindNodeRegistryHosts paths runtimeMode harborPortValue
  usesHostBindMounts <- kindUsesHostBindMounts paths runtimeMode
  when (clusterCreated && not usesHostBindMounts) $
    prepareKindNodeRuntimePaths paths clusterPrepareState runtimeMode
  unless usesHostBindMounts $
    prepareKindNodeClaimDirectories paths clusterPrepareState runtimeMode discoveredClaims
  writeFile (edgePortPath paths) (show edgePortValue)
  writeFile (harborPortPath paths) (show harborPortValue)
  writeFile (pulsarHttpPortPath paths) (show pulsarHttpPortValue)
  publishGeneratedKubeconfig paths (Text.pack kubeconfigContents)
  activeStateTime <- getCurrentTime
  let activeState0 =
        clusterUpState
          inputs
          runtimeMode
          True
          edgePortValue
          harborPortValue
          discoveredRoutes
          discoveredClaims
          activeStateTime
  activeState <-
    startLifecyclePhase
      paths
      activeState0
      "cluster-up"
      "wait-for-kubernetes-api"
      "waiting for the repo-local Kind kubeconfig and Kubernetes API to become reachable"
  ensureOuterContainerKindNetworkAccess paths runtimeMode
  waitForKubernetesApi paths runtimeMode
  configureRuntimeModeCluster paths runtimeMode
  now <- getCurrentTime
  let seedState = activeState {claims = platformClaimsForRuntime runtimeMode, updatedAt = now}
  warmupValuesPath <- writeHelmValuesFile paths (clusterUpControlPlane inputs) seedState (clusterUpPayload inputs) WarmupPhase
  bootstrapValuesPath <- writeHelmValuesFile paths (clusterUpControlPlane inputs) seedState (clusterUpPayload inputs) BootstrapPhase
  harborFinalValuesPath <- writeHelmValuesFile paths (clusterUpControlPlane inputs) seedState (clusterUpPayload inputs) HarborFinalPhase
  finalValuesPath <- writeHelmValuesFile paths (clusterUpControlPlane inputs) seedState (clusterUpPayload inputs) FinalPhase
  renderedChartPath <- renderHelmChart paths runtimeMode [finalValuesPath]
  when clusterCreated $
    putStrLn "cluster-up phase: preload-bootstrap-images - skipped broad pre-Harbor support-image preload; Harbor-first publication owns remaining images"
  preloadHostCachedWarmupImagesOnKindWorker paths seedState runtimeMode
  applyBootstrapState paths runtimeMode (clusterUpDemoUiEnabled inputs) discoveredClaims
  let initialState = seedState {claims = discoveredClaims}
  initialStateWithDependencies <-
    startLifecyclePhase
      paths
      initialState
      "cluster-up"
      "ensure-helm-dependencies"
      "reusing or hydrating the top-level Helm dependency archive cache"
  ensureHelmDependencies paths
  storageReconcileState <-
    startLifecyclePhase
      paths
      initialStateWithDependencies
      "cluster-up"
      "reconcile-storage-and-warmup"
      "installing Gateway prerequisites, reconciling persistent volumes, and applying the warmup chart"
  ensureEnvoyGatewayCrdsInstalled paths storageReconcileState
  reconcilePersistentVolumes storageReconcileState
  deployChart paths storageReconcileState [warmupValuesPath] False
  state0 <- reconcileOperatorManagedPersistentVolumes paths storageReconcileState
  persistClusterState paths state0
  harborBootstrapState <-
    startLifecyclePhase
      paths
      state0
      "cluster-up"
      "bootstrap-harbor"
      "repairing Harbor bootstrap state and waiting for the Harbor registry to become ready"
  repairHarborDatabaseMigrationState harborBootstrapState
  bootstrapHarborWithRepair paths harborBootstrapState [bootstrapValuesPath]
  buildState <-
    startLifecyclePhase
      paths
      harborBootstrapState
      "cluster-up"
      "build-cluster-images"
      ("docker build " <> clusterWorkloadImageRef runtimeMode)
  buildClusterImages paths buildState runtimeMode
  imageOverridesPath <- publishClusterImages paths buildState renderedChartPath runtimeMode
  harborFinalState <-
    startLifecyclePhase
      paths
      buildState
      "cluster-up"
      "deploy-harbor-final-phase"
      "deploying Harbor-backed platform workloads and waiting for Harbor plus Gateway rollouts"
  preloadHarborBackedImagesOnKindWorker paths harborFinalState runtimeMode imageOverridesPath
  deployChart paths harborFinalState [harborFinalValuesPath, imageOverridesPath] True
  waitForHarborFinalPhaseRollouts harborFinalState
  waitForGatewayApiCrds harborFinalState
  finalDeployState <-
    startLifecyclePhase
      paths
      harborFinalState
      "cluster-up"
      "deploy-final-phase"
      "deploying the final chart and waiting for routed workloads to become ready"
  -- Phase 7 Sprint 7.1: when the demo surface is enabled, the
  -- FinalPhase chart deploy applies the @keycloak-postgresql@
  -- PerconaPGCluster CR; the Percona operator then creates 4 PVCs
  -- (3 data + 1 pgbackrest repo) on the supported @infernix-manual@
  -- storage class, which has no provisioner. The explicit final-phase
  -- PV reconcile creates matching PVs and waits for them to bind before
  -- rollout checks observe Keycloak. For @demo_ui = false@, Keycloak
  -- and its Patroni cluster are absent, so this extra reconcile is
  -- skipped.
  deployChart paths finalDeployState [finalValuesPath, imageOverridesPath] False
  finalDeployStateWithOperatorClaims <-
    if clusterStateHasDemoUi finalDeployState
      then reconcileFinalPhaseOperatorManagedPersistentVolumes paths finalDeployState
      else pure finalDeployState
  waitForFinalPhaseRollouts finalDeployStateWithOperatorClaims
  postKeycloakRealmState <-
    if clusterStateHasDemoUi finalDeployStateWithOperatorClaims
      then do
        keycloakRealmState <-
          startLifecyclePhase
            paths
            finalDeployStateWithOperatorClaims
            "cluster-up"
            "reconcile-keycloak-realm"
            "reconciling the demo Keycloak realm and browser redirect URIs"
        reconcileKeycloakRealmConfiguration paths keycloakRealmState
        pure keycloakRealmState
      else pure finalDeployStateWithOperatorClaims
  routedPublicationState <-
    startLifecyclePhase
      paths
      postKeycloakRealmState
      "cluster-up"
      "wait-for-routed-publication"
      "probing the routed publication surface on the chosen edge before declaring success"
  waitForRoutedPublicationSurface paths routedPublicationState
  _ <- refreshPersistentClaims routedPublicationState >>= clearLifecycleProgress paths
  putStrLn "cluster up complete"
  putStrLn ("controlPlaneContext: " <> controlPlaneContextId (clusterUpControlPlane inputs))
  putStrLn ("runtimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("edgePort: " <> show edgePortValue)
  putStrLn ("harborPort: " <> show harborPortValue)
  putStrLn ("generatedDemoConfigPath: " <> clusterUpDemoConfigPath inputs)
  putStrLn ("publishedDemoConfigPath: " <> clusterUpPublishedCatalogPath inputs)
  putStrLn ("mountedDemoConfigPath: " <> clusterUpMountedCatalogPath inputs)

prepareClusterUpInputs :: Paths -> RuntimeMode -> IO ClusterUpInputs
prepareClusterUpInputs paths runtimeMode = do
  requestedPort <- chooseEdgePort paths
  requestedHarborPort <- chooseHarborPort paths
  requestedPulsarHttpPort <- choosePulsarHttpPort paths
  generatedConfigPath <- requireGeneratedDemoConfigFile paths runtimeMode
  generatedConfig <- decodeDemoConfigFile generatedConfigPath
  let demoUiEnabledValue = demoUiEnabled generatedConfig
      publishedCatalogPath = Config.publishedConfigMapCatalogPath paths
      configMapManifestPath = Config.publishedConfigMapManifestPath paths
      publicationPath = Config.publicationStatePath paths
      mountedCatalogPath = Config.watchedDemoConfigPath
      payload = Lazy.fromStrict (renderGeneratedDemoConfigPayload paths runtimeMode demoUiEnabledValue Coordinator)
  createDirectoryIfMissing True (buildRoot paths)
  createDirectoryIfMissing True (takeDirectory publishedCatalogPath)
  createDirectoryIfMissing True (takeDirectory configMapManifestPath)
  createDirectoryIfMissing True (takeDirectory publicationPath)
  Lazy.writeFile publishedCatalogPath payload
  writeFile configMapManifestPath (renderConfigMapManifest payload)
  pure
    ClusterUpInputs
      { clusterUpControlPlane = Config.controlPlaneContext paths,
        clusterUpRequestedEdgePort = requestedPort,
        clusterUpRequestedHarborPort = requestedHarborPort,
        clusterUpRequestedPulsarHttpPort = requestedPulsarHttpPort,
        clusterUpDemoUiEnabled = demoUiEnabledValue,
        clusterUpDemoConfigPath = generatedConfigPath,
        clusterUpKubeconfigPath = Config.generatedKubeconfigPath paths,
        clusterUpPublishedCatalogPath = publishedCatalogPath,
        clusterUpConfigMapManifestPath = configMapManifestPath,
        clusterUpMountedCatalogPath = mountedCatalogPath,
        clusterUpPayload = payload
      }

clusterUpState :: ClusterUpInputs -> RuntimeMode -> Bool -> Int -> Int -> [RouteInfo] -> [PersistentClaim] -> UTCTime -> ClusterState
clusterUpState inputs runtimeMode clusterPresentValue edgePortValue harborPortValue routesValue claimsValue updatedAtValue =
  ClusterState
    { clusterPresent = clusterPresentValue,
      edgePort = edgePortValue,
      harborPort = harborPortValue,
      routes = routesValue,
      storageClass = "infernix-manual",
      claims = claimsValue,
      clusterRuntimeMode = runtimeMode,
      kubeconfigPath = clusterUpKubeconfigPath inputs,
      generatedDemoConfigPath = clusterUpDemoConfigPath inputs,
      publishedDemoConfigPath = clusterUpPublishedCatalogPath inputs,
      publishedConfigMapManifestPath = clusterUpConfigMapManifestPath inputs,
      mountedDemoConfigPath = clusterUpMountedCatalogPath inputs,
      lifecycleProgress = Nothing,
      updatedAt = updatedAtValue
    }

requireGeneratedDemoConfigFile :: Paths -> RuntimeMode -> IO FilePath
requireGeneratedDemoConfigFile paths expectedRuntimeMode = do
  let filePath = Config.generatedDemoConfigPath paths
  _ <- ensureGeneratedDemoConfigFile paths expectedRuntimeMode True
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

resolveCommandRuntimeMode :: Paths -> Maybe RuntimeMode -> Maybe ClusterState -> IO RuntimeMode
resolveCommandRuntimeMode _ (Just runtimeMode) _ = pure runtimeMode
resolveCommandRuntimeMode paths Nothing maybeState = do
  let substratePath = Config.generatedDemoConfigPath paths
  substrateExists <- doesFileExist substratePath
  if substrateExists
    then configRuntimeMode <$> decodeDemoConfigFile substratePath
    else maybe (Config.targetRuntimeModeForExecutionContext paths) (pure . clusterRuntimeMode) maybeState

resolveClusterRuntimeMode :: Paths -> Maybe RuntimeMode -> IO RuntimeMode
resolveClusterRuntimeMode _ (Just runtimeMode) = pure runtimeMode
resolveClusterRuntimeMode paths Nothing = Config.targetRuntimeModeForExecutionContext paths

discoverClusterCommandPaths :: IO Paths
discoverClusterCommandPaths = do
  paths <- Config.discoverPaths
  Config.ensureRepoLayout paths
  case Config.controlPlaneContext paths of
    HostNative -> do
      _ <- materializeHostManifestFile paths
      Config.discoverPaths
    OuterContainer -> pure paths

matchingClusterState :: RuntimeMode -> Maybe ClusterState -> Maybe ClusterState
matchingClusterState runtimeMode maybeState =
  case maybeState of
    Just state
      | clusterRuntimeMode state == runtimeMode -> Just state
    _ -> Nothing

clusterDown :: Maybe RuntimeMode -> IO ()
clusterDown maybeRuntimeMode = do
  paths <- discoverClusterCommandPaths
  recordedState <- loadClusterState paths
  runtimeMode <- resolveCommandRuntimeMode paths maybeRuntimeMode recordedState
  let maybeState = matchingClusterState runtimeMode recordedState
  clusterExists <- kindClusterExists paths runtimeMode
  when clusterExists $ do
    usesHostBindMounts <- kindUsesHostBindMounts paths runtimeMode
    case maybeState of
      Just state
        | not usesHostBindMounts -> do
            replayState <-
              startLifecyclePhase
                paths
                state
                "cluster-down"
                "replay-retained-state"
                "replaying retained Kind runtime data back into the repo-local data root"
            syncKindNodeRuntimePathsToHost paths runtimeMode (Just replayState)
      _ ->
        unless usesHostBindMounts $
          syncKindNodeRuntimePathsToHost paths runtimeMode maybeState
    case maybeState of
      Just state -> do
        deleteState <-
          startLifecyclePhase
            paths
            state
            "cluster-down"
            "delete-kind-cluster"
            "deleting the Kind cluster after retained runtime data handling is complete"
        deleteKindCluster paths (clusterRuntimeMode deleteState)
      Nothing -> deleteKindCluster paths runtimeMode
  scrubNonRetainedClusterDirectories paths runtimeMode
  case maybeState of
    Nothing -> putStrLn "cluster already absent"
    Just state
      | clusterRuntimeMode state /= runtimeMode -> putStrLn "cluster down complete"
      | otherwise -> do
          now <- getCurrentTime
          _ <-
            clearLifecycleProgress
              paths
              state
                { clusterPresent = False,
                  updatedAt = now
                }
          putStrLn "cluster down complete"

clusterStatus :: Maybe RuntimeMode -> IO ()
clusterStatus maybeRuntimeMode = do
  paths <- Config.discoverPaths
  recordedState <- loadClusterState paths
  runtimeMode <- resolveCommandRuntimeMode paths maybeRuntimeMode recordedState
  let maybeState = matchingClusterState runtimeMode recordedState
  case maybeState of
    Nothing -> do
      putStrLn "cluster not yet reconciled"
      putStrLn ("runtimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
      putStrLn "lifecycleStatus: idle"
      putStrLn "lifecyclePhase: not-yet-reconciled"
      putStrLn ("buildRoot: " <> buildRoot paths)
      putStrLn ("dataRoot: " <> dataRoot paths)
      putStrLn ("expectedDemoConfigPath: " <> Config.generatedDemoConfigPath paths)
      putStrLn ("expectedMountedDemoConfigPath: " <> Config.watchedDemoConfigPath)
    Just state -> do
      ensureOuterContainerKindNetworkAccess paths (clusterRuntimeMode state)
      actualPresent <- kindClusterExists paths (clusterRuntimeMode state)
      now <- getCurrentTime
      cacheEntries <- countLeafEntries (modelCacheRoot paths)
      resultCount <- countLeafEntries (resultsRoot paths)
      nodeCount <- kubectlLineCountIfReachable state ["get", "nodes", "--no-headers"]
      podCount <- kubectlLineCountIfReachable state ["get", "pods", "-A", "--no-headers"]
      putStrLn ("clusterPresent: " <> show actualPresent)
      putStrLn ("controlPlaneContext: " <> controlPlaneContextId (Config.controlPlaneContext paths))
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
      putStrLn ("storageHealth: " <> show (length (claims state)) <> " chart-owned claim roots prepared")
      mapM_ putStrLn (lifecycleStatusLines now actualPresent state)
      publicationSummaryLines <- publicationStateSummaryLines (Config.publicationStatePath paths)
      putStrLn ("kubernetesNodeCount: " <> show nodeCount)
      putStrLn ("kubernetesPodCount: " <> show podCount)
      putStrLn ("runtimeResultCount: " <> show resultCount)
      putStrLn ("modelCacheEntryCount: " <> show cacheEntries)
      mapM_ putStrLn publicationSummaryLines
      mapM_
        (\route -> putStrLn ("route: " <> Text.unpack (path route) <> " -> " <> Text.unpack (purpose route)))
        (routes state)

lifecycleStatusLines :: UTCTime -> Bool -> ClusterState -> [String]
lifecycleStatusLines now actualPresent state =
  case lifecycleProgress state of
    Nothing ->
      [ "lifecycleStatus: idle",
        "lifecyclePhase: " <> idleLifecyclePhase actualPresent
      ]
    Just progress ->
      let heartbeatAgeSeconds :: Integer
          heartbeatAgeSeconds =
            max 0 (round (diffUTCTime now (lifecycleHeartbeatAt progress)))
       in [ "lifecycleStatus: in-progress",
            "lifecycleAction: " <> lifecycleAction progress,
            "lifecyclePhase: " <> lifecyclePhase progress,
            "lifecycleDetail: " <> lifecycleDetail progress,
            "lifecycleHeartbeatAt: " <> show (lifecycleHeartbeatAt progress),
            "lifecycleHeartbeatAgeSeconds: " <> show heartbeatAgeSeconds
          ]

idleLifecyclePhase :: Bool -> String
idleLifecyclePhase actualPresent =
  if actualPresent
    then "steady-state"
    else "cluster-absent"

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
  paths <- discoverClusterCommandPaths
  recordedState <- loadClusterState paths
  runtimeMode <- resolveCommandRuntimeMode paths Nothing recordedState
  let maybeState = matchingClusterState runtimeMode recordedState
  case maybeState of
    Nothing -> putStrLn "No cluster state is available. Run `infernix cluster up` first."
    Just state
      | not (clusterPresent state) -> putStrLn "Cluster is currently absent."
      | otherwise -> do
          ensureOuterContainerKindNetworkAccess paths (clusterRuntimeMode state)
          ensureClusterKubeconfigPresent paths state
          putStr =<< captureHostToolCmd paths Nothing [] HostKubectl (kubeconfigArgs state <> args)

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
    publishGeneratedKubeconfig paths . Text.pack =<< waitForKindKubeconfigOrFail paths (clusterRuntimeMode state)

publicationStateSummaryLines :: FilePath -> IO [String]
publicationStateSummaryLines publicationPath = do
  publicationExists <- doesFileExist publicationPath
  if not publicationExists
    then pure []
    else do
      contents <- readFile publicationPath
      pure
        ( map ("publicationInferenceDispatchMode: " <>) (maybeToList (publicationInferenceDispatchMode contents))
            <> map ("publicationHostInferenceBatchTopic: " <>) (maybeToList (publicationHostInferenceBatchTopic contents))
            <> map ("publicationApiUpstreamMode: " <>) (maybeToList (publicationApiUpstreamMode contents))
            <> publicationUpstreamLines contents
        )

publicationInferenceDispatchMode :: String -> Maybe String
publicationInferenceDispatchMode contents =
  firstJsonStringField
    "\"inferenceDispatchMode\":"
    "inferenceDispatchMode"
    (lines contents)

publicationHostInferenceBatchTopic :: String -> Maybe String
publicationHostInferenceBatchTopic contents =
  firstJsonStringField
    "\"hostInferenceBatchTopic\":"
    "hostInferenceBatchTopic"
    (lines contents)

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
chooseEdgePort paths = chooseDynamicPort 9090 =<< readEdgePortMaybe paths

-- | Phase 3 follow-on (2026-05-29): pick a free host-side TCP port for
-- Harbor's Kind hostPort mapping, mirroring 'chooseEdgePort'. The
-- in-cluster Kubernetes NodePort number stays @30002@ — only the
-- Kind hostPort observed by the operator host is dynamic, so the
-- chart's Harbor sub-chart still resolves to @<node>:30002@ for
-- in-cluster reachability while the host probe and the containerd
-- registry-hosts namespace honor whatever port is actually free on
-- the operator's machine.
chooseHarborPort :: Paths -> IO Int
chooseHarborPort paths = chooseDynamicPort 30002 =<< readHarborPortMaybe paths

-- | Phase 7 follow-on: pick a free host-side TCP port for the Pulsar proxy
-- HTTP NodePort's Kind hostPort mapping, mirroring 'chooseEdgePort' and
-- 'chooseHarborPort'. The in-cluster Kubernetes NodePort number stays
-- @30080@; only the Kind hostPort observed by the operator host shifts when
-- another process (for example a VSCode auto-forwarded port) already holds
-- the @30080@ baseline. The Apple host-native service daemon reads the
-- selected port back from 'pulsarHttpPortPath' to reach the in-cluster
-- Pulsar proxy directly, bypassing the JWT-gated edge route.
choosePulsarHttpPort :: Paths -> IO Int
choosePulsarHttpPort paths = chooseDynamicPort 30080 =<< readPulsarHttpPortMaybe paths

chooseDynamicPort :: Int -> Maybe Int -> IO Int
chooseDynamicPort baseline maybeStoredPort =
  case maybeStoredPort of
    Just storedPort
      | storedPort >= baseline -> do
          storedPortFree <- portIsFree storedPort
          if storedPortFree
            then pure storedPort
            else firstAvailablePort (storedPort + 1)
    _ -> firstAvailablePort baseline

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

kindRuntimeRoot :: Paths -> RuntimeMode -> FilePath
kindRuntimeRoot paths runtimeMode =
  kindRoot paths </> Text.unpack (runtimeModeId runtimeMode)

claimDirectory :: Paths -> RuntimeMode -> PersistentClaim -> FilePath
claimDirectory paths runtimeMode persistentClaim =
  kindRuntimeRoot paths runtimeMode
    </> Text.unpack (namespace persistentClaim)
    </> Text.unpack (release persistentClaim)
    </> Text.unpack (workload persistentClaim)
    </> show (ordinal persistentClaim)
    </> Text.unpack (claim persistentClaim)

ensureClaimDirectoryReady :: Paths -> RuntimeMode -> PersistentClaim -> IO ()
ensureClaimDirectoryReady paths runtimeMode persistentClaim = do
  let directoryPath = claimDirectory paths runtimeMode persistentClaim
  createDirectoryIfMissing True directoryPath
  -- Repo-local claim mirrors stay broadly writable so Apple can sync them into Linux Kind nodes
  -- even though the macOS host filesystem cannot model those node-local container owners.
  runHostToolCmd paths Nothing [] HostChmod ["-R", "a+rwX", directoryPath]
  case claimOwner persistentClaim of
    Nothing -> pure ()
    Just owner
      | hostClaimOwnershipAlignmentSupported paths -> do
          -- Phase 2 Sprint 2.13 follow-on (2026-05-31): chown alignment is a
          -- best-effort source-ownership tag across host/launcher/node
          -- filesystem boundaries. The actual Kind worker pod copies its own
          -- ownership during `prepareKindNodeRuntimePaths`, so a failure here
          -- is non-fatal as long as the directory is broadly writable (it is,
          -- per the `chmod a+rwX` above). Treat the chown as advisory: log
          -- the failure and continue so the lifecycle keeps moving.
          chownResult <- tryCommand Nothing [] "chown" ["-R", owner, directoryPath]
          case chownResult of
            Right _ -> pure ()
            Left err ->
              putStrLn
                ( "warning: chown advisory failed for "
                    <> directoryPath
                    <> " (filesystem does not honor host-side ownership for "
                    <> owner
                    <> "); continuing with broadly writable permissions instead. ("
                    <> stripChownFailureNoise err
                    <> ")"
                )
      | otherwise -> pure ()
  where
    stripChownFailureNoise = takeWhile (/= '\n')

hostClaimOwnershipAlignmentSupported :: Paths -> Bool
hostClaimOwnershipAlignmentSupported paths =
  Config.controlPlaneContext paths == OuterContainer

claimOwner :: PersistentClaim -> Maybe String
claimOwner claimSpec
  | workload claimSpec == "minio" && claim claimSpec == "data" = Just "1001:1001"
  | "harbor-postgresql" `List.isPrefixOf` Text.unpack (workload claimSpec) = Just "26:26"
  | otherwise = Nothing

ensureKindCluster :: Paths -> RuntimeMode -> Int -> Int -> Int -> IO (Int, Int, Int, String, Bool)
ensureKindCluster paths runtimeMode requestedPort requestedHarborPort requestedPulsarHttpPort = do
  clusterExists <- kindClusterExists paths runtimeMode
  (selectedPort, selectedHarborPort, selectedPulsarHttpPort, clusterCreated) <-
    if clusterExists
      then do
        maybeExistingPort <- currentKindEdgePort paths runtimeMode
        maybeExistingHarborPort <- currentKindHarborPort paths runtimeMode
        maybeExistingPulsarHttpPort <- currentKindPulsarHttpPort paths runtimeMode
        pure
          ( fromMaybe requestedPort maybeExistingPort,
            fromMaybe requestedHarborPort maybeExistingHarborPort,
            fromMaybe requestedPulsarHttpPort maybeExistingPulsarHttpPort,
            False
          )
      else do
        (createdPort, createdHarborPort, createdPulsarHttpPort) <- createKindCluster paths runtimeMode requestedPort requestedHarborPort requestedPulsarHttpPort
        pure (createdPort, createdHarborPort, createdPulsarHttpPort, True)
  kubeconfigResult <- waitForKindKubeconfig paths runtimeMode
  case kubeconfigResult of
    Right kubeconfigContents ->
      pure (selectedPort, selectedHarborPort, selectedPulsarHttpPort, normalizeKubeconfigServer (Config.controlPlaneContext paths) kubeconfigContents, clusterCreated)
    Left err
      | clusterExists -> do
          deleteKindCluster paths runtimeMode
          (recreatedPort, recreatedHarborPort, recreatedPulsarHttpPort) <- createKindCluster paths runtimeMode requestedPort requestedHarborPort requestedPulsarHttpPort
          recreatedKubeconfig <- waitForKindKubeconfigOrFail paths runtimeMode
          pure (recreatedPort, recreatedHarborPort, recreatedPulsarHttpPort, normalizeKubeconfigServer (Config.controlPlaneContext paths) recreatedKubeconfig, True)
      | otherwise ->
          ioError
            ( userError
                ( "kind cluster became visible before its kubeconfig was readable for "
                    <> kindClusterName paths runtimeMode
                    <> ":\n"
                    <> err
                )
            )

createKindCluster :: Paths -> RuntimeMode -> Int -> Int -> Int -> IO (Int, Int, Int)
createKindCluster paths runtimeMode = case runtimeMode of
  LinuxGpu -> createLinuxGpuCluster paths
  _ -> go
  where
    go candidatePort harborPortCandidate pulsarHttpPortCandidate = do
      configPath <- writeGeneratedKindConfig paths runtimeMode candidatePort harborPortCandidate pulsarHttpPortCandidate
      result <- withKindScratchKubeconfig paths runtimeMode $ \scratchKubeconfig ->
        tryCommand
          Nothing
          [("KUBECONFIG", scratchKubeconfig)]
          "kind"
          ["create", "cluster", "--name", kindClusterName paths runtimeMode, "--config", configPath]
      case result of
        Right _ -> pure (candidatePort, harborPortCandidate, pulsarHttpPortCandidate)
        Left err
          | "address already in use" `List.isInfixOf` err ->
              go (candidatePort + 1) (harborPortCandidate + 1) (pulsarHttpPortCandidate + 1)
          | otherwise ->
              ioError
                (userError ("kind create cluster failed for " <> kindClusterName paths runtimeMode <> ":\n" <> err))

createLinuxGpuCluster :: Paths -> Int -> Int -> Int -> IO (Int, Int, Int)
createLinuxGpuCluster paths = go
  where
    go candidatePort harborPortCandidate pulsarHttpPortCandidate = do
      ensureLinuxGpuHostPrerequisites paths
      nvkindBinary <- ensureNvkindBinary paths
      configPath <- writeGeneratedKindConfig paths LinuxGpu candidatePort harborPortCandidate pulsarHttpPortCandidate
      result <- withKindScratchKubeconfig paths LinuxGpu $ \scratchKubeconfig ->
        tryCommand
          Nothing
          [("KUBECONFIG", scratchKubeconfig)]
          nvkindBinary
          [ "cluster",
            "create",
            "--name",
            kindClusterName paths LinuxGpu,
            "--config-template",
            configPath,
            "--kubeconfig",
            scratchKubeconfig,
            "--wait",
            "5m"
          ]
      case result of
        Right _ -> pure (candidatePort, harborPortCandidate, pulsarHttpPortCandidate)
        Left err
          | "address already in use" `List.isInfixOf` err ->
              go (candidatePort + 1) (harborPortCandidate + 1) (pulsarHttpPortCandidate + 1)
          | linuxGpuNvkindConfigMapBug err -> do
              clusterCreated <- kindClusterExists paths LinuxGpu
              if clusterCreated
                then do
                  putStrLn
                    ( "nvkind hit its known configmap persistence bug (nvkind reported: "
                        <> firstNonEmptyLine err
                        <> "); kind cluster was created — continuing with repo-owned linux-gpu node setup"
                    )
                  bootstrapResult <- try (completeLinuxGpuNodeBootstrap paths) :: IO (Either SomeException ())
                  case bootstrapResult of
                    Right () -> pure (candidatePort, harborPortCandidate, pulsarHttpPortCandidate)
                    Left bootstrapErr ->
                      ioError
                        ( userError
                            ( "repo-owned linux-gpu node bootstrap failed after working around the nvkind configmap persistence bug for "
                                <> kindClusterName paths LinuxGpu
                                <> ":\n"
                                <> displayException bootstrapErr
                            )
                        )
                else
                  ioError
                    ( userError
                        ( "nvkind cluster create hit its known configmap persistence bug but the kind cluster was not created for "
                            <> kindClusterName paths LinuxGpu
                            <> "; treat as fatal. nvkind reported:\n"
                            <> err
                        )
                    )
          | otherwise ->
              ioError
                (userError ("nvkind cluster create failed for " <> kindClusterName paths LinuxGpu <> ":\n" <> err))

linuxGpuNvkindConfigMapBug :: String -> Bool
linuxGpuNvkindConfigMapBug err =
  "%!w(<nil>)" `List.isInfixOf` err
    && ( "adding config to cluster" `List.isInfixOf` err
           || "writing configmap" `List.isInfixOf` err
       )

-- | First non-blank line of a captured error, trimmed, for single-line
-- diagnostics (e.g. the nvkind configmap-bug recovery log). Falls back to
-- the trimmed whole string when every line is blank.
firstNonEmptyLine :: String -> String
firstNonEmptyLine err =
  case dropWhile (all isSpace) (lines err) of
    (line : _) -> trim line
    [] -> trim err

completeLinuxGpuNodeBootstrap :: Paths -> IO ()
completeLinuxGpuNodeBootstrap paths = do
  nodeNames <- kindNodeNames paths LinuxGpu
  let workerNodeNames = filter (/= kindControlPlaneNodeName paths LinuxGpu) nodeNames
  mapM_ bootstrapWorkerNode workerNodeNames
  where
    bootstrapWorkerNode nodeName =
      runDockerNodeScript
        paths
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

runDockerNodeScript :: Paths -> String -> String -> IO ()
runDockerNodeScript paths nodeName script =
  runHostToolCmd paths Nothing [] HostDocker ["exec", nodeName, "bash", "-c", script]

data LinuxGpuProbeResults = LinuxGpuProbeResults
  { hostGpuResult :: Either String String,
    dockerRuntimeResult :: Either String String,
    dockerVolumeMountResult :: Either String String
  }

ensureLinuxGpuHostPrerequisites :: Paths -> IO ()
ensureLinuxGpuHostPrerequisites paths = do
  probeResults <- linuxGpuProbeResults paths
  unless (linuxGpuPreflightSatisfied (Config.controlPlaneContext paths) probeResults) $ do
    let failureReport = linuxGpuHostFailureReport (Config.controlPlaneContext paths) probeResults
    ioError (userError failureReport)

linuxGpuSupportedOnHost :: IO Bool
linuxGpuSupportedOnHost = do
  paths <- Config.discoverPaths
  linuxGpuPreflightSatisfied (Config.controlPlaneContext paths) <$> linuxGpuProbeResults paths

linuxGpuProbeResults :: Paths -> IO LinuxGpuProbeResults
linuxGpuProbeResults paths = do
  hostGpuResult <- tryHostToolCmd paths Nothing [] HostNvidiaSmi ["-L"]
  dockerRuntimeResult <- tryHostToolCmd paths Nothing [] HostDocker dockerGpuProbeCommand
  defaultRuntimeVolumeMountResult <- tryHostToolCmd paths Nothing [] HostDocker dockerVolumeMountProbeCommand
  gpuVolumeMountResult <- tryHostToolCmd paths Nothing [] HostDocker dockerGpuVolumeMountProbeCommand
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

linuxGpuPreflightSatisfied :: ControlPlaneContext -> LinuxGpuProbeResults -> Bool
linuxGpuPreflightSatisfied controlPlane probeResults =
  commandSucceeded (dockerRuntimeResult probeResults)
    && commandSucceeded (dockerVolumeMountResult probeResults)
    && (controlPlane == OuterContainer || commandSucceeded (hostGpuResult probeResults))

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

linuxGpuHostFailureReport :: ControlPlaneContext -> LinuxGpuProbeResults -> String
linuxGpuHostFailureReport controlPlane probeResults =
  unlines
    ( [ "linux-gpu requires a real NVIDIA host plus a Docker engine configured for GPU and the NVIDIA volume-mount worker-device contract that nvkind uses for Kind workers.",
        "",
        "Active control-plane context: " <> controlPlaneContextId controlPlane
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
      | controlPlane == OuterContainer =
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
        | Config.controlPlaneContext paths == OuterContainer = ["--internal"]
        | otherwise = []
      commandArgs = ["get", "kubeconfig", "--name", kindClusterName paths runtimeMode] <> internalFlag
  retryCommandOutput
    30
    1000000
    ("kind " <> unwords commandArgs)
    (tryHostToolCmd paths Nothing [] HostKind commandArgs)

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

publishGeneratedKubeconfig :: Paths -> Text.Text -> IO ()
publishGeneratedKubeconfig paths kubeconfigContents = do
  removeGeneratedKubeconfigLockFile paths
  writeTextFile (Config.generatedKubeconfigPath paths) kubeconfigContents
  removeGeneratedKubeconfigLockFile paths

generatedKubeconfigLockPath :: Paths -> FilePath
generatedKubeconfigLockPath paths = Config.generatedKubeconfigPath paths <> ".lock"

removeGeneratedKubeconfigLockFile :: Paths -> IO ()
removeGeneratedKubeconfigLockFile = removeFileIfExists . generatedKubeconfigLockPath

removeKubeconfigArtifacts :: FilePath -> IO ()
removeKubeconfigArtifacts kubeconfigFile = do
  removeFileIfExists kubeconfigFile
  removeFileIfExists (kubeconfigFile <> ".lock")

removeFileIfExists :: FilePath -> IO ()
removeFileIfExists filePath = do
  fileExists <- doesFileExist filePath
  when fileExists (removeFile filePath)

withKindScratchKubeconfig :: Paths -> RuntimeMode -> (FilePath -> IO a) -> IO a
withKindScratchKubeconfig paths runtimeMode action = do
  scratchRoot <- getTemporaryDirectory
  let scratchKubeconfig = scratchRoot </> ("infernix-kind-" <> kindClusterName paths runtimeMode <> ".kubeconfig")
  -- Kind and nvkind take file locks while creating or deleting clusters. Keep those transient
  -- locks off repo-visible bind mounts, then publish the durable repo-local kubeconfig ourselves.
  removeGeneratedKubeconfigLockFile paths
  removeKubeconfigArtifacts scratchKubeconfig
  finally (action scratchKubeconfig) (removeKubeconfigArtifacts scratchKubeconfig)

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
  result <- retryCommandOutput 24 500000 commandLabel (tryHostToolCmd paths Nothing [] HostKubectl args)
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
            harborPort = 0,
            routes = routeInventory demoUiEnabledValue,
            storageClass = "infernix-manual",
            claims = claimInventory,
            clusterRuntimeMode = runtimeMode,
            kubeconfigPath = Config.generatedKubeconfigPath paths,
            generatedDemoConfigPath = Config.generatedDemoConfigPath paths,
            publishedDemoConfigPath = Config.publishedConfigMapCatalogPath paths,
            publishedConfigMapManifestPath = Config.publishedConfigMapManifestPath paths,
            mountedDemoConfigPath = Config.watchedDemoConfigPath,
            lifecycleProgress = Nothing,
            updatedAt = now
          }
  applyNamespace state "platform"
  resetStorageClasses paths state
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

resetStorageClasses :: Paths -> ClusterState -> IO ()
resetStorageClasses paths state = do
  existingClasses <- lines <$> kubectlOutput state ["get", "storageclass", "-o", "name"]
  mapM_ (\storageClassName -> runHostToolCmd paths Nothing [] HostKubectl (kubeconfigArgs state <> ["delete", storageClassName])) existingClasses

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

buildClusterImages :: Paths -> ClusterState -> RuntimeMode -> IO ()
buildClusterImages paths state runtimeMode = do
  let runtimeModeName = Text.unpack (runtimeModeId (clusterWorkloadRuntimeMode runtimeMode))
      imageRef = clusterWorkloadImageRef runtimeMode
      goImage = "golang:1.24"
      baseImage =
        case clusterWorkloadRuntimeMode runtimeMode of
          LinuxGpu -> "nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04"
          _ -> "ubuntu:24.04"
      engineBaseImage = "nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04"
      dockerBuildArgs targetImageRef =
        [ "build",
          "-f",
          "docker/Dockerfile",
          "--provenance=false",
          "--build-arg",
          "GO_IMAGE=" <> goImage,
          "--build-arg",
          "BASE_IMAGE=" <> baseImage,
          "--build-arg",
          "RUNTIME_MODE=" <> runtimeModeName,
          "-t",
          targetImageRef,
          "."
        ]
  imageReusable <- dockerImageReusableForHarborPush imageRef
  if Config.controlPlaneContext paths == OuterContainer && imageReusable
    then putStrLn ("reusing baked cluster image for " <> runtimeModeName <> ": " <> imageRef)
    else do
      putStrLn ("building cluster images for " <> runtimeModeName)
      ensureDockerBuildBaseImage paths state goImage
      ensureDockerBuildBaseImage paths state baseImage
      runCommandMonitored
        paths
        state
        (Just (repoRoot paths))
        []
        "docker"
        (dockerBuildArgs imageRef)
  buildPerEngineImages imageRef baseImage engineBaseImage
  where
    buildPerEngineImages controlPlaneImageRef controlPlaneBaseImage engineBaseImage =
      case runtimeMode of
        LinuxGpu ->
          forM_ (perEngineDeploymentNames runtimeMode) $ \engineName -> do
            let engineImageRef = Text.unpack (perEngineImageName runtimeMode engineName)
            engineImageReusable <- dockerImageReusableForHarborPush engineImageRef
            if Config.controlPlaneContext paths == OuterContainer && engineImageReusable
              then putStrLn ("reusing per-engine image for " <> Text.unpack engineName <> ": " <> engineImageRef)
              else do
                ensureDockerBuildBaseImage paths state controlPlaneBaseImage
                ensureDockerBuildBaseImage paths state engineBaseImage
                runCommandMonitored
                  paths
                  state
                  (Just (repoRoot paths))
                  []
                  "docker"
                  [ "build",
                    "-f",
                    "docker/engine.Dockerfile",
                    "--provenance=false",
                    "--build-arg",
                    "ENGINE=" <> Text.unpack engineName,
                    "--build-arg",
                    "CONTROL_PLANE_IMAGE=" <> controlPlaneImageRef,
                    "--build-arg",
                    "BASE_IMAGE=" <> engineBaseImage,
                    "-t",
                    engineImageRef,
                    "."
                  ]
        _ -> pure ()

-- Docker 29 + BuildKit may leave local repo-owned images as OCI indexes
-- with provenance attestations. Harbor publication is still Docker-push
-- based for repo-owned images, and those indexed local images have produced
-- intermittent "blob ... not found" failures against the MinIO-backed Harbor
-- registry. Images rebuilt with --provenance=false inspect as plain image
-- manifests; older Docker releases may omit Descriptor and are accepted after
-- the normal inspect succeeds.
dockerImageReusableForHarborPush :: String -> IO Bool
dockerImageReusableForHarborPush imageRef = do
  inspectResult <- tryCommand Nothing [] "docker" ["image", "inspect", imageRef, "--format", "{{.Descriptor.mediaType}}"]
  case inspectResult of
    Left _ -> pure False
    Right descriptor
      | "image.index" `List.isInfixOf` descriptor -> pure False
      | "manifest.list" `List.isInfixOf` descriptor -> pure False
      | otherwise -> pure True

ensureDockerBuildBaseImage :: Paths -> ClusterState -> String -> IO ()
ensureDockerBuildBaseImage paths state imageRef = do
  imagePresent <- maybeRun "docker" ["image", "inspect", imageRef]
  unless imagePresent $
    case dockerHubMirrorRef imageRef of
      Nothing -> pure ()
      Just mirrorRef -> do
        mirrorState <-
          startLifecyclePhase
            paths
            state
            "cluster-up"
            "build-cluster-images"
            ("pulling Docker build base image " <> imageRef <> " via " <> mirrorRef)
        runCommandMonitored paths mirrorState Nothing [] "docker" ["pull", mirrorRef]
        runCommandMonitored paths mirrorState Nothing [] "docker" ["tag", mirrorRef, imageRef]
        requireDockerImagePresent imageRef ("mirror pull completed for " <> mirrorRef <> ", but " <> imageRef <> " is still not inspectable locally after tagging")

requireDockerImagePresent :: String -> String -> IO ()
requireDockerImagePresent imageRef message = do
  imagePresent <- maybeRun "docker" ["image", "inspect", imageRef]
  unless imagePresent (ioError (userError message))

dockerHubMirrorRef :: String -> Maybe String
dockerHubMirrorRef imageRef =
  ("mirror.gcr.io/" <>) <$> normalizedDockerHubPath imageRef
  where
    normalizedDockerHubPath rawImage =
      case stripRegistryPrefix rawImage of
        Just pathValue -> Just (ensureLibraryPrefix pathValue)
        Nothing ->
          if usesImplicitDockerHub rawImage
            then Just (ensureLibraryPrefix rawImage)
            else Nothing

    stripRegistryPrefix rawImage =
      case break (== '/') rawImage of
        ("docker.io", '/' : pathValue) -> Just pathValue
        _ -> Nothing

    usesImplicitDockerHub rawImage =
      case break (== '/') rawImage of
        (_, []) -> True
        (registryOrNamespace, _ : _) -> not (hasExplicitRegistryComponent registryOrNamespace)

    hasExplicitRegistryComponent component =
      '.' `elem` component || ':' `elem` component || component == "localhost"

    ensureLibraryPrefix pathValue =
      case break (== '/') pathValue of
        (_, []) -> "library/" <> pathValue
        _ -> pathValue

publishClusterImages :: Paths -> ClusterState -> FilePath -> RuntimeMode -> IO FilePath
publishClusterImages paths state renderedChartPath runtimeMode = do
  targetArchitecture <- resolveClusterWorkloadArchitecture paths runtimeMode
  let outputPath =
        buildRoot paths
          </> ("harbor-image-overrides-" <> Text.unpack (runtimeModeId runtimeMode) <> ".yaml")
      hostHarborAddress = "localhost:" <> show (harborPort state)
  PublishImages.publishChartImagesFile
    PublishImages.defaultHarborPublishOptions
      { PublishImages.harborHost = hostHarborAddress,
        PublishImages.harborClientHost = hostHarborAddress,
        PublishImages.harborApiHost = harborApiHost paths runtimeMode (harborPort state),
        PublishImages.harborDockerCommand = resolveHostToolForCluster paths HostDocker,
        PublishImages.harborSkopeoCommand = resolveHostToolForCluster paths HostSkopeo,
        PublishImages.harborTargetArchitecture = targetArchitecture
      }
    ( \detail -> do
        detailState <- startLifecyclePhase paths state "cluster-up" "publish-harbor-images" detail
        pure (Just (lifecycleCommandMonitor paths detailState))
    )
    renderedChartPath
    outputPath
  pure outputPath

preloadHostCachedWarmupImagesOnKindWorker :: Paths -> ClusterState -> RuntimeMode -> IO ()
preloadHostCachedWarmupImagesOnKindWorker paths state runtimeMode =
  when (runtimeMode /= AppleSilicon) $ do
    workerContainers <- kindWorkerNodeNames paths runtimeMode
    forM_ workerContainers $ \workerContainer ->
      mapM_ (preloadHostCachedWarmupImage paths state workerContainer) hostCachedWarmupImageRefs

-- | Phase 3 Sprint 3.11 (2026-05-29): the warmup-preload list tracks
-- the multi-arch upstream image inventory after the `bitnamilegacy/*`
-- retirement. The MinIO server image is `minio/minio` (multi-arch); the
-- volume-permissions init container uses `busybox` (multi-arch); the
-- separate `minio-object-browser` Deployment was removed when
-- `console.enabled` flipped to `false` in `chart/values.yaml`.
hostCachedWarmupImageRefs :: [String]
hostCachedWarmupImageRefs =
  [ "docker.io/apachepulsar/pulsar-all:4.0.9",
    "docker.io/minio/minio:RELEASE.2025-09-07T16-13-09Z",
    "docker.io/minio/mc:RELEASE.2025-08-13T08-35-41Z",
    "docker.io/busybox:1.36",
    "docker.io/envoyproxy/gateway:v1.7.2",
    "docker.io/percona/percona-distribution-postgresql:18.3-1",
    "docker.io/percona/percona-pgbackrest:2.58.0-1",
    "docker.io/percona/percona-pgbouncer:1.25.1-1",
    "docker.io/percona/percona-postgresql-operator:2.9.0",
    "quay.io/keycloak/keycloak:26.0.7"
  ]

preloadHostCachedWarmupImage :: Paths -> ClusterState -> String -> String -> IO ()
preloadHostCachedWarmupImage paths state workerContainer imageRef = do
  imagePresent <- ensureHostWarmupImageCached paths state imageRef
  when imagePresent $ do
    preloadState <-
      startLifecyclePhase
        paths
        state
        "cluster-up"
        "preload-bootstrap-images"
        ("preloading host-cached warmup image " <> imageRef <> " on " <> workerContainer)
    let dockerCommand = resolveClusterCommandWithPaths paths "docker"
        streamImportScript =
          "set -euo pipefail; \"$1\" image save \"$2\" | \"$1\" exec -i \"$3\" ctr --namespace=k8s.io images import -"
    result <-
      ( try
          ( runCommandMonitored
              paths
              preloadState
              Nothing
              []
              "bash"
              ["-lc", streamImportScript, "infernix-image-stream", dockerCommand, imageRef, workerContainer]
          ) ::
          IO (Either IOException ())
      )
    case result of
      Right _ -> pure ()
      Left err -> do
        putStrLn
          ( "warmup image preload skipped after failure for "
              <> imageRef
              <> ": "
              <> displayException err
          )

ensureHostWarmupImageCached :: Paths -> ClusterState -> String -> IO Bool
ensureHostWarmupImageCached paths state imageRef = do
  imagePresent <- maybeRun "docker" ["image", "inspect", imageRef]
  if imagePresent
    then pure True
    else hydrateMissingHostWarmupImage paths state imageRef

hydrateMissingHostWarmupImage :: Paths -> ClusterState -> String -> IO Bool
hydrateMissingHostWarmupImage paths state imageRef =
  case dockerHubMirrorRef imageRef of
    Nothing -> pure False
    Just mirrorRef -> do
      hydrateState <-
        startLifecyclePhase
          paths
          state
          "cluster-up"
          "preload-bootstrap-images"
          ("hydrating warmup image " <> imageRef <> " via " <> mirrorRef)
      -- Phase 3 Sprint 3.11 (2026-05-29): the @--platform@ pin is
      -- derived from the active substrate so Apple Silicon hydrates
      -- arm64 base images natively. The hardcoded @linux/amd64@ this
      -- replaced was the Docker 29.x mirror fallback added when only
      -- amd64 substrates were supported.
      targetArchitecture <- resolveClusterWorkloadArchitecture paths (clusterRuntimeMode state)
      let platformFlagValue = "linux/" <> targetArchitecture
      hydrateResult <-
        ( try
            ( do
                runCommandMonitored paths hydrateState Nothing [] "docker" ["pull", "--platform", platformFlagValue, mirrorRef]
                runCommandMonitored paths hydrateState Nothing [] "docker" ["tag", mirrorRef, imageRef]
                requireDockerImagePresent imageRef ("mirror pull completed for " <> mirrorRef <> ", but " <> imageRef <> " is still not inspectable locally after tagging")
            ) ::
            IO (Either IOException ())
        )
      case hydrateResult of
        Right _ -> pure True
        Left err -> do
          putStrLn
            ( "warmup image mirror hydration skipped after failure for "
                <> imageRef
                <> " via "
                <> mirrorRef
                <> ": "
                <> displayException err
            )
          pure False

preloadHarborBackedImagesOnKindWorker :: Paths -> ClusterState -> RuntimeMode -> FilePath -> IO ()
preloadHarborBackedImagesOnKindWorker paths state runtimeMode imageOverridesPath = do
  imageRefs <- harborOverlayImageRefs paths imageOverridesPath
  workerContainers <- kindWorkerNodeNames paths runtimeMode
  let uniqueImageRefs = List.nub (filter shouldPreloadOnWorker (map trim imageRefs))
  unless (null uniqueImageRefs) $ do
    putStrLn "preloading Harbor-backed final images on the Kind workers"
    forM_ workerContainers $ \workerContainer ->
      mapM_
        ( \imageRef -> do
            imageState <-
              startLifecyclePhase
                paths
                state
                "cluster-up"
                "preload-harbor-images"
                ("preloading Harbor-backed image " <> imageRef <> " on " <> workerContainer)
            preloadHarborImageOnNode paths imageState workerContainer imageRef
        )
        uniqueImageRefs
  where
    shouldPreloadOnWorker imageRef = not (null imageRef)

harborOverlayImageRefs :: Paths -> FilePath -> IO [String]
harborOverlayImageRefs _paths imageOverridesPath =
  filter (not . null) <$> discoverHarborOverlayImageRefsFile imageOverridesPath

preloadHarborImageOnNode :: Paths -> ClusterState -> String -> String -> IO ()
preloadHarborImageOnNode paths state nodeContainer imageRef = go (12 :: Int) ""
  where
    commandArgs =
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
    go remainingAttempts lastFailure = do
      result <-
        ProcessMonitor.tryCommandMonitored
          Nothing
          []
          "docker"
          commandArgs
          (Just (lifecycleCommandMonitor paths state))
      case result of
        Right _ -> pure ()
        Left err
          | remainingAttempts > 1 -> do
              threadDelay 5000000
              go (remainingAttempts - 1) (chooseError err lastFailure)
          | otherwise ->
              ioError
                ( userError
                    ( "Kind worker could not preload Harbor-backed image "
                        <> imageRef
                        <> ":\n"
                        <> chooseError err lastFailure
                    )
                )

    chooseError current previous
      | null current = previous
      | otherwise = current

maybeRun :: String -> [String] -> IO Bool
maybeRun command arguments = do
  result <- tryCommand Nothing [] command arguments
  pure (either (const False) (const True) result)

waitForHarborRegistry :: Paths -> RuntimeMode -> Int -> IO ()
waitForHarborRegistry paths runtimeMode harborPortValue = do
  result <- waitForHarborRegistryResult paths runtimeMode harborPortValue 60 5000000
  case result of
    Right _ -> pure ()
    Left err ->
      ioError
        (userError ("Harbor registry never became ready enough for image publication:\n" <> err))

waitForHarborRegistryResult :: Paths -> RuntimeMode -> Int -> Int -> Int -> IO (Either String String)
waitForHarborRegistryResult paths runtimeMode harborPortValue attempts delayMicros = do
  let registryApiUrl = "http://" <> harborApiHost paths runtimeMode harborPortValue <> "/api/v2.0/health"
      probeCommand = do
        response <-
          tryCommand
            Nothing
            []
            "curl"
            ["-sS", "-m", "30", "-o", "-", "-w", "\n%{http_code}", registryApiUrl]
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
      deployResult <- tryDeployChartWithTimeout paths state valuesPaths False harborBootstrapHelmTimeout
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
                  waitForHarborRegistry paths (clusterRuntimeMode state) (harborPort state)
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
      registryResult <- waitForHarborRegistryResult paths (clusterRuntimeMode state) (harborPort state) 1 0
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
          ( [ "set -eu"
            ]
              <> harborMigrationDirtyCountShell
              <> [ "if [ \"$dirty_count\" = \"0\" ]; then",
                   "  echo clean",
                   "else",
                   "  echo dirty",
                   "fi"
                 ]
          )
  result <- runHarborDatabaseCommand state detectionCommand
  case result of
    Right output -> pure ("dirty" `List.isInfixOf` output)
    Left _ -> pure False

repairHarborDatabaseMigrationState :: ClusterState -> IO ()
repairHarborDatabaseMigrationState state = do
  waitForHarborDatabaseReadyWithRepair state
  let repairCommand =
        unlines
          ( [ "set -eu"
            ]
              <> harborMigrationDirtyCountShell
              <> [ "if [ \"$dirty_count\" != \"0\" ]; then",
                   "  psql -h 127.0.0.1 -U " <> harborPostgresUserName <> " -d registry -v ON_ERROR_STOP=1 -c \"DROP SCHEMA IF EXISTS " <> harborPostgresSchemaName <> " CASCADE;\"",
                   "  psql -h 127.0.0.1 -U " <> harborPostgresUserName <> " -d registry -v ON_ERROR_STOP=1 -c \"CREATE SCHEMA " <> harborPostgresSchemaName <> " AUTHORIZATION " <> harborPostgresUserName <> ";\"",
                   "  psql -h 127.0.0.1 -U " <> harborPostgresUserName <> " -d registry -v ON_ERROR_STOP=1 -c \"GRANT ALL ON SCHEMA " <> harborPostgresSchemaName <> " TO " <> harborPostgresUserName <> ";\"",
                   "fi"
                 ]
          )
  repairResult <- runHarborDatabaseCommand state repairCommand
  case repairResult of
    Right _ -> pure ()
    Left err ->
      ioError
        (userError ("failed to repair dirty Harbor database migration state:\n" <> err))

harborMigrationDirtyCountShell :: [String]
harborMigrationDirtyCountShell =
  [ "migration_table_exists=$(psql -h 127.0.0.1 -U " <> harborPostgresUserName <> " -d registry -v ON_ERROR_STOP=1 -Atqc \"SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = '" <> harborPostgresSchemaName <> "' AND table_name = 'schema_migrations') THEN 'yes' ELSE 'no' END\")",
    "if [ \"$migration_table_exists\" = \"yes\" ]; then",
    "  dirty_count=$(psql -h 127.0.0.1 -U " <> harborPostgresUserName <> " -d registry -v ON_ERROR_STOP=1 -Atqc \"SELECT COUNT(*)::text FROM " <> harborPostgresSchemaName <> ".schema_migrations WHERE dirty = TRUE\")",
    "else",
    "  dirty_count=0",
    "fi"
  ]

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
waitForHarborPostgresPodsReady state = go totalAttempts False False ""
  where
    totalAttempts = 72 :: Int

    go remainingAttempts restartIssued reinitIssued lastError = do
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
      case currentError of
        "" -> pure ()
        _
          | remainingAttempts <= 1 ->
              ioError
                ( userError
                    ( "Harbor PostgreSQL pods never became ready:\n"
                        <> chooseError currentError lastError
                    )
                )
          | otherwise -> do
              (restarted, reinitialized) <-
                repairHarborPostgresStartup
                  allStartupPodsPresent
                  attemptsElapsed
                  restartIssued
                  reinitIssued
                  startupPods
              threadDelay 5000000
              go
                (remainingAttempts - 1)
                (restartIssued || restarted)
                (reinitIssued || reinitialized)
                (chooseError currentError lastError)

    repairHarborPostgresStartup allStartupPodsPresent attemptsElapsed restartIssued reinitIssued startupPods = do
      restarted <-
        if restartIssued
          then pure False
          else
            restartHarborPostgresStartupPodsIfStuck
              state
              allStartupPodsPresent
              attemptsElapsed
              startupPods
      reinitialized <-
        if reinitIssued || restarted
          then pure False
          else
            reinitializeHarborPostgresReplicasIfStuck
              state
              attemptsElapsed
              (restartIssued || restarted)
              startupPods
      pure (restarted, reinitialized)

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
restartHarborPostgresStartupPodsIfStuck state _allStartupPodsPresent attemptsElapsed startupPods =
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
        && ( any podLooksStuck startupPods
               || attemptsElapsed >= harborPostgresStartupRepairGraceAttempts
           )
    podLooksStuck startupPod =
      not (harborPostgresStartupPodReady startupPod)
        && ( "CrashLoopBackOff" `List.isInfixOf` harborPostgresStartupPodStatus startupPod
               || harborPostgresStartupPodStatus startupPod == "Error"
               || harborPostgresStartupPodStatus startupPod == "Init:Error"
           )

reinitializeHarborPostgresReplicasIfStuck :: ClusterState -> Int -> Bool -> [HarborPostgresStartupPod] -> IO Bool
reinitializeHarborPostgresReplicasIfStuck state attemptsElapsed restartIssued startupPods = do
  primaryPodName <- harborPostgresPrimaryPodNameMaybe state
  if shouldReinitialize primaryPodName
    then do
      putStrLn
        ( "repairing Harbor PostgreSQL replicas from leader: "
            <> List.intercalate ", " (replicaPodNames primaryPodName)
        )
      result <-
        ( try
            ( runCommand
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
                         "patronictl",
                         "-k",
                         "reinit",
                         harborPostgresPatroniClusterName
                       ]
                    <> replicaPodNames primaryPodName
                    <> ["--force", "--wait", "--from-leader"]
                )
            ) ::
            IO (Either IOException ())
        )
      case result of
        Right _ -> pure ()
        Left err ->
          putStrLn
            ( "Harbor PostgreSQL replica reinitialization command failed; continuing rollout wait: "
                <> displayException err
            )
      pure True
    else pure False
  where
    stuckDataPodNames =
      [ harborPostgresStartupPodName startupPod
      | startupPod <- startupPods,
        not (harborPostgresStartupPodReady startupPod),
        "harbor-postgresql-instance" `List.isPrefixOf` harborPostgresStartupPodName startupPod
      ]
    replicaPodNames primaryPodName =
      filter (/= primaryPodName) stuckDataPodNames
    shouldReinitialize primaryPodName =
      restartIssued
        && attemptsElapsed >= harborPostgresReplicaReinitGraceAttempts
        && not (null primaryPodName)
        && not (null (replicaPodNames primaryPodName))

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
  pure (firstOrEmpty podNames)

firstOrEmpty :: [String] -> String
firstOrEmpty values =
  case values of
    firstValue : _ -> firstValue
    [] -> ""

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
tryDeployChart paths state valuesPaths waitForRollout =
  tryDeployChartWithTimeout paths state valuesPaths waitForRollout "30m"

tryDeployChartWithTimeout :: Paths -> ClusterState -> [FilePath] -> Bool -> String -> IO (Either String String)
tryDeployChartWithTimeout paths state valuesPaths waitForRollout timeoutValue = do
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
    timeoutArgs = ["--timeout", timeoutValue]
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

reconcileKeycloakRealmConfiguration :: Paths -> ClusterState -> IO ()
reconcileKeycloakRealmConfiguration paths state =
  when (clusterStateHasDemoUi state) $ do
    putStrLn "reconciling Keycloak demo realm"
    manager <- newManager defaultManagerSettings
    go manager (30 :: Int) ""
  where
    go manager remainingAttempts lastError = do
      result <-
        ( try
            (reconcileKeycloakRealmConfigurationOnce paths state manager) ::
            IO (Either SomeException ())
        )
      case result of
        Right _ -> pure ()
        Left err
          | remainingAttempts > 1 -> do
              threadDelay 2000000
              go manager (remainingAttempts - 1) (displayException err)
          | otherwise ->
              ioError
                ( userError
                    ( "Keycloak realm reconcile failed:\n"
                        <> chooseError (displayException err) lastError
                    )
                )
    chooseError current previous
      | null current = previous
      | otherwise = current

reconcileKeycloakRealmConfigurationOnce :: Paths -> ClusterState -> Manager -> IO ()
reconcileKeycloakRealmConfigurationOnce paths state manager = do
  credentials <- readKeycloakAdminCredentials state
  token <- requestKeycloakAdminToken manager (clusterEdgeBaseUrl paths state) credentials
  putKeycloakJson
    manager
    token
    (keycloakAdminRealmUrl paths state)
    keycloakRealmReconcilePayload
  clientValue <- fetchKeycloakSpaClient paths state manager token
  clientIdValue <- requireKeycloakClientInternalId clientValue
  clientPayload <-
    case keycloakSpaClientReconcilePayload paths state clientValue of
      Right value -> pure value
      Left err -> ioError (userError err)
  putKeycloakJson
    manager
    token
    (keycloakAdminRealmUrl paths state <> "/clients/" <> urlEncodedString clientIdValue)
    clientPayload

readKeycloakAdminCredentials :: ClusterState -> IO KeycloakAdminCredentials
readKeycloakAdminCredentials state = do
  encodedUsername <-
    kubectlOutput
      state
      [ "-n",
        "platform",
        "get",
        "secret",
        keycloakAdminSecretName,
        "-o",
        "jsonpath={.data.username}"
      ]
  encodedPassword <-
    kubectlOutput
      state
      [ "-n",
        "platform",
        "get",
        "secret",
        keycloakAdminSecretName,
        "-o",
        "jsonpath={.data.password}"
      ]
  KeycloakAdminCredentials
    <$> decodeKubernetesSecretField keycloakAdminSecretName "username" encodedUsername
    <*> decodeKubernetesSecretField keycloakAdminSecretName "password" encodedPassword

decodeKubernetesSecretField :: String -> String -> String -> IO String
decodeKubernetesSecretField secretName fieldName encodedValue =
  case Base64.decode (ByteString8.pack (trim encodedValue)) of
    Left err ->
      ioError
        ( userError
            ( "failed to decode "
                <> secretName
                <> "."
                <> fieldName
                <> ": "
                <> err
            )
        )
    Right decodedValue -> pure (ByteString8.unpack decodedValue)

requestKeycloakAdminToken :: Manager -> String -> KeycloakAdminCredentials -> IO KeycloakAdminToken
requestKeycloakAdminToken manager edgeBaseUrl credentials = do
  baseRequest <- parseRequest (edgeBaseUrl <> "/auth/realms/master/protocol/openid-connect/token")
  let formBody =
        [ ("grant_type", "password"),
          ("client_id", "admin-cli"),
          ("username", ByteString8.pack (keycloakAdminUsername credentials)),
          ("password", ByteString8.pack (keycloakAdminPassword credentials))
        ]
      tokenRequest =
        urlEncodedBody formBody (baseRequest {method = "POST"})
  response <- httpLbs tokenRequest manager
  let code = statusCode (responseStatus response)
  if code == 200
    then decodeKeycloakAdminTokenResponse (responseBody response)
    else
      ioError
        ( userError
            ( "Keycloak admin token request failed with status "
                <> show code
                <> ":\n"
                <> lazyBodyToString (responseBody response)
            )
        )

decodeKeycloakAdminTokenResponse :: Lazy.ByteString -> IO KeycloakAdminToken
decodeKeycloakAdminTokenResponse responsePayload =
  case eitherDecode responsePayload of
    Right token -> pure token
    Left decodeError ->
      ioError
        ( userError
            ( "failed to decode Keycloak admin token response:\n"
                <> decodeError
            )
        )

fetchKeycloakSpaClient :: Paths -> ClusterState -> Manager -> KeycloakAdminToken -> IO Value
fetchKeycloakSpaClient paths state manager token = do
  clientsValue <-
    getKeycloakJson
      manager
      token
      ( keycloakAdminRealmUrl paths state
          <> "/clients?clientId="
          <> urlEncodedString keycloakSpaClientId
      )
  clientValues <-
    case requireJsonArrayPath [] clientsValue of
      Right values -> pure values
      Left err -> ioError (userError ("invalid Keycloak clients response: " <> err))
  case List.find isSpaClient clientValues of
    Just clientValue -> pure clientValue
    Nothing ->
      ioError
        ( userError
            ( "Keycloak client "
                <> keycloakSpaClientId
                <> " was not present in realm "
                <> keycloakRealmName
            )
        )
  where
    isSpaClient clientValue =
      lookupJsonStringPath ["clientId"] clientValue == Just keycloakSpaClientId

requireKeycloakClientInternalId :: Value -> IO String
requireKeycloakClientInternalId clientValue =
  case lookupJsonStringPath ["id"] clientValue of
    Just clientIdValue -> pure clientIdValue
    Nothing ->
      ioError
        ( userError
            ( "Keycloak client "
                <> keycloakSpaClientId
                <> " did not include an internal id"
            )
        )

getKeycloakJson :: Manager -> KeycloakAdminToken -> String -> IO Value
getKeycloakJson manager token url = do
  request <- parseRequest url
  response <-
    httpLbs
      request
        { requestHeaders =
            keycloakAuthorizationHeader token : requestHeaders request
        }
      manager
  let code = statusCode (responseStatus response)
  if code >= 200 && code < 300
    then decodeKeycloakJsonResponse url (responseBody response)
    else
      ioError
        ( userError
            ( "Keycloak GET "
                <> url
                <> " failed with status "
                <> show code
                <> ":\n"
                <> lazyBodyToString (responseBody response)
            )
        )

decodeKeycloakJsonResponse :: String -> Lazy.ByteString -> IO Value
decodeKeycloakJsonResponse url responsePayload =
  case eitherDecode responsePayload of
    Right value -> pure value
    Left decodeError ->
      ioError
        ( userError
            ( "failed to decode Keycloak JSON response from "
                <> url
                <> ":\n"
                <> decodeError
            )
        )

putKeycloakJson :: Manager -> KeycloakAdminToken -> String -> Value -> IO ()
putKeycloakJson manager token url payload = do
  request <- parseRequest url
  response <-
    httpLbs
      request
        { method = "PUT",
          requestHeaders =
            [ keycloakAuthorizationHeader token,
              ("Content-Type", "application/json")
            ],
          requestBody = RequestBodyLBS (encode payload)
        }
      manager
  let code = statusCode (responseStatus response)
  unless (code `elem` [200, 204]) $
    ioError
      ( userError
          ( "Keycloak PUT "
              <> url
              <> " failed with status "
              <> show code
              <> ":\n"
              <> lazyBodyToString (responseBody response)
          )
      )

keycloakAuthorizationHeader :: KeycloakAdminToken -> Header
keycloakAuthorizationHeader token =
  ( "Authorization",
    ByteString8.pack ("Bearer " <> Text.unpack (keycloakAdminAccessToken token))
  )

keycloakRealmReconcilePayload :: Value
keycloakRealmReconcilePayload =
  object
    [ "realm" .= keycloakRealmName,
      "loginTheme" .= keycloakLoginThemeName,
      "registrationAllowed" .= True,
      "registrationEmailAsUsername" .= False,
      "verifyEmail" .= False,
      "loginWithEmailAllowed" .= False,
      "duplicateEmailsAllowed" .= True,
      "resetPasswordAllowed" .= False,
      "editUsernameAllowed" .= False,
      "passwordPolicy" .= ("length(8)" :: String)
    ]

keycloakSpaClientReconcilePayload :: Paths -> ClusterState -> Value -> Either String Value
keycloakSpaClientReconcilePayload paths state (Object objectValue) =
  Right
    ( Object
        ( foldr
            (\(fieldName, fieldValue) -> KeyMap.insert (Key.fromText fieldName) fieldValue)
            objectValue
            [ ("redirectUris", keycloakStringArray (keycloakSpaRedirectUris paths state)),
              ("webOrigins", keycloakStringArray (keycloakSpaWebOrigins paths state)),
              ("publicClient", Bool True),
              ("standardFlowEnabled", Bool True),
              ("directAccessGrantsEnabled", Bool False),
              ("serviceAccountsEnabled", Bool False),
              ("implicitFlowEnabled", Bool False),
              ("protocol", String "openid-connect"),
              ("attributes", Object reconciledAttributes)
            ]
        )
    )
  where
    currentAttributes =
      case KeyMap.lookup (Key.fromText "attributes") objectValue of
        Just (Object attributesValue) -> attributesValue
        _ -> KeyMap.empty
    reconciledAttributes =
      foldr
        (\(fieldName, fieldValue) -> KeyMap.insert (Key.fromText fieldName) fieldValue)
        currentAttributes
        [ ("pkce.code.challenge.method", String "S256"),
          ("post.logout.redirect.uris", String "+")
        ]
keycloakSpaClientReconcilePayload _paths _state _ =
  Left "Keycloak SPA client representation was not a JSON object"

keycloakSpaRedirectUris :: Paths -> ClusterState -> [String]
keycloakSpaRedirectUris paths state =
  List.nub
    [ "/*",
      "http://127.0.0.1:" <> show (edgePort state) <> "/*",
      "http://localhost:" <> show (edgePort state) <> "/*",
      "http://infernix-linux-cpu-control-plane:30090/*",
      "http://infernix-linux-gpu-control-plane:30090/*",
      "http://infernix-apple-silicon-control-plane:30090/*",
      clusterEdgeBaseUrl paths state <> "/*"
    ]

keycloakSpaWebOrigins :: Paths -> ClusterState -> [String]
keycloakSpaWebOrigins paths state =
  List.nub
    [ "+",
      "http://127.0.0.1:" <> show (edgePort state),
      "http://localhost:" <> show (edgePort state),
      "http://infernix-linux-cpu-control-plane:30090",
      "http://infernix-linux-gpu-control-plane:30090",
      "http://infernix-apple-silicon-control-plane:30090",
      clusterEdgeBaseUrl paths state
    ]

keycloakStringArray :: [String] -> Value
keycloakStringArray values =
  Array (Vector.fromList (map (String . Text.pack) values))

keycloakAdminRealmUrl :: Paths -> ClusterState -> String
keycloakAdminRealmUrl paths state =
  clusterEdgeBaseUrl paths state <> "/auth/admin/realms/" <> keycloakRealmName

urlEncodedString :: String -> String
urlEncodedString =
  ByteString8.unpack . urlEncode True . ByteString8.pack

lazyBodyToString :: Lazy.ByteString -> String
lazyBodyToString = LazyChar8.unpack

detectDirtyPulsarBootstrapState :: Paths -> RuntimeMode -> IO (Maybe String)
detectDirtyPulsarBootstrapState paths runtimeMode = do
  maybeState <- loadClusterState paths
  clusterExists <- kindClusterExists paths runtimeMode
  case matchingClusterState runtimeMode maybeState of
    Just state
      | clusterPresent state && clusterExists ->
          inspectPods state pulsarZookeeperPodNames
    _ -> pure Nothing
  where
    inspectPods _ [] = pure Nothing
    inspectPods state (podName : remainingPods) = do
      dirtyPod <- pulsarBootstrapLogShowsDirtyState state podName
      if dirtyPod
        then
          pure
            ( Just
                ( podName
                    <> " reported stale epoch/zxid metadata on its retained volume"
                )
            )
        else inspectPods state remainingPods

pulsarBootstrapLogShowsDirtyState :: ClusterState -> String -> IO Bool
pulsarBootstrapLogShowsDirtyState state podName = do
  previousLogsDirty <- podLogsContainDirtyMarker state podName True
  if previousLogsDirty
    then pure True
    else podLogsContainDirtyMarker state podName False

podLogsContainDirtyMarker :: ClusterState -> String -> Bool -> IO Bool
podLogsContainDirtyMarker state podName usePreviousLogs = do
  result <-
    tryCommand
      Nothing
      []
      "kubectl"
      ( kubeconfigArgs state
          <> [ "-n",
               "platform",
               "logs",
               podName,
               "--tail=200"
             ]
          <> previousArgs
      )
  pure (either (const False) pulsarBootstrapLogIndicatesDirtyState result)
  where
    previousArgs
      | usePreviousLogs = ["--previous"]
      | otherwise = []

pulsarBootstrapLogIndicatesDirtyState :: String -> Bool
pulsarBootstrapLogIndicatesDirtyState output =
  any (`List.isInfixOf` output) pulsarBootstrapDirtyLogMarkers

resetPulsarClaimDirectories :: Paths -> RuntimeMode -> IO ()
resetPulsarClaimDirectories paths runtimeMode = do
  maybeState <- loadClusterState paths
  case matchingClusterState runtimeMode maybeState of
    Nothing -> pure ()
    Just state -> do
      let pulsarClaims = filter isPulsarPersistentClaim (claims state)
      unless (null pulsarClaims) $
        putStrLn "resetting retained Pulsar claim roots"
      mapM_ (resetClaimDirectory state) pulsarClaims
  where
    isPulsarPersistentClaim persistentClaim =
      "pulsar-" `List.isPrefixOf` Text.unpack (workload persistentClaim)
    resetClaimDirectory state persistentClaim = do
      let directoryPath = claimDirectory paths (clusterRuntimeMode state) persistentClaim
      directoryPresent <- doesDirectoryExist directoryPath
      when directoryPresent (removePathForcibly directoryPath)

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
  createDirectoryIfMissing True (helmDependencyArchivesDirectory paths)
  mapM_ (ensureHelmDependencyArchivePresent paths) helmDependencyArchives

ensureHelmDependencyArchivePresent :: Paths -> FilePath -> IO ()
ensureHelmDependencyArchivePresent paths archiveRelativePath = do
  let archivePath = repoRoot paths </> archiveRelativePath
  archivePresent <- doesFileExist archivePath
  unless archivePresent $ do
    let archiveName = takeFileName archiveRelativePath
        fetchDirectory = helmDependencyArchivesDirectory paths </> (".fetch-" <> archiveName)
        fetchedArchivePath = fetchDirectory </> archiveName
    fetchDirectoryPresent <- doesDirectoryExist fetchDirectory
    when fetchDirectoryPresent (removePathForcibly fetchDirectory)
    createDirectoryIfMissing True fetchDirectory
    fetchHelmDependencyArchive paths archiveRelativePath fetchDirectory
    fetchedArchivePresent <- doesFileExist fetchedArchivePath
    unless fetchedArchivePresent $
      ioError
        ( userError
            ( "Helm dependency fetch did not produce the expected archive:\n"
                <> fetchedArchivePath
            )
        )
    renameFile fetchedArchivePath archivePath
    removePathForcibly fetchDirectory

fetchHelmDependencyArchive :: Paths -> FilePath -> FilePath -> IO ()
fetchHelmDependencyArchive paths archiveRelativePath destinationDirectory =
  case archiveRelativePath of
    "chart/charts/harbor-1.18.3.tgz" ->
      fetchChartFromHelmRepository paths "harbor" "1.18.3" "https://helm.goharbor.io" destinationDirectory
    "chart/charts/pg-operator-2.9.0.tgz" ->
      fetchChartFromHelmRepository paths "pg-operator" "2.9.0" "https://percona.github.io/percona-helm-charts" destinationDirectory
    "chart/charts/pg-db-2.9.0.tgz" ->
      fetchChartFromHelmRepository paths "pg-db" "2.9.0" "https://percona.github.io/percona-helm-charts" destinationDirectory
    "chart/charts/pulsar-4.5.0.tgz" ->
      fetchChartFromHelmRepository paths "pulsar" "4.5.0" "https://pulsar.apache.org/charts" destinationDirectory
    "chart/charts/gateway-helm-v1.7.2.tgz" ->
      runCommand
        Nothing
        (Config.helmEnvironment paths)
        "helm"
        [ "pull",
          "oci://docker.io/envoyproxy/gateway-helm",
          "--version",
          "v1.7.2",
          "--destination",
          destinationDirectory
        ]
    _ ->
      ioError
        ( userError
            ( "Unsupported Helm dependency archive path:\n"
                <> archiveRelativePath
            )
        )

fetchChartFromHelmRepository :: Paths -> String -> String -> String -> FilePath -> IO ()
fetchChartFromHelmRepository paths chartName version repositoryUrl destinationDirectory =
  runCommand
    Nothing
    (Config.helmEnvironment paths)
    "helm"
    [ "pull",
      chartName,
      "--repo",
      repositoryUrl,
      "--version",
      version,
      "--destination",
      destinationDirectory
    ]

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
  mapM_ (ensureClaimDirectoryReady paths (clusterRuntimeMode state)) operatorClaims
  usesHostBindMounts <- kindUsesHostBindMounts paths (clusterRuntimeMode state)
  unless usesHostBindMounts $
    prepareKindNodeClaimDirectories paths state (clusterRuntimeMode state) operatorClaims
  let updatedState = state {claims = mergePersistentClaims (claims state) operatorClaims}
  reconcilePersistentVolumes updatedState
  waitForPersistentClaimsBound updatedState operatorClaims
  waitForHarborDatabaseReadyWithRepair updatedState
  pure updatedState

-- | Phase 7 Sprint 7.1: second pass over operator-managed PVCs after the
-- FinalPhase chart deploy applies the @keycloak-postgresql@ PerconaPGCluster
-- CR. The Percona operator creates 4 additional PVCs (3 data + 1
-- pgbackrest repo) on the supported @infernix-manual@ storage class; we
-- create the matching PVs and wait for them to bind so the Keycloak
-- Deployment is not blocked behind a Pending database. Unlike the warmup
-- reconcile, this pass skips Harbor's database-ready repair because that
-- already ran during the earlier 'reconcileOperatorManagedPersistentVolumes'
-- call.
reconcileFinalPhaseOperatorManagedPersistentVolumes :: Paths -> ClusterState -> IO ClusterState
reconcileFinalPhaseOperatorManagedPersistentVolumes paths state = do
  operatorClaims <- waitForOperatorManagedPersistentClaims state finalPhaseExpectedOperatorClaims
  mapM_ (ensureClaimDirectoryReady paths (clusterRuntimeMode state)) operatorClaims
  usesHostBindMounts <- kindUsesHostBindMounts paths (clusterRuntimeMode state)
  unless usesHostBindMounts $
    prepareKindNodeClaimDirectories paths state (clusterRuntimeMode state) operatorClaims
  let updatedState = state {claims = mergePersistentClaims (claims state) operatorClaims}
  reconcilePersistentVolumes updatedState
  waitForPersistentClaimsBound updatedState operatorClaims
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
      case () of
        _
          | length currentClaims >= expectedCount ->
              pure currentClaims
          | remainingAttempts <= 1 ->
              ioError
                ( userError
                    ( "operator-managed PostgreSQL claims never appeared; expected at least "
                        <> show expectedCount
                        <> " but found "
                        <> show (length currentClaims)
                        <> " after retries"
                    )
                )
          | otherwise -> do
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
    Just clusterValue ->
      operatorManagedClaimFromValue itemValue clusterValue

operatorManagedClaimFromValue :: Value -> Text.Text -> Either String (Maybe OperatorManagedClaim)
operatorManagedClaimFromValue itemValue clusterValue
  | null roleValue =
      Right Nothing
  | storageClassValue /= Just "infernix-manual" =
      Left ("operator-managed PostgreSQL PVC uses unsupported storageClassName " <> show storageClassValue)
  | otherwise =
      Right
        ( Just
            OperatorManagedClaim
              { operatorClaimNamespace =
                  lookupStringOr "default" ["metadata", "namespace"],
                operatorClaimCluster = Text.unpack clusterValue,
                operatorClaimInstanceSet =
                  lookupStringOr "" ["metadata", "labels", "postgres-operator.crunchydata.com/instance-set"],
                operatorClaimRole = roleValue,
                operatorClaimDataKind =
                  lookupStringOr (if null repositoryValue then "" else "pgbackrest") ["metadata", "labels", "postgres-operator.crunchydata.com/data"],
                operatorClaimInstance =
                  lookupStringOr "" ["metadata", "labels", "postgres-operator.crunchydata.com/instance"],
                operatorClaimRepository = repositoryValue,
                operatorClaimPvcName =
                  lookupStringOr "" ["metadata", "name"],
                operatorClaimRequestedStorage =
                  lookupStringOr "5Gi" ["spec", "resources", "requests", "storage"]
              }
        )
  where
    repositoryValue =
      lookupStringOr "" ["metadata", "labels", "postgres-operator.crunchydata.com/pgbackrest-repo"]
    roleValue =
      lookupStringOr (if null repositoryValue then "" else "pgbackrest") ["metadata", "labels", "postgres-operator.crunchydata.com/role"]
    storageClassValue =
      lookupJsonStringPath ["spec", "storageClassName"] itemValue
    lookupStringOr defaultValue pathSegments =
      fromMaybe defaultValue (lookupJsonStringPath pathSegments itemValue)

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
    && lookupJsonStringPath ["inferenceDispatchMode"] publicationPayload
      == Just (Text.unpack (expectedInferenceDispatchModeForRuntime expectedRuntimeMode))
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
          case () of
            _
              | phaseValue == "Bound" ->
                  pure ()
              | remainingAttempts <= 1 ->
                  ioError
                    ( userError
                        ( "persistent claim "
                            <> pvcNameValue
                            <> " never reached Bound phase; last phase was "
                            <> choosePhase phaseValue lastPhase
                        )
                    )
              | otherwise -> do
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

writeGeneratedKindConfig :: Paths -> RuntimeMode -> Int -> Int -> Int -> IO FilePath
writeGeneratedKindConfig paths runtimeMode edgePortValue harborPortValue pulsarHttpPortValue = do
  let outputPath =
        buildRoot paths
          </> "kind"
          </> ("cluster-" <> Text.unpack (runtimeModeId runtimeMode) <> ".generated.yaml")
  hostKindRoot <- resolveHostKindRoot paths runtimeMode
  usesHostBindMounts <- kindUsesHostBindMounts paths runtimeMode
  writeRegistryHostsConfig paths runtimeMode harborPortValue
  hostRegistryHostsDirectory <- resolveHostRegistryHostsRoot paths runtimeMode
  writeTextFile outputPath (Text.pack (renderKindConfig paths runtimeMode edgePortValue harborPortValue pulsarHttpPortValue hostKindRoot hostRegistryHostsDirectory usesHostBindMounts))
  pure outputPath

-- | Phase 3 follow-on (2026-05-29): the containerd registry-hosts
-- namespace is keyed on @localhost:<host-port>@ — the same address
-- @docker push@ targets when publishing images — so the resolution
-- target points containerd at @<kind-node>:30002@ (the in-cluster
-- NodePort, which stays fixed).
writeRegistryHostsConfig :: Paths -> RuntimeMode -> Int -> IO ()
writeRegistryHostsConfig paths runtimeMode harborPortValue = do
  let namespaceName = "localhost:" <> show harborPortValue
      inClusterTarget = kindClusterName paths runtimeMode <> "-control-plane:30002"
  writeRegistryNamespace namespaceName inClusterTarget (localRegistryHostsRoot paths runtimeMode)
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

-- | Phase 2 Sprint 2.13: legacy host-kind-root env override
-- retired. The supported flow now derives @hostKindRoot@ from the
-- typed @HostConfig.hostFilesystem.kindRoot@ field that
-- 'Infernix.Config.discoverPaths' already threads through 'Paths', so
-- the host-side Kind root falls out of 'kindRuntimeRoot' directly.
resolveHostKindRoot :: Paths -> RuntimeMode -> IO FilePath
resolveHostKindRoot paths runtimeMode =
  resolveHostRepoPath paths (kindRuntimeRoot paths runtimeMode)

localRegistryHostsRoot :: Paths -> RuntimeMode -> FilePath
localRegistryHostsRoot paths runtimeMode =
  repoRoot paths
    </> ".build"
    </> "kind"
    </> Text.unpack (runtimeModeId runtimeMode)
    </> "registry"

resolveHostRegistryHostsRoot :: Paths -> RuntimeMode -> IO FilePath
resolveHostRegistryHostsRoot paths runtimeMode =
  resolveHostRepoPath paths (localRegistryHostsRoot paths runtimeMode)

-- | Phase 2 Sprint 2.13: legacy host-repo-root env override
-- retired. On host-native Apple, the typed
-- @HostConfig.hostFilesystem.repoRoot@ already matches the host
-- filesystem so we return it directly. On the Linux outer-container
-- path, the manifest value is the launcher-internal @/workspace@
-- path; the actual host-side path lives only in the launcher
-- container's bind-mount metadata, which we discover by asking the
-- Docker daemon via the mounted Docker socket. Without this
-- translation, nested Kind workers receive the launcher's
-- @/workspace/...@ paths verbatim and Docker creates a separate
-- host-side directory tree at @/workspace/...@ that diverges from
-- the operator's real repo root.
resolveHostRepoRoot :: Paths -> IO FilePath
resolveHostRepoRoot paths
  | not (isBakedLinuxOuterContainerManifest paths) = pure (repoRoot paths)
  | otherwise = do
      launcherContainer <- currentLauncherContainerName
      mountResult <-
        tryHostToolCmd
          paths
          Nothing
          []
          HostDocker
          [ "inspect",
            launcherContainer,
            "--format",
            "{{range .Mounts}}{{if eq .Destination \"" <> repoRoot paths <> "/.data\"}}{{.Source}}{{end}}{{end}}"
          ]
      case mountResult of
        Right rawSource ->
          let trimmedSource = trim rawSource
           in if null trimmedSource
                then pure (repoRoot paths)
                else pure (takeDirectory trimmedSource)
        Left _ -> pure (repoRoot paths)

-- | Detect whether 'paths' was discovered from the baked Linux outer-
-- container host manifest (the one shipped with the launcher image)
-- versus a unit-test fixture or operator-edited manifest. The
-- docker-inspect host-path translation only fires for the fully-baked
-- profile; tests + operator-overridden manifests are taken verbatim.
-- The check compares 'repoRoot', 'kindRoot', and 'dataRoot'
-- simultaneously: a unit test that synthesises a fixture overrides
-- @kindRoot@ + @dataRoot@ to point at the test sandbox, which falls
-- out of this check.
isBakedLinuxOuterContainerManifest :: Paths -> Bool
isBakedLinuxOuterContainerManifest paths =
  Config.controlPlaneContext paths == OuterContainer
    && repoRoot paths == "/workspace"
    && kindRoot paths == "/workspace/.data/runtime/kind"
    && dataRoot paths == "/workspace/.data"

resolveHostRepoPath :: Paths -> FilePath -> IO FilePath
resolveHostRepoPath paths containerPath = do
  hostRepoRoot <- resolveHostRepoRoot paths
  let normalizedRepoRoot = normalise (repoRoot paths)
      normalizedContainerPath = normalise containerPath
      repoRootPrefix = addTrailingPathSeparator normalizedRepoRoot
  pure (resolveHostRepoPathFromNormalized hostRepoRoot normalizedRepoRoot repoRootPrefix normalizedContainerPath)

resolveHostRepoPathFromNormalized :: FilePath -> FilePath -> FilePath -> FilePath -> FilePath
resolveHostRepoPathFromNormalized hostRepoRoot normalizedRepoRoot repoRootPrefix normalizedContainerPath
  | normalizedContainerPath == normalizedRepoRoot = hostRepoRoot
  | otherwise =
      case List.stripPrefix repoRootPrefix normalizedContainerPath of
        Just relativePath -> hostRepoRoot </> relativePath
        Nothing -> normalizedContainerPath

renderKindConfig :: Paths -> RuntimeMode -> Int -> Int -> Int -> FilePath -> FilePath -> Bool -> String
renderKindConfig paths runtimeMode edgePortValue harborPortValue pulsarHttpPortValue hostKindRoot registryHostsDirectory usesHostBindMounts =
  unlines (preamble <> containerdConfigPatchesBlock <> ["nodes:"] <> nodeBlock "control-plane" initLabels edgePortLines <> workerNodeBlocks)
  where
    preamble =
      [ "kind: Cluster",
        "apiVersion: kind.x-k8s.io/v1alpha4",
        "name: " <> kindClusterName paths runtimeMode,
        "networking:",
        "  apiServerAddress: \"127.0.0.1\""
      ]
    -- Phase 3 follow-on (2026-05-29): enable containerd's
    -- hosts.toml-driven registry resolution so each Kind node treats
    -- /etc/containerd/certs.d/<namespace>/hosts.toml as the authoritative
    -- mapping for that namespace. Without this, containerd ignores the
    -- registry-hosts files we mount via extraMounts and kubelet dials
    -- @localhost:<harborPort>@ literally inside the node, which has
    -- nothing listening and refuses the connection. Kind 0.31 does not
    -- emit @config_path@ by default; the patch matches what
    -- @writeRegistryHostsConfig@ already provisions under
    -- @\/etc\/containerd\/certs.d@.
    containerdConfigPatchesBlock =
      [ "containerdConfigPatches:",
        "  - |-",
        "    [plugins.\"io.containerd.grpc.v1.cri\".registry]",
        "      config_path = \"/etc/containerd/certs.d\""
      ]
    initLabels = controlPlaneRuntimeModeLabels runtimeMode
    workerLabels = runtimeModeLabels runtimeMode
    workerNodeBlocks =
      concat (replicate (kindWorkerCount runtimeMode) (nodeBlock "worker" workerLabels []))
    edgePortLines =
      [ "    extraPortMappings:",
        "      - containerPort: 30090",
        "        hostPort: " <> show edgePortValue,
        "        listenAddress: \"127.0.0.1\"",
        "        protocol: TCP",
        "      - containerPort: 30002",
        "        hostPort: " <> show harborPortValue,
        "        listenAddress: \"127.0.0.1\"",
        "        protocol: TCP",
        "      - containerPort: 30011",
        "        hostPort: 30011",
        "        listenAddress: \"127.0.0.1\"",
        "        protocol: TCP",
        "      - containerPort: 30080",
        "        hostPort: " <> show pulsarHttpPortValue,
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
      | usesHostBindMounts =
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

kindWorkerCount :: RuntimeMode -> Int
kindWorkerCount runtimeMode =
  case runtimeMode of
    LinuxCpu -> 2
    _ -> 1

-- | Phase 2 Sprint 2.13: legacy host-repo-root env check
-- retired. The supported control-plane-context detector is the typed
-- @Paths.controlPlaneContext@ already derived from 'HostConfig'; no
-- env consultation is needed.
kindUsesHostBindMounts :: Paths -> RuntimeMode -> IO Bool
-- Linux outer-container runs can hand the host Docker daemon host-resolved paths, so Kind nodes
-- can mount retained state directly. Apple keeps explicit sync to avoid macOS uid/gid issues.
kindUsesHostBindMounts paths runtimeMode =
  case runtimeMode of
    AppleSilicon -> pure False
    _ -> pure (Config.controlPlaneContext paths == OuterContainer)

prepareKindNodeRuntimePaths :: Paths -> ClusterState -> RuntimeMode -> IO ()
prepareKindNodeRuntimePaths paths state runtimeMode = do
  let localKindRoot = kindRuntimeRoot paths runtimeMode
      controlPlaneNodeName = kindControlPlaneNodeName paths runtimeMode
  createDirectoryIfMissing True localKindRoot
  -- Phase 2 Sprint 2.13 follow-on (2026-05-29): scrub known
  -- non-retained service state from the local kind root before the
  -- bulk copy. Older binaries retained these trees on `cluster down`;
  -- the current retention contract excludes them so fresh service
  -- control planes are not replayed with stale backing data.
  scrubNonRetainedClusterDirectories paths runtimeMode
  nodeNames <- kindNodeNames paths runtimeMode
  mapM_
    ( primeNode
        localKindRoot
        controlPlaneNodeName
    )
    nodeNames
  where
    primeNode localKindRoot controlPlaneNodeName nodeName = do
      runHostToolCmd paths Nothing [] HostDocker ["exec", nodeName, "mkdir", "-p", nodeMountedKindRoot]
      -- Stateful platform workloads schedule on worker nodes, so replay retained runtime data only
      -- there instead of copying large claim trees into the tainted control-plane node.
      unless (nodeName == controlPlaneNodeName) $ do
        copyState <-
          startLifecyclePhase
            paths
            state
            "cluster-up"
            "prepare-kind-cluster"
            ("syncing retained Kind runtime data into " <> nodeName)
        copyDirectoryContentsToContainer paths (Just copyState) localKindRoot nodeName nodeMountedKindRoot

primeKindNodeRegistryHosts :: Paths -> RuntimeMode -> Int -> IO ()
primeKindNodeRegistryHosts paths runtimeMode harborPortValue = do
  let namespaceDirName = "localhost:" <> show harborPortValue
      registryDirectoryInNode = "/etc/containerd/certs.d/" <> namespaceDirName
      registryHostsPath = localRegistryHostsRoot paths runtimeMode </> namespaceDirName </> "hosts.toml"
  registryHostsContents <- readFile registryHostsPath
  nodeNames <- kindNodeNames paths runtimeMode
  mapM_ (primeNode registryDirectoryInNode registryHostsContents) nodeNames
  where
    primeNode registryDirectoryInNode registryHostsContents nodeName = do
      runHostToolCmd paths Nothing [] HostDocker ["exec", nodeName, "mkdir", "-p", registryDirectoryInNode]
      runCommandWithInput
        Nothing
        []
        "docker"
        ["exec", "-i", nodeName, "cp", "/dev/stdin", registryDirectoryInNode </> "hosts.toml"]
        registryHostsContents

-- | Phase 2 Sprint 2.13 follow-on (2026-05-29): defensively remove
-- any retained Patroni directory trees from the on-host kind root
-- before the next cluster up's bulk replay copies them into the
-- worker. The Patroni claim directories live at
-- @<kindRuntimeRoot>/platform/infernix/<workload>/...@ for the known
-- operator-managed PostgreSQL clusters (Harbor + Keycloak).
scrubStalePatroniDirectories :: Paths -> RuntimeMode -> IO ()
scrubStalePatroniDirectories paths runtimeMode =
  mapM_ scrubDirectory patroniWorkloadDirectories
  where
    patroniWorkloadDirectories =
      [ "platform" </> "infernix" </> name
      | name <-
          [ "harbor-postgresql-instance1",
            "harbor-postgresql-pgbackrest",
            "keycloak-postgresql-instance1",
            "keycloak-postgresql-pgbackrest"
          ]
      ]
    scrubDirectory relativePath = do
      let absolutePath = kindRuntimeRoot paths runtimeMode </> relativePath
      directoryPresent <- doesDirectoryExist absolutePath
      when directoryPresent (removePathForcibly absolutePath)

scrubNonRetainedClusterDirectories :: Paths -> RuntimeMode -> IO ()
scrubNonRetainedClusterDirectories paths runtimeMode = do
  scrubStalePatroniDirectories paths runtimeMode
  scrubRetainedHarborRegistryCache paths runtimeMode
  scrubRetainedHarborRegistryStorage paths runtimeMode

-- Harbor's registry Redis claim is rebuildable cache state. Retaining it
-- while the registry bucket and Harbor database are reset can leave blob
-- existence keys for content that no longer exists in MinIO, causing
-- later `docker push` attempts to skip uploads and fail the final
-- manifest write with "blob ... not found".
scrubRetainedHarborRegistryCache :: Paths -> RuntimeMode -> IO ()
scrubRetainedHarborRegistryCache paths runtimeMode = do
  let redisRoot = kindRuntimeRoot paths runtimeMode </> "platform" </> "infernix" </> "harbor-redis"
  directoryPresent <- doesDirectoryExist redisRoot
  when directoryPresent (removePathForcibly redisRoot)

-- Harbor's registry bucket is a rebuildable publication cache. The
-- model, engine-artifact, and demo object buckets stay durable, but
-- the Harbor database and Redis cache are recreated with the
-- non-retained state above;
-- carrying old registry blobs or incomplete multipart upload metadata
-- across that reset can leave the fresh registry pointing at incomplete
-- or missing blobs during `docker push`.
scrubRetainedHarborRegistryStorage :: Paths -> RuntimeMode -> IO ()
scrubRetainedHarborRegistryStorage paths runtimeMode = do
  let minioRoot = kindRuntimeRoot paths runtimeMode </> "platform" </> "infernix" </> "minio"
  minioPresent <- doesDirectoryExist minioRoot
  when minioPresent $ do
    ordinalNames <- listDirectory minioRoot
    forM_ ordinalNames $ \ordinalName -> do
      let dataRoot = minioRoot </> ordinalName </> "data"
      scrubDirectory (dataRoot </> "harbor-registry")
      scrubDirectory (dataRoot </> ".minio.sys" </> "buckets" </> "harbor-registry")
      scrubDirectory (dataRoot </> ".minio.sys" </> "multipart")
      scrubDirectory (dataRoot </> ".minio.sys" </> "tmp")
  where
    scrubDirectory absolutePath = do
      directoryPresent <- doesDirectoryExist absolutePath
      when directoryPresent (removePathForcibly absolutePath)

prepareKindNodeClaimDirectories :: Paths -> ClusterState -> RuntimeMode -> [PersistentClaim] -> IO ()
prepareKindNodeClaimDirectories paths _state runtimeMode persistentClaims = do
  nodeNames <- kindNodeNames paths runtimeMode
  mapM_ (prepareOnNode nodeNames) persistentClaims
  where
    prepareOnNode nodeNames persistentClaim =
      mapM_ (prepareOnSingleNode persistentClaim) nodeNames
    prepareOnSingleNode persistentClaim nodeName = do
      let directoryPath = nodeMountedClaimPath persistentClaim
      runHostToolCmd paths Nothing [] HostDocker ["exec", nodeName, "mkdir", "-p", directoryPath]
      runHostToolCmd paths Nothing [] HostDocker ["exec", nodeName, "chmod", "-R", "a+rwX", directoryPath]
      case claimOwner persistentClaim of
        Nothing -> pure ()
        Just owner -> runHostToolCmd paths Nothing [] HostDocker ["exec", nodeName, "chown", "-R", owner, directoryPath]

syncKindNodeRuntimePathsToHost :: Paths -> RuntimeMode -> Maybe ClusterState -> IO ()
syncKindNodeRuntimePathsToHost paths runtimeMode maybeState = do
  let localKindRoot = kindRuntimeRoot paths runtimeMode
  createDirectoryIfMissing True localKindRoot
  syncedClaims <- syncClaimDirectoriesWhenAvailable paths maybeState
  unless syncedClaims $ do
    nodeNames <- kindNodeNames paths runtimeMode
    mapM_
      ( \nodeName -> do
          maybeCopyState <-
            case maybeState of
              Just state ->
                Just
                  <$> startLifecyclePhase
                    paths
                    state
                    "cluster-down"
                    "replay-retained-state"
                    ("copying retained Kind runtime data from " <> nodeName <> " back to the host")
              Nothing -> pure Nothing
          copyDirectoryContentsFromContainer paths maybeCopyState nodeName nodeMountedKindRoot localKindRoot
      )
      nodeNames
  scrubNonRetainedClusterDirectories paths runtimeMode

syncClaimDirectoriesWhenAvailable :: Paths -> Maybe ClusterState -> IO Bool
syncClaimDirectoriesWhenAvailable paths maybeState =
  case maybeState of
    Just state | not (null (claims state)) -> syncClaimDirectoriesFromOwningNodes paths state
    _ -> pure False

-- | Phase 2 Sprint 2.13 follow-on (2026-05-29): operator-managed
-- Patroni Postgres claims are not retained across cluster lifecycles.
-- The Percona Operator recreates the cluster from scratch on each
-- `cluster up`, and the upstream chart + this binary reconcile the
-- demo Keycloak realm config separately. Retaining the partial
-- `/pgdata/pg18` tree from a previous interrupted run causes the
-- @postgres-startup@ init container in the new pod to crash on
-- invalid bootstrap state (surfaced by the 2026-05-29 Apple cohort
-- `infernix test all` integration replay).
isPatroniManagedClaim :: PersistentClaim -> Bool
isPatroniManagedClaim persistentClaim =
  let workloadName = Text.unpack (workload persistentClaim)
   in "harbor-postgresql-" `List.isPrefixOf` workloadName
        || "keycloak-postgresql-" `List.isPrefixOf` workloadName

syncClaimDirectoriesFromOwningNodes :: Paths -> ClusterState -> IO Bool
syncClaimDirectoriesFromOwningNodes paths state = do
  claimNodeBindings <- discoverClaimNodeBindings state
  let retainedClaims = filter (not . isPatroniManagedClaim) (claims state)
  claimSyncResults <-
    mapM
      (\persistentClaim -> syncClaimDirectoryFromOwningNode paths state persistentClaim claimNodeBindings)
      retainedClaims
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
  pure (either (const Map.empty) parseClaimNodeBindings result)
  where
    claimNodeBindingsTemplate =
      "go-template={{range .items}}{{ $node := .spec.nodeName }}{{range .spec.volumes}}{{if .persistentVolumeClaim}}{{printf \"%s\\t%s\\n\" .persistentVolumeClaim.claimName $node}}{{end}}{{end}}{{end}}"

parseClaimNodeBindings :: String -> Map.Map String String
parseClaimNodeBindings output =
  Map.fromList (mapMaybe parseClaimNodeBindingLine (lines output))

syncClaimDirectoryFromOwningNode :: Paths -> ClusterState -> PersistentClaim -> Map.Map String String -> IO Bool
syncClaimDirectoryFromOwningNode paths state persistentClaim claimNodeBindings =
  case Map.lookup (persistentVolumeClaimName persistentClaim) claimNodeBindings of
    Nothing -> pure False
    Just nodeName -> do
      let containerDirectory = nodeMountedClaimPath persistentClaim
          localDirectory = claimDirectory paths (clusterRuntimeMode state) persistentClaim
      containerExists <- containerDirectoryExists paths nodeName containerDirectory
      if containerExists
        then do
          localDirectoryExists <- doesDirectoryExist localDirectory
          when localDirectoryExists (removePathForcibly localDirectory)
          createDirectoryIfMissing True localDirectory
          copyState <-
            startLifecyclePhase
              paths
              state
              "cluster-down"
              "replay-retained-state"
              ("copying claim " <> persistentVolumeClaimName persistentClaim <> " from " <> nodeName <> " back to the host")
          copyDirectoryContentsFromContainer paths (Just copyState) nodeName containerDirectory localDirectory
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

kindWorkerNodeNames :: Paths -> RuntimeMode -> IO [String]
kindWorkerNodeNames paths runtimeMode =
  filter (/= kindControlPlaneNodeName paths runtimeMode) <$> kindNodeNames paths runtimeMode

copyDirectoryContentsToContainer :: Paths -> Maybe ClusterState -> FilePath -> String -> FilePath -> IO ()
copyDirectoryContentsToContainer paths maybeState localDirectory nodeName containerDirectory = do
  hasEntries <- directoryHasEntries localDirectory
  when hasEntries $
    case maybeState of
      Just state ->
        runCommandMonitored
          paths
          state
          Nothing
          []
          "docker"
          ["cp", localDirectory </> ".", nodeName <> ":" <> containerDirectory]
      Nothing ->
        runCommand
          Nothing
          []
          "docker"
          ["cp", localDirectory </> ".", nodeName <> ":" <> containerDirectory]

copyDirectoryContentsFromContainer :: Paths -> Maybe ClusterState -> String -> FilePath -> FilePath -> IO ()
copyDirectoryContentsFromContainer paths maybeState nodeName containerDirectory localDirectory = do
  hasEntries <- containerDirectoryHasEntries paths nodeName containerDirectory
  when hasEntries $
    case maybeState of
      Just state ->
        runCommandMonitored
          paths
          state
          Nothing
          []
          "docker"
          ["cp", (nodeName <> ":" <> containerDirectory) </> ".", localDirectory]
      Nothing ->
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

containerDirectoryHasEntries :: Paths -> String -> FilePath -> IO Bool
containerDirectoryHasEntries paths nodeName directory = do
  result <- tryHostToolCmd paths Nothing [] HostDocker ["exec", nodeName, "sh", "-lc", "ls -A " <> directory]
  pure (either (const False) directoryListingHasEntries result)

directoryListingHasEntries :: String -> Bool
directoryListingHasEntries output =
  not (all (all isSpace) (lines output))

containerDirectoryExists :: Paths -> String -> FilePath -> IO Bool
containerDirectoryExists paths nodeName directory = do
  result <- tryHostToolCmd paths Nothing [] HostDocker ["exec", nodeName, "sh", "-lc", "test -d " <> directory]
  pure (either (const False) (const True) result)

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
currentKindEdgePort paths runtimeMode = currentKindContainerPort paths runtimeMode "30090/tcp"

-- | Phase 3 follow-on (2026-05-29): the Harbor-facing Kind hostPort
-- mapping is now dynamic. When the cluster already exists, the
-- supported reconcile honors the port the existing Kind container is
-- actually publishing rather than re-using a stale persisted value,
-- so the binary's Harbor health probe + publication path target the
-- same address operators see from the host.
currentKindHarborPort :: Paths -> RuntimeMode -> IO (Maybe Int)
currentKindHarborPort paths runtimeMode = currentKindContainerPort paths runtimeMode "30002/tcp"

currentKindPulsarHttpPort :: Paths -> RuntimeMode -> IO (Maybe Int)
currentKindPulsarHttpPort paths runtimeMode = currentKindContainerPort paths runtimeMode "30080/tcp"

currentKindContainerPort :: Paths -> RuntimeMode -> String -> IO (Maybe Int)
currentKindContainerPort paths runtimeMode containerSpec = do
  result <- tryHostToolCmd paths Nothing [] HostDocker ["port", kindClusterName paths runtimeMode <> "-control-plane", containerSpec]
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

-- | Phase 2 Sprint 2.13: @engineCommandOverridesFromEnvironment@
-- retired. The Sprint 4.13 chart no longer renders per-binding
-- @INFERNIX_ENGINE_COMMAND_*@ env entries; engine command overrides
-- now flow through the typed @ClusterConfig.engine.commandOverrides@
-- field instead. The Helm values file therefore always renders an
-- empty override list at this layer (operators set overrides via the
-- top-level @clusterConfig.engine@ block in @chart/values.yaml@,
-- which feeds the cluster-config ConfigMap directly).
writeHelmValuesFile :: Paths -> ControlPlaneContext -> ClusterState -> Lazy.ByteString -> HelmDeployPhase -> IO FilePath
writeHelmValuesFile paths controlPlane state demoConfigPayload deployPhase = do
  let outputPath =
        buildRoot paths
          </> ("helm-values-" <> phaseSuffix deployPhase <> "-" <> Text.unpack (runtimeModeId (clusterRuntimeMode state)) <> ".yaml")
  writeFile outputPath (renderHelmValues paths controlPlane state demoConfigPayload deployPhase [])
  pure outputPath
  where
    phaseSuffix phaseValue = case phaseValue of
      WarmupPhase -> "warmup"
      BootstrapPhase -> "bootstrap"
      HarborFinalPhase -> "harbor-final"
      FinalPhase -> "final"

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

renderHelmValues :: Paths -> ControlPlaneContext -> ClusterState -> Lazy.ByteString -> HelmDeployPhase -> [(String, String)] -> String
renderHelmValues paths controlPlane state demoConfigPayload deployPhase engineCommandOverrides =
  unlines
    ( [ "runtimeMode: " <> Text.unpack (runtimeModeId (clusterRuntimeMode state)),
        "controlPlaneContext: " <> show (controlPlaneContextId controlPlane),
        "gateway:",
        "  publishedPort: " <> show (edgePort state),
        "  publishedNodePort: 30090",
        "  listenerPort: 80",
        -- Phase 3 follow-on (2026-05-29): Harbor's @externalURL@ in
        -- the chart references the dynamically chosen host-side port
        -- so Harbor's own redirect responses point clients at the
        -- same address the binary's publication path and the
        -- containerd registry-hosts namespace use.
        "harbor:",
        "  externalURL: \"http://localhost:" <> show (harborPort state) <> "\"",
        "demoConfig:",
        "  fileName: infernix-substrate.dhall",
        "  catalogPayload: |",
        indentBlock 4 (LazyChar8.unpack demoConfigPayload),
        "demo:",
        "  enabled: " <> yamlBool demoUiEnabledValue,
        "  replicaCount: " <> show (repoWorkloadReplicaCount deployPhase),
        "  port: 8080",
        "  image:",
        "    repository: " <> clusterWorkloadImageRepository (clusterRuntimeMode state),
        "    tag: local",
        "    pullPolicy: IfNotPresent",
        "publication:",
        "  payloadJson: |",
        indentBlock 4 (renderPublicationState controlPlane state),
        -- Phase 7 Sprint 7.7: the supported three-role daemon split
        -- replaces the legacy `service.*` Deployment. The split workloads
        -- depend on Pulsar (`coordinator` consumes inference-request
        -- topics, runs the bootstrap subscription, and registers schemas)
        -- so we hold their replica counts at zero until `FinalPhase`
        -- brings the upstream Pulsar chart up. `demo.replicaCount` was
        -- already phase-gated for the same reason.
        "coordinator:",
        "  enabled: " <> yamlBool demoUiEnabledValue,
        "  replicaCount: " <> show (repoCoordinatorReplicaCount deployPhase),
        "  image:",
        "    repository: " <> clusterWorkloadImageRepository (clusterRuntimeMode state),
        "    tag: local",
        "    pullPolicy: IfNotPresent",
        "engine:",
        "  replicaCount: " <> show (repoEngineReplicaCount deployPhase),
        "  image:",
        "    repository: " <> clusterWorkloadImageRepository (clusterRuntimeMode state),
        "    tag: local",
        "    pullPolicy: IfNotPresent",
        "  perEngine:",
        "    enabled: " <> yamlBool (not (null perEngineNames)),
        "    replicaCount: " <> show (repoPerEngineReplicaCount deployPhase),
        "    names:",
        renderYamlStringList 6 (map Text.unpack perEngineNames),
        "    images:"
      ]
        <> perEngineImageValueLines
        <> routeHelmValues demoUiEnabledValue
        <> unsupportedMonitoringOverrides
        <> serviceEngineAdapterOverrides
        <> phaseChartOverrides deployPhase
        <> bootstrapHarborOverrides deployPhase
    )
  where
    demoUiEnabledValue = clusterStateHasDemoUi state
    perEngineNames = perEngineDeploymentNames (clusterRuntimeMode state)
    perEngineImageValueLines =
      if null perEngineNames
        then ["      {}"]
        else concatMap perEngineImageLines perEngineNames
    perEngineImageLines engineName =
      [ "      " <> Text.unpack engineName <> ":",
        "        repository: " <> Text.unpack (perEngineImageRepository (clusterRuntimeMode state) engineName),
        "        tag: local",
        "        pullPolicy: IfNotPresent"
      ]

    repoWorkloadReplicaCount :: HelmDeployPhase -> Int
    repoWorkloadReplicaCount phaseValue = case phaseValue of
      WarmupPhase -> 0
      BootstrapPhase -> 0
      HarborFinalPhase -> 0
      FinalPhase -> 2
    -- Phase 7 Sprint 7.7: zero out the coordinator + engine roles in
    -- every pre-Pulsar phase, then come up with the supported supported
    -- HA replicaCount (coordinator >= 2 for stateless coordination;
    -- linux-cpu engines run at 2 on the two-worker CPU validation
    -- lane; linux-gpu stays at 1 for single-GPU hosts).
    repoCoordinatorReplicaCount :: HelmDeployPhase -> Int
    repoCoordinatorReplicaCount phaseValue = case phaseValue of
      WarmupPhase -> 0
      BootstrapPhase -> 0
      HarborFinalPhase -> 0
      FinalPhase -> 2
    -- On Apple Silicon the engine role runs host-native (the same-binary
    -- host daemon launched from `./.build/infernix`); the cluster substrate
    -- must not deploy an in-cluster engine pod because it would compete with
    -- host engine members for the same Metal-backed work.
    -- Linux substrates keep the in-cluster engine deployment.
    repoEngineReplicaCount :: HelmDeployPhase -> Int
    repoEngineReplicaCount phaseValue = case (phaseValue, clusterRuntimeMode state) of
      (WarmupPhase, _) -> 0
      (BootstrapPhase, _) -> 0
      (HarborFinalPhase, _) -> 0
      (FinalPhase, AppleSilicon) -> 0
      (FinalPhase, LinuxCpu) -> 2
      (FinalPhase, _) -> 1
    -- Phase 4 Sprint 4.17 follow-on (2026-06-11): the repo-owned
    -- linux-gpu lifecycle targets the documented single-worker,
    -- single-GPU Kind lane. The static chart still supports explicit
    -- per-engine replicas for operator-provided multi-GPU values, but the
    -- generated lifecycle values keep those deployments at zero replicas
    -- so the normal final-phase Helm wait does not require every framework
    -- image to hold the one GPU concurrently. Integration and Playwright
    -- validation scale one per-engine deployment at a time when proving the
    -- routed per-engine topics.
    repoPerEngineReplicaCount :: HelmDeployPhase -> Int
    repoPerEngineReplicaCount phaseValue = case (phaseValue, clusterRuntimeMode state) of
      (WarmupPhase, _) -> 0
      (BootstrapPhase, _) -> 0
      (HarborFinalPhase, _) -> 0
      (FinalPhase, LinuxGpu) -> 0
      (FinalPhase, _) -> 1
    renderYamlStringList indent values =
      case values of
        [] -> replicate indent ' ' <> "[]"
        _ -> unlines (map (\value -> replicate indent ' ' <> "- " <> value) values)
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
      FinalPhase -> finalChartOverrides
    finalChartOverrides =
      [ "upstreamCharts:",
        "  keycloakpg:",
        "    enabled: " <> yamlBool demoUiEnabledValue,
        "keycloak:",
        "  enabled: " <> yamlBool demoUiEnabledValue
      ]
        <> [ "  externalBaseUrl: " <> clusterEdgeBaseUrl paths state <> "/auth"
           | demoUiEnabledValue
           ]
        <> if demoUiEnabledValue
          then
            [ "clusterConfig:",
              "  minio:",
              "    presignPublicEndpoint: " <> clusterEdgeBaseUrl paths state <> "/minio/s3",
              "  keycloak:",
              "    baseUrl: " <> clusterEdgeBaseUrl paths state <> "/auth",
              "    clientId: " <> keycloakSpaClientId,
              "    jwksUrl: http://infernix-keycloak.platform.svc.cluster.local:8080/auth/realms/"
                <> keycloakRealmName
                <> "/protocol/openid-connect/certs"
            ]
          else []
    preFinalChartOverrides envoyGatewayEnabled =
      [ "upstreamCharts:",
        "  harbor:",
        "    enabled: true",
        "  postgresOperator:",
        "    enabled: true",
        "  harborpg:",
        "    enabled: true",
        -- Phase 7 Sprint 7.1: gate the Keycloak Patroni cluster the
        -- same way Pulsar is gated. Pre-final phases bring up Harbor +
        -- its Patroni backend; the demo-only Keycloak + its Patroni
        -- backend only roll out in FinalPhase. Otherwise the warmup
        -- helm-install can hang for 30m on the Keycloak Deployment
        -- post-install readiness probe while waiting for its Patroni
        -- replicas to come up alongside Harbor's.
        "  keycloakpg:",
        "    enabled: false",
        "  minio:",
        "    enabled: true",
        "  pulsar:",
        "    enabled: false",
        "  envoyGateway:",
        "    enabled: " <> yamlBool envoyGatewayEnabled,
        "repoGateway:",
        "  enabled: false",
        "keycloak:",
        "  externalBaseUrl: " <> clusterEdgeBaseUrl paths state <> "/auth",
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

-- | Phase 3 follow-on (2026-05-29): the host-side variant honors the
-- dynamic Harbor port chosen by 'chooseHarborPort' (passed in from
-- 'ClusterState.harborPort'). The outer-container variant stays on
-- the fixed in-cluster NodePort because in-cluster wiring is
-- independent of the operator's host port allocations.
harborApiHost :: Paths -> RuntimeMode -> Int -> String
harborApiHost paths runtimeMode harborPortValue
  | Config.controlPlaneContext paths == OuterContainer = kindControlPlaneNodeName paths runtimeMode <> ":30002"
  | otherwise = "127.0.0.1:" <> show harborPortValue

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
  | Config.controlPlaneContext paths == OuterContainer = kindControlPlaneNodeName paths (clusterRuntimeMode state)
  | otherwise = "127.0.0.1"

clusterEdgePort :: Paths -> ClusterState -> Int
clusterEdgePort paths state
  | Config.controlPlaneContext paths == OuterContainer = 30090
  | otherwise = edgePort state

-- | Capture kubectl output for helpers that only carry 'ClusterState'.
-- The shared command helpers resolve the literal @"kubectl"@ through
-- the staged host manifest before spawning, so these state-only call
-- sites stay on the HostTool path without widening every helper
-- signature to carry 'Paths'.
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

perEngineDeploymentNames :: RuntimeMode -> [Text.Text]
perEngineDeploymentNames runtimeMode =
  case runtimeMode of
    LinuxGpu -> frameworkEngineNamesForMode runtimeMode
    _ -> []

-- | Phase 3 Sprint 3.12: select the native container architecture for
-- cluster workloads. Apple remains arm64, linux-gpu remains amd64
-- because CUDA arm64 is not a supported substrate, and linux-cpu uses
-- the typed host architecture from `InfernixHost.dhall`.
resolveClusterWorkloadArchitecture :: Paths -> RuntimeMode -> IO String
resolveClusterWorkloadArchitecture paths runtimeMode =
  case clusterWorkloadArchitectureForHostArchitecture runtimeMode (hostArchitectureForPaths paths) of
    Right architecture -> pure architecture
    Left message -> ioError (userError message)

clusterWorkloadArchitectureForHostArchitecture :: RuntimeMode -> Text.Text -> Either String String
clusterWorkloadArchitectureForHostArchitecture runtimeMode hostArchitecture =
  case runtimeMode of
    AppleSilicon -> Right "arm64"
    LinuxGpu -> Right "amd64"
    LinuxCpu ->
      case Text.unpack (HostConfig.normalizeHostArchitecture hostArchitecture) of
        "amd64" -> Right "amd64"
        "arm64" -> Right "arm64"
        unsupported ->
          Left
            ( "Unsupported native host architecture for linux-cpu publication: "
                <> unsupported
                <> ". Supported linux-cpu hosts are native linux/amd64 and linux/arm64."
            )

hostArchitectureForPaths :: Paths -> Text.Text
hostArchitectureForPaths paths =
  case pathsHostConfig paths of
    Just hostConfig -> HostConfig.hostArchitecture hostConfig
    Nothing -> HostConfig.normalizeHostArchitecture (Text.pack System.Info.arch)

deleteKindCluster :: Paths -> RuntimeMode -> IO ()
deleteKindCluster paths runtimeMode = go (3 :: Int) ""
  where
    commandArgs = ["delete", "cluster", "--name", kindClusterName paths runtimeMode]
    commandLabel = "kind " <> unwords commandArgs

    go remainingAttempts lastError = do
      result <- withKindScratchKubeconfig paths runtimeMode $ \scratchKubeconfig ->
        tryCommand
          Nothing
          [("KUBECONFIG", scratchKubeconfig)]
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

-- | Phase 2 Sprint 2.13 — resolve an external tool's absolute path via
-- the staged host manifest when 'pathsHostConfig' is present. When the
-- manifest is absent (first-run bootstrap, unit tests without a
-- fixture), the bare tool name is returned and the caller's @env =
-- 'clusterSubprocessBaseEnv'@ supplies the supported minimal @PATH@.
-- Either way, the bare-name @proc "<command>"@ lint gate stays happy
-- because the lookup is typed.
resolveHostToolForCluster :: Paths -> HostTool -> FilePath
resolveHostToolForCluster paths tool =
  case pathsHostConfig paths of
    Just config ->
      let candidate = HostTools.hostToolPath config tool
       in if Text.null candidate
            then Text.unpack (HostTools.hostToolName tool)
            else Text.unpack candidate
    Nothing -> Text.unpack (HostTools.hostToolName tool)

-- | Run a typed 'HostTool' invocation. Wraps 'runCommand' after
-- resolving the absolute path through 'resolveHostToolForCluster'.
runHostToolCmd :: Paths -> Maybe FilePath -> [(String, String)] -> HostTool -> [String] -> IO ()
runHostToolCmd paths maybeWorkingDirectory envOverrides tool =
  runCommand maybeWorkingDirectory envOverrides (resolveHostToolForCluster paths tool)

-- | 'tryCommand' variant that takes a typed 'HostTool'.
tryHostToolCmd :: Paths -> Maybe FilePath -> [(String, String)] -> HostTool -> [String] -> IO (Either String String)
tryHostToolCmd paths maybeWorkingDirectory envOverrides tool =
  tryCommand maybeWorkingDirectory envOverrides (resolveHostToolForCluster paths tool)

-- | 'captureCommand' variant that takes a typed 'HostTool'.
captureHostToolCmd :: Paths -> Maybe FilePath -> [(String, String)] -> HostTool -> [String] -> IO String
captureHostToolCmd paths maybeWorkingDirectory envOverrides tool =
  captureCommand maybeWorkingDirectory envOverrides (resolveHostToolForCluster paths tool)

runCommand :: Maybe FilePath -> [(String, String)] -> FilePath -> [String] -> IO ()
runCommand maybeWorkingDirectory envOverrides command args = do
  result <- tryCommand maybeWorkingDirectory envOverrides command args
  case result of
    Right _ -> pure ()
    Left err ->
      ioError (userError ("command failed: " <> command <> " " <> unwords args <> "\n" <> err))

-- | Phase 2 Sprint 2.13: @getEnvironment@ whole-env capture retired.
-- The supported subprocess invocation uses a fixed minimal env
-- ('clusterSubprocessBaseEnv') plus the caller-supplied
-- @envOverrides@; nothing inherits from the daemon's @environ@. Any
-- value the spawned process needs must be declared explicitly here
-- or in 'envOverrides'.
runCommandWithInput :: Maybe FilePath -> [(String, String)] -> FilePath -> [String] -> String -> IO ()
runCommandWithInput maybeWorkingDirectory envOverrides command args inputPayload = do
  paths <- Config.discoverPaths
  let resolvedCommand = resolveClusterCommandWithPaths paths command
      mergedEnv = mergeEnvironment (clusterSubprocessBaseEnvFor paths) envOverrides
  (exitCode, _, stderrOutput) <-
    readCreateProcessWithExitCode
      (proc resolvedCommand args)
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
  paths <- Config.discoverPaths
  let resolvedCommand = resolveClusterCommandWithPaths paths command
      mergedEnv = mergeEnvironment (clusterSubprocessBaseEnvFor paths) envOverrides
  processResult <-
    try
      ( readCreateProcessWithExitCode
          (proc resolvedCommand args)
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

-- | Phase 2 Sprint 2.13 + Phase 7 Sprint 7.17 Apple cohort closure
-- (2026-05-29): the supported base env for every cluster lifecycle
-- subprocess. The PATH entry is derived from the staged host
-- manifest's @toolPaths@ when present so nested third-party
-- invocations (most importantly @kind@ shelling out to @docker@) can
-- locate the same absolute binaries the binary itself uses, including
-- Apple Silicon Homebrew's @\/opt\/homebrew\/bin@ prefix. When the
-- manifest is absent (unit-test fixture without a 'HostConfig'), the
-- helper falls back to the minimal POSIX PATH.
clusterSubprocessBaseEnvFor :: Paths -> [(String, String)]
clusterSubprocessBaseEnvFor paths =
  [ ("PATH", subprocessSearchPath paths),
    ("LANG", "C.UTF-8"),
    ("LC_ALL", "C.UTF-8")
  ]

subprocessSearchPath :: Paths -> String
subprocessSearchPath paths =
  let fallback =
        [ "/usr/local/sbin",
          "/usr/local/bin",
          "/usr/sbin",
          "/usr/bin",
          "/sbin",
          "/bin"
        ]
      manifestDirs = maybe [] hostToolParentDirs (pathsHostConfig paths)
   in List.intercalate ":" (List.nub (manifestDirs <> fallback))

hostToolParentDirs :: HostConfig.HostConfig -> [FilePath]
hostToolParentDirs config =
  let allTools =
        [ HostDocker,
          HostKubectl,
          HostHelm,
          HostKind,
          HostCurl,
          HostTar,
          HostBash,
          HostSkopeo,
          HostHostname,
          HostChown,
          HostNvidiaSmi,
          HostNvkind,
          HostCrictl
        ]
      pathFor tool = Text.unpack (HostTools.hostToolPath config tool)
      absoluteEntries =
        [ takeDirectory entry
        | tool <- allTools,
          let entry = pathFor tool,
          not (null entry)
        ]
   in List.nub absoluteEntries

captureCommand :: Maybe FilePath -> [(String, String)] -> FilePath -> [String] -> IO String
captureCommand maybeWorkingDirectory envOverrides command args = do
  result <- tryCommand maybeWorkingDirectory envOverrides command args
  case result of
    Right stdoutOutput -> pure stdoutOutput
    Left err ->
      ioError (userError ("command failed: " <> command <> " " <> unwords args <> "\n" <> err))

resolveClusterCommandWithPaths :: Paths -> FilePath -> FilePath
resolveClusterCommandWithPaths paths command =
  case hostToolForClusterCommand command of
    Just tool -> resolveHostToolForCluster paths tool
    Nothing -> command

hostToolForClusterCommand :: FilePath -> Maybe HostTool
hostToolForClusterCommand command =
  case command of
    "docker" -> Just HostDocker
    "kubectl" -> Just HostKubectl
    "helm" -> Just HostHelm
    "kind" -> Just HostKind
    "curl" -> Just HostCurl
    "tar" -> Just HostTar
    "chown" -> Just HostChown
    "hostname" -> Just HostHostname
    "nvidia-smi" -> Just HostNvidiaSmi
    "nvkind" -> Just HostNvkind
    "skopeo" -> Just HostSkopeo
    "bash" -> Just HostBash
    _ -> Nothing

mergeEnvironment :: [(String, String)] -> [(String, String)] -> [(String, String)]
mergeEnvironment baseEnv overrides =
  overrides <> filter (\(key, _) -> key `notElem` map fst overrides) baseEnv

normalizeKubeconfigServer :: ControlPlaneContext -> String -> String
normalizeKubeconfigServer _controlPlane kubeconfigContents = kubeconfigContents

ensureOuterContainerKindNetworkAccess :: Paths -> RuntimeMode -> IO ()
ensureOuterContainerKindNetworkAccess paths _runtimeMode
  | Config.controlPlaneContext paths /= OuterContainer = pure ()
  | otherwise = do
      launcherContainer <- currentLauncherContainerName
      connectResult <- tryHostToolCmd paths Nothing [] HostDocker ["network", "connect", "kind", launcherContainer]
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

-- | Phase 2 Sprint 2.13: @HOSTNAME@ env read retired. The supported
-- launcher-id discovery now reads @/etc/hostname@ directly (Docker
-- writes the container id into this file on container start), falling
-- back to the @hostname@ binary only if the file cannot be read.
currentLauncherContainerName :: IO String
currentLauncherContainerName = do
  fileHostname <- readEtcHostnameMaybe
  case fileHostname of
    Just nameValue -> pure nameValue
    Nothing -> do
      hostnameOutput <- captureCommand Nothing [] "hostname" []
      let hostnameValue = trim hostnameOutput
      if null hostnameValue
        then ioError (userError "linux outer-container control plane could not determine its container id")
        else pure hostnameValue

-- | Phase 2 Sprint 2.13: read @/etc/hostname@ for the supported
-- in-container hostname discovery (Docker writes the container id
-- there at startup). Returns 'Nothing' on any read error so callers
-- can fall back to the @hostname@ binary.
readEtcHostnameMaybe :: IO (Maybe String)
readEtcHostnameMaybe = do
  result <- try (readFile "/etc/hostname") :: IO (Either IOException String)
  case result of
    Left _ -> pure Nothing
    Right contents ->
      let trimmed = trim contents
       in pure (if null trimmed then Nothing else Just trimmed)

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
  case suffix of
    [] -> [prefix]
    _ : rest -> prefix : splitTabs rest
  where
    (prefix, suffix) = break (== '\t') value

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
