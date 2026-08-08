{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Infernix.ExecutionPlan
  ( CompiledDaemon,
    CompiledPlacement,
    CompiledRuntimePlan,
    ConfigError (..),
    ConfigErrors,
    Enforcer,
    EnforcerPlan,
    EngineRoute,
    ExecutableModel,
    MemoryCeiling,
    MemoryGrant,
    RawRuntimeConfig,
    RefinementError (..),
    RefinementErrors,
    Resource (..),
    RuntimeObservation,
    RuntimePlan,
    UnavailableModel,
    compileRuntimePlan,
    compiledDaemonConsumerSubscriptionType,
    compiledDaemonLocation,
    compiledDaemonMemberId,
    compiledDaemonPulsarConnectionMode,
    compiledDaemonRequestTopics,
    compiledDaemonResultTopic,
    compiledDaemonRole,
    compiledPlacementDescriptor,
    compiledPlacementEngine,
    compiledPlacementId,
    compiledPlacementRoutes,
    compiledPlanAvailableModels,
    compiledPlanActiveDaemonRole,
    compiledPlanConfiguredModels,
    compiledPlanCoordinatorDaemon,
    compiledPlanEngineDaemons,
    compiledPlanModelBootstrapTopic,
    compiledPlanModelsBucket,
    compiledPlanPlacementEnforcedResources,
    compiledPlanPlacementEnforcementShape,
    compiledPlanRequestTopics,
    compiledPlanResultTopic,
    compiledPlanRuntimeMode,
    compiledPlanWebappDaemon,
    compiledRuntimePlanPlacements,
    engineRouteMaxInflightPerMember,
    engineRouteMemberId,
    engineRoutePoolId,
    engineRouteSubscriptionType,
    engineRouteTopic,
    executableModelDescriptor,
    executableModelEngine,
    executableModelGpuVramCeilingMib,
    executableModelId,
    executableModelResidentCeilingMib,
    executableModelResidentResource,
    executableModelRoutes,
    linuxOuterEnvelopeHeadroomMib,
    lookupCompiledPlacement,
    lookupCompiledEngineDaemon,
    lookupExecutableModel,
    lookupRuntimeUnavailableModel,
    memoryCeilingMib,
    predictedAdmissionRejection,
    refineRuntimePlan,
    runtimePlanCompiledPlan,
    runtimePlanModels,
    runtimePlanUnavailableModels,
    unavailableModelDescriptor,
    unavailableModelReason,
  )
where

import Data.Char (isAsciiLower, isDigit, isSpace)
import Data.List (group, sort)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Infernix.Bootstrap.Models qualified as BootstrapModels
import Infernix.EngineRouting (enginePoolTopicForMode)
import Infernix.ExecutionPlan.Internal
  ( CompiledDaemon (..),
    CompiledPlacement (..),
    CompiledResources (..),
    CompiledRuntimePlan (..),
    EnforcedGrant (..),
    Enforcer (..),
    EnforcerPlan (..),
    EngineRoute (..),
    ExecutableModel (..),
    MemoryCeiling (..),
    MemoryGrant (..),
    PlacementEnforcementShape (..),
    PlacementObservation (..),
    RawRuntimeConfig (..),
    Resource (..),
    RuntimeObservation (..),
    RuntimePlan (..),
    RuntimeResources (..),
    UnavailableModel (..),
  )
import Infernix.Types
  ( ConsumerSubscriptionType (ConsumerShared),
    DaemonConfig (..),
    DaemonRole (..),
    DemoConfig (..),
    EngineBinding (..),
    EngineMember (..),
    EnginePool (..),
    InferenceError (..),
    InferenceMemoryBudget (..),
    InferenceMemoryResource,
    ModelDescriptor (..),
    PodMemoryLimit (..),
    PulsarConnectionMode (..),
    RequestField (..),
    RuntimeMode (..),
    defaultModelBootstrapTopic,
    defaultModelsBucket,
    hostPartitionInferenceCapacityMib,
    inferenceMemoryBudgetPodLimits,
    inferenceMemoryBudgetResource,
    inferenceMemoryBudgetSource,
    modelMemoryFootprintMib,
  )
import Infernix.Types qualified as Types

data ConfigError
  = EmptyModelCatalog
  | EmptyPoolCatalog
  | EmptyMemberCatalog
  | BlankModelsBucket
  | BlankModelBootstrapTopic
  | ModelsBucketMismatch Text Text
  | ModelBootstrapTopicMismatch Text Text
  | BlankConfigMapName
  | BlankGeneratedPath
  | BlankMountedPath
  | InvalidActiveDaemonRole
  | DaemonRoleMismatch Text DaemonRole DaemonRole
  | DaemonMemberMismatch Text (Maybe Text) (Maybe Text)
  | DaemonConnectionModeMismatch Text PulsarConnectionMode PulsarConnectionMode
  | InvalidModelDescriptor Text
  | InvalidModelId Text
  | InvalidMatrixRowId Text
  | UnenforceableModelMemoryFootprint Text Integer
  | DuplicateModelId Text
  | DuplicateMatrixRowId Text
  | DuplicatePoolId Text
  | DuplicateMemberId Text
  | DuplicatePoolModelReference Text Text
  | DuplicatePoolMemberReference Text Text
  | DuplicateMemberPoolReference Text Text
  | DuplicateRequestField Text Text
  | InvalidPoolId Text
  | InvalidMemberId Text
  | EmptyPoolModels Text
  | EmptyPoolMembers Text
  | EmptyMemberPools Text
  | UnknownSelectedEngine Text Text
  | UnsupportedGpuRequirement Text RuntimeMode
  | DanglingPoolModel Text Text
  | DanglingPoolMember Text Text
  | DanglingMemberPool Text Text
  | PoolMemberLinkMissing Text Text
  | MemberPoolLinkMissing Text Text
  | UnplacedModel Text
  | MultiplyPlacedModel Text [Text]
  | InvalidPoolSubscription Text
  | ModelWithoutEligibleMember Text
  | DuplicateDerivedRouteTopic Text [(Text, Text)]
  | TopicFamilyCollision Text [Text]
  | RuntimeBudgetMismatch RuntimeMode InferenceMemoryResource
  | GpuDualResourceBudgetRequired
  | GpuModelWithoutVramEnforcer Text
  | InvalidMemoryEnforcer Text
  deriving (Eq, Show)

type ConfigErrors = NonEmpty ConfigError

data RefinementError
  = -- | Phase 4 Sprint 4.34: this machine placed models and admitted none of
    -- them. A daemon built from that plan would start, report ready, and answer
    -- every request with a memory rejection, which is a worse failure than
    -- refusing to start. It is a refinement error rather than a config error
    -- because admission belongs to the machine that will execute: a catalog the
    -- coordinator's box cannot fund says nothing about the engine's box.
    NoAdmissiblePlacement [Text]
  | DuplicatePlacementObservation Text
  | MissingPlacementObservation Text
  | UnexpectedPlacementObservation Text
  | PlacementObservationResourceMismatch Text
  | PhysicalFootprintSamplerUnavailable Text
  | HostPartitionObservationUnavailable Text
  | HostPartitionMismatch Text Types.HostMemoryPartition Types.HostMemoryPartition
  | ResidentSamplerUnavailable Text
  | NvidiaSamplerUnavailable Text
  | OuterEnvelopeUnavailable Text
  | OuterEnvelopeTooSmall Text Integer Integer
  | OuterEnvelopeTooLarge Text Integer Integer
  | NvidiaEnvelopeUnavailable Text
  | NvidiaEnvelopeTooSmall Text Integer Integer
  deriving (Eq, Show)

type RefinementErrors = NonEmpty RefinementError

data ResourceWitness resource where
  HostRamWitness :: ResourceWitness 'HostRam
  PodRamWitness :: ResourceWitness 'PodRam
  NvidiaVramWitness :: ResourceWitness 'NvidiaVram

-- | Memory retained outside a Linux child execution grant for the Haskell
-- daemon and worst-case sampler overshoot.
linuxOuterEnvelopeHeadroomMib :: Int
linuxOuterEnvelopeHeadroomMib = 1024

maxEnforceableMemoryMib :: Integer
maxEnforceableMemoryMib =
  toInteger (maxBound :: Word64) `div` 1048576

compileRuntimePlan :: RawRuntimeConfig -> Either ConfigErrors CompiledRuntimePlan
compileRuntimePlan (RawRuntimeConfig config) =
  case compilerErrors config of
    [] -> do
      (coordinatorCapability, webappCapability, engineCapabilities) <-
        mapLeftSingleton (compileDaemonCapabilities config)
      compiledPlacementList <-
        mapLeftSingleton (traverse (compileModel config) (models config))
      Right
        CompiledRuntimePlan
          { compiledConfig = config,
            compiledCoordinator = coordinatorCapability,
            compiledWebapp = webappCapability,
            compiledEngineDaemonMap = engineCapabilities,
            compiledPlacements =
              Map.fromList
                [ (modelId (placementDescriptor placement), placement)
                | placement <- compiledPlacementList
                ]
          }
    firstError : remainingErrors -> Left (firstError :| remainingErrors)

mapLeftSingleton :: Either ConfigError value -> Either ConfigErrors value
mapLeftSingleton =
  either (Left . (:| [])) Right

-- | Phase 8 Sprint 8.10: the engine daemons are derived one per member, so the
-- missing-daemon and duplicate-member refusals this used to raise have no
-- inhabitant left and are retired with the field they guarded.
compileDaemonCapabilities ::
  DemoConfig ->
  Either ConfigError (CompiledDaemon, CompiledDaemon, Map.Map Text CompiledDaemon)
compileDaemonCapabilities config =
  Right
    ( CompiledDaemon (coordinatorDaemon config),
      CompiledDaemon (webappDaemon config),
      Map.fromList
        [ (memberIdValue, CompiledDaemon daemon)
        | daemon <- engineDaemons config,
          Just memberIdValue <- [daemonConfigMemberId daemon]
        ]
    )

-- | Place one model on the validated engine-pool graph. This is pure graph
-- validation: it decides where a model /may/ run, never whether the machine
-- reading the config can fund it.
compileModel ::
  DemoConfig ->
  ModelDescriptor ->
  Either ConfigError CompiledPlacement
compileModel config model = do
  binding <-
    maybe
      (Left (UnknownSelectedEngine (modelId model) (selectedEngine model)))
      Right
      (Map.lookup (selectedEngine model) engineMap)
  pool <-
    case filter ((modelId model `elem`) . enginePoolModelIds) (enginePools config) of
      [singlePool] -> Right singlePool
      [] -> Left (UnplacedModel (modelId model))
      manyPools -> Left (MultiplyPlacedModel (modelId model) (map enginePoolId manyPools))
  routeList <- traverse (routeForMember pool) (enginePoolMemberIds pool)
  routes <-
    case NonEmpty.nonEmpty routeList of
      Nothing -> Left (ModelWithoutEligibleMember (modelId model))
      Just nonEmptyRoutes -> Right nonEmptyRoutes
  Right
    CompiledPlacement
      { placementDescriptor = model,
        placementEngine = binding,
        placementRoutes = routes
      }
  where
    engineMap = Map.fromList [(engineBindingName binding, binding) | binding <- engines config]
    memberMap = Map.fromList [(engineMemberId member, member) | member <- engineMembers config]
    routeForMember pool memberIdValue = do
      member <-
        maybe
          (Left (DanglingPoolMember (enginePoolId pool) memberIdValue))
          Right
          (Map.lookup memberIdValue memberMap)
      if enginePoolId pool `elem` engineMemberPoolIds member
        then
          Right
            EngineRoute
              { routePoolId = enginePoolId pool,
                routeMemberId = memberIdValue,
                routeTopic =
                  enginePoolTopicForMode
                    (configRuntimeMode config)
                    (enginePoolId pool)
                    (modelId model),
                routeSubscriptionType = enginePoolSubscriptionType pool,
                routeMaxInflightPerMember = enginePoolMaxInflightPerMember pool
              }
        else Left (PoolMemberLinkMissing (enginePoolId pool) memberIdValue)

-- | Which enforcement mechanism a placement runs under on this machine, and the
-- declared limits its grants will be admitted against.
--
-- Phase 4 Sprint 4.34: the enforcer must choose its samplers before it can
-- admit anything, so the shape is decided here, once, from the runtime mode,
-- the budget, and whether the model uses the device. 'admitPlacementResources'
-- reads the same value, which is why the probe and the grant cannot name
-- different limits.
--
-- 'Nothing' means the runtime mode and the declared budget name no mechanism at
-- all. 'compilerErrors' already rejects that pair as 'RuntimeBudgetMismatch' /
-- 'GpuDualResourceBudgetRequired', so it is unreachable from a compiled plan;
-- admission still fails closed on it rather than assuming a lane.
placementEnforcementShape ::
  RuntimeMode ->
  InferenceMemoryBudget ->
  ModelDescriptor ->
  Maybe PlacementEnforcementShape
placementEnforcementShape runtimeModeValue budget model =
  case (runtimeModeValue, budget) of
    (AppleSilicon, HostEnforcedBudget partition) ->
      Just (HostEnforcementShape partition)
    (LinuxCpu, SubstrateEnforcedBudget podLimit)
      | podMemoryLimitResource podLimit == Types.PodRam ->
          Just (PodEnforcementShape podLimit)
    -- Phase 6 Sprint 6.44 — a @linux-gpu@ model that actually uses the device
    -- must clear both limits, and each admitted quantity becomes its own
    -- resource-indexed grant with its own live watchdog. A @linux-gpu@ model
    -- that does not require the device stays on the resident-set lane alone: a
    -- VRAM grant it would never consume is not evidence of anything.
    (LinuxGpu, DualEnforcedBudget podLimit vramLimit)
      | podMemoryLimitResource podLimit == Types.PodRam,
        podMemoryLimitResource vramLimit == Types.GpuVram ->
          Just
            ( if requiresGpu model
                then GpuEnforcementShape podLimit vramLimit
                else PodEnforcementShape podLimit
            )
    _ -> Nothing

-- | The physical resources an enforcement shape binds, in enforcement order.
placementShapeEnforcedResources :: PlacementEnforcementShape -> [InferenceMemoryResource]
placementShapeEnforcedResources shape =
  case shape of
    HostEnforcementShape {} -> [Types.UnifiedHostRam]
    PodEnforcementShape {} -> [Types.PodRam]
    GpuEnforcementShape {} -> [Types.PodRam, Types.GpuVram]

-- | Admit one placement against the declared capacity of the machine that will
-- execute it. Reachable only from 'refineRuntimePlan', which needs a
-- 'RuntimeObservation' the enforcer alone can produce, so no routing-only role
-- can perform admission.
admitPlacementResources ::
  RuntimeMode ->
  InferenceMemoryBudget ->
  ModelDescriptor ->
  Either InferenceError CompiledResources
admitPlacementResources runtimeModeValue budget model =
  case placementEnforcementShape runtimeModeValue budget model of
    Just (HostEnforcementShape partition) ->
      CompiledHostResources
        (HostFootprintWatchdogPlan partition)
        <$> admitGrant
          HostRamWitness
          (inferenceMemoryBudgetSource budget)
          model
          (hostPartitionInferenceCapacityMib partition)
    Just (PodEnforcementShape podLimit) ->
      CompiledPodResources
        (LinuxProcessGroupRssWatchdogPlan podLimit)
        <$> admitGrant
          PodRamWitness
          (Types.podMemoryLimitSourceText (podMemoryLimitSource podLimit))
          model
          (podMemoryLimitMib podLimit)
    Just (GpuEnforcementShape podLimit vramLimit) ->
      CompiledGpuResources
        (LinuxProcessGroupRssWatchdogPlan podLimit)
        <$> admitGrant
          PodRamWitness
          (Types.podMemoryLimitSourceText (podMemoryLimitSource podLimit))
          model
          (podMemoryLimitMib podLimit)
        <*> pure (NvidiaVramAccountingPlan vramLimit)
        <*> admitGrant
          NvidiaVramWitness
          (Types.podMemoryLimitSourceText (podMemoryLimitSource vramLimit))
          model
          (podMemoryLimitMib vramLimit)
    Nothing ->
      Left
        ModelMemoryLimitExceeded
          { inferenceErrorModelId = modelId model,
            inferenceErrorRequiredMib = modelMemoryFootprintMib (modelRamFootprint model),
            inferenceErrorAvailableMib = 0,
            inferenceErrorResource = inferenceMemoryBudgetResource budget,
            inferenceErrorSource = "runtime-memory-enforcer-mismatch"
          }

-- | Admit one resource. The rejection payload names the resource the witness
-- indexes and the source of the limit that rejected it, so a dual-resource
-- placement reports which of its two independent limits was exceeded instead of
-- collapsing both onto one budget-wide source string.
admitGrant ::
  ResourceWitness resource ->
  Text ->
  ModelDescriptor ->
  Int ->
  Either InferenceError (MemoryGrant resource)
admitGrant witness limitSource model availableMib
  | requiredMib > availableMib =
      Left
        ModelMemoryLimitExceeded
          { inferenceErrorModelId = modelId model,
            inferenceErrorRequiredMib = requiredMib,
            inferenceErrorAvailableMib = availableMib,
            inferenceErrorResource = witnessInferenceResource witness,
            inferenceErrorSource = limitSource
          }
  | otherwise = Right (MemoryGrant (MemoryCeiling requiredMib))
  where
    requiredMib = modelMemoryFootprintMib (modelRamFootprint model)

witnessInferenceResource :: ResourceWitness resource -> InferenceMemoryResource
witnessInferenceResource witness =
  case witness of
    HostRamWitness -> Types.UnifiedHostRam
    PodRamWitness -> Types.PodRam
    NvidiaVramWitness -> Types.GpuVram

compilerErrors :: DemoConfig -> [ConfigError]
compilerErrors config =
  basicErrors
    <> structuralErrors
    <> graphErrors
    <> daemonErrors
    <> runtimeErrors
    <> budgetErrors
  where
    modelIds = map modelId (models config)
    matrixIds = map matrixRowId (models config)
    engineIds = map engineBindingName (engines config)
    poolIds = map enginePoolId (enginePools config)
    memberIds = map engineMemberId (engineMembers config)
    modelIdSet = Set.fromList modelIds
    engineIdSet = Set.fromList engineIds
    poolIdSet = Set.fromList poolIds
    memberIdSet = Set.fromList memberIds
    poolMap = Map.fromList [(enginePoolId pool, pool) | pool <- enginePools config]
    memberMap = Map.fromList [(engineMemberId member, member) | member <- engineMembers config]
    derivedRouteSources =
      Map.fromListWith
        (<>)
        [ ( enginePoolTopicForMode
              (configRuntimeMode config)
              (enginePoolId pool)
              modelIdValue,
            [(enginePoolId pool, modelIdValue)]
          )
        | pool <- enginePools config,
          modelIdValue <- enginePoolModelIds pool
        ]
    topicFamilies =
      Map.fromListWith
        Set.union
        ( [ (topic, Set.singleton "coordinator-request")
          | topic <- requestTopics config
          ]
            <> [(resultTopic config, Set.singleton "result")]
            <> [(modelBootstrapTopic config, Set.singleton "model-bootstrap-request")]
            <> [ ( topic,
                   Set.singleton "model-bootstrap-ready"
                 )
               | modelIdValue <- modelIds,
                 let topic = compiledModelBootstrapReadyTopic modelIdValue
               ]
            <> [ (topic, Set.singleton "engine-route")
               | topic <- Map.keys derivedRouteSources
               ]
        )
    modelPlacements modelIdValue =
      [enginePoolId pool | pool <- enginePools config, modelIdValue `elem` enginePoolModelIds pool]
    -- Phase 8 Sprint 8.10: the checks that only ever caught a generated field
    -- disagreeing with what the binary derives are retired together with those
    -- fields. They were the symptom, not the guard: the engine list, the engine
    -- daemons, the topics, the per-entity runtime mode and location, the pool
    -- in-flight knob, and the substrate limit's resource/source are now derived
    -- at decode, so there is nothing left for them to disagree with.
    basicErrors =
      [EmptyModelCatalog | null (models config)]
        <> [EmptyPoolCatalog | null (enginePools config)]
        <> [EmptyMemberCatalog | null (engineMembers config)]
        <> [BlankModelsBucket | blankText (modelsBucket config)]
        <> [BlankModelBootstrapTopic | blankText (modelBootstrapTopic config)]
        <> [ ModelsBucketMismatch defaultModelsBucket (modelsBucket config)
           | not (blankText (modelsBucket config)),
             modelsBucket config /= defaultModelsBucket
           ]
        <> [ ModelBootstrapTopicMismatch defaultModelBootstrapTopic (modelBootstrapTopic config)
           | not (blankText (modelBootstrapTopic config)),
             modelBootstrapTopic config /= defaultModelBootstrapTopic
           ]
        <> [BlankConfigMapName | blankText (configMapName config)]
        <> [BlankGeneratedPath | all isSpace (generatedPath config)]
        <> [BlankMountedPath | all isSpace (mountedPath config)]
        <> [InvalidActiveDaemonRole | not activeRoleDeclared]
        <> [ InvalidModelDescriptor (modelId model)
           | model <- models config,
             invalidModel model
           ]
        <> [InvalidModelId (modelId model) | model <- models config, not (canonicalIdentifier (modelId model))]
        <> [InvalidMatrixRowId (matrixRowId model) | model <- models config, not (canonicalIdentifier (matrixRowId model))]
        <> [ UnenforceableModelMemoryFootprint
               (modelId model)
               (toInteger (modelMemoryFootprintMib (modelRamFootprint model)))
           | model <- models config,
             toInteger (modelMemoryFootprintMib (modelRamFootprint model))
               > maxEnforceableMemoryMib
           ]
    activeRoleDeclared =
      activeDaemonRole config
        `elem` ( daemonConfigRole (coordinatorDaemon config)
                   : daemonConfigRole (webappDaemon config)
                   : map daemonConfigRole (engineDaemons config)
               )
    invalidModel model =
      any
        blankText
        [matrixRowId model, modelId model, selectedEngine model]
        || null (requestShape model)
        || any invalidRequestField (requestShape model)
    invalidRequestField requestField =
      blankText (name requestField) || blankText (label requestField)
    structuralErrors =
      map DuplicateModelId (duplicates modelIds)
        <> map DuplicateMatrixRowId (duplicates matrixIds)
        <> map DuplicatePoolId (duplicates poolIds)
        <> map DuplicateMemberId (duplicates memberIds)
        <> [ DuplicatePoolModelReference (enginePoolId pool) duplicateModelId
           | pool <- enginePools config,
             duplicateModelId <- duplicates (enginePoolModelIds pool)
           ]
        <> [ DuplicatePoolMemberReference (enginePoolId pool) duplicateMemberId
           | pool <- enginePools config,
             duplicateMemberId <- duplicates (enginePoolMemberIds pool)
           ]
        <> [ DuplicateMemberPoolReference (engineMemberId member) duplicatePoolId
           | member <- engineMembers config,
             duplicatePoolId <- duplicates (engineMemberPoolIds member)
           ]
        <> [ DuplicateRequestField (modelId model) duplicateFieldName
           | model <- models config,
             duplicateFieldName <- duplicates (map name (requestShape model))
           ]
        <> [InvalidPoolId (enginePoolId pool) | pool <- enginePools config, not (canonicalIdentifier (enginePoolId pool))]
        <> [InvalidMemberId (engineMemberId member) | member <- engineMembers config, not (canonicalIdentifier (engineMemberId member))]
        <> [ DuplicateDerivedRouteTopic topic sources
           | (topic, sources) <- Map.toList derivedRouteSources,
             length sources > 1
           ]
        <> [ TopicFamilyCollision topic (Set.toAscList families)
           | (topic, families) <- Map.toList topicFamilies,
             Set.size families > 1
           ]
    graphErrors =
      [EmptyPoolModels (enginePoolId pool) | pool <- enginePools config, null (enginePoolModelIds pool)]
        <> [EmptyPoolMembers (enginePoolId pool) | pool <- enginePools config, null (enginePoolMemberIds pool)]
        <> [EmptyMemberPools (engineMemberId member) | member <- engineMembers config, null (engineMemberPoolIds member)]
        <> [ DanglingPoolModel (enginePoolId pool) referencedModel
           | pool <- enginePools config,
             referencedModel <- enginePoolModelIds pool,
             referencedModel `Set.notMember` modelIdSet
           ]
        <> [ DanglingPoolMember (enginePoolId pool) referencedMember
           | pool <- enginePools config,
             referencedMember <- enginePoolMemberIds pool,
             referencedMember `Set.notMember` memberIdSet
           ]
        <> [ DanglingMemberPool (engineMemberId member) referencedPool
           | member <- engineMembers config,
             referencedPool <- engineMemberPoolIds member,
             referencedPool `Set.notMember` poolIdSet
           ]
        <> [ PoolMemberLinkMissing (enginePoolId pool) referencedMember
           | pool <- enginePools config,
             referencedMember <- enginePoolMemberIds pool,
             Just member <- [Map.lookup referencedMember memberMap],
             enginePoolId pool `notElem` engineMemberPoolIds member
           ]
        <> [ MemberPoolLinkMissing (engineMemberId member) referencedPool
           | member <- engineMembers config,
             referencedPool <- engineMemberPoolIds member,
             Just pool <- [Map.lookup referencedPool poolMap],
             engineMemberId member `notElem` enginePoolMemberIds pool
           ]
        <> [UnplacedModel modelIdValue | modelIdValue <- modelIds, null (modelPlacements modelIdValue)]
        <> [ MultiplyPlacedModel modelIdValue placements
           | modelIdValue <- modelIds,
             let placements = modelPlacements modelIdValue,
             length placements > 1
           ]
        <> [InvalidPoolSubscription (enginePoolId pool) | pool <- enginePools config, enginePoolSubscriptionType pool /= ConsumerShared]
        <> [ ModelWithoutEligibleMember modelIdValue
           | modelIdValue <- modelIds,
             [pool] <- [filter ((modelIdValue `elem`) . enginePoolModelIds) (enginePools config)],
             null
               [ ()
               | memberIdValue <- enginePoolMemberIds pool,
                 Just member <- [Map.lookup memberIdValue memberMap],
                 enginePoolId pool `elem` engineMemberPoolIds member
               ]
           ]
    -- The two in-cluster daemons still declare their role, member identity, and
    -- Pulsar connection mode, so those three checks stay. Every other daemon
    -- check compared a generated mirror against a derivation, and the engine
    -- daemons are no longer declared at all.
    daemonErrors =
      daemonShapeErrors "coordinator" Coordinator Nothing ConfiguredTransport (coordinatorDaemon config)
        <> daemonShapeErrors "webapp" Webapp Nothing ConfiguredTransport (webappDaemon config)
    daemonShapeErrors label expectedRole expectedMember expectedConnection daemon =
      [ DaemonRoleMismatch label expectedRole (daemonConfigRole daemon)
      | daemonConfigRole daemon /= expectedRole
      ]
        <> [ DaemonMemberMismatch label expectedMember (daemonConfigMemberId daemon)
           | daemonConfigMemberId daemon /= expectedMember
           ]
        <> [ DaemonConnectionModeMismatch label expectedConnection (daemonConfigPulsarConnectionMode daemon)
           | daemonConfigPulsarConnectionMode daemon /= expectedConnection
           ]
    runtimeErrors =
      [ UnknownSelectedEngine (modelId model) (selectedEngine model)
      | model <- models config,
        selectedEngine model `Set.notMember` engineIdSet
      ]
        <> [ UnsupportedGpuRequirement (modelId model) (configRuntimeMode config)
           | configRuntimeMode config == LinuxCpu,
             model <- models config,
             requiresGpu model
           ]
    budgetErrors =
      memoryEnforcerErrors (inferenceMemoryBudget config)
        <> runtimeBudgetErrors (configRuntimeMode config) (inferenceMemoryBudget config)
        <> [ GpuModelWithoutVramEnforcer (modelId model)
           | configRuntimeMode config == LinuxGpu,
             model <- models config,
             requiresGpu model,
             Types.GpuVram
               `notElem` map
                 podMemoryLimitResource
                 (inferenceMemoryBudgetPodLimits (inferenceMemoryBudget config))
           ]

-- | Every named limit in a budget must be positive.
memoryEnforcerErrors :: InferenceMemoryBudget -> [ConfigError]
memoryEnforcerErrors budget =
  concatMap podLimitErrors (inferenceMemoryBudgetPodLimits budget)
  where
    podLimitErrors podLimit =
      -- Phase 8 Sprint 8.9 removed the non-empty-source check: the source is a
      -- closed sum now, so a blank one is not a constructible term. Phase 8
      -- Sprint 8.10 removed the resource checks with the wire field: which
      -- physical resource a limit bounds is decided by the runtime mode and by
      -- which half of the budget it occupies, so a limit claiming the wrong one
      -- is not a constructible term either. @Natural@ still admits zero, so the
      -- positivity check stays.
      [InvalidMemoryEnforcer "substrate memory limit must be positive" | podMemoryLimitMib podLimit <= 0]

runtimeBudgetErrors :: RuntimeMode -> InferenceMemoryBudget -> [ConfigError]
runtimeBudgetErrors runtimeModeValue budget =
  case (runtimeModeValue, budget) of
    (AppleSilicon, HostEnforcedBudget _) -> []
    (LinuxCpu, SubstrateEnforcedBudget podLimit)
      | podMemoryLimitResource podLimit == Types.PodRam -> []
    (LinuxGpu, DualEnforcedBudget podLimit vramLimit)
      | podMemoryLimitResource podLimit == Types.PodRam,
        podMemoryLimitResource vramLimit == Types.GpuVram ->
          []
    -- A @linux-gpu@ budget that names only one resource cannot enforce the
    -- other, so it is rejected as a config error rather than silently admitting
    -- device work against a host-RAM limit.
    (LinuxGpu, _) -> [GpuDualResourceBudgetRequired]
    _ -> [RuntimeBudgetMismatch runtimeModeValue (inferenceMemoryBudgetResource budget)]

compiledModelBootstrapReadyTopic :: Text -> Text
compiledModelBootstrapReadyTopic =
  BootstrapModels.bootstrapReadyTopicFor
    "persistent://infernix/system"

-- | Admit the compiled placements against this machine's declared capacity and
-- refine the admitted ones against live enforcement observations.
--
-- Phase 4 Sprint 4.34: admission lives here, not in 'compileRuntimePlan'. The
-- 'RuntimeObservation' argument is what keeps it engine-only — its constructor
-- is package internal and only 'Infernix.Runtime.Enforcer' can fill it from
-- live probes, so a routing-only role has no way to reach admission at all.
refineRuntimePlan ::
  RuntimeObservation ->
  CompiledRuntimePlan ->
  Either RefinementErrors RuntimePlan
refineRuntimePlan (RuntimeObservation observations) compiledPlan =
  case refinementErrors of
    [] ->
      Right
        RuntimePlan
          { runtimeCompiledPlan = compiledPlan,
            runtimeExecutables = Map.fromList executableEntries,
            runtimeUnavailable = Map.fromList unavailableEntries
          }
    firstError : remainingErrors -> Left (firstError :| remainingErrors)
  where
    runtimeModeValue = compiledPlanRuntimeMode compiledPlan
    budget = inferenceMemoryBudget (compiledConfig compiledPlan)
    admitted =
      [ ( placementId,
          case admitPlacementResources runtimeModeValue budget (placementDescriptor placement) of
            Left admissionError ->
              Left
                UnavailableModel
                  { unavailableDescriptor = placementDescriptor placement,
                    unavailableReason = admissionError
                  }
            Right resources -> Right resources
        )
      | (placementId, placement) <- Map.toList (compiledPlacements compiledPlan)
      ]
    unavailableEntries =
      [(placementId, unavailable) | (placementId, Left unavailable) <- admitted]
    admittedResources =
      Map.fromList [(placementId, resources) | (placementId, Right resources) <- admitted]
    -- Fires only when models were placed and none survived admission, so the
    -- deliberately empty `--empty-models` image bake is untouched.
    noAdmissiblePlacementErrors =
      [ NoAdmissiblePlacement (map fst unavailableEntries)
      | not (Map.null (compiledPlacements compiledPlan)),
        Map.null admittedResources
      ]
    observationsById =
      Map.fromListWith (<>) [(observationId observation, [observation]) | observation <- observations]
    placementIds = Map.keysSet (compiledPlacements compiledPlan)
    admittedIds = Map.keysSet admittedResources
    observationIds = Map.keysSet observationsById
    duplicateErrors =
      [ DuplicatePlacementObservation placementId
      | (placementId, placementObservations) <- Map.toList observationsById,
        length placementObservations > 1
      ]
    -- Only an admitted placement needs an observation: a rejected one names no
    -- enforcer to probe. An observation for a rejected placement is still
    -- legitimate — the enforcer probes before it knows the admission result —
    -- so `unexpected` is measured against every placement, not just the
    -- admitted ones.
    missingErrors =
      map MissingPlacementObservation (Set.toList (admittedIds `Set.difference` observationIds))
    unexpectedErrors =
      map UnexpectedPlacementObservation (Set.toList (observationIds `Set.difference` placementIds))
    refined =
      [ (placementId, refinePlacement placementId placement resources observation)
      | (placementId, placement) <- Map.toList (compiledPlacements compiledPlan),
        Just resources <- [Map.lookup placementId admittedResources],
        [observation] <- [Map.findWithDefault [] placementId observationsById]
      ]
    refinementErrors =
      noAdmissiblePlacementErrors
        <> duplicateErrors
        <> missingErrors
        <> unexpectedErrors
        <> [err | (_, Left errors) <- refined, err <- NonEmpty.toList errors]
    executableEntries =
      [(placementId, executable) | (placementId, Right executable) <- refined]

observationId :: PlacementObservation -> Text
observationId = \case
  HostPlacementObservation placementId _ _ -> placementId
  PodPlacementObservation placementId _ _ -> placementId
  GpuPlacementObservation placementId _ _ _ _ -> placementId

refinePlacement ::
  Text ->
  CompiledPlacement ->
  CompiledResources ->
  PlacementObservation ->
  Either RefinementErrors ExecutableModel
refinePlacement placementId placement admittedResources observation =
  case (admittedResources, observation) of
    (CompiledHostResources plan grant, HostPlacementObservation _ samplerAvailable observedPartition) ->
      case hostRefinementErrors plan samplerAvailable observedPartition of
        [] ->
          Right
            ( executable
                (RuntimeHostResources (EnforcedGrant (hostEnforcer plan) grant))
            )
        firstError : remainingErrors -> Left (firstError :| remainingErrors)
    (CompiledPodResources plan grant, PodPlacementObservation _ samplerAvailable outerLimitMib) ->
      case podRefinementErrors plan samplerAvailable outerLimitMib of
        [] ->
          Right
            ( executable
                (RuntimePodResources (EnforcedGrant (podEnforcer plan) grant))
            )
        firstError : remainingErrors -> Left (firstError :| remainingErrors)
    (CompiledGpuResources podPlan podGrant vramPlan vramGrant, GpuPlacementObservation _ rssAvailable outerLimitMib nvidiaAvailable observedVramMib) ->
      case podRefinementErrors podPlan rssAvailable outerLimitMib
        <> [NvidiaSamplerUnavailable placementId | not nvidiaAvailable]
        <> nvidiaRefinementErrors nvidiaAvailable observedVramMib vramGrant of
        [] ->
          Right
            ( executable
                ( RuntimeGpuResources
                    (EnforcedGrant (podEnforcer podPlan) podGrant)
                    (EnforcedGrant (vramEnforcer vramPlan) vramGrant)
                )
            )
        firstError : remainingErrors -> Left (firstError :| remainingErrors)
    _ -> Left (PlacementObservationResourceMismatch placementId :| [])
  where
    executable resources =
      ExecutableModel
        { executableDescriptor = placementDescriptor placement,
          executableEngine = placementEngine placement,
          executableRoutes = placementRoutes placement,
          executableResources = resources
        }
    hostRefinementErrors plan samplerAvailable maybeObservedPartition =
      [PhysicalFootprintSamplerUnavailable placementId | not samplerAvailable]
        <> case maybeObservedPartition of
          Nothing -> [HostPartitionObservationUnavailable placementId]
          Just observedPartition ->
            [ HostPartitionMismatch placementId expectedPartition observedPartition
            | observedPartition /= expectedPartition
            ]
      where
        expectedPartition =
          case plan of
            HostFootprintWatchdogPlan partition -> partition
    podRefinementErrors plan samplerAvailable maybeOuterLimitMib =
      [ResidentSamplerUnavailable placementId | not samplerAvailable]
        <> case maybeOuterLimitMib of
          Nothing -> [OuterEnvelopeUnavailable placementId]
          Just outerLimitMib ->
            [ OuterEnvelopeTooSmall placementId requiredOuterLimitMib (toInteger outerLimitMib)
            | toInteger outerLimitMib < requiredOuterLimitMib
            ]
              <> [ OuterEnvelopeTooLarge placementId requiredOuterLimitMib (toInteger outerLimitMib)
                 | toInteger outerLimitMib > requiredOuterLimitMib
                 ]
      where
        requiredOuterLimitMib =
          toInteger configuredChildLimitMib
            + toInteger linuxOuterEnvelopeHeadroomMib
        configuredChildLimitMib =
          case plan of
            LinuxProcessGroupRssWatchdogPlan podLimit ->
              podMemoryLimitMib podLimit
    nvidiaRefinementErrors samplerAvailable maybeObservedVramMib grant
      | not samplerAvailable = []
      | otherwise =
          case maybeObservedVramMib of
            Nothing -> [NvidiaEnvelopeUnavailable placementId]
            Just observedVramMib ->
              [ NvidiaEnvelopeTooSmall placementId requiredVramMib (toInteger observedVramMib)
              | toInteger observedVramMib < requiredVramMib
              ]
      where
        requiredVramMib = toInteger (memoryCeilingMib (grantCeiling grant))

hostEnforcer :: EnforcerPlan 'HostRam -> Enforcer 'HostRam
hostEnforcer (HostFootprintWatchdogPlan partition) = HostFootprintWatchdogEnforcer partition

podEnforcer :: EnforcerPlan 'PodRam -> Enforcer 'PodRam
podEnforcer (LinuxProcessGroupRssWatchdogPlan podLimit) = LinuxProcessGroupRssWatchdogEnforcer podLimit

vramEnforcer :: EnforcerPlan 'NvidiaVram -> Enforcer 'NvidiaVram
vramEnforcer (NvidiaVramAccountingPlan podLimit) = NvidiaVramAccountingEnforcer podLimit

grantCeiling :: MemoryGrant resource -> MemoryCeiling resource
grantCeiling (MemoryGrant ceilingValue) = ceilingValue

memoryCeilingMib :: MemoryCeiling resource -> Int
memoryCeilingMib (MemoryCeiling mib) = mib

lookupCompiledPlacement :: Text -> CompiledRuntimePlan -> Maybe CompiledPlacement
lookupCompiledPlacement modelIdValue = Map.lookup modelIdValue . compiledPlacements

compiledRuntimePlanPlacements :: CompiledRuntimePlan -> [CompiledPlacement]
compiledRuntimePlanPlacements = Map.elems . compiledPlacements

-- | How the machine that will execute this model is expected to admit it, from
-- the budget this plan declares.
--
-- Phase 4 Sprint 4.34: this is a *prediction*, never a decision. The authority
-- is the executing engine's own refined plan, and this function exists only so
-- a validation harness can state an expectation before that engine answers.
-- Production code must not consult it — the whole point of the admission split
-- is that a machine which will not run the work does not get a verdict — and
-- 'predictedAdmissionViolations' in "Infernix.Lint.HaskellStyle" enforces that.
-- Once the machine contract carries each box's own capacity, this prediction is
-- only as good as the contract the caller happens to hold.
predictedAdmissionRejection :: CompiledRuntimePlan -> Text -> Maybe InferenceError
predictedAdmissionRejection compiledPlan modelIdValue = do
  placement <- lookupCompiledPlacement modelIdValue compiledPlan
  either Just (const Nothing) $
    admitPlacementResources
      (compiledPlanRuntimeMode compiledPlan)
      (inferenceMemoryBudget (compiledConfig compiledPlan))
      (placementDescriptor placement)

lookupRuntimeUnavailableModel :: Text -> RuntimePlan -> Maybe UnavailableModel
lookupRuntimeUnavailableModel modelIdValue = Map.lookup modelIdValue . runtimeUnavailable

runtimePlanUnavailableModels :: RuntimePlan -> [UnavailableModel]
runtimePlanUnavailableModels = Map.elems . runtimeUnavailable

compiledPlanRuntimeMode :: CompiledRuntimePlan -> RuntimeMode
compiledPlanRuntimeMode = configRuntimeMode . compiledConfig

compiledPlanCoordinatorDaemon :: CompiledRuntimePlan -> CompiledDaemon
compiledPlanCoordinatorDaemon = compiledCoordinator

compiledPlanWebappDaemon :: CompiledRuntimePlan -> CompiledDaemon
compiledPlanWebappDaemon = compiledWebapp

compiledPlanEngineDaemons :: CompiledRuntimePlan -> [CompiledDaemon]
compiledPlanEngineDaemons = Map.elems . compiledEngineDaemonMap

lookupCompiledEngineDaemon :: Text -> CompiledRuntimePlan -> Maybe CompiledDaemon
lookupCompiledEngineDaemon memberIdValue =
  Map.lookup memberIdValue . compiledEngineDaemonMap

compiledDaemonRole :: CompiledDaemon -> DaemonRole
compiledDaemonRole (CompiledDaemon daemon) = daemonConfigRole daemon

compiledDaemonLocation :: CompiledDaemon -> Text
compiledDaemonLocation (CompiledDaemon daemon) = daemonConfigLocation daemon

compiledDaemonMemberId :: CompiledDaemon -> Maybe Text
compiledDaemonMemberId (CompiledDaemon daemon) = daemonConfigMemberId daemon

compiledDaemonRequestTopics :: CompiledDaemon -> [Text]
compiledDaemonRequestTopics (CompiledDaemon daemon) =
  daemonConfigRequestTopics daemon

compiledDaemonResultTopic :: CompiledDaemon -> Text
compiledDaemonResultTopic (CompiledDaemon daemon) =
  daemonConfigResultTopic daemon

compiledDaemonConsumerSubscriptionType ::
  CompiledDaemon ->
  Maybe ConsumerSubscriptionType
compiledDaemonConsumerSubscriptionType (CompiledDaemon daemon) =
  daemonConfigConsumerSubscriptionType daemon

compiledDaemonPulsarConnectionMode ::
  CompiledDaemon ->
  PulsarConnectionMode
compiledDaemonPulsarConnectionMode (CompiledDaemon daemon) =
  daemonConfigPulsarConnectionMode daemon

compiledPlanRequestTopics :: CompiledRuntimePlan -> [Text]
compiledPlanRequestTopics = requestTopics . compiledConfig

compiledPlanResultTopic :: CompiledRuntimePlan -> Text
compiledPlanResultTopic = resultTopic . compiledConfig

compiledPlanModelsBucket :: CompiledRuntimePlan -> Text
compiledPlanModelsBucket = modelsBucket . compiledConfig

compiledPlanModelBootstrapTopic :: CompiledRuntimePlan -> Text
compiledPlanModelBootstrapTopic = modelBootstrapTopic . compiledConfig

compiledPlanConfiguredModels :: CompiledRuntimePlan -> [ModelDescriptor]
compiledPlanConfiguredModels = models . compiledConfig

compiledPlanAvailableModels :: CompiledRuntimePlan -> [ModelDescriptor]
compiledPlanAvailableModels = map placementDescriptor . Map.elems . compiledPlacements

compiledPlanActiveDaemonRole :: CompiledRuntimePlan -> DaemonRole
compiledPlanActiveDaemonRole = activeDaemonRole . compiledConfig

compiledPlacementId :: CompiledPlacement -> Text
compiledPlacementId = modelId . placementDescriptor

compiledPlacementDescriptor :: CompiledPlacement -> ModelDescriptor
compiledPlacementDescriptor = placementDescriptor

compiledPlacementEngine :: CompiledPlacement -> EngineBinding
compiledPlacementEngine = placementEngine

compiledPlacementRoutes :: CompiledPlacement -> NonEmpty EngineRoute
compiledPlacementRoutes = placementRoutes

unavailableModelDescriptor :: UnavailableModel -> ModelDescriptor
unavailableModelDescriptor = unavailableDescriptor

unavailableModelReason :: UnavailableModel -> InferenceError
unavailableModelReason = unavailableReason

lookupExecutableModel :: Text -> RuntimePlan -> Maybe ExecutableModel
lookupExecutableModel modelIdValue = Map.lookup modelIdValue . runtimeExecutables

runtimePlanModels :: RuntimePlan -> [ExecutableModel]
runtimePlanModels = Map.elems . runtimeExecutables

runtimePlanCompiledPlan :: RuntimePlan -> CompiledRuntimePlan
runtimePlanCompiledPlan = runtimeCompiledPlan

executableModelId :: ExecutableModel -> Text
executableModelId = modelId . executableDescriptor

executableModelDescriptor :: ExecutableModel -> ModelDescriptor
executableModelDescriptor = executableDescriptor

executableModelEngine :: ExecutableModel -> EngineBinding
executableModelEngine = executableEngine

executableModelRoutes :: ExecutableModel -> NonEmpty EngineRoute
executableModelRoutes = executableRoutes

executableModelResidentCeilingMib :: ExecutableModel -> Int
executableModelResidentCeilingMib executable =
  case executableResources executable of
    RuntimeHostResources grant -> enforcedGrantCeilingMib grant
    RuntimePodResources grant -> enforcedGrantCeilingMib grant
    RuntimeGpuResources grant _ -> enforcedGrantCeilingMib grant

-- | The enforcement shape a placement takes under this plan's runtime mode and
-- declared budget. This is the enforcer's sampler-selection input and the
-- admission input, in that order.
compiledPlanPlacementEnforcementShape ::
  CompiledRuntimePlan ->
  CompiledPlacement ->
  Maybe PlacementEnforcementShape
compiledPlanPlacementEnforcementShape compiledPlan placement =
  placementEnforcementShape
    (compiledPlanRuntimeMode compiledPlan)
    (inferenceMemoryBudget (compiledConfig compiledPlan))
    (placementDescriptor placement)

-- | The physical resources a placement will have enforced, in enforcement
-- order. A GPU placement names both its pod RAM and its NVIDIA VRAM resource;
-- every other placement names exactly one. The empty list is the mode/budget
-- pair that names no mechanism, which 'compilerErrors' already rejects.
--
-- This is the placement-side counterpart of 'executableModelResidentResource'
-- plus 'executableModelGpuVramCeilingMib', and it exists so callers can observe
-- which resources a placement is bound to without reaching the grants
-- themselves — which, after Sprint 4.34's admission split, a placement no
-- longer holds.
compiledPlanPlacementEnforcedResources ::
  CompiledRuntimePlan ->
  CompiledPlacement ->
  [InferenceMemoryResource]
compiledPlanPlacementEnforcedResources compiledPlan =
  maybe [] placementShapeEnforcedResources
    . compiledPlanPlacementEnforcementShape compiledPlan

executableModelResidentResource :: ExecutableModel -> InferenceMemoryResource
executableModelResidentResource executable =
  case executableResources executable of
    RuntimeHostResources _ -> Types.UnifiedHostRam
    RuntimePodResources _ -> Types.PodRam
    RuntimeGpuResources _ _ -> Types.PodRam

executableModelGpuVramCeilingMib :: ExecutableModel -> Maybe Int
executableModelGpuVramCeilingMib executable =
  case executableResources executable of
    RuntimeGpuResources _ grant -> Just (enforcedGrantCeilingMib grant)
    _ -> Nothing

enforcedGrantCeilingMib :: EnforcedGrant resource -> Int
enforcedGrantCeilingMib (EnforcedGrant _ grant) =
  memoryCeilingMib (grantCeiling grant)

engineRoutePoolId :: EngineRoute -> Text
engineRoutePoolId = routePoolId

engineRouteMemberId :: EngineRoute -> Text
engineRouteMemberId = routeMemberId

engineRouteTopic :: EngineRoute -> Text
engineRouteTopic = routeTopic

engineRouteSubscriptionType :: EngineRoute -> ConsumerSubscriptionType
engineRouteSubscriptionType = routeSubscriptionType

engineRouteMaxInflightPerMember :: EngineRoute -> Int
engineRouteMaxInflightPerMember = routeMaxInflightPerMember

duplicates :: (Ord value) => [value] -> [value]
duplicates = foldr collectDuplicate [] . group . sort
  where
    collectDuplicate values duplicatesFound =
      case values of
        firstValue : _ : _ -> firstValue : duplicatesFound
        _ -> duplicatesFound

canonicalIdentifier :: Text -> Bool
canonicalIdentifier value =
  case Text.uncons value of
    Just (firstCharacter, remaining)
      | identifierAlphaNumeric firstCharacter ->
          validTail False remaining
    _ -> False
  where
    validTail previousWasSeparator remaining =
      case Text.uncons remaining of
        Nothing -> not previousWasSeparator
        Just (character, rest)
          | identifierAlphaNumeric character -> validTail False rest
          | identifierSeparator character && not previousWasSeparator ->
              validTail True rest
          | otherwise -> False

    identifierAlphaNumeric character =
      isAsciiLower character || isDigit character

    identifierSeparator character =
      character `elem` ("._-" :: String)

blankText :: Text -> Bool
blankText = Text.null . Text.strip
