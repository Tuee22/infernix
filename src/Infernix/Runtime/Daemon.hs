{-# LANGUAGE OverloadedStrings #-}

module Infernix.Runtime.Daemon
  ( runProductionDaemon,
  )
where

import Control.Concurrent (forkIO, threadDelay)
import Control.Monad (forM_, forever, when)
import Data.List (intercalate)
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Infernix.ClusterConfig
  ( ClusterConfig (..),
    CoordinatorWiring (..),
    DemoBackendWiring (..),
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
import Infernix.Dispatch.ContextModelMap qualified as ContextModelMap
import Infernix.ExecutionPlan
  ( CompiledDaemon,
    CompiledRuntimePlan,
    compiledDaemonLocation,
    compiledDaemonMemberId,
    compiledDaemonRequestTopics,
    compiledDaemonResultTopic,
    compiledDaemonRole,
    compiledPlanAvailableModels,
    compiledPlanCoordinatorDaemon,
    compiledPlanEngineDaemons,
    compiledPlanRuntimeMode,
    compiledPlanWebappDaemon,
    lookupCompiledEngineDaemon,
    runtimePlanCompiledPlan,
    runtimePlanModels,
  )
import Infernix.MachineContract (SystemContractDigest, digestSystemContractFile)
import Infernix.Runtime.CappedEngine (engineExecutionRuntimePlan)
import Infernix.Runtime.Enforcer (EngineExecutionPlan, refineCompiledRuntimePlan)
import Infernix.Runtime.KVCache qualified as KVCache
import Infernix.Runtime.Pulsar
  ( ContractDigestAuthority,
    DaemonTopicCapability,
    EngineMemberClaim,
    PulsarTransport,
    clearServiceReadinessMarker,
    consumeTopicForever,
    contractDigestAuthorityForRole,
    coordinatorTopicCapabilities,
    discoverPulsarTransport,
    drainTopicWithKVCache,
    engineTopicCapabilities,
    ensureRegisteredSchemasForPlanWithRetry,
    ensureSchemaMarkersForPlan,
    pulsarWebSocketBase,
    reconcileStartupTopicsForPlanWithRetry,
    reconcileSupportedNamespacesForPlanWithRetry,
    renderPulsarWebSocketBase,
    runDispatcherLoop,
    runModelBootstrapLoop,
    runResultBridgeLoop,
    sweepEagerModelCacheForPlan,
    withEngineMemberClaim,
    writeServiceReadinessMarker,
  )
import Infernix.Substrate (decodeCompiledRuntimePlanFile)
import Infernix.Types hiding (generatedDemoConfigPath)

-- | Phase 7 Sprint 7.8: daemon role orchestration lives outside the
-- Pulsar transport module. The daemon layer decides which role starts
-- coordinator loops, which role owns engine execution, and which
-- process-local engine KV cache is threaded into request handling.
data DaemonExecutionPlan
  = RoutingDaemonPlan CompiledRuntimePlan
  | ExecutingDaemonPlan Text.Text EngineExecutionPlan

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
  compiledPlanResult <- decodeCompiledRuntimePlanFile selectedDemoConfigPath
  compiledPlan <-
    case compiledPlanResult of
      Left errors ->
        ioError
          (userError ("generated substrate execution plan did not compile: " <> show errors))
      Right plan -> pure plan
  -- Phase 8 Sprint 8.11: the digest registered on every topic this daemon
  -- touches is the digest of the payload it actually compiled its plan from,
  -- which in a pod is the mounted publication rather than the generated pair on
  -- disk. That is the point: the broker check has to cover the contract the
  -- daemon is really running.
  contractDigest <- digestSystemContractFile selectedDemoConfigPath
  when (compiledPlanRuntimeMode compiledPlan /= runtimeMode) $
    ioError
      ( userError
          ( "generated substrate runtime does not match the requested daemon runtime: compiled "
              <> Text.unpack (runtimeModeId (compiledPlanRuntimeMode compiledPlan))
              <> ", requested "
              <> Text.unpack (runtimeModeId runtimeMode)
          )
      )
  compiledDaemon <- requireCompiledDaemon daemonRole maybeEngineName compiledPlan
  daemonExecutionPlan <-
    case compiledDaemonRole compiledDaemon of
      Engine -> do
        refinementResult <- refineCompiledRuntimePlan paths compiledPlan
        case refinementResult of
          Left errors ->
            ioError
              (userError ("generated substrate runtime plan could not be refined against live enforcement: " <> show errors))
          Right executionPlan -> do
            memberIdValue <-
              case compiledDaemonMemberId compiledDaemon of
                Nothing ->
                  ioError
                    (userError "compiled engine daemon has no member identity")
                Just memberId -> pure memberId
            pure (ExecutingDaemonPlan memberIdValue executionPlan)
      Coordinator -> pure (RoutingDaemonPlan compiledPlan)
      Webapp ->
        ioError
          (userError "webapp role does not run the inference topic daemon")
  topicCapabilities <-
    case daemonTopicCapabilities daemonExecutionPlan of
      Left err -> ioError (userError err)
      Right [] ->
        ioError
          (userError "compiled daemon capability does not authorize any request topics")
      Right capabilities -> pure capabilities
  let daemonLocation = case maybeClusterConfig of
        Just clusterConfig ->
          let mounted = Text.unpack (coordinatorDaemonLocation (clusterCoordinator clusterConfig))
           in if null mounted then Text.unpack (compiledDaemonLocation compiledDaemon) else mounted
        Nothing -> Text.unpack (compiledDaemonLocation compiledDaemon)
  putStrLn ("serviceControlPlaneContext: " <> controlPlaneContextId controlPlane)
  putStrLn ("serviceDaemonRole: " <> Text.unpack (daemonRoleId (compiledDaemonRole compiledDaemon)))
  forM_ maybeEngineName $ \engineName ->
    putStrLn ("serviceEngineName: " <> Text.unpack engineName)
  forM_ (compiledDaemonMemberId compiledDaemon) $ \memberId ->
    putStrLn ("serviceEngineMemberId: " <> Text.unpack memberId)
  putStrLn ("serviceDaemonLocation: " <> daemonLocation)
  putStrLn ("serviceCatalogSource: " <> catalogSource)
  putStrLn ("serviceRuntimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("serviceDemoConfigPath: " <> selectedDemoConfigPath)
  putStrLn ("serviceMountedDemoConfigPath: " <> watchedDemoConfigPath)
  putStrLn ("serviceRequestTopics: " <> intercalate "," (map Text.unpack (compiledDaemonRequestTopics compiledDaemon)))
  putStrLn ("serviceResultTopic: " <> Text.unpack (compiledDaemonResultTopic compiledDaemon))
  putStrLn ("serviceExecutableModelCount: " <> show (daemonExecutableModelCount daemonExecutionPlan))
  putStrLn "serviceHttpListener: disabled"
  clearServiceReadinessMarker paths
  case maybeTransport of
    Nothing ->
      runFilesystemTopicSpool paths daemonExecutionPlan topicCapabilities engineKVCache
    Just transport ->
      runWebSocketPulsarDaemon paths daemonExecutionPlan topicCapabilities engineKVCache transport (contractDigestAuthorityForRole (compiledDaemonRole compiledDaemon)) contractDigest

daemonExecutableModelCount :: DaemonExecutionPlan -> Int
daemonExecutableModelCount daemonPlan =
  case daemonPlan of
    RoutingDaemonPlan compiledPlan ->
      length (compiledPlanAvailableModels compiledPlan)
    ExecutingDaemonPlan _ executionPlan ->
      let runtimePlan = engineExecutionRuntimePlan executionPlan
       in length (runtimePlanModels runtimePlan)

daemonCompiledPlan :: DaemonExecutionPlan -> CompiledRuntimePlan
daemonCompiledPlan daemonPlan =
  case daemonPlan of
    RoutingDaemonPlan compiledPlan -> compiledPlan
    ExecutingDaemonPlan _ executionPlan ->
      runtimePlanCompiledPlan (engineExecutionRuntimePlan executionPlan)

daemonTopicCapabilities ::
  DaemonExecutionPlan ->
  Either String [DaemonTopicCapability]
daemonTopicCapabilities daemonPlan =
  case daemonPlan of
    RoutingDaemonPlan compiledPlan ->
      Right (coordinatorTopicCapabilities compiledPlan)
    ExecutingDaemonPlan memberIdValue executionPlan ->
      engineTopicCapabilities memberIdValue executionPlan

runFilesystemTopicSpool ::
  Paths ->
  DaemonExecutionPlan ->
  [DaemonTopicCapability] ->
  KVCache.EngineKVCache ->
  IO ()
runFilesystemTopicSpool paths daemonPlan topicCapabilities engineKVCache = do
  let compiledPlan = daemonCompiledPlan daemonPlan
  ensureSchemaMarkersForPlan paths compiledPlan
  writeServiceReadinessMarker paths
  putStrLn "serviceSubscriptionMode: filesystem-topic-spool"
  forever $ do
    forM_
      topicCapabilities
      (\capability -> drainTopicWithKVCache paths capability (Just engineKVCache))
    threadDelay 500000

runWebSocketPulsarDaemon ::
  Paths ->
  DaemonExecutionPlan ->
  [DaemonTopicCapability] ->
  KVCache.EngineKVCache ->
  PulsarTransport ->
  ContractDigestAuthority ->
  SystemContractDigest ->
  IO ()
runWebSocketPulsarDaemon paths daemonPlan topicCapabilities engineKVCache transport contractAuthority contractDigest = do
  let compiledPlan = daemonCompiledPlan daemonPlan
  ensureSchemaMarkersForPlan paths compiledPlan
  reconcileSupportedNamespacesForPlanWithRetry transport compiledPlan
  reconcileStartupTopicsForPlanWithRetry transport compiledPlan
  ensureRegisteredSchemasForPlanWithRetry paths transport contractAuthority contractDigest compiledPlan
  -- Phase 8 Sprint 8.12: an engine holds the broker-side claim on its member
  -- identity for the whole of its consuming life.
  --
  -- The claim sits here rather than first for two reasons. The namespace and
  -- the claim topic have to exist before an exclusive subscription on one can
  -- be granted, and the reconcile above is what creates them — claiming first
  -- would leave a cold-cluster engine retrying a topic nothing had created yet.
  -- And the contract-digest check runs before it, so a machine that disagrees
  -- with the fleet's registered contract refuses before it claims an identity
  -- inside that fleet rather than after.
  --
  -- What the position does guarantee is what matters: the claim precedes the
  -- readiness sentinel and every pool subscription, so a machine refused for
  -- adopting another machine's identity never reports ready and never takes a
  -- message a second machine might answer too.
  withDaemonEngineMemberClaim transport daemonPlan $ \_memberClaim -> do
    writeServiceReadinessMarker paths
    putStrLn "serviceSubscriptionMode: websocket-pulsar"
    putStrLn ("servicePulsarWsBaseUrl: " <> renderPulsarWebSocketBase (pulsarWebSocketBase transport))
    case (daemonPlan, compiledPlanRuntimeMode compiledPlan, topicCapabilities) of
      (ExecutingDaemonPlan {}, AppleSilicon, primaryCapability : extraCapabilities) -> do
        forM_
          extraCapabilities
          ( \capability ->
              forkIO
                ( consumeTopicForever
                    transport
                    paths
                    capability
                    (Just engineKVCache)
                )
          )
        consumeTopicForever transport paths primaryCapability (Just engineKVCache)
      (ExecutingDaemonPlan {}, _, capabilities) -> do
        forM_
          capabilities
          ( \capability ->
              forkIO
                ( consumeTopicForever
                    transport
                    paths
                    capability
                    (Just engineKVCache)
                )
          )
        forever (threadDelay 60000000)
      (RoutingDaemonPlan routingPlan, _, capabilities) -> do
        forM_
          capabilities
          ( \capability ->
              forkIO
                ( consumeTopicForever
                    transport
                    paths
                    capability
                    (Just engineKVCache)
                )
          )
        startCoordinatorLoops transport routingPlan
        forever (threadDelay 60000000)

-- | Phase 8 Sprint 8.12 — take the broker-side member claim when, and only
-- when, this daemon is an engine.
--
-- A coordinator and a webapp have no member identity to claim: they are
-- routers and presenters, and the fleet's one-process-per-machine rule is about
-- the processes that hold KV caches, load weights, and admit work against a
-- machine's capacity. Claiming for them would create an exclusive slot nothing
-- protects and would refuse a legitimate second coordinator during a rollout.
withDaemonEngineMemberClaim ::
  PulsarTransport ->
  DaemonExecutionPlan ->
  (Maybe EngineMemberClaim -> IO a) ->
  IO a
withDaemonEngineMemberClaim transport daemonPlan action =
  case daemonPlan of
    RoutingDaemonPlan _ -> action Nothing
    ExecutingDaemonPlan memberIdValue executionPlan ->
      let runtimePlan = engineExecutionRuntimePlan executionPlan
       in withEngineMemberClaim
            transport
            (compiledPlanRuntimeMode (runtimePlanCompiledPlan runtimePlan))
            memberIdValue
            (action . Just)

startCoordinatorLoops ::
  PulsarTransport ->
  CompiledRuntimePlan ->
  IO ()
startCoordinatorLoops transport compiledPlan = do
  putStrLn "serviceResultBridgeMode: failover-subscription"
  _ <-
    forkIO
      ( runResultBridgeLoop
          transport
          compiledPlan
      )
  putStrLn "serviceModelBootstrapMode: failover-subscription"
  _ <-
    forkIO
      ( runModelBootstrapLoop
          transport
          compiledPlan
      )
  -- Phase 8 Sprint 8.5: eager model-cache staging. Begin staging every model
  -- in the mounted substrate config the moment the coordinator comes up, so no
  -- inference races a cold cache. Runs in the background; the lazy
  -- `runModelBootstrapLoop` above remains the on-demand fallback, and the
  -- `cluster up` warm-model-cache barrier waits on the `.ready` sentinels.
  putStrLn "serviceEagerModelCacheMode: startup-sweep"
  _ <-
    forkIO
      ( sweepEagerModelCacheForPlan
          transport
          compiledPlan
      )
  putStrLn "serviceDispatcherMode: per-context-failover"
  contextModelMap <- ContextModelMap.newContextModelMap
  _ <-
    forkIO
      ( runDispatcherLoop
          transport
          compiledPlan
          contextModelMap
      )
  pure ()

resolveClusterControlPlaneContext :: ClusterConfig -> ControlPlaneContext -> ControlPlaneContext
resolveClusterControlPlaneContext clusterConfig fallback =
  let mounted = Text.unpack (coordinatorControlPlaneContext (clusterCoordinator clusterConfig))
   in fromMaybe fallback (parseControlPlaneContext mounted)

demoConfigCatalogSource :: String
demoConfigCatalogSource = "generated-build-root"

requireCompiledDaemon :: DaemonRole -> Maybe Text.Text -> CompiledRuntimePlan -> IO CompiledDaemon
requireCompiledDaemon daemonRole maybeEngineName compiledPlan =
  case daemonRole of
    Coordinator -> pure (compiledPlanCoordinatorDaemon compiledPlan)
    Webapp -> pure (compiledPlanWebappDaemon compiledPlan)
    Engine ->
      case maybeEngineName of
        Just engineName ->
          maybe missingCompiledDaemon pure (lookupCompiledEngineDaemon engineName compiledPlan)
        -- Phase 4 Sprint 4.34: identity fails closed. The retired form took the
        -- first entry of the compiled catalog, which is a `Map` keyed by member
        -- id, so the silent default was the lexicographically smallest id — and
        -- no bootstrap path passes a name, so two machines resolving the same
        -- identity was the default rather than an edge case. Each would then
        -- assert its own physical RAM as the budget for work the other may
        -- execute, and nothing detects it: the broker sees two ordinary `Shared`
        -- consumers with distinct process-qualified names.
        --
        -- One compiled engine daemon is not a default — it is a determination,
        -- and the daemon adopts it. Two or more without a name is a daemon that
        -- cannot say which member it is, and it refuses to start.
        Nothing ->
          case compiledPlanEngineDaemons compiledPlan of
            [singleDaemon] -> pure singleDaemon
            [] -> missingCompiledDaemon
            manyDaemons ->
              ioError
                ( userError
                    ( "engine daemon identity is ambiguous: the compiled plan has "
                        <> show (length manyDaemons)
                        <> " engine members and no --engine-name was given. Pass"
                        <> " --engine-name with one of: "
                        <> intercalate
                          ", "
                          [ Text.unpack memberIdValue
                          | daemon <- manyDaemons,
                            Just memberIdValue <- [compiledDaemonMemberId daemon]
                          ]
                        <> ". A daemon that cannot establish which member it is"
                        <> " refuses to start rather than adopting a default,"
                        <> " because each member asserts its own machine's"
                        <> " capacity for the work it admits."
                    )
                )
  where
    missingCompiledDaemon =
      ioError
        ( userError
            ( "generated substrate file does not contain daemon metadata for role "
                <> Text.unpack (daemonRoleId daemonRole)
                <> maybe "" ((" and engine " <>) . Text.unpack) maybeEngineName
            )
        )
