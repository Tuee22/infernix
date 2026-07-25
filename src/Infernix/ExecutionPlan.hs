{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedStrings #-}

module Infernix.ExecutionPlan
  ( CompiledRuntimePlan,
    ConfigError (..),
    ConfigErrors,
    EnforcerPlan,
    ExecutableModel,
    RawRuntimeConfig,
    Resource (..),
    ResourceGrant,
    compileRuntimePlan,
    executableModelDescriptor,
    executableModelEngine,
    executableModelGrant,
    executableModelId,
    lookupExecutableModel,
    runtimePlanConfig,
    runtimePlanModels,
  )
where

import Data.List (group, sort)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.ExecutionPlan.Internal (RawRuntimeConfig (..))
import Infernix.Types

-- | Resources are promoted to the type level so an enforcer or grant for one
-- resource cannot be substituted for another.
data Resource = IndexedHostRam | IndexedPodRam | IndexedVram

data EnforcerPlan (resource :: Resource) where
  HostFootprintWatchdog :: HostMemoryPartition -> EnforcerPlan 'IndexedHostRam
  PodCgroupLimit :: PodMemoryLimit -> EnforcerPlan 'IndexedPodRam
  NvidiaVramAccounting :: PodMemoryLimit -> EnforcerPlan 'IndexedVram

data ResourceGrant (resource :: Resource) where
  ResourceGrant :: MemoryGrant -> EnforcerPlan resource -> ResourceGrant resource

-- | A placement exists only after graph validation, engine resolution, and
-- memory admission all succeed.  Its constructor is intentionally hidden.
data ExecutableModel where
  ExecutableModel ::
    ModelDescriptor ->
    EngineBinding ->
    ResourceGrant resource ->
    ExecutableModel

data CompiledRuntimePlan = CompiledRuntimePlan
  { compiledConfig :: DemoConfig,
    compiledModels :: Map Text ExecutableModel
  }

data ConfigError
  = DuplicateModelId Text
  | DuplicateEngineId Text
  | DuplicatePoolId Text
  | DuplicateMemberId Text
  | UnknownSelectedEngine Text Text
  | ModelRuntimeMismatch Text RuntimeMode RuntimeMode
  | DanglingPoolModel Text Text
  | DanglingPoolMember Text Text
  | DanglingMemberPool Text Text
  | UnplacedModel Text
  | MultiplyPlacedModel Text [Text]
  | PoolRuntimeMismatch Text RuntimeMode RuntimeMode
  | MemberRuntimeMismatch Text RuntimeMode RuntimeMode
  | GpuModelWithoutVramEnforcer Text
  | InvalidMemoryEnforcer Text
  | ModelAdmissionRejected InferenceError
  deriving (Eq, Show)

type ConfigErrors = NonEmpty ConfigError

compileRuntimePlan :: RawRuntimeConfig -> Either ConfigErrors CompiledRuntimePlan
compileRuntimePlan (RawRuntimeConfig config) =
  case structuralErrors <> placementErrors <> executableErrors of
    [] ->
      Right
        CompiledRuntimePlan
          { compiledConfig = config,
            compiledModels =
              Map.fromList
                [(executableModelId executableModel, executableModel) | executableModel <- mapMaybe compileModel (models config)]
          }
    firstError : remainingErrors -> Left (firstError :| remainingErrors)
  where
    modelIds = map modelId (models config)
    engineIds = map engineBindingName (engines config)
    poolIds = map enginePoolId (enginePools config)
    memberIds = map engineMemberId (engineMembers config)
    modelIdSet = Set.fromList modelIds
    engineIdSet = Set.fromList engineIds
    poolIdSet = Set.fromList poolIds
    memberIdSet = Set.fromList memberIds
    placedModelIds = Set.fromList (concatMap enginePoolModelIds (enginePools config))
    modelPlacements modelIdValue =
      [enginePoolId pool | pool <- enginePools config, modelIdValue `elem` enginePoolModelIds pool]
    structuralErrors =
      map DuplicateModelId (duplicates modelIds)
        <> map DuplicateEngineId (duplicates engineIds)
        <> map DuplicatePoolId (duplicates poolIds)
        <> map DuplicateMemberId (duplicates memberIds)
    placementErrors =
      [ DanglingPoolModel (enginePoolId pool) referencedModel
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
        <> [UnplacedModel modelIdValue | modelIdValue <- modelIds, modelIdValue `Set.notMember` placedModelIds]
        <> [ MultiplyPlacedModel modelIdValue placements
           | modelIdValue <- modelIds,
             let placements = modelPlacements modelIdValue,
             length placements > 1
           ]
        <> [ PoolRuntimeMismatch (enginePoolId pool) (configRuntimeMode config) (enginePoolRuntimeMode pool)
           | pool <- enginePools config,
             enginePoolRuntimeMode pool /= configRuntimeMode config
           ]
        <> [ MemberRuntimeMismatch (engineMemberId member) (configRuntimeMode config) (engineMemberRuntimeMode member)
           | member <- engineMembers config,
             engineMemberRuntimeMode member /= configRuntimeMode config
           ]
    executableErrors =
      [ UnknownSelectedEngine (modelId model) (selectedEngine model)
      | model <- models config,
        selectedEngine model `Set.notMember` engineIdSet
      ]
        <> [ ModelRuntimeMismatch (modelId model) (configRuntimeMode config) (runtimeMode model)
           | model <- models config,
             runtimeMode model /= configRuntimeMode config
           ]
        <> memoryEnforcerErrors (inferenceMemoryBudget config)
        <> [ GpuModelWithoutVramEnforcer (modelId model)
           | model <- models config,
             requiresGpu model,
             inferenceMemoryBudgetResource (inferenceMemoryBudget config) /= GpuVram
           ]
    engineMap = Map.fromList [(engineBindingName binding, binding) | binding <- engines config]
    compileModel model =
      case (Map.lookup (selectedEngine model) engineMap, admitModelMemory (inferenceMemoryBudget config) model) of
        (Nothing, _) -> Nothing
        (_, Left _) -> Nothing
        (Just binding, Right grant) ->
          Just (executableForBudget (inferenceMemoryBudget config) model binding grant)

memoryEnforcerErrors :: InferenceMemoryBudget -> [ConfigError]
memoryEnforcerErrors budget =
  case budget of
    HostEnforcedBudget _ -> []
    SubstrateEnforcedBudget podLimit
      | podMemoryLimitMib podLimit <= 0 ->
          [InvalidMemoryEnforcer "substrate memory limit must be positive"]
      | Text.null (Text.strip (podMemoryLimitSource podLimit)) ->
          [InvalidMemoryEnforcer "substrate memory enforcer source must be non-empty"]
      | otherwise -> []

executableForBudget :: InferenceMemoryBudget -> ModelDescriptor -> EngineBinding -> MemoryGrant -> ExecutableModel
executableForBudget budget model binding grant =
  case budget of
    HostEnforcedBudget partition ->
      ExecutableModel model binding (ResourceGrant grant (HostFootprintWatchdog partition))
    SubstrateEnforcedBudget podLimit ->
      case podMemoryLimitResource podLimit of
        GpuVram -> ExecutableModel model binding (ResourceGrant grant (NvidiaVramAccounting podLimit))
        PodRam -> ExecutableModel model binding (ResourceGrant grant (PodCgroupLimit podLimit))
        UnifiedHostRam ->
          ExecutableModel model binding (ResourceGrant grant (PodCgroupLimit podLimit))

duplicates :: (Ord value) => [value] -> [value]
duplicates = foldr collectDuplicate [] . group . sort
  where
    collectDuplicate values duplicatesFound =
      case values of
        firstValue : _ : _ -> firstValue : duplicatesFound
        _ -> duplicatesFound

lookupExecutableModel :: Text -> CompiledRuntimePlan -> Maybe ExecutableModel
lookupExecutableModel modelIdValue = Map.lookup modelIdValue . compiledModels

runtimePlanModels :: CompiledRuntimePlan -> [ExecutableModel]
runtimePlanModels = Map.elems . compiledModels

-- | Transitional projection for non-routing configuration consumers. Runtime
-- routing and launch APIs consume 'ExecutableModel', never this projection.
runtimePlanConfig :: CompiledRuntimePlan -> DemoConfig
runtimePlanConfig = compiledConfig

executableModelId :: ExecutableModel -> Text
executableModelId (ExecutableModel model _ _) = modelId model

executableModelDescriptor :: ExecutableModel -> ModelDescriptor
executableModelDescriptor (ExecutableModel model _ _) = model

executableModelEngine :: ExecutableModel -> EngineBinding
executableModelEngine (ExecutableModel _ binding _) = binding

executableModelGrant :: ExecutableModel -> MemoryGrant
executableModelGrant (ExecutableModel _ _ (ResourceGrant grant _)) = grant
