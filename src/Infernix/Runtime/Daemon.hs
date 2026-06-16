{-# LANGUAGE OverloadedStrings #-}

module Infernix.Runtime.Daemon
  ( runProductionDaemon,
  )
where

import Control.Concurrent (forkIO, threadDelay)
import Control.Monad (forM_, forever, when)
import Data.List (find, intercalate)
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Infernix.ClusterConfig
  ( ClusterConfig (..),
    CoordinatorWiring (..),
    DemoBackendWiring (..),
    EngineCommandOverride (..),
    EngineWiring (..),
  )
import Infernix.Config
  ( ControlPlaneContext,
    Paths,
    controlPlaneContext,
    controlPlaneContextId,
    generatedDemoConfigPath,
    parseControlPlaneContext,
    watchedDemoConfigPath,
  )
import Infernix.Conversation.Topic qualified as ConversationTopic
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Dispatch.ContextModelMap qualified as ContextModelMap
import Infernix.Models (perEngineBatchTopicForMode)
import Infernix.Runtime.KVCache qualified as KVCache
import Infernix.Runtime.Pulsar
  ( PulsarTransport,
    clearServiceReadinessMarker,
    consumeTopicForever,
    discoverPulsarTransport,
    drainTopicWithKVCache,
    ensureRegisteredSchemasWithRetry,
    ensureSchemaMarkers,
    pulsarWebSocketBase,
    reconcileSupportedNamespacesWithRetry,
    renderPulsarWebSocketBase,
    runDispatcherLoop,
    runModelBootstrapLoop,
    runResultBridgeLoop,
    writeServiceReadinessMarker,
  )
import Infernix.Runtime.Worker (EngineCommandOverrideMap)
import Infernix.Types hiding (generatedDemoConfigPath)

-- | Phase 7 Sprint 7.8: daemon role orchestration lives outside the
-- Pulsar transport module. The daemon layer decides which role starts
-- coordinator loops, which role owns engine execution, and which
-- process-local engine KV cache is threaded into request handling.
runProductionDaemon :: Paths -> RuntimeMode -> Maybe ClusterConfig -> Maybe FilePath -> DaemonRole -> Maybe Text.Text -> IO ()
runProductionDaemon paths runtimeMode maybeClusterConfig maybeDemoConfigPath daemonRole maybeEngineName = do
  maybeTransport <- discoverPulsarTransport paths runtimeMode maybeClusterConfig
  engineKVCache <- KVCache.newEngineKVCache
  let controlPlane = case maybeClusterConfig of
        Just clusterConfig -> resolveClusterControlPlaneContext clusterConfig (controlPlaneContext paths)
        Nothing -> controlPlaneContext paths
      catalogSource = case maybeClusterConfig of
        Just clusterConfig -> Text.unpack (coordinatorCatalogSource (clusterCoordinator clusterConfig))
        Nothing -> demoConfigCatalogSource
      selectedDemoConfigPath = case maybeDemoConfigPath of
        Just demoConfigPath -> demoConfigPath
        Nothing ->
          case maybeClusterConfig of
            Just clusterConfig ->
              let demoPath = Text.unpack (demoConfigFilePath (clusterDemoBackend clusterConfig))
               in if null demoPath then generatedDemoConfigPath paths else demoPath
            Nothing -> generatedDemoConfigPath paths
      engineOverrides = engineOverridesFromClusterConfig maybeClusterConfig
  demoConfig <- decodeDemoConfigFile selectedDemoConfigPath
  daemonConfig <- requireDaemonConfig runtimeMode daemonRole maybeEngineName demoConfig
  let daemonLocation = case maybeClusterConfig of
        Just clusterConfig ->
          let mounted = Text.unpack (coordinatorDaemonLocation (clusterCoordinator clusterConfig))
           in if null mounted then Text.unpack (daemonConfigLocation daemonConfig) else mounted
        Nothing -> Text.unpack (daemonConfigLocation daemonConfig)
  putStrLn ("serviceControlPlaneContext: " <> controlPlaneContextId controlPlane)
  putStrLn ("serviceDaemonRole: " <> Text.unpack (daemonRoleId daemonRole))
  forM_ maybeEngineName $ \engineName ->
    putStrLn ("serviceEngineName: " <> Text.unpack engineName)
  forM_ (daemonConfigMemberId daemonConfig) $ \memberId ->
    putStrLn ("serviceEngineMemberId: " <> Text.unpack memberId)
  putStrLn ("serviceDaemonLocation: " <> daemonLocation)
  putStrLn ("serviceCatalogSource: " <> catalogSource)
  putStrLn ("serviceRuntimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("serviceDemoConfigPath: " <> selectedDemoConfigPath)
  putStrLn ("serviceMountedDemoConfigPath: " <> watchedDemoConfigPath)
  putStrLn ("serviceRequestTopics: " <> intercalate "," (map Text.unpack (daemonConfigRequestTopics daemonConfig)))
  putStrLn ("serviceResultTopic: " <> Text.unpack (daemonConfigResultTopic daemonConfig))
  forM_ (daemonConfigHostBatchTopic daemonConfig) $ \topicValue ->
    putStrLn ("serviceHostBatchTopic: " <> Text.unpack topicValue)
  putStrLn ("serviceEngineBindingCount: " <> show (length (engines demoConfig)))
  putStrLn "serviceHttpListener: disabled"
  clearServiceReadinessMarker paths
  case maybeTransport of
    Nothing ->
      runFilesystemTopicSpool paths runtimeMode engineOverrides daemonConfig demoConfig engineKVCache
    Just transport ->
      runWebSocketPulsarDaemon paths runtimeMode engineOverrides daemonConfig demoConfig daemonRole engineKVCache transport

engineOverridesFromClusterConfig :: Maybe ClusterConfig -> EngineCommandOverrideMap
engineOverridesFromClusterConfig maybeClusterConfig =
  case maybeClusterConfig of
    Just clusterConfig ->
      map
        (\override -> (engineOverrideKey override, engineOverrideValue override))
        (engineCommandOverrides (clusterEngine clusterConfig))
    Nothing -> []

runFilesystemTopicSpool ::
  Paths ->
  RuntimeMode ->
  EngineCommandOverrideMap ->
  DaemonConfig ->
  DemoConfig ->
  KVCache.EngineKVCache ->
  IO ()
runFilesystemTopicSpool paths runtimeMode engineOverrides daemonConfig demoConfig engineKVCache = do
  ensureSchemaMarkers paths demoConfig
  writeServiceReadinessMarker paths
  putStrLn "serviceSubscriptionMode: filesystem-topic-spool"
  forever $ do
    forM_
      (daemonConfigRequestTopics daemonConfig)
      (drainTopicWithKVCache paths runtimeMode engineOverrides daemonConfig (Just engineKVCache))
    threadDelay 500000

runWebSocketPulsarDaemon ::
  Paths ->
  RuntimeMode ->
  EngineCommandOverrideMap ->
  DaemonConfig ->
  DemoConfig ->
  DaemonRole ->
  KVCache.EngineKVCache ->
  PulsarTransport ->
  IO ()
runWebSocketPulsarDaemon paths runtimeMode engineOverrides daemonConfig demoConfig daemonRole engineKVCache transport = do
  ensureSchemaMarkers paths demoConfig
  reconcileSupportedNamespacesWithRetry transport demoConfig
  ensureRegisteredSchemasWithRetry paths transport demoConfig
  writeServiceReadinessMarker paths
  putStrLn "serviceSubscriptionMode: websocket-pulsar"
  putStrLn ("servicePulsarWsBaseUrl: " <> renderPulsarWebSocketBase (pulsarWebSocketBase transport))
  case (runtimeMode, daemonRole, daemonConfigRequestTopics daemonConfig) of
    (AppleSilicon, Engine, primaryTopic : extraTopics) -> do
      forM_
        extraTopics
        (forkIO . consumeTopicForever transport paths runtimeMode engineOverrides daemonConfig demoConfig (Just engineKVCache))
      consumeTopicForever transport paths runtimeMode engineOverrides daemonConfig demoConfig (Just engineKVCache) primaryTopic
    _ -> do
      forM_
        (daemonConfigRequestTopics daemonConfig)
        (forkIO . consumeTopicForever transport paths runtimeMode engineOverrides daemonConfig demoConfig (Just engineKVCache))
      when (daemonRole == Coordinator) $
        startCoordinatorLoops transport runtimeMode daemonConfig demoConfig
      forever (threadDelay 60000000)

startCoordinatorLoops ::
  PulsarTransport ->
  RuntimeMode ->
  DaemonConfig ->
  DemoConfig ->
  IO ()
startCoordinatorLoops transport runtimeMode daemonConfig demoConfig = do
  putStrLn "serviceResultBridgeMode: failover-subscription"
  _ <-
    forkIO
      ( runResultBridgeLoop
          transport
          runtimeMode
          (daemonConfigResultTopic daemonConfig)
          ConversationTopic.defaultDemoTopicNamespace
      )
  putStrLn "serviceModelBootstrapMode: failover-subscription"
  _ <-
    forkIO
      ( runModelBootstrapLoop
          transport
          ConversationTopic.systemTopicNamespace
      )
  putStrLn "serviceDispatcherMode: per-context-failover"
  contextModelMap <- ContextModelMap.newContextModelMap
  _ <-
    forkIO
      ( runDispatcherLoop
          transport
          runtimeMode
          (firstOrEmpty (daemonConfigRequestTopics daemonConfig))
          ConversationTopic.defaultDemoTopicNamespace
          contextModelMap
          (models demoConfig)
      )
  pure ()

firstOrEmpty :: [Text.Text] -> Text.Text
firstOrEmpty [] = ""
firstOrEmpty (topic : _) = topic

resolveClusterControlPlaneContext :: ClusterConfig -> ControlPlaneContext -> ControlPlaneContext
resolveClusterControlPlaneContext clusterConfig fallback =
  let mounted = Text.unpack (coordinatorControlPlaneContext (clusterCoordinator clusterConfig))
   in fromMaybe fallback (parseControlPlaneContext mounted)

demoConfigCatalogSource :: String
demoConfigCatalogSource = "generated-build-root"

requireDaemonConfig :: RuntimeMode -> DaemonRole -> Maybe Text.Text -> DemoConfig -> IO DaemonConfig
requireDaemonConfig runtimeMode daemonRole maybeEngineName demoConfig
  | daemonConfigRole (coordinatorDaemon demoConfig) == daemonRole =
      pure (coordinatorDaemon demoConfig)
  | daemonRole == Engine =
      maybe missingDaemonConfig pure selectEngineDaemon
  | otherwise = missingDaemonConfig
  where
    selectEngineDaemon =
      maybe firstEngineDaemon engineDaemonForName maybeEngineName
    firstEngineDaemon =
      find ((== Engine) . daemonConfigRole) (engineDaemons demoConfig)
    engineDaemonForName engineName =
      find (engineDaemonMatches engineName) (engineDaemons demoConfig)
      where
        expectedTopic = perEngineBatchTopicForMode runtimeMode engineName
        engineDaemonMatches selector daemonConfig =
          daemonConfigRole daemonConfig == Engine
            && (daemonConfigMemberId daemonConfig == Just selector || engineDaemonConsumes expectedTopic daemonConfig)
    engineDaemonConsumes expectedTopic daemonConfig =
      daemonConfigRole daemonConfig == Engine
        && expectedTopic `elem` daemonConfigRequestTopics daemonConfig
    missingDaemonConfig =
      ioError
        ( userError
            ( "generated substrate file does not contain daemon metadata for role "
                <> Text.unpack (daemonRoleId daemonRole)
                <> maybe "" ((" and engine " <>) . Text.unpack) maybeEngineName
            )
        )
