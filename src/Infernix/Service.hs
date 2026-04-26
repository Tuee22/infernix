module Infernix.Service
  ( activateHostBridgeRoute,
    restoreClusterServiceRoute,
    runService,
  )
where

import Data.Text qualified as Text
import Infernix.Cluster (loadClusterState)
import Infernix.Config
import Infernix.Models
  ( hostBridgeApiUpstream,
    renderPublicationState,
    renderPublicationStateWithApiUpstream,
  )
import Infernix.Runtime.Pulsar (runProductionDaemon)
import Infernix.Types (ClusterState, RuntimeMode, clusterPresent, clusterRuntimeMode, runtimeModeId)

runService :: Maybe RuntimeMode -> IO ()
runService maybeRuntimeMode = do
  paths <- discoverPaths
  ensureRepoLayout paths
  runtimeMode <- resolveRuntimeMode maybeRuntimeMode
  runProductionDaemon paths runtimeMode

activateHostBridgeRoute :: Paths -> RuntimeMode -> Int -> IO ()
activateHostBridgeRoute paths runtimeMode port = do
  maybeState <- loadClusterState paths
  ensureBridgeRuntimeMode maybeState runtimeMode True
  state <- requireActiveClusterState maybeState
  writeFile
    (publicationStatePath paths)
    (renderPublicationStateWithApiUpstream (controlPlaneContext paths) state (hostBridgeApiUpstream port))

restoreClusterServiceRoute :: Paths -> IO ()
restoreClusterServiceRoute paths = do
  maybeState <- loadClusterState paths
  case maybeState of
    Just state
      | clusterPresent state ->
          writeFile (publicationStatePath paths) (renderPublicationState (controlPlaneContext paths) state)
    _ -> pure ()

ensureBridgeRuntimeMode :: Maybe ClusterState -> RuntimeMode -> Bool -> IO ()
ensureBridgeRuntimeMode maybeState runtimeMode bridgeActive =
  case (bridgeActive, maybeState) of
    (True, Just state)
      | clusterRuntimeMode state /= runtimeMode ->
          ioError
            ( userError
                ( "host-native service runtime mode "
                    <> Text.unpack (runtimeModeId runtimeMode)
                    <> " does not match the active cluster runtime mode "
                    <> Text.unpack (runtimeModeId (clusterRuntimeMode state))
                )
            )
    _ -> pure ()

requireActiveClusterState :: Maybe ClusterState -> IO ClusterState
requireActiveClusterState maybeState =
  case maybeState of
    Just state
      | clusterPresent state -> pure state
    _ -> ioError (userError "host bridge activation requires an active cluster state")
