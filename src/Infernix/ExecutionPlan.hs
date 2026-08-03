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
    compiledPlacementEnforcedResources,
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
    compiledPlanRequestTopics,
    compiledPlanResultTopic,
    compiledPlanRuntimeMode,
    compiledPlanWebappDaemon,
    compiledRuntimePlanPlacements,
    compiledRuntimePlanUnavailableModels,
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
    lookupUnavailableModel,
    memoryCeilingMib,
    refineRuntimePlan,
    runtimePlanCompiledPlan,
    runtimePlanModels,
    unavailableModelDescriptor,
    unavailableModelReason,
  )
where

import Data.Char (isAsciiLower, isDigit, isSpace)
import Data.List (group, sort)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Infernix.Bootstrap.Models qualified as BootstrapModels
import Infernix.EngineBindings (canonicalEngineBindingForSelectedEngine)
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
    RuntimeLane (..),
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
  | EmptyEngineCatalog
  | EmptyPoolCatalog
  | EmptyMemberCatalog
  | EmptyEngineDaemonCatalog
  | EmptyRequestTopics
  | BlankRequestTopic
  | BlankResultTopic
  | BlankModelsBucket
  | BlankModelBootstrapTopic
  | ModelsBucketMismatch Text Text
  | ModelBootstrapTopicMismatch Text Text
  | InvalidEdgePort Int
  | BlankConfigMapName
  | BlankGeneratedPath
  | BlankMountedPath
  | InvalidActiveDaemonRole
  | InvalidDaemonConfig Text
  | DaemonRoleMismatch Text DaemonRole DaemonRole
  | DaemonMemberMismatch Text (Maybe Text) (Maybe Text)
  | DaemonLocationMismatch Text Text Text
  | DaemonRequestTopicsMismatch Text [Text] [Text]
  | DaemonResultTopicMismatch Text Text Text
  | DaemonConnectionModeMismatch Text PulsarConnectionMode PulsarConnectionMode
  | DaemonSubscriptionMismatch Text ConsumerSubscriptionType (Maybe ConsumerSubscriptionType)
  | EngineDaemonMemberMissing Text
  | MissingEngineDaemon Text
  | DuplicateEngineDaemonMember Text
  | InvalidEngineBinding Text
  | UnsupportedEngineBinding RuntimeMode Text
  | EngineBindingMismatch Text EngineBinding EngineBinding
  | UnsupportedEngineAdapterType Text Text
  | InvalidModelDescriptor Text
  | InvalidModelId Text
  | InvalidMatrixRowId Text
  | InvalidAdapterId Text Text
  | UnenforceableModelMemoryFootprint Text Integer
  | DuplicateModelId Text
  | DuplicateMatrixRowId Text
  | DuplicateEngineId Text
  | DuplicatePoolId Text
  | DuplicateMemberId Text
  | DuplicateRequestTopic Text
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
  | ModelRuntimeMismatch Text RuntimeMode RuntimeMode
  | ModelRuntimeLaneMismatch Text RuntimeMode RuntimeLane
  | UnsupportedGpuRequirement Text RuntimeMode
  | DanglingPoolModel Text Text
  | DanglingPoolMember Text Text
  | DanglingMemberPool Text Text
  | PoolMemberLinkMissing Text Text
  | MemberPoolLinkMissing Text Text
  | UnknownDaemonMember Text
  | UnplacedModel Text
  | MultiplyPlacedModel Text [Text]
  | PoolRuntimeMismatch Text RuntimeMode RuntimeMode
  | MemberRuntimeMismatch Text RuntimeMode RuntimeMode
  | MemberLocationMismatch Text RuntimeMode Text
  | InvalidPoolSubscription Text
  | InvalidPoolMaxInflight Text Int
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
  = DuplicatePlacementObservation Text
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
      compiledModels <-
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
                | Left placement <- compiledModels
                ],
            compiledUnavailable =
              Map.fromList
                [ (modelId (unavailableDescriptor unavailable), unavailable)
                | Right unavailable <- compiledModels
                ]
          }
    firstError : remainingErrors -> Left (firstError :| remainingErrors)

mapLeftSingleton :: Either ConfigError value -> Either ConfigErrors value
mapLeftSingleton =
  either (Left . (:| [])) Right

compileDaemonCapabilities ::
  DemoConfig ->
  Either ConfigError (CompiledDaemon, CompiledDaemon, Map.Map Text CompiledDaemon)
compileDaemonCapabilities config = do
  engineEntries <- traverse compiledEngineDaemon (engineMembers config)
  pure
    ( CompiledDaemon (coordinatorDaemon config),
      CompiledDaemon (webappDaemon config),
      Map.fromList engineEntries
    )
  where
    compiledEngineDaemon member =
      case filter
        ((== Just (engineMemberId member)) . daemonConfigMemberId)
        (engineDaemons config) of
        [daemon] ->
          Right (engineMemberId member, CompiledDaemon daemon)
        [] ->
          Left (MissingEngineDaemon (engineMemberId member))
        _ ->
          Left (DuplicateEngineDaemonMember (engineMemberId member))

compileModel ::
  DemoConfig ->
  ModelDescriptor ->
  Either ConfigError (Either CompiledPlacement UnavailableModel)
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
  case compileResources (configRuntimeMode config) (inferenceMemoryBudget config) model of
    Left admissionError ->
      Right
        ( Right
            UnavailableModel
              { unavailableDescriptor = model,
                unavailableReason = admissionError
              }
        )
    Right resources ->
      Right
        ( Left
            CompiledPlacement
              { placementDescriptor = model,
                placementEngine = binding,
                placementRoutes = routes,
                placementResources = resources
              }
        )
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

compileResources ::
  RuntimeMode ->
  InferenceMemoryBudget ->
  ModelDescriptor ->
  Either InferenceError CompiledResources
compileResources runtimeModeValue budget model =
  case (runtimeModeValue, budget) of
    (AppleSilicon, HostEnforcedBudget partition) ->
      CompiledHostResources
        (HostFootprintWatchdogPlan partition)
        <$> admitGrant
          HostRamWitness
          (inferenceMemoryBudgetSource budget)
          model
          (hostPartitionInferenceCapacityMib partition)
    (LinuxCpu, SubstrateEnforcedBudget podLimit)
      | podMemoryLimitResource podLimit == Types.PodRam ->
          CompiledPodResources
            (LinuxProcessGroupRssWatchdogPlan podLimit)
            <$> admitGrant
              PodRamWitness
              (podMemoryLimitSource podLimit)
              model
              (podMemoryLimitMib podLimit)
    -- Phase 6 Sprint 6.44 — a @linux-gpu@ model that actually uses the device
    -- must clear both limits, and each admitted quantity becomes its own
    -- resource-indexed grant with its own live watchdog. A @linux-gpu@ model
    -- that does not require the device stays on the resident-set lane alone: a
    -- VRAM grant it would never consume is not evidence of anything.
    (LinuxGpu, DualEnforcedBudget podLimit vramLimit)
      | podMemoryLimitResource podLimit == Types.PodRam,
        podMemoryLimitResource vramLimit == Types.GpuVram ->
          if requiresGpu model
            then
              CompiledGpuResources
                (LinuxProcessGroupRssWatchdogPlan podLimit)
                <$> admitGrant
                  PodRamWitness
                  (podMemoryLimitSource podLimit)
                  model
                  (podMemoryLimitMib podLimit)
                <*> pure (NvidiaVramAccountingPlan vramLimit)
                <*> admitGrant
                  NvidiaVramWitness
                  (podMemoryLimitSource vramLimit)
                  model
                  (podMemoryLimitMib vramLimit)
            else
              CompiledPodResources
                (LinuxProcessGroupRssWatchdogPlan podLimit)
                <$> admitGrant
                  PodRamWitness
                  (podMemoryLimitSource podLimit)
                  model
                  (podMemoryLimitMib podLimit)
    _ ->
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
    canonicalBindings =
      [ ( binding,
          canonicalEngineBindingForSelectedEngine
            (configRuntimeMode config)
            (engineBindingName binding)
        )
      | binding <- engines config
      ]
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
    basicErrors =
      [EmptyModelCatalog | null (models config)]
        <> [EmptyEngineCatalog | null (engines config)]
        <> [EmptyPoolCatalog | null (enginePools config)]
        <> [EmptyMemberCatalog | null (engineMembers config)]
        <> [EmptyEngineDaemonCatalog | null (engineDaemons config)]
        <> [EmptyRequestTopics | null (requestTopics config)]
        <> [BlankRequestTopic | any blankText (requestTopics config)]
        <> [BlankResultTopic | blankText (resultTopic config)]
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
        <> [InvalidEdgePort (configEdgePort config) | configEdgePort config < 0 || configEdgePort config > 65535]
        <> [BlankConfigMapName | blankText (configMapName config)]
        <> [BlankGeneratedPath | all isSpace (generatedPath config)]
        <> [BlankMountedPath | all isSpace (mountedPath config)]
        <> [InvalidActiveDaemonRole | not activeRoleDeclared]
        <> [InvalidDaemonConfig "coordinator" | invalidDaemon (coordinatorDaemon config)]
        <> [InvalidDaemonConfig "webapp" | invalidDaemon (webappDaemon config)]
        <> [ InvalidDaemonConfig (fromMaybe (daemonConfigLocation daemon) (daemonConfigMemberId daemon))
           | daemon <- engineDaemons config,
             invalidDaemon daemon
           ]
        <> [ InvalidEngineBinding (engineBindingName binding)
           | binding <- engines config,
             invalidEngine binding
           ]
        <> [ UnsupportedEngineBinding
               (configRuntimeMode config)
               (engineBindingName binding)
           | (binding, Nothing) <- canonicalBindings
           ]
        <> [ EngineBindingMismatch
               (engineBindingName binding)
               canonicalBinding
               binding
           | (binding, Just canonicalBinding) <- canonicalBindings,
             binding /= canonicalBinding
           ]
        <> [ UnsupportedEngineAdapterType
               (engineBindingName binding)
               (engineBindingAdapterType binding)
           | binding <- engines config,
             engineBindingAdapterType binding `Set.notMember` supportedAdapterTypes
           ]
        <> [ InvalidModelDescriptor (modelId model)
           | model <- models config,
             invalidModel model
           ]
        <> [InvalidModelId (modelId model) | model <- models config, not (canonicalIdentifier (modelId model))]
        <> [InvalidMatrixRowId (matrixRowId model) | model <- models config, not (canonicalIdentifier (matrixRowId model))]
        <> [ InvalidAdapterId (engineBindingName binding) (engineBindingAdapterId binding)
           | binding <- engines config,
             not (canonicalIdentifier (engineBindingAdapterId binding))
           ]
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
    invalidDaemon daemon =
      blankText (daemonConfigLocation daemon)
        || null (daemonConfigRequestTopics daemon)
        || any blankText (daemonConfigRequestTopics daemon)
        || blankText (daemonConfigResultTopic daemon)
    invalidEngine binding =
      any
        blankText
        [ engineBindingName binding,
          engineBindingAdapterId binding,
          engineBindingAdapterType binding,
          engineBindingAdapterLocator binding,
          engineBindingAdapterEntrypoint binding,
          engineBindingSetupEntrypoint binding,
          Text.pack (engineBindingProjectDirectory binding)
        ]
    invalidModel model =
      any
        blankText
        [matrixRowId model, modelId model, selectedEngine model]
        || null (requestShape model)
        || any invalidRequestField (requestShape model)
    invalidRequestField requestField =
      blankText (name requestField) || blankText (label requestField)
    supportedAdapterTypes =
      Set.fromList ["native-process-runner", "python-stdio"]
    structuralErrors =
      map DuplicateModelId (duplicates modelIds)
        <> map DuplicateMatrixRowId (duplicates matrixIds)
        <> map DuplicateEngineId (duplicates engineIds)
        <> map DuplicatePoolId (duplicates poolIds)
        <> map DuplicateMemberId (duplicates memberIds)
        <> map DuplicateRequestTopic (duplicates (requestTopics config))
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
        <> [UnknownDaemonMember memberIdValue | daemon <- engineDaemons config, Just memberIdValue <- [daemonConfigMemberId daemon], memberIdValue `Set.notMember` memberIdSet]
        <> [UnplacedModel modelIdValue | modelIdValue <- modelIds, null (modelPlacements modelIdValue)]
        <> [ MultiplyPlacedModel modelIdValue placements
           | modelIdValue <- modelIds,
             let placements = modelPlacements modelIdValue,
             length placements > 1
           ]
        <> [InvalidPoolSubscription (enginePoolId pool) | pool <- enginePools config, enginePoolSubscriptionType pool /= ConsumerShared]
        <> [InvalidPoolMaxInflight (enginePoolId pool) (enginePoolMaxInflightPerMember pool) | pool <- enginePools config, enginePoolMaxInflightPerMember pool <= 0]
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
    daemonErrors =
      daemonShapeErrors "coordinator" Coordinator Nothing ConfiguredTransport (coordinatorDaemon config)
        <> daemonShapeErrors "webapp" Webapp Nothing ConfiguredTransport (webappDaemon config)
        <> [ DaemonLocationMismatch "coordinator" "cluster-pod" (daemonConfigLocation (coordinatorDaemon config))
           | daemonConfigLocation (coordinatorDaemon config) /= "cluster-pod"
           ]
        <> [ DaemonLocationMismatch "webapp" "cluster-pod" (daemonConfigLocation (webappDaemon config))
           | daemonConfigLocation (webappDaemon config) /= "cluster-pod"
           ]
        <> [ EngineDaemonMemberMissing (daemonConfigLocation daemon)
           | daemon <- engineDaemons config,
             Nothing <- [daemonConfigMemberId daemon]
           ]
        <> [ MissingEngineDaemon memberIdValue
           | memberIdValue <- memberIds,
             null (engineDaemonsFor memberIdValue)
           ]
        <> [ DuplicateEngineDaemonMember memberIdValue
           | memberIdValue <- memberIds,
             length (engineDaemonsFor memberIdValue) > 1
           ]
        <> concat
          [ daemonShapeErrors
              memberIdValue
              Engine
              (Just memberIdValue)
              (expectedEngineConnectionMode (configRuntimeMode config))
              daemon
              <> [ DaemonLocationMismatch memberIdValue (engineMemberLocation member) (daemonConfigLocation daemon)
                 | daemonConfigLocation daemon /= engineMemberLocation member
                 ]
              <> [ DaemonRequestTopicsMismatch memberIdValue expectedTopics (daemonConfigRequestTopics daemon)
                 | daemonConfigRequestTopics daemon /= expectedTopics
                 ]
          | member <- engineMembers config,
            let memberIdValue = engineMemberId member,
            let expectedTopics = expectedEngineTopics member,
            daemon <- engineDaemonsFor memberIdValue
          ]
    daemonShapeErrors label expectedRole expectedMember expectedConnection daemon =
      [ DaemonRoleMismatch label expectedRole (daemonConfigRole daemon)
      | daemonConfigRole daemon /= expectedRole
      ]
        <> [ DaemonMemberMismatch label expectedMember (daemonConfigMemberId daemon)
           | daemonConfigMemberId daemon /= expectedMember
           ]
        <> [ DaemonResultTopicMismatch label (resultTopic config) (daemonConfigResultTopic daemon)
           | daemonConfigResultTopic daemon /= resultTopic config
           ]
        <> [ DaemonConnectionModeMismatch label expectedConnection (daemonConfigPulsarConnectionMode daemon)
           | daemonConfigPulsarConnectionMode daemon /= expectedConnection
           ]
        <> [ DaemonSubscriptionMismatch label ConsumerShared (daemonConfigConsumerSubscriptionType daemon)
           | daemonConfigConsumerSubscriptionType daemon /= Just ConsumerShared
           ]
        <> [ DaemonRequestTopicsMismatch label (requestTopics config) (daemonConfigRequestTopics daemon)
           | expectedRole /= Engine,
             daemonConfigRequestTopics daemon /= requestTopics config
           ]
    engineDaemonsFor memberIdValue =
      filter ((== Just memberIdValue) . daemonConfigMemberId) (engineDaemons config)
    expectedEngineTopics member =
      [ enginePoolTopicForMode
          (configRuntimeMode config)
          (enginePoolId pool)
          modelIdValue
      | pool <- enginePools config,
        enginePoolId pool `elem` engineMemberPoolIds member,
        engineMemberId member `elem` enginePoolMemberIds pool,
        modelIdValue <- enginePoolModelIds pool
      ]
    expectedEngineConnectionMode runtimeModeValue =
      case runtimeModeValue of
        AppleSilicon -> PublicationEdgeAutoDiscovery
        LinuxCpu -> ConfiguredTransport
        LinuxGpu -> ConfiguredTransport
    runtimeErrors =
      [ UnknownSelectedEngine (modelId model) (selectedEngine model)
      | model <- models config,
        selectedEngine model `Set.notMember` engineIdSet
      ]
        <> [ ModelRuntimeMismatch (modelId model) (configRuntimeMode config) (runtimeMode model)
           | model <- models config,
             runtimeMode model /= configRuntimeMode config
           ]
        <> [ ModelRuntimeLaneMismatch (modelId model) (configRuntimeMode config) (runtimeLane model)
           | model <- models config,
             runtimeLane model /= expectedRuntimeLane (configRuntimeMode config) (requiresGpu model)
           ]
        <> [ UnsupportedGpuRequirement (modelId model) (configRuntimeMode config)
           | configRuntimeMode config == LinuxCpu,
             model <- models config,
             requiresGpu model
           ]
        <> [ PoolRuntimeMismatch (enginePoolId pool) (configRuntimeMode config) (enginePoolRuntimeMode pool)
           | pool <- enginePools config,
             enginePoolRuntimeMode pool /= configRuntimeMode config
           ]
        <> [ MemberRuntimeMismatch (engineMemberId member) (configRuntimeMode config) (engineMemberRuntimeMode member)
           | member <- engineMembers config,
             engineMemberRuntimeMode member /= configRuntimeMode config
           ]
        <> [ MemberLocationMismatch (engineMemberId member) (configRuntimeMode config) (engineMemberLocation member)
           | member <- engineMembers config,
             engineMemberLocation member /= expectedMemberLocation (configRuntimeMode config)
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
    expectedRuntimeLane runtimeModeValue gpuRequired =
      case runtimeModeValue of
        AppleSilicon -> AppleSiliconHost
        LinuxCpu -> KindLinuxCpu
        LinuxGpu
          | gpuRequired -> KindLinuxGpuGpu
          | otherwise -> KindLinuxGpuShared
    expectedMemberLocation runtimeModeValue =
      case runtimeModeValue of
        AppleSilicon -> "control-plane-host"
        LinuxCpu -> "cluster-pod"
        LinuxGpu -> "cluster-pod"

-- | Every named limit in a budget must be positive, carry a source, and not
-- claim the unified host RAM that only the Apple partition arm enforces. The
-- dual arm additionally pins which physical resource each half names, so a
-- config cannot present two RAM limits — or two VRAM limits — as dual
-- enforcement.
memoryEnforcerErrors :: InferenceMemoryBudget -> [ConfigError]
memoryEnforcerErrors budget =
  concatMap podLimitErrors (inferenceMemoryBudgetPodLimits budget)
    <> dualArmErrors
  where
    podLimitErrors podLimit =
      [InvalidMemoryEnforcer "substrate memory limit must be positive" | podMemoryLimitMib podLimit <= 0]
        <> [InvalidMemoryEnforcer "substrate memory enforcer source must be non-empty" | Text.null (Text.strip (podMemoryLimitSource podLimit))]
        <> [InvalidMemoryEnforcer "substrate memory enforcer cannot claim unified host RAM" | podMemoryLimitResource podLimit == Types.UnifiedHostRam]
    dualArmErrors =
      case budget of
        DualEnforcedBudget podLimit vramLimit ->
          [ InvalidMemoryEnforcer "dual memory enforcer must name a pod RAM limit first"
          | podMemoryLimitResource podLimit /= Types.PodRam
          ]
            <> [ InvalidMemoryEnforcer "dual memory enforcer must name a GPU VRAM limit second"
               | podMemoryLimitResource vramLimit /= Types.GpuVram
               ]
        _ -> []

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
            runtimeExecutables = Map.fromList executableEntries
          }
    firstError : remainingErrors -> Left (firstError :| remainingErrors)
  where
    observationsById =
      Map.fromListWith (<>) [(observationId observation, [observation]) | observation <- observations]
    placementIds = Map.keysSet (compiledPlacements compiledPlan)
    observationIds = Map.keysSet observationsById
    duplicateErrors =
      [ DuplicatePlacementObservation placementId
      | (placementId, placementObservations) <- Map.toList observationsById,
        length placementObservations > 1
      ]
    missingErrors =
      map MissingPlacementObservation (Set.toList (placementIds `Set.difference` observationIds))
    unexpectedErrors =
      map UnexpectedPlacementObservation (Set.toList (observationIds `Set.difference` placementIds))
    refined =
      [ (placementId, refinePlacement placementId placement observation)
      | (placementId, placement) <- Map.toList (compiledPlacements compiledPlan),
        [observation] <- [Map.findWithDefault [] placementId observationsById]
      ]
    refinementErrors =
      duplicateErrors
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
  PlacementObservation ->
  Either RefinementErrors ExecutableModel
refinePlacement placementId placement observation =
  case (placementResources placement, observation) of
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

lookupUnavailableModel :: Text -> CompiledRuntimePlan -> Maybe UnavailableModel
lookupUnavailableModel modelIdValue = Map.lookup modelIdValue . compiledUnavailable

compiledRuntimePlanUnavailableModels :: CompiledRuntimePlan -> [UnavailableModel]
compiledRuntimePlanUnavailableModels = Map.elems . compiledUnavailable

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

-- | The physical resources a compiled placement will have enforced, in
-- enforcement order. A GPU placement names both its pod RAM and its NVIDIA
-- VRAM resource; every other placement names exactly one. This is the
-- compile-time counterpart of 'executableModelResidentResource' plus
-- 'executableModelGpuVramCeilingMib', and it exists so callers can observe
-- which resources a placement is bound to without reaching the grants
-- themselves.
compiledPlacementEnforcedResources :: CompiledPlacement -> [InferenceMemoryResource]
compiledPlacementEnforcedResources placement =
  case placementResources placement of
    CompiledHostResources {} -> [Types.UnifiedHostRam]
    CompiledPodResources {} -> [Types.PodRam]
    CompiledGpuResources {} -> [Types.PodRam, Types.GpuVram]

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
