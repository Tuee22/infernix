{-# LANGUAGE DataKinds #-}

-- | One adjustment point for the intended public capability API. The fixtures
-- deliberately do not import implementation modules directly.
module DesiredApi
  ( CompiledRuntimePlan,
    Enforcer,
    EnforcerPlan,
    EngineRoute,
    ExecutableModel,
    HostMemoryPartition,
    MemoryCeiling,
    MemoryGrant,
    ModelMemoryFootprint,
    RawRuntimeConfig,
    Resource (..),
    RuntimePlan,
    lookupExecutableModel,
  )
where

import Infernix.ExecutionPlan
  ( CompiledRuntimePlan,
    Enforcer,
    EnforcerPlan,
    EngineRoute,
    ExecutableModel,
    MemoryCeiling,
    MemoryGrant,
    RawRuntimeConfig,
    Resource (..),
    RuntimePlan,
    lookupExecutableModel,
  )
import Infernix.Types
  ( HostMemoryPartition,
    ModelMemoryFootprint,
  )
