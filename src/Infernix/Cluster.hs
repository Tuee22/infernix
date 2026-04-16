{-# LANGUAGE OverloadedStrings #-}

module Infernix.Cluster
  ( clusterDown,
    clusterStatus,
    clusterUp,
    loadClusterState,
    runKubectlCompat,
  )
where

import Data.Char (isSpace)
import qualified Data.Text as Text
import Data.Time (getCurrentTime)
import Infernix.Config
import Infernix.Models
import Infernix.Storage
import Infernix.Types
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath ((</>))
import System.Process (readProcess)
import Text.Read (readMaybe)

clusterStatePath :: Paths -> FilePath
clusterStatePath paths = runtimeRoot paths </> "cluster-state.state"

clusterUp :: IO ()
clusterUp = do
  paths <- discoverPaths
  ensureRepoLayout paths
  port <- chooseEdgePort paths
  mapM_ (createDirectoryIfMissing True . claimDirectory paths) platformClaims
  writeFile (edgePortPath paths) (show port)
  writeTextFile (generatedTestConfigPath paths) (Text.pack (renderTestConfig port))
  writeTextFile (generatedKubeconfigPath paths) (Text.pack (renderKubeconfig port))
  now <- getCurrentTime
  let state =
        ClusterState
          { clusterPresent = True,
            edgePort = port,
            routes = routeInventory,
            storageClass = "infernix-manual",
            claims = platformClaims,
            kubeconfigPath = generatedKubeconfigPath paths,
            testConfigPath = generatedTestConfigPath paths,
            updatedAt = now
          }
  writeStateFile (clusterStatePath paths) state
  putStrLn ("cluster up complete on port " <> show port)

clusterDown :: IO ()
clusterDown = do
  paths <- discoverPaths
  maybeState <- loadClusterState paths
  case maybeState of
    Nothing -> putStrLn "cluster already absent"
    Just state -> do
      now <- getCurrentTime
      writeStateFile
        (clusterStatePath paths)
        state
          { clusterPresent = False,
            updatedAt = now
          }
      putStrLn "cluster down complete"

clusterStatus :: IO ()
clusterStatus = do
  paths <- discoverPaths
  maybeState <- loadClusterState paths
  case maybeState of
    Nothing -> putStrLn "cluster not yet reconciled"
    Just state -> do
      putStrLn ("clusterPresent: " <> show (clusterPresent state))
      putStrLn ("edgePort: " <> show (edgePort state))
      putStrLn ("storageClass: " <> Text.unpack (storageClass state))
      putStrLn ("kubeconfigPath: " <> kubeconfigPath state)
      putStrLn ("testConfigPath: " <> testConfigPath state)
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
  paths <- discoverPaths
  maybeState <- loadClusterState paths
  case maybeState of
    Nothing -> putStrLn "No cluster state is available. Run `infernix cluster up` first."
    Just state
      | not (clusterPresent state) -> putStrLn "Cluster is currently absent."
      | otherwise -> putStr (renderKubectl state args)

chooseEdgePort :: Paths -> IO Int
chooseEdgePort paths = do
  edgePortExists <- doesFileExist (edgePortPath paths)
  case edgePortExists of
    True -> do
      contents <- readFile (edgePortPath paths)
      case readMaybe (dropWhile isSpace contents) of
        Just port -> pure port
        Nothing -> allocatePort
    False -> allocatePort

allocatePort :: IO Int
allocatePort = do
  output <-
    readProcess
      "python3"
      [ "-c",
        unlines
          [ "import socket",
            "sock = socket.socket()",
            "sock.bind(('127.0.0.1', 0))",
            "print(sock.getsockname()[1])",
            "sock.close()"
          ]
      ]
      ""
  case readMaybe (dropWhile isSpace output) of
    Just port -> pure port
    Nothing -> pure 4010

claimDirectory :: Paths -> PersistentClaim -> FilePath
claimDirectory paths persistentClaim =
  kindRoot paths
    </> Text.unpack (namespace persistentClaim)
    </> Text.unpack (release persistentClaim)
    </> Text.unpack (workload persistentClaim)
    </> show (ordinal persistentClaim)
    </> Text.unpack (claim persistentClaim)

renderKubeconfig :: Int -> String
renderKubeconfig port =
  unlines
    [ "apiVersion: v1",
      "kind: Config",
      "clusters:",
      "- name: infernix-local",
      "  cluster:",
      "    server: http://127.0.0.1:" <> show port,
      "contexts:",
      "- name: infernix-local",
      "  context:",
      "    cluster: infernix-local",
      "    user: infernix-local",
      "current-context: infernix-local",
      "users:",
      "- name: infernix-local",
      "  user: {}"
    ]

renderKubectl :: ClusterState -> [String] -> String
renderKubectl state args = case args of
  ["get", "storageclass"] ->
    unlines
      [ "NAME              PROVISIONER                    RECLAIMPOLICY   VOLUMEBINDINGMODE",
        Text.unpack (storageClass state) <> "   kubernetes.io/no-provisioner   Delete          WaitForFirstConsumer"
      ]
  ["get", "nodes"] ->
    unlines
      [ "NAME             STATUS",
        "infernix-kind    Ready"
      ]
  ["get", "pods", "-A"] ->
    unlines
      [ "NAMESPACE   NAME                STATUS",
        "platform    harbor-0            Running",
        "platform    minio-0             Running",
        "platform    pulsar-0            Running",
        "platform    infernix-service-0  Running",
        "platform    infernix-web-0      Running"
      ]
  ["get", "pv,pvc", "-A"] ->
    unlines
      ( ["KIND   NAMESPACE   NAME                            STATUS   STORAGECLASS"]
          <> concatMap renderClaim (claims state)
      )
  _ -> "Unsupported kubectl compatibility command.\n"
  where
    renderClaim persistentClaim =
      let baseName =
            Text.unpack (namespace persistentClaim)
              <> "-"
              <> Text.unpack (release persistentClaim)
              <> "-"
              <> Text.unpack (workload persistentClaim)
              <> "-"
              <> show (ordinal persistentClaim)
              <> "-"
              <> Text.unpack (claim persistentClaim)
          storageClassName = Text.unpack (storageClass state)
       in [ "PV     " <> Text.unpack (namespace persistentClaim) <> "   " <> baseName <> "                     Bound    " <> storageClassName,
            "PVC    " <> Text.unpack (namespace persistentClaim) <> "   " <> Text.unpack (claim persistentClaim) <> "                       Bound    " <> storageClassName
          ]
