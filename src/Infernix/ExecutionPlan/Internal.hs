{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RoleAnnotations #-}

module Infernix.ExecutionPlan.Internal
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
where

import Data.List.NonEmpty (NonEmpty)
import Data.Map.Strict (Map)
import Data.Text (Text)
import Infernix.Types
  ( ConsumerSubscriptionType,
    DaemonConfig,
    DemoConfig,
    EngineBinding,
    HostMemoryPartition,
    InferenceError,
    ModelDescriptor,
    PodMemoryLimit,
  )

-- | The physical resource bounded by a grant. The promoted constructors keep
-- host RAM, pod RAM, and NVIDIA VRAM proofs distinct at compile time.
data Resource
  = HostRam
  | PodRam
  | NvidiaVram
  deriving (Eq, Ord, Read, Show)

-- | A positive admitted ceiling for exactly one resource.
newtype MemoryCeiling (resource :: Resource) = MemoryCeiling Int
  deriving (Eq, Ord, Show)

type role MemoryCeiling nominal

-- | Admission proof for exactly one resource. Its constructor is package
-- internal; only the execution-plan compiler may mint it.
newtype MemoryGrant (resource :: Resource) = MemoryGrant (MemoryCeiling resource)
  deriving (Eq, Show)

type role MemoryGrant nominal

-- | Declarative enforcement expected from a placement before a live probe has
-- verified it.
data EnforcerPlan (resource :: Resource) where
  HostFootprintWatchdogPlan :: HostMemoryPartition -> EnforcerPlan 'HostRam
  LinuxProcessGroupRssWatchdogPlan :: PodMemoryLimit -> EnforcerPlan 'PodRam
  NvidiaVramAccountingPlan :: PodMemoryLimit -> EnforcerPlan 'NvidiaVram

type role EnforcerPlan nominal

deriving instance Eq (EnforcerPlan resource)

deriving instance Show (EnforcerPlan resource)

-- | Live enforcement capability. Constructors remain package internal so raw
-- configuration cannot be promoted directly to execution authority.
data Enforcer (resource :: Resource) where
  HostFootprintWatchdogEnforcer :: HostMemoryPartition -> Enforcer 'HostRam
  LinuxProcessGroupRssWatchdogEnforcer :: PodMemoryLimit -> Enforcer 'PodRam
  NvidiaVramAccountingEnforcer :: PodMemoryLimit -> Enforcer 'NvidiaVram

type role Enforcer nominal

deriving instance Eq (Enforcer resource)

deriving instance Show (Enforcer resource)

-- | A matching live enforcer and admitted grant. The shared resource index
-- makes cross-resource substitution a type error.
data EnforcedGrant (resource :: Resource) where
  EnforcedGrant :: Enforcer resource -> MemoryGrant resource -> EnforcedGrant resource

type role EnforcedGrant nominal

deriving instance Eq (EnforcedGrant resource)

deriving instance Show (EnforcedGrant resource)

-- | Compile-time resource requirements. Linux GPU placements carry both
-- independent host/pod RAM and VRAM grants.
data CompiledResources
  = CompiledHostResources
      (EnforcerPlan 'HostRam)
      (MemoryGrant 'HostRam)
  | CompiledPodResources
      (EnforcerPlan 'PodRam)
      (MemoryGrant 'PodRam)
  | CompiledGpuResources
      (EnforcerPlan 'PodRam)
      (MemoryGrant 'PodRam)
      (EnforcerPlan 'NvidiaVram)
      (MemoryGrant 'NvidiaVram)
  deriving (Eq, Show)

-- | Runtime-refined resource capabilities. An 'ExecutableModel' can only hold
-- this live form, never a descriptive 'EnforcerPlan'.
data RuntimeResources
  = RuntimeHostResources (EnforcedGrant 'HostRam)
  | RuntimePodResources (EnforcedGrant 'PodRam)
  | RuntimeGpuResources
      (EnforcedGrant 'PodRam)
      (EnforcedGrant 'NvidiaVram)
  deriving (Eq, Show)

-- | A validated model route for one eligible pool member.
data EngineRoute = EngineRoute
  { routePoolId :: Text,
    routeMemberId :: Text,
    routeTopic :: Text,
    routeSubscriptionType :: ConsumerSubscriptionType,
    routeMaxInflightPerMember :: Int
  }
  deriving (Eq, Ord, Show)

-- | Compiler-validated daemon wiring. The wrapped raw record is never exposed
-- through the public execution-plan API; possession proves its role, member,
-- location, topics, and connection mode agree with the compiled graph.
newtype CompiledDaemon = CompiledDaemon DaemonConfig
  deriving (Eq, Show)

-- | The enforcement shape a placement takes on the machine that will execute
-- it: which mechanism observes it and which declared limits its grants are
-- admitted against. It is derived from the runtime mode, the declared budget,
-- and whether the model uses the device — never from a placement, because a
-- placement carries no resources.
--
-- Phase 4 Sprint 4.34: this value is what keeps the enforcer's sampler choice
-- and the admitted grant from drifting apart. The enforcer must know which
-- mechanism to probe /before/ it can admit anything, and admission must bind
-- its grants to the same limits the probe verified; both read this one value.
data PlacementEnforcementShape
  = HostEnforcementShape HostMemoryPartition
  | PodEnforcementShape PodMemoryLimit
  | GpuEnforcementShape PodMemoryLimit PodMemoryLimit
  deriving (Eq, Show)

-- | A placement produced by pure graph validation. It names a model, its
-- engine, and its eligible routes; it holds no memory grant, because admission
-- is an observation of the machine that will execute and the compiler runs on
-- every role.
data CompiledPlacement = CompiledPlacement
  { placementDescriptor :: ModelDescriptor,
    placementEngine :: EngineBinding,
    placementRoutes :: NonEmpty EngineRoute
  }
  deriving (Eq, Show)

-- | A catalog model that was placed by the compiler but could not be admitted
-- against the executing machine's capacity. Keeping it in the refined plan
-- prevents silent loss and makes accounting exhaustive.
data UnavailableModel = UnavailableModel
  { unavailableDescriptor :: ModelDescriptor,
    unavailableReason :: InferenceError
  }
  deriving (Eq, Show)

-- | The validated result of compiling raw configuration. The raw record is
-- retained only package internally for narrow non-routing projections.
--
-- Every role compiles this value, so it carries no admission result: what a
-- machine can fund is a fact about that machine, and the coordinator is not it.
data CompiledRuntimePlan = CompiledRuntimePlan
  { compiledConfig :: DemoConfig,
    compiledCoordinator :: CompiledDaemon,
    compiledWebapp :: CompiledDaemon,
    compiledEngineDaemonMap :: Map Text CompiledDaemon,
    compiledPlacements :: Map Text CompiledPlacement
  }
  deriving (Eq, Show)

-- | Package-internal observations produced only after substrate-specific live
-- probes succeed. Each observation is keyed by the placement's model id.
data PlacementObservation
  = HostPlacementObservation Text Bool (Maybe HostMemoryPartition)
  | PodPlacementObservation Text Bool (Maybe Int)
  | GpuPlacementObservation Text Bool (Maybe Int) Bool (Maybe Int)
  deriving (Eq, Show)

newtype RuntimeObservation = RuntimeObservation [PlacementObservation]
  deriving (Eq, Show)

-- | Runtime-refined placement. Its constructor is hidden from public callers.
data ExecutableModel = ExecutableModel
  { executableDescriptor :: ModelDescriptor,
    executableEngine :: EngineBinding,
    executableRoutes :: NonEmpty EngineRoute,
    executableResources :: RuntimeResources
  }
  deriving (Eq, Show)

-- | A plan whose executable entries all carry verified live capabilities, and
-- whose rejected entries name the executing machine's own refusal. Admission
-- happens here rather than at compile time, so this is the only value that can
-- answer "can this machine run this model".
data RuntimePlan = RuntimePlan
  { runtimeCompiledPlan :: CompiledRuntimePlan,
    runtimeExecutables :: Map Text ExecutableModel,
    runtimeUnavailable :: Map Text UnavailableModel
  }
  deriving (Eq, Show)

-- | Untrusted decoded configuration. Its constructor lives in this non-exposed
-- module so external callers cannot manufacture raw configuration.
newtype RawRuntimeConfig = RawRuntimeConfig DemoConfig
