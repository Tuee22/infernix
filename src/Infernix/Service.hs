module Infernix.Service
  ( activateHostBridgeRoute,
    restoreClusterServiceRoute,
    runService,
  )
where

import Control.Exception (finally)
import Control.Monad (when)
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Infernix.Cluster (loadClusterState)
import Infernix.Config
import Infernix.Models
  ( hostBridgeApiUpstream,
    renderPublicationState,
    renderPublicationStateWithApiUpstream,
  )
import Infernix.Storage (readEdgePortMaybe)
import Infernix.Types (ClusterState, RuntimeMode, clusterPresent, clusterRuntimeMode, kubeconfigPath, runtimeModeId)
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.Process (callProcess)

clusterServiceUpstreamRef :: String
clusterServiceUpstreamRef = "infernix-service.platform.svc.cluster.local:80"

defaultHostBridgePort :: Int
defaultHostBridgePort = 18081

runService :: Maybe RuntimeMode -> Maybe Int -> IO ()
runService maybeRuntimeMode maybePort = do
  paths <- discoverPaths
  ensureRepoLayout paths
  runtimeMode <- resolveRuntimeMode maybeRuntimeMode
  maybeState <- loadClusterState paths
  envPort <- lookupEnv "INFERNIX_PORT"
  maybeControlPlaneOverride <- lookupEnv "INFERNIX_CONTROL_PLANE_CONTEXT"
  maybeDaemonLocationOverride <- lookupEnv "INFERNIX_DAEMON_LOCATION"
  maybeCatalogSourceOverride <- lookupEnv "INFERNIX_CATALOG_SOURCE"
  maybeDemoConfigOverride <- lookupEnv "INFERNIX_DEMO_CONFIG_PATH"
  maybePublicationStateOverride <- lookupEnv "INFERNIX_PUBLICATION_STATE_PATH"
  maybeBindHostOverride <- lookupEnv "INFERNIX_BIND_HOST"
  maybeRouteProbeOverride <- lookupEnv "INFERNIX_ROUTE_PROBE_BASE_URL"
  edgePort <- readEdgePortMaybe paths
  generatedConfigExists <- doesFileExist (generatedDemoConfigPath paths runtimeMode)
  mountedConfigExists <- doesFileExist (watchedDemoConfigPath runtimeMode)
  let demoConfigPath = generatedDemoConfigPath paths runtimeMode
      publishedCatalogPath = publishedConfigMapCatalogPath paths runtimeMode
      mountedCatalogPath = watchedDemoConfigPath runtimeMode
      selectedDemoConfigPath =
        case maybeDemoConfigOverride of
          Just overridePath -> overridePath
          Nothing
            | mountedConfigExists -> mountedCatalogPath
            | generatedConfigExists -> demoConfigPath
            | otherwise -> publishedCatalogPath
      controlPlane = fromMaybe (controlPlaneContext paths) maybeControlPlaneOverride
      daemonLocation =
        fromMaybe
          ( case controlPlane of
              "host-native" -> "control-plane-host"
              _ -> "control-plane-container"
          )
          maybeDaemonLocationOverride
      bridgeActive = controlPlane == "host-native" && daemonLocation == "control-plane-host" && maybe False clusterPresent maybeState
      defaultBindHost
        | bridgeActive = "0.0.0.0"
        | otherwise = "127.0.0.1"
      bindHost = fromMaybe defaultBindHost maybeBindHostOverride
      defaultPort
        | bridgeActive = defaultHostBridgePort
        | otherwise = 8080
      port = fromMaybe (maybe defaultPort read envPort) maybePort
      catalogSource =
        fromMaybe
          ( case maybeDemoConfigOverride of
              Just _ -> "env-config-override"
              Nothing
                | mountedConfigExists -> "mounted-configmap"
                | generatedConfigExists -> "generated-build-root"
                | otherwise -> "published-configmap-mirror"
          )
          maybeCatalogSourceOverride
      publicationState = fromMaybe (publicationStatePath paths) maybePublicationStateOverride
      routeProbeBaseUrl =
        case maybeRouteProbeOverride of
          Just overrideValue -> Just overrideValue
          Nothing
            | daemonLocation == "cluster-pod" -> Just "http://infernix-edge.platform.svc.cluster.local"
            | bridgeActive ->
                fmap (\publishedEdgePort -> "http://127.0.0.1:" <> show publishedEdgePort) edgePort
            | otherwise -> Nothing
  ensureBridgeRuntimeMode maybeState runtimeMode bridgeActive
  putStrLn ("serviceControlPlaneContext: " <> controlPlane)
  putStrLn ("serviceDaemonLocation: " <> daemonLocation)
  putStrLn ("serviceCatalogSource: " <> catalogSource)
  putStrLn ("serviceRuntimeMode: " <> showRuntimeMode runtimeMode)
  putStrLn ("serviceDemoConfigPath: " <> selectedDemoConfigPath)
  putStrLn ("serviceMountedDemoConfigPath: " <> mountedCatalogPath)
  let launchService =
        callProcess
          "python3"
          ( serviceServerArgs
              paths
              bindHost
              port
              runtimeMode
              controlPlane
              daemonLocation
              catalogSource
              selectedDemoConfigPath
              mountedCatalogPath
              publicationState
              routeProbeBaseUrl
          )
  if bridgeActive
    then do
      activateHostBridgeRoute paths runtimeMode port
      launchService `finally` restoreClusterServiceRoute paths
    else launchService

activateHostBridgeRoute :: Paths -> RuntimeMode -> Int -> IO ()
activateHostBridgeRoute paths runtimeMode port = do
  maybeState <- loadClusterState paths
  ensureBridgeRuntimeMode maybeState runtimeMode True
  state <- requireActiveClusterState maybeState
  activateHostBridge paths state (publicationStatePath paths) port

restoreClusterServiceRoute :: Paths -> IO ()
restoreClusterServiceRoute paths = do
  maybeState <- loadClusterState paths
  case maybeState of
    Just state
      | clusterPresent state -> do
          writeFile (publicationStatePath paths) (renderPublicationState (controlPlaneContext paths) state)
          setEdgeServiceUpstream state clusterServiceUpstreamRef
    _ -> pure ()

activateHostBridge :: Paths -> ClusterState -> FilePath -> Int -> IO ()
activateHostBridge paths state publicationState port = do
  writeFile
    publicationState
    (renderPublicationStateWithApiUpstream (controlPlaneContext paths) state (hostBridgeApiUpstream port))
  setEdgeServiceUpstream state ("host.docker.internal:" <> show port)

setEdgeServiceUpstream :: ClusterState -> String -> IO ()
setEdgeServiceUpstream state upstreamRef = do
  let kubectlBaseArgs =
        [ "--kubeconfig",
          kubeconfigPath state,
          "-n",
          "platform"
        ]
  callProcess "kubectl" (kubectlBaseArgs <> ["set", "env", "deployment/infernix-edge", "INFERNIX_SERVICE_UPSTREAM=" <> upstreamRef])
  callProcess "kubectl" (kubectlBaseArgs <> ["rollout", "status", "deployment/infernix-edge", "--timeout=120s"])

serviceServerArgs ::
  Paths ->
  FilePath ->
  Int ->
  RuntimeMode ->
  String ->
  String ->
  String ->
  FilePath ->
  FilePath ->
  FilePath ->
  Maybe String ->
  [String]
serviceServerArgs paths bindHost port runtimeMode controlPlane daemonLocation catalogSource selectedDemoConfigPath mountedCatalogPath publicationState maybeRouteProbeBaseUrl =
  [ repoRoot paths </> "tools" </> "service_server.py",
    "--repo-root",
    repoRoot paths,
    "--host",
    bindHost,
    "--port",
    show port,
    "--runtime-mode",
    showRuntimeMode runtimeMode,
    "--control-plane-context",
    controlPlane,
    "--daemon-location",
    daemonLocation,
    "--catalog-source",
    catalogSource,
    "--demo-config",
    selectedDemoConfigPath,
    "--mounted-demo-config",
    mountedCatalogPath,
    "--publication-state",
    publicationState
  ]
    <> maybe [] (\baseUrl -> ["--route-probe-base-url", baseUrl]) maybeRouteProbeBaseUrl

ensureBridgeRuntimeMode :: Maybe ClusterState -> RuntimeMode -> Bool -> IO ()
ensureBridgeRuntimeMode maybeState runtimeMode bridgeActive =
  when bridgeActive $
    case maybeState of
      Just state
        | clusterRuntimeMode state /= runtimeMode ->
            ioError
              ( userError
                  ( "host-native service runtime mode "
                      <> showRuntimeMode runtimeMode
                      <> " does not match the active cluster runtime mode "
                      <> showRuntimeMode (clusterRuntimeMode state)
                  )
              )
      _ -> pure ()

requireActiveClusterState :: Maybe ClusterState -> IO ClusterState
requireActiveClusterState maybeState =
  case maybeState of
    Just state
      | clusterPresent state -> pure state
    _ -> ioError (userError "host bridge activation requires an active cluster state")

showRuntimeMode :: RuntimeMode -> String
showRuntimeMode = Text.unpack . runtimeModeId
