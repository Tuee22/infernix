{-# LANGUAGE OverloadedStrings #-}

module Infernix.Cluster
  ( clusterDown,
    clusterStatus,
    clusterUp,
    loadClusterState,
    runKubectlCompat,
  )
where

import Control.Concurrent (threadDelay)
import Control.Monad (forM_, unless, when)
import Data.ByteString.Lazy qualified as Lazy
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.Char (isSpace)
import Data.List qualified as List
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Infernix.Config (Paths (..))
import Infernix.Config qualified as Config
import Infernix.Models
import Infernix.Storage
import Infernix.Types
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory, removePathForcibly)
import System.Environment (getEnvironment, lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.Process
  ( CreateProcess (cwd, env),
    proc,
    readCreateProcessWithExitCode,
    readProcess,
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
    ("apachepulsar", "https://pulsar.apache.org/charts"),
    ("bitnami", "https://charts.bitnami.com/bitnami"),
    ("ingress-nginx", "https://kubernetes.github.io/ingress-nginx")
  ]

helmDependencyArchives :: [FilePath]
helmDependencyArchives =
  [ "chart/charts/harbor-1.18.3.tgz",
    "chart/charts/pulsar-4.5.0.tgz",
    "chart/charts/minio-17.0.21.tgz",
    "chart/charts/ingress-nginx-4.15.1.tgz"
  ]

finalPhaseDeployments :: [String]
finalPhaseDeployments =
  [ "deployment/infernix-edge",
    "deployment/infernix-harbor-core",
    "deployment/infernix-harbor-gateway",
    "deployment/infernix-harbor-jobservice",
    "deployment/infernix-harbor-nginx",
    "deployment/infernix-harbor-portal",
    "deployment/infernix-harbor-registry",
    "deployment/infernix-minio-console",
    "deployment/infernix-minio-gateway",
    "deployment/infernix-pulsar-gateway",
    "deployment/infernix-service",
    "deployment/infernix-web"
  ]

finalPhaseStatefulSets :: [String]
finalPhaseStatefulSets =
  [ "statefulset/infernix-harbor-database",
    "statefulset/infernix-harbor-redis",
    "statefulset/infernix-harbor-trivy",
    "statefulset/infernix-infernix-pulsar-bookie",
    "statefulset/infernix-infernix-pulsar-broker",
    "statefulset/infernix-infernix-pulsar-proxy",
    "statefulset/infernix-infernix-pulsar-recovery",
    "statefulset/infernix-infernix-pulsar-toolset",
    "statefulset/infernix-infernix-pulsar-zookeeper",
    "statefulset/infernix-minio"
  ]

data HelmDeployPhase
  = WarmupPhase
  | BootstrapPhase
  | FinalPhase

data HarborBootstrapOutcome
  = HarborRegistryReady
  | HarborMigrationDirty
  | HarborBootstrapTimedOut String

clusterUp :: Maybe RuntimeMode -> IO ()
clusterUp maybeRuntimeMode = do
  paths <- Config.discoverPaths
  Config.ensureRepoLayout paths
  runtimeMode <- Config.resolveRuntimeMode maybeRuntimeMode
  let controlPlane = Config.controlPlaneContext paths
  requestedPort <- chooseEdgePort paths
  (edgePortValue, kubeconfigContents) <- ensureKindCluster paths runtimeMode requestedPort
  writeFile (edgePortPath paths) (show edgePortValue)
  writeTextFile (Config.generatedKubeconfigPath paths) (Text.pack kubeconfigContents)
  waitForKubernetesApi paths runtimeMode
  configureRuntimeModeCluster paths runtimeMode
  let demoConfigPath = Config.generatedDemoConfigPath paths runtimeMode
      publishedCatalogPath = Config.publishedConfigMapCatalogPath paths runtimeMode
      configMapManifestPath = Config.publishedConfigMapManifestPath paths
      publicationPath = Config.publicationStatePath paths
      mountedCatalogPath = Config.watchedDemoConfigPath runtimeMode
      demoConfig =
        DemoConfig
          { configRuntimeMode = runtimeMode,
            configEdgePort = edgePortValue,
            configMapName = "infernix-demo-config",
            generatedPath = demoConfigPath,
            mountedPath = mountedCatalogPath,
            models = catalogForMode runtimeMode
          }
      payload = encodeDemoConfig demoConfig
  createDirectoryIfMissing True (buildRoot paths)
  createDirectoryIfMissing True (takeDirectory demoConfigPath)
  createDirectoryIfMissing True (takeDirectory publishedCatalogPath)
  createDirectoryIfMissing True (takeDirectory configMapManifestPath)
  createDirectoryIfMissing True (takeDirectory publicationPath)
  Lazy.writeFile demoConfigPath payload
  Lazy.writeFile publishedCatalogPath payload
  writeFile configMapManifestPath (renderConfigMapManifest runtimeMode payload)
  now <- getCurrentTime
  let seedState =
        ClusterState
          { clusterPresent = True,
            edgePort = edgePortValue,
            routes = routeInventory,
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
  finalValuesPath <- writeHelmValuesFile paths controlPlane seedState payload FinalPhase
  renderedChartPath <- renderHelmChart paths runtimeMode [finalValuesPath]
  discoveredClaims <- discoverPersistentClaims paths renderedChartPath
  mapM_ (createDirectoryIfMissing True . claimDirectory paths) discoveredClaims
  applyBootstrapState paths runtimeMode discoveredClaims
  let state = seedState {claims = discoveredClaims}
  writeFile publicationPath (renderPublicationState controlPlane state)
  reconcilePersistentVolumes state
  repairHarborDatabaseStorageState paths state
  publishBootstrapRegistryImages paths renderedChartPath
  deployChart paths state [warmupValuesPath] False
  repairHarborDatabaseMigrationState paths state
  bootstrapHarborWithRepair paths state [bootstrapValuesPath]
  buildClusterImages paths runtimeMode
  imageOverridesPath <- publishClusterImages paths renderedChartPath runtimeMode
  deployChart paths state [finalValuesPath, imageOverridesPath] True
  waitForFinalPhaseRollouts state
  writeStateFile (clusterStatePath paths) state
  putStrLn "cluster up complete"
  putStrLn ("controlPlaneContext: " <> controlPlane)
  putStrLn ("runtimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("edgePort: " <> show edgePortValue)
  putStrLn ("generatedDemoConfigPath: " <> demoConfigPath)
  putStrLn ("publishedDemoConfigPath: " <> publishedCatalogPath)
  putStrLn ("mountedDemoConfigPath: " <> mountedCatalogPath)

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
  when clusterExists $
    runCommand
      Nothing
      [("KUBECONFIG", Config.generatedKubeconfigPath paths)]
      "kind"
      ["delete", "cluster", "--name", kindClusterName paths runtimeMode]
  cleanupBootstrapRegistry
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
      putStrLn ("expectedDemoConfigPath: " <> Config.generatedDemoConfigPath paths runtimeMode)
      putStrLn ("expectedMountedDemoConfigPath: " <> Config.watchedDemoConfigPath runtimeMode)
    Just state -> do
      actualPresent <- kindClusterExists paths (clusterRuntimeMode state)
      cacheEntries <- countLeafEntries (modelCacheRoot paths)
      resultCount <- countLeafEntries (resultsRoot paths)
      objectCount <- countLeafEntries (objectStoreRoot paths)
      durableManifestCount <- countLeafEntries (objectStoreRoot paths </> "manifests")
      nodeCount <-
        if actualPresent
          then countNonEmptyLines <$> kubectlOutput state ["get", "nodes", "--no-headers"]
          else pure 0
      podCount <-
        if actualPresent
          then countNonEmptyLines <$> kubectlOutput state ["get", "pods", "-A", "--no-headers"]
          else pure 0
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
      putStrLn ("kubernetesNodeCount: " <> show nodeCount)
      putStrLn ("kubernetesPodCount: " <> show podCount)
      putStrLn ("runtimeResultCount: " <> show resultCount)
      putStrLn ("objectStoreObjectCount: " <> show objectCount)
      putStrLn ("modelCacheEntryCount: " <> show cacheEntries)
      putStrLn ("durableManifestCount: " <> show durableManifestCount)
      mapM_
        (\route -> putStrLn ("route: " <> Text.unpack (path route) <> " -> " <> Text.unpack (purpose route)))
        (routes state)

loadClusterState :: Paths -> IO (Maybe ClusterState)
loadClusterState paths = do
  stateExists <- doesFileExist (clusterStatePath paths)
  if stateExists
    then readStateFileMaybe (clusterStatePath paths)
    else pure Nothing

runKubectlCompat :: [String] -> IO ()
runKubectlCompat args = do
  paths <- Config.discoverPaths
  maybeState <- loadClusterState paths
  case maybeState of
    Nothing -> putStrLn "No cluster state is available. Run `infernix cluster up` first."
    Just state
      | not (clusterPresent state) -> putStrLn "Cluster is currently absent."
      | otherwise -> putStr =<< captureCommand Nothing [] "kubectl" (kubeconfigArgs state <> args)

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
  output <-
    readProcess
      "python3"
      [ "-c",
        unlines
          [ "import socket",
            "import sys",
            "port = int(sys.argv[1])",
            "sock = socket.socket()",
            "try:",
            "    sock.bind(('127.0.0.1', port))",
            "except OSError:",
            "    print('busy')",
            "else:",
            "    print('free')",
            "finally:",
            "    sock.close()"
          ],
        show candidatePort
      ]
      ""
  pure ("free" `elem` words output)

claimDirectory :: Paths -> PersistentClaim -> FilePath
claimDirectory paths persistentClaim =
  kindRoot paths
    </> Text.unpack (namespace persistentClaim)
    </> Text.unpack (release persistentClaim)
    </> Text.unpack (workload persistentClaim)
    </> show (ordinal persistentClaim)
    </> Text.unpack (claim persistentClaim)

ensureKindCluster :: Paths -> RuntimeMode -> Int -> IO (Int, String)
ensureKindCluster paths runtimeMode requestedPort = do
  clusterExists <- kindClusterExists paths runtimeMode
  selectedPort <-
    if clusterExists
      then do
        maybeExistingPort <- currentKindEdgePort paths runtimeMode
        pure (fromMaybe requestedPort maybeExistingPort)
      else createKindCluster paths runtimeMode requestedPort
  kubeconfigResult <- waitForKindKubeconfig paths runtimeMode
  case kubeconfigResult of
    Right kubeconfigContents ->
      pure (selectedPort, normalizeKubeconfigServer (Config.controlPlaneContext paths) kubeconfigContents)
    Left err
      | clusterExists -> do
          runCommand Nothing [] "kind" ["delete", "cluster", "--name", kindClusterName paths runtimeMode]
          recreatedPort <- createKindCluster paths runtimeMode requestedPort
          recreatedKubeconfig <- waitForKindKubeconfigOrFail paths runtimeMode
          pure (recreatedPort, normalizeKubeconfigServer (Config.controlPlaneContext paths) recreatedKubeconfig)
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
createKindCluster paths runtimeMode = go
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

waitForKindKubeconfig :: Paths -> RuntimeMode -> IO (Either String String)
waitForKindKubeconfig paths runtimeMode =
  retryCommandOutput
    30
    1000000
    ("kind get kubeconfig --name " <> kindClusterName paths runtimeMode)
    (tryCommand Nothing [] "kind" ["get", "kubeconfig", "--name", kindClusterName paths runtimeMode])

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
    LinuxCuda -> configureLinuxCudaCluster paths runtimeMode
    _ -> pure ()

configureLinuxCudaCluster :: Paths -> RuntimeMode -> IO ()
configureLinuxCudaCluster paths runtimeMode = do
  putStrLn "configuring linux-cuda runtime support"
  installLinuxCudaRuntimeShim paths runtimeMode
  advertiseLinuxCudaResources paths
  waitForLinuxCudaResources paths

installLinuxCudaRuntimeShim :: Paths -> RuntimeMode -> IO ()
installLinuxCudaRuntimeShim paths runtimeMode =
  forM_ nodeContainerNames installIntoNode
  where
    nodeContainerNames =
      [ kindClusterName paths runtimeMode <> "-control-plane",
        kindClusterName paths runtimeMode <> "-worker"
      ]
    installIntoNode nodeContainerName =
      runCommand
        Nothing
        []
        "docker"
        [ "exec",
          nodeContainerName,
          "sh",
          "-lc",
          unlines
            [ "set -eu",
              "if command -v nvidia-container-runtime >/dev/null 2>&1; then",
              "  exit 0",
              "fi",
              "runtime_path=$(command -v runc)",
              "ln -sf \"$runtime_path\" /usr/bin/nvidia-container-runtime"
            ]
        ]

advertiseLinuxCudaResources :: Paths -> IO ()
advertiseLinuxCudaResources paths = do
  gpuNodes <- linuxCudaNodeNames paths
  when (null gpuNodes) $
    ioError (userError "linux-cuda cluster did not expose any infernix.runtime/gpu=true nodes")
  forM_
    gpuNodes
    ( \nodeName ->
        runCommand
          Nothing
          []
          "kubectl"
          [ "--kubeconfig",
            Config.generatedKubeconfigPath paths,
            "patch",
            "node",
            nodeName,
            "--subresource=status",
            "--type=merge",
            "-p",
            "{\"status\":{\"capacity\":{\"nvidia.com/gpu\":\"1\"},\"allocatable\":{\"nvidia.com/gpu\":\"1\"}}}"
          ]
    )

waitForLinuxCudaResources :: Paths -> IO ()
waitForLinuxCudaResources paths = go (30 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 =
          ioError (userError "linux-cuda nodes never reported allocatable nvidia.com/gpu resources")
      | otherwise = do
          allocatableValues <- linuxCudaAllocatableValues paths
          if not (null allocatableValues) && not (any null allocatableValues) && "<no value>" `notElem` allocatableValues
            then pure ()
            else do
              threadDelay 1000000
              go (remainingAttempts - 1)

linuxCudaNodeNames :: Paths -> IO [String]
linuxCudaNodeNames paths =
  filter (not . null) . lines
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
        "jsonpath={range .items[*]}{.metadata.name}{\"\\n\"}{end}"
      ]

linuxCudaAllocatableValues :: Paths -> IO [String]
linuxCudaAllocatableValues paths =
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

applyBootstrapState :: Paths -> RuntimeMode -> [PersistentClaim] -> IO ()
applyBootstrapState paths runtimeMode claimInventory = do
  now <- getCurrentTime
  let state =
        ClusterState
          { clusterPresent = True,
            edgePort = 0,
            routes = routeInventory,
            storageClass = "infernix-manual",
            claims = claimInventory,
            clusterRuntimeMode = runtimeMode,
            kubeconfigPath = Config.generatedKubeconfigPath paths,
            generatedDemoConfigPath = Config.generatedDemoConfigPath paths runtimeMode,
            publishedDemoConfigPath = Config.publishedConfigMapCatalogPath paths runtimeMode,
            publishedConfigMapManifestPath = Config.publishedConfigMapManifestPath paths,
            mountedDemoConfigPath = Config.watchedDemoConfigPath runtimeMode,
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
  let runtimeModeName = Text.unpack (runtimeModeId runtimeMode)
      dockerBuildArgs dockerfile imageRef = ["build", "-f", dockerfile, "-t", imageRef, "."]
  putStrLn ("building cluster images for " <> runtimeModeName)
  ensureWebBuildDependencies paths
  runCommand (Just (repoRoot paths)) [] "npm" ["--prefix", "web", "run", "build"]
  runCommand (Just (repoRoot paths)) [] "docker" (dockerBuildArgs "docker/service.Dockerfile" serviceImageRef)
  runCommand (Just (repoRoot paths)) [] "docker" (dockerBuildArgs "web/Dockerfile" webImageRef)

publishBootstrapRegistryImages :: Paths -> FilePath -> IO ()
publishBootstrapRegistryImages paths renderedChartPath = do
  ensureBootstrapRegistry paths
  imageRefs <- discoverChartImages paths renderedChartPath
  let bootstrapImages = filter isBootstrapImage imageRefs
  forM_ bootstrapImages $ \imageRef -> do
    ensureLocalImageAvailable imageRef
    let targetRef = bootstrapRegistryTarget imageRef
    runCommand Nothing [] "docker" ["tag", imageRef, targetRef]
    runCommand Nothing [] "docker" ["push", targetRef]
  where
    isBootstrapImage imageRef =
      imageRef /= serviceImageRef
        && imageRef /= webImageRef
        && any (`List.isInfixOf` imageRef) ["bitnamilegacy/", "apachepulsar/"]

discoverChartImages :: Paths -> FilePath -> IO [String]
discoverChartImages paths renderedChartPath =
  filter (not . null) . lines
    <$> captureCommand
      (Just (repoRoot paths))
      []
      "python3"
      [repoRoot paths </> "tools" </> "discover_chart_images.py", renderedChartPath]

ensureLocalImageAvailable :: String -> IO ()
ensureLocalImageAvailable imageRef = do
  inspectionResult <- tryCommand Nothing [] "docker" ["image", "inspect", imageRef]
  case inspectionResult of
    Right _ -> pure ()
    Left _ -> runCommand Nothing [] "docker" ["pull", imageRef]

ensureBootstrapRegistry :: Paths -> IO ()
ensureBootstrapRegistry paths = do
  ensureBootstrapRegistryImage paths
  runningResult <- tryCommand Nothing [] "docker" ["inspect", "-f", "{{.State.Running}}", bootstrapRegistryName]
  case runningResult of
    Right output
      | trim output == "true" -> ensureRegistryConnectedToKindNetwork
      | trim output == "false" -> do
          runCommand Nothing [] "docker" ["start", bootstrapRegistryName]
          ensureRegistryConnectedToKindNetwork
      | otherwise -> startRegistry
    Left _ -> startRegistry
  where
    startRegistry =
      do
        runCommand
          Nothing
          []
          "docker"
          [ "run",
            "-d",
            "--name",
            bootstrapRegistryName,
            "--network",
            "kind",
            "-p",
            "30001:5000",
            bootstrapRegistryImageRef
          ]
        ensureRegistryConnectedToKindNetwork
    ensureRegistryConnectedToKindNetwork = do
      _ <- tryCommand Nothing [] "docker" ["network", "connect", "kind", bootstrapRegistryName]
      pure ()

ensureBootstrapRegistryImage :: Paths -> IO ()
ensureBootstrapRegistryImage paths = do
  let imageRoot = buildRoot paths </> "kind" </> "bootstrap-registry"
      binaryPath = imageRoot </> "registry"
      dockerfilePath = imageRoot </> "Dockerfile"
      configPath = imageRoot </> "config.yml"
  createDirectoryIfMissing True imageRoot
  imageArch <- bootstrapRegistryImageArchitecture
  binaryPresent <- doesFileExist binaryPath
  unless binaryPresent $
    downloadBootstrapRegistryBinary imageRoot imageArch
  writeFile dockerfilePath (renderBootstrapRegistryDockerfile binaryPath configPath)
  writeFile configPath renderBootstrapRegistryConfig
  imageInspection <- tryCommand Nothing [] "docker" ["image", "inspect", bootstrapRegistryImageRef]
  case imageInspection of
    Right _ -> pure ()
    Left _ -> runCommand (Just imageRoot) [] "docker" ["build", "-t", bootstrapRegistryImageRef, "."]

bootstrapRegistryImageArchitecture :: IO String
bootstrapRegistryImageArchitecture = do
  dockerArch <- trim <$> captureCommand Nothing [] "docker" ["version", "--format", "{{.Server.Arch}}"]
  case dockerArch of
    "amd64" -> pure "amd64"
    "arm64" -> pure "arm64"
    "x86_64" -> pure "amd64"
    "aarch64" -> pure "arm64"
    _ -> ioError (userError ("unsupported Docker server architecture for bootstrap registry: " <> dockerArch))

downloadBootstrapRegistryBinary :: FilePath -> String -> IO ()
downloadBootstrapRegistryBinary imageRoot imageArch = do
  let archiveName = "registry_" <> bootstrapRegistryVersion <> "_linux_" <> imageArch <> ".tar.gz"
      archivePath = imageRoot </> archiveName
      archiveUrl = bootstrapRegistryReleaseUrl <> "/" <> archiveName
  runCommand Nothing [] "curl" ["-fsSL", "--retry", "5", "--retry-all-errors", "-o", archivePath, archiveUrl]
  runCommand (Just imageRoot) [] "tar" ["-xzf", archiveName]

renderBootstrapRegistryDockerfile :: FilePath -> FilePath -> String
renderBootstrapRegistryDockerfile binaryPath configPath =
  unlines
    [ "FROM scratch",
      "COPY " <> takeFileName binaryPath <> " /registry",
      "COPY " <> takeFileName configPath <> " /etc/distribution/config.yml",
      "EXPOSE 5000",
      "ENTRYPOINT [\"/registry\", \"serve\", \"/etc/distribution/config.yml\"]"
    ]

renderBootstrapRegistryConfig :: String
renderBootstrapRegistryConfig =
  unlines
    [ "version: 0.1",
      "log:",
      "  level: info",
      "storage:",
      "  filesystem:",
      "    rootdirectory: /var/lib/registry",
      "http:",
      "  addr: :5000"
    ]

cleanupBootstrapRegistry :: IO ()
cleanupBootstrapRegistry = do
  _ <- tryCommand Nothing [] "docker" ["rm", "-f", bootstrapRegistryName]
  pure ()

bootstrapRegistryTarget :: String -> String
bootstrapRegistryTarget imageRef =
  bootstrapRegistryHost <> "/library/" <> stripDockerIo repositoryPart <> ":" <> tagPart
  where
    reversedImageRef = reverse imageRef
    (reversedTag, reversedRepositoryWithSeparator) = break (== ':') reversedImageRef
    (repositoryPart, tagPart) =
      case reversedRepositoryWithSeparator of
        ':' : reversedRepository -> (reverse reversedRepository, reverse reversedTag)
        _ -> (imageRef, "latest")

stripDockerIo :: String -> String
stripDockerIo value =
  fromMaybe value (List.stripPrefix "docker.io/" value)

ensureWebBuildDependencies :: Paths -> IO ()
ensureWebBuildDependencies paths = do
  let webRoot = repoRoot paths </> "web"
      depsRoot = webRoot </> "node_modules"
      packageLock = webRoot </> "package-lock.json"
  depsPresent <- doesDirectoryExist depsRoot
  packageLockPresent <- doesFileExist packageLock
  if depsPresent && packageLockPresent
    then pure ()
    else runCommand (Just (repoRoot paths)) [] "npm" ["--prefix", "web", "ci"]

publishClusterImages :: Paths -> FilePath -> RuntimeMode -> IO FilePath
publishClusterImages paths renderedChartPath runtimeMode = do
  let outputPath =
        buildRoot paths
          </> ("harbor-image-overrides-" <> Text.unpack (runtimeModeId runtimeMode) <> ".yaml")
  runCommand
    (Just (repoRoot paths))
    []
    "python3"
    [ repoRoot paths </> "tools" </> "publish_chart_images.py",
      renderedChartPath,
      outputPath,
      "--harbor-api-host",
      harborApiHost paths
    ]
  pure outputPath

waitForHarborRegistry :: Paths -> IO ()
waitForHarborRegistry paths = do
  result <- waitForHarborRegistryResult paths 60 5000000
  case result of
    Right _ -> pure ()
    Left err ->
      ioError
        (userError ("Harbor registry never became ready enough for image publication:\n" <> err))

waitForHarborRegistryResult :: Paths -> Int -> Int -> IO (Either String String)
waitForHarborRegistryResult paths attempts delayMicros = do
  let registryApiUrl = "http://" <> harborApiHost paths <> "/api/v2.0/health"
      probeCommand =
        tryCommand
          Nothing
          []
          "python3"
          [ "-c",
            unlines
              [ "import urllib.error",
                "import urllib.request",
                "try:",
                "    with urllib.request.urlopen(" <> show registryApiUrl <> ", timeout=5) as response:",
                "        payload = response.read().decode('utf-8', errors='replace')",
                "except urllib.error.HTTPError as exc:",
                "    payload = exc.read().decode('utf-8', errors='replace')",
                "    if exc.code not in {200, 401, 403}:",
                "        raise",
                "except Exception as exc:",
                "    raise SystemExit(str(exc))",
                "if 'healthy' not in payload.lower() and 'status' not in payload.lower():",
                "    raise SystemExit('harbor health payload not ready')",
                "print('ready')"
              ]
          ]
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
                  waitForHarborRegistry paths
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
repairHarborBootstrapState paths state maybeError = do
  resetRequired <- harborDatabaseResetRequired state maybeError
  if resetRequired
    then resetHarborDatabaseStorageState paths state
    else repairHarborDatabaseStorageState paths state
  cleanupHarborMigrationJob state
  repairHarborDatabaseMigrationState paths state

harborDatabaseResetRequired :: ClusterState -> Maybe String -> IO Bool
harborDatabaseResetRequired state maybeError = do
  migrationPermissionDenied <- harborMigrationHookPermissionDenied state
  pure
    ( migrationPermissionDenied
        || maybe False isHarborPermissionError maybeError
    )
  where
    isHarborPermissionError err =
      "Permission denied" `List.isInfixOf` err
        || "could not open file" `List.isInfixOf` err

harborMigrationHookPermissionDenied :: ClusterState -> IO Bool
harborMigrationHookPermissionDenied state = do
  result <-
    tryCommand
      Nothing
      []
      "kubectl"
      ( kubeconfigArgs state
          <> [ "-n",
               "platform",
               "logs",
               "job/migration-job",
               "--tail=200"
             ]
      )
  pure
    ( case result of
        Right output ->
          "Permission denied" `List.isInfixOf` output
            || "could not open file" `List.isInfixOf` output
        Left _ -> False
    )

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
      registryResult <- waitForHarborRegistryResult paths 1 0
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
            "export PGPASSWORD=\"$POSTGRES_PASSWORD\"",
            "registry_present=$(psql -U postgres -d postgres -Atqc \"SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_database WHERE datname = 'registry') THEN 'true' ELSE 'false' END\")",
            "if [ \"$registry_present\" != \"true\" ]; then",
            "  echo clean",
            "  exit 0",
            "fi",
            "dirty_count=$(psql -U postgres -d registry -Atqc \"SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'schema_migrations') THEN (SELECT COUNT(*)::text FROM schema_migrations WHERE dirty = TRUE) ELSE '0' END\")",
            "if [ \"$dirty_count\" = \"0\" ]; then",
            "  echo clean",
            "else",
            "  echo dirty",
            "fi"
          ]
  result <-
    tryCommand
      Nothing
      []
      "kubectl"
      ( kubeconfigArgs state
          <> [ "-n",
               "platform",
               "exec",
               "infernix-harbor-database-0",
               "--",
               "sh",
               "-lc",
               detectionCommand
             ]
      )
  case result of
    Right output -> pure ("dirty" `List.isInfixOf` output)
    Left _ -> pure False

repairHarborDatabaseStorageState :: Paths -> ClusterState -> IO ()
repairHarborDatabaseStorageState paths state =
  case List.find isHarborDatabaseClaim (claims state) of
    Nothing -> pure ()
    Just persistentClaim -> do
      let postgresRoot = claimDirectory paths persistentClaim </> "pgdata"
          versionFile = postgresRoot </> "pg15" </> "PG_VERSION"
      postgresRootExists <- doesDirectoryExist postgresRoot
      versionFileExists <- doesFileExist versionFile
      when (postgresRootExists && not versionFileExists) $ do
        removePathForcibly postgresRoot
        createDirectoryIfMissing True (claimDirectory paths persistentClaim)
        _ <-
          tryCommand
            Nothing
            []
            "kubectl"
            ( kubeconfigArgs state
                <> [ "-n",
                     "platform",
                     "delete",
                     "pod",
                     "infernix-harbor-database-0",
                     "--ignore-not-found=true",
                     "--wait=true"
                   ]
            )
        pure ()
  where
    isHarborDatabaseClaim persistentClaim =
      namespace persistentClaim == "platform"
        && release persistentClaim == "infernix"
        && workload persistentClaim == "harbor-database"
        && claim persistentClaim == "data"

resetHarborDatabaseStorageState :: Paths -> ClusterState -> IO ()
resetHarborDatabaseStorageState paths state =
  case List.find isHarborDatabaseClaim (claims state) of
    Nothing -> pure ()
    Just persistentClaim -> do
      let postgresRoot = claimDirectory paths persistentClaim </> "pgdata"
      postgresRootExists <- doesDirectoryExist postgresRoot
      when postgresRootExists (removePathForcibly postgresRoot)
      createDirectoryIfMissing True (claimDirectory paths persistentClaim)
      _ <-
        tryCommand
          Nothing
          []
          "kubectl"
          ( kubeconfigArgs state
              <> [ "-n",
                   "platform",
                   "delete",
                   "pod",
                   "infernix-harbor-database-0",
                   "--ignore-not-found=true",
                   "--wait=true"
                 ]
          )
      pure ()
  where
    isHarborDatabaseClaim persistentClaim =
      namespace persistentClaim == "platform"
        && release persistentClaim == "infernix"
        && workload persistentClaim == "harbor-database"
        && claim persistentClaim == "data"

repairHarborDatabaseMigrationState :: Paths -> ClusterState -> IO ()
repairHarborDatabaseMigrationState paths state = do
  waitForHarborDatabaseReadyWithRepair paths state
  let repairCommand =
        unlines
          [ "set -eu",
            "export PGPASSWORD=\"$POSTGRES_PASSWORD\"",
            "registry_present=$(psql -U postgres -d postgres -Atqc \"SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_database WHERE datname = 'registry') THEN 'true' ELSE 'false' END\")",
            "if [ \"$registry_present\" = \"true\" ]; then",
            "  dirty_count=$(psql -U postgres -d registry -Atqc \"SELECT CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'schema_migrations') THEN (SELECT COUNT(*)::text FROM schema_migrations WHERE dirty = TRUE) ELSE '0' END\")",
            "  if [ \"$dirty_count\" != \"0\" ]; then",
            "    psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'registry' AND pid <> pg_backend_pid();\"",
            "    psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c \"DROP DATABASE IF EXISTS registry;\"",
            "    psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c \"CREATE DATABASE registry;\"",
            "  fi",
            "fi"
          ]
  _ <-
    tryCommand
      Nothing
      []
      "kubectl"
      ( kubeconfigArgs state
          <> [ "-n",
               "platform",
               "exec",
               "infernix-harbor-database-0",
               "--",
               "sh",
               "-lc",
               repairCommand
             ]
      )
  pure ()

waitForHarborDatabaseReadyWithRepair :: Paths -> ClusterState -> IO ()
waitForHarborDatabaseReadyWithRepair paths state = go (72 :: Int) ""
  where
    waitArgs =
      kubeconfigArgs state
        <> [ "-n",
             "platform",
             "wait",
             "--for=condition=Ready",
             "pod/infernix-harbor-database-0",
             "--timeout=5s"
           ]
    go remainingAttempts lastError = do
      result <- tryCommand Nothing [] "kubectl" waitArgs
      case result of
        Right _ -> pure ()
        Left err -> do
          storageCorrupt <- harborDatabaseStorageCorrupt state
          when storageCorrupt (repairHarborDatabaseStorageState paths state)
          if remainingAttempts <= 1
            then
              ioError
                ( userError
                    ( "Harbor database pod never became ready:\n"
                        <> chooseError err lastError
                    )
                )
            else do
              threadDelay 5000000
              go (remainingAttempts - 1) (chooseError err lastError)

    chooseError current previous
      | null current = previous
      | otherwise = current

harborDatabaseStorageCorrupt :: ClusterState -> IO Bool
harborDatabaseStorageCorrupt state = do
  currentLogs <- tryCommand Nothing [] "kubectl" (kubeconfigArgs state <> ["-n", "platform", "logs", "infernix-harbor-database-0"])
  previousLogs <- tryCommand Nothing [] "kubectl" (kubeconfigArgs state <> ["-n", "platform", "logs", "infernix-harbor-database-0", "--previous"])
  pure
    (any hasConflictMarker [either id id currentLogs, either id id previousLogs])
  where
    hasConflictMarker output = "exists but is not empty" `List.isInfixOf` output

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

waitForFinalPhaseRollouts :: ClusterState -> IO ()
waitForFinalPhaseRollouts state = do
  putStrLn "waiting for final platform rollouts"
  mapM_ (waitForWorkloadRollout state 1200) finalPhaseStatefulSets
  mapM_ (waitForWorkloadRollout state 900) finalPhaseDeployments

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
          | "no repository definition" `List.isInfixOf` err ->
              do
                ensureHelmRepositoryDefinitions paths
                runCommand (Just (repoRoot paths)) (Config.helmEnvironment paths) "helm" ["dependency", "build", "chart"]
          | otherwise ->
              ioError (userError ("command failed: helm dependency build --skip-refresh chart\n" <> err))

ensureHelmRepositoryDefinitions :: Paths -> IO ()
ensureHelmRepositoryDefinitions paths =
  mapM_
    (\(repoName, repoUrl) -> runCommand (Just (repoRoot paths)) (Config.helmEnvironment paths) "helm" ["repo", "add", "--force-update", repoName, repoUrl])
    helmRepositories

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
  writeRegistryNamespace "localhost:30001" (bootstrapRegistryName <> ":5000") registryRoot
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
        "name: " <> kindClusterName paths runtimeMode
      ]
        <> cudaRuntimePatch
    cudaRuntimePatch =
      case runtimeMode of
        LinuxCuda ->
          [ "containerdConfigPatches:",
            "  - |-",
            "    [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.nvidia]",
            "      privileged_without_host_devices = false",
            "      runtime_type = \"io.containerd.runc.v2\"",
            "    [plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.nvidia.options]",
            "      BinaryName = \"/usr/bin/nvidia-container-runtime\""
          ]
        _ -> []
    initLabels = controlPlaneRuntimeModeLabels runtimeMode
    workerLabels = runtimeModeLabels runtimeMode
    edgePortLines =
      [ "    extraPortMappings:",
        "      - containerPort: 30090",
        "        hostPort: " <> show edgePortValue,
        "        protocol: TCP",
        "      - containerPort: 30002",
        "        hostPort: 30002",
        "        protocol: TCP",
        "      - containerPort: 30011",
        "        hostPort: 30011",
        "        protocol: TCP",
        "      - containerPort: 30080",
        "        hostPort: 30080",
        "        protocol: TCP",
        "      - containerPort: 30650",
        "        hostPort: 30650",
        "        protocol: TCP"
      ]
    nodeBlock role labels extraLines =
      [ "  - role: " <> role
      ]
        <> extraLines
        <> [ "    extraMounts:",
             "      - hostPath: " <> hostKindRoot,
             "        containerPath: " <> nodeMountedKindRoot,
             "      - hostPath: " <> registryHostsDirectory,
             "        containerPath: /etc/containerd/certs.d",
             "    kubeadmConfigPatches:",
             "      - |",
             "        kind: " <> kubeConfiguration role,
             "        nodeRegistration:",
             "          kubeletExtraArgs:",
             "            node-labels: " <> show labels
           ]
    kubeConfiguration role
      | role == "control-plane" = "InitConfiguration"
      | otherwise = "JoinConfiguration"

runtimeModeLabels :: RuntimeMode -> String
runtimeModeLabels runtimeMode = case runtimeMode of
  AppleSilicon -> "infernix.runtime/mode=apple-silicon"
  LinuxCpu -> "infernix.runtime/mode=linux-cpu"
  LinuxCuda -> "infernix.runtime/mode=linux-cuda,infernix.runtime/gpu=true"

controlPlaneRuntimeModeLabels :: RuntimeMode -> String
controlPlaneRuntimeModeLabels runtimeMode = case runtimeMode of
  LinuxCuda -> "infernix.runtime/mode=linux-cuda"
  _ -> runtimeModeLabels runtimeMode

kindClusterName :: Paths -> RuntimeMode -> String
kindClusterName paths runtimeMode =
  let baseName = "infernix-" <> Text.unpack (runtimeModeId runtimeMode)
   in if dataRoot paths == repoRoot paths </> ".data"
        then baseName
        else baseName <> "-" <> show (clusterNameHash (dataRoot paths))

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
  let outputPath =
        buildRoot paths
          </> ("helm-values-" <> phaseSuffix deployPhase <> "-" <> Text.unpack (runtimeModeId (clusterRuntimeMode state)) <> ".yaml")
  writeFile outputPath (renderHelmValues controlPlane state demoConfigPayload deployPhase)
  pure outputPath
  where
    phaseSuffix phaseValue = case phaseValue of
      WarmupPhase -> "warmup"
      BootstrapPhase -> "bootstrap"
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
discoverPersistentClaims paths renderedChartPath = do
  output <-
    captureCommand
      (Just (repoRoot paths))
      []
      "python3"
      [repoRoot paths </> "tools" </> "discover_chart_claims.py", renderedChartPath]
  mapM parseClaimLine (filter (not . null) (lines output))
  where
    parseClaimLine lineValue =
      case splitTabs lineValue of
        [namespaceValue, releaseValue, workloadValue, ordinalValue, claimValue, pvcNameValue, requestedStorageValue] ->
          case readMaybe ordinalValue of
            Just ordinalNumber ->
              pure
                PersistentClaim
                  { namespace = Text.pack namespaceValue,
                    release = Text.pack releaseValue,
                    workload = Text.pack workloadValue,
                    ordinal = ordinalNumber,
                    claim = Text.pack claimValue,
                    pvcName = Text.pack pvcNameValue,
                    requestedStorage = Text.pack requestedStorageValue
                  }
            Nothing ->
              ioError (userError ("rendered chart claim had an invalid ordinal: " <> lineValue))
        [namespaceValue, releaseValue, workloadValue, ordinalValue, claimValue] ->
          case readMaybe ordinalValue of
            Just ordinalNumber ->
              pure
                PersistentClaim
                  { namespace = Text.pack namespaceValue,
                    release = Text.pack releaseValue,
                    workload = Text.pack workloadValue,
                    ordinal = ordinalNumber,
                    claim = Text.pack claimValue,
                    pvcName = Text.pack (releaseValue <> "-" <> workloadValue <> "-" <> ordinalValue <> "-" <> claimValue),
                    requestedStorage = "5Gi"
                  }
            Nothing ->
              ioError (userError ("rendered chart claim had an invalid ordinal: " <> lineValue))
        _ ->
          ioError (userError ("rendered chart claim line was malformed: " <> lineValue))

renderHelmValues :: String -> ClusterState -> Lazy.ByteString -> HelmDeployPhase -> String
renderHelmValues controlPlane state demoConfigPayload deployPhase =
  unlines
    ( [ "runtimeMode: " <> Text.unpack (runtimeModeId (clusterRuntimeMode state)),
        "controlPlaneContext: " <> show controlPlane,
        "edge:",
        "  port: " <> show (edgePort state),
        "  replicaCount: " <> show (repoWorkloadReplicaCount deployPhase),
        "  routes:",
        renderRoutesYaml (routes state),
        "demoConfig:",
        "  fileName: infernix-demo-" <> Text.unpack (runtimeModeId (clusterRuntimeMode state)) <> ".dhall",
        "  catalogPayload: |",
        indentBlock 4 (LazyChar8.unpack demoConfigPayload),
        "publication:",
        "  payloadJson: |",
        indentBlock 4 (renderPublicationState controlPlane state),
        "service:",
        "  replicaCount: " <> show (repoWorkloadReplicaCount deployPhase),
        "  image:",
        "    repository: infernix-service",
        "    tag: local",
        "    pullPolicy: IfNotPresent",
        "web:",
        "  replicaCount: " <> show (repoWorkloadReplicaCount deployPhase),
        "  image:",
        "    repository: infernix-web",
        "    tag: local",
        "    pullPolicy: IfNotPresent",
        "platformPortals:",
        "  harbor:",
        "    replicaCount: " <> show (repoWorkloadReplicaCount deployPhase),
        "  minio:",
        "    replicaCount: " <> show (repoWorkloadReplicaCount deployPhase),
        "  pulsar:",
        "    replicaCount: " <> show (repoWorkloadReplicaCount deployPhase)
      ]
        <> bootstrapRegistryOverrides deployPhase
        <> bootstrapHarborOverrides deployPhase
    )
  where
    repoWorkloadReplicaCount :: HelmDeployPhase -> Int
    repoWorkloadReplicaCount phaseValue = case phaseValue of
      WarmupPhase -> 0
      BootstrapPhase -> 0
      FinalPhase -> 1
    bootstrapRegistryOverrides phaseValue = case phaseValue of
      WarmupPhase -> bootstrapRegistryMinioOverrides <> bootstrapRegistryPulsarOverrides
      BootstrapPhase -> bootstrapRegistryMinioOverrides <> bootstrapRegistryPulsarOverrides
      FinalPhase -> []
    bootstrapRegistryMinioOverrides =
      [ "minio:",
        "  image:",
        "    registry: " <> bootstrapRegistryHost,
        "    repository: library/bitnamilegacy/minio",
        "  clientImage:",
        "    registry: " <> bootstrapRegistryHost,
        "    repository: library/bitnamilegacy/minio-client",
        "  defaultInitContainers:",
        "    volumePermissions:",
        "      image:",
        "        registry: " <> bootstrapRegistryHost,
        "        repository: library/bitnamilegacy/os-shell",
        "  console:",
        "    image:",
        "      registry: " <> bootstrapRegistryHost,
        "      repository: library/bitnamilegacy/minio-object-browser"
      ]
    bootstrapRegistryPulsarOverrides =
      [ "pulsar:",
        "  defaultPulsarImageRepository: " <> bootstrapRegistryHost <> "/library/apachepulsar/pulsar-all"
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
      FinalPhase ->
        [ "harbor:",
          "  enableMigrateHelmHook: true"
        ]

renderRoutesYaml :: [RouteInfo] -> String
renderRoutesYaml =
  concatMap
    ( \route ->
        unlines
          [ "    - path: " <> Text.unpack (path route),
            "      purpose: " <> Text.unpack (purpose route)
          ]
    )

harborApiHost :: Paths -> String
harborApiHost paths
  | Config.controlPlaneContext paths == "outer-container" = "host.docker.internal:30002"
  | otherwise = "127.0.0.1:30002"

bootstrapRegistryHost :: String
bootstrapRegistryHost = "localhost:30001"

bootstrapRegistryName :: String
bootstrapRegistryName = "infernix-bootstrap-registry"

bootstrapRegistryImageRef :: String
bootstrapRegistryImageRef = bootstrapRegistryName <> ":" <> bootstrapRegistryVersion

bootstrapRegistryVersion :: String
bootstrapRegistryVersion = "3.1.0"

bootstrapRegistryReleaseUrl :: String
bootstrapRegistryReleaseUrl = "https://github.com/distribution/distribution/releases/download/v" <> bootstrapRegistryVersion

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

kubectlOutput :: ClusterState -> [String] -> IO String
kubectlOutput state args = captureCommand Nothing [] "kubectl" (kubeconfigArgs state <> args)

kubeconfigArgs :: ClusterState -> [String]
kubeconfigArgs state = ["--kubeconfig", kubeconfigPath state]

serviceImageRef :: String
serviceImageRef = "infernix-service:local"

webImageRef :: String
webImageRef = "infernix-web:local"

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
  (exitCode, stdoutOutput, stderrOutput) <-
    readCreateProcessWithExitCode
      (proc command args)
        { cwd = maybeWorkingDirectory,
          env = Just mergedEnv
        }
      ""
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
normalizeKubeconfigServer controlPlane kubeconfigContents
  | controlPlane == "outer-container" =
      let rewrittenServers =
            Text.replace
              "https://127.0.0.1:"
              "https://host.docker.internal:"
              (Text.replace "https://localhost:" "https://host.docker.internal:" (Text.pack kubeconfigContents))
          serverLine = "    server: https://host.docker.internal:"
          tlsServerNameLine = "    tls-server-name: localhost"
          injectTlsServerName line
            | Text.isPrefixOf serverLine line = [line, tlsServerNameLine]
            | otherwise = [line]
          withTlsServerName
            | Text.isInfixOf tlsServerNameLine rewrittenServers = rewrittenServers
            | otherwise = Text.unlines (concatMap injectTlsServerName (Text.lines rewrittenServers))
       in Text.unpack withTlsServerName
  | otherwise = kubeconfigContents

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
