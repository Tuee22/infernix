module Infernix.Runtime.Enforcer
  ( refineCompiledRuntimePlan,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Infernix.Config (Paths)
import Infernix.DemoConfig (observeAppleHostMemoryPartition)
import Infernix.ExecutionPlan
  ( CompiledRuntimePlan,
    RefinementErrors,
    RuntimePlan,
    compiledPlanPlacementEnforcementShape,
    refineRuntimePlan,
  )
import Infernix.ExecutionPlan.Internal
  ( CompiledPlacement (placementDescriptor),
    CompiledRuntimePlan (compiledPlacements),
    PlacementEnforcementShape
      ( GpuEnforcementShape,
        HostEnforcementShape,
        PodEnforcementShape
      ),
    PlacementObservation
      ( GpuPlacementObservation,
        HostPlacementObservation,
        PodPlacementObservation
      ),
    RuntimeObservation (RuntimeObservation),
  )
import Infernix.Runtime.CappedEngine
  ( EngineExecutionAuthority,
    newEngineExecutionAuthority,
    observeNvidiaDeviceVramMib,
    probeNvidiaVramSampler,
    verifyPhysicalFootprintSampler,
    verifyProcessGroupRssSampler,
  )
import Infernix.Runtime.Enforcer.Internal (readCgroupMemoryLimitMib)
import Infernix.Types (HostMemoryPartition, ModelDescriptor (modelId))
import System.IO (hPutStrLn, stderr)

-- | Probe the enforcement mechanisms named by a compiled plan and refine it
-- into the only value accepted by the engine launch boundary. Probe results
-- are observations, not permanent assumptions: each watchdog still fails
-- closed if its sampler disappears during an execution.
-- | The authority is minted here, with the plan it serializes, and nowhere
-- else. Returning the pair is what makes concurrent reuse of one refined plan
-- unrepresentable: a caller has no way to obtain a second token.
refineCompiledRuntimePlan ::
  Paths ->
  CompiledRuntimePlan ->
  IO (Either RefinementErrors (RuntimePlan, EngineExecutionAuthority))
refineCompiledRuntimePlan paths compiledPlan = do
  -- Phase 4 Sprint 4.34: which samplers to probe is derived from the runtime
  -- mode, the declared budget, and whether the model uses the device — not from
  -- a resource the placement carries, because after the admission split it
  -- carries none. A placement whose mode and budget name no mechanism at all
  -- gets no observation and is rejected by admission inside
  -- 'refineRuntimePlan'; 'compilerErrors' already refuses that pair upstream.
  let shapedPlacements =
        [ (placement, compiledPlanPlacementEnforcementShape compiledPlan placement)
        | placement <- Map.elems (compiledPlacements compiledPlan)
        ]
      shapes = [shape | (_, Just shape) <- shapedPlacements]
      needsHostSampler = any isHostShape shapes
      needsPodSampler = any isResidentShape shapes
      needsNvidiaSampler = any isGpuShape shapes
  hostSamplerAvailable <-
    if needsHostSampler
      then verifyPhysicalFootprintSampler
      else pure False
  observedHostPartition <-
    if needsHostSampler
      then observeAppleHostMemoryPartition paths
      else pure Nothing
  podSamplerAvailable <-
    if needsPodSampler
      then verifyProcessGroupRssSampler
      else pure False
  outerLimitMib <-
    if needsPodSampler
      then readCgroupMemoryLimitMib
      else pure Nothing
  -- Sprint 6.44: the probe's reason is logged here rather than discarded.
  -- `NvidiaSamplerUnavailable` names the placement but carries no diagnosis, so
  -- a `linux-gpu` engine that cannot enforce VRAM used to crash-loop with an
  -- error that said nothing about which precondition failed.
  nvidiaSamplerAvailable <-
    if needsNvidiaSampler
      then do
        probed <- probeNvidiaVramSampler
        case probed of
          Right _ -> pure True
          Left reason -> do
            hPutStrLn
              stderr
              ( "engine refinement: NVIDIA VRAM sampler unavailable: "
                  <> Text.unpack reason
              )
            pure False
      else pure False
  observedVramMib <-
    if needsNvidiaSampler
      then observeNvidiaDeviceVramMib
      else pure Nothing
  let observations =
        [ placementObservation
            observedHostPartition
            hostSamplerAvailable
            podSamplerAvailable
            outerLimitMib
            nvidiaSamplerAvailable
            observedVramMib
            (modelId (placementDescriptor placement))
            shape
        | (placement, Just shape) <- shapedPlacements
        ]
  case refineRuntimePlan (RuntimeObservation observations) compiledPlan of
    Left errors -> pure (Left errors)
    Right runtimePlan -> do
      authority <- newEngineExecutionAuthority
      pure (Right (runtimePlan, authority))

isHostShape :: PlacementEnforcementShape -> Bool
isHostShape shape =
  case shape of
    HostEnforcementShape {} -> True
    PodEnforcementShape {} -> False
    GpuEnforcementShape {} -> False

isResidentShape :: PlacementEnforcementShape -> Bool
isResidentShape shape =
  case shape of
    HostEnforcementShape {} -> False
    PodEnforcementShape {} -> True
    GpuEnforcementShape {} -> True

isGpuShape :: PlacementEnforcementShape -> Bool
isGpuShape shape =
  case shape of
    HostEnforcementShape {} -> False
    PodEnforcementShape {} -> False
    GpuEnforcementShape {} -> True

placementObservation ::
  Maybe HostMemoryPartition ->
  Bool ->
  Bool ->
  Maybe Int ->
  Bool ->
  Maybe Int ->
  Text.Text ->
  PlacementEnforcementShape ->
  PlacementObservation
placementObservation
  observedHostPartition
  hostSamplerAvailable
  podSamplerAvailable
  outerLimitMib
  nvidiaSamplerAvailable
  observedVramMib
  placementId
  shape =
    case shape of
      HostEnforcementShape {} ->
        HostPlacementObservation placementId hostSamplerAvailable observedHostPartition
      PodEnforcementShape {} ->
        PodPlacementObservation placementId podSamplerAvailable outerLimitMib
      GpuEnforcementShape {} ->
        GpuPlacementObservation
          placementId
          podSamplerAvailable
          outerLimitMib
          nvidiaSamplerAvailable
          observedVramMib
