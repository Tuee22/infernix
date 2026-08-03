{-# LANGUAGE ScopedTypeVariables #-}

module Infernix.Runtime.Enforcer
  ( refineCompiledRuntimePlan,
  )
where

import Control.Exception (IOException, try)
import Data.List (find)
import Data.Map.Strict qualified as Map
import Infernix.Config (Paths)
import Infernix.DemoConfig (observeAppleHostMemoryPartition)
import Infernix.ExecutionPlan
  ( CompiledRuntimePlan,
    RefinementErrors,
    RuntimePlan,
    refineRuntimePlan,
  )
import Infernix.ExecutionPlan.Internal
  ( CompiledPlacement (placementDescriptor, placementResources),
    CompiledResources
      ( CompiledGpuResources,
        CompiledHostResources,
        CompiledPodResources
      ),
    CompiledRuntimePlan (compiledPlacements),
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
    verifyPhysicalFootprintSampler,
    verifyProcessGroupRssSampler,
  )
import Infernix.Runtime.Enforcer.Internal (parseFiniteMib)
import Infernix.Types (HostMemoryPartition, ModelDescriptor (modelId))
import System.FilePath ((</>))

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
  let placements = Map.elems (compiledPlacements compiledPlan)
      needsHostSampler = any isHostPlacement placements
      needsPodSampler = any isPodPlacement placements
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
  let observations =
        map
          (placementObservation observedHostPartition hostSamplerAvailable podSamplerAvailable outerLimitMib)
          placements
  case refineRuntimePlan (RuntimeObservation observations) compiledPlan of
    Left errors -> pure (Left errors)
    Right runtimePlan -> do
      authority <- newEngineExecutionAuthority
      pure (Right (runtimePlan, authority))

isHostPlacement :: CompiledPlacement -> Bool
isHostPlacement placement =
  case placementResources placement of
    CompiledHostResources {} -> True
    CompiledPodResources {} -> False
    CompiledGpuResources {} -> False

isPodPlacement :: CompiledPlacement -> Bool
isPodPlacement placement =
  case placementResources placement of
    CompiledHostResources {} -> False
    CompiledPodResources {} -> True
    CompiledGpuResources {} -> True

placementObservation ::
  Maybe HostMemoryPartition ->
  Bool ->
  Bool ->
  Maybe Int ->
  CompiledPlacement ->
  PlacementObservation
placementObservation observedHostPartition hostSamplerAvailable podSamplerAvailable outerLimitMib placement =
  case placementResources placement of
    CompiledHostResources {} ->
      HostPlacementObservation placementId hostSamplerAvailable observedHostPartition
    CompiledPodResources {} ->
      PodPlacementObservation placementId podSamplerAvailable outerLimitMib
    CompiledGpuResources {} ->
      GpuPlacementObservation
        placementId
        podSamplerAvailable
        outerLimitMib
        False
        Nothing
  where
    placementId = modelId (placementDescriptor placement)

readCgroupMemoryLimitMib :: IO (Maybe Int)
readCgroupMemoryLimitMib = do
  maybeRelativePath <- readCurrentCgroupPath
  case maybeRelativePath of
    Nothing -> pure Nothing
    Just relativePath ->
      firstFiniteLimit
        ["/sys/fs/cgroup" </> relativePath </> "memory.max"]

readCurrentCgroupPath :: IO (Maybe FilePath)
readCurrentCgroupPath = do
  readResult <- try (readFile "/proc/self/cgroup")
  pure $
    case readResult of
      Left (_ :: IOException) -> Nothing
      Right contents ->
        dropWhile (== '/')
          . drop (length ("0::" :: String))
          <$> find (startsWithUnifiedHierarchy . trimLine) (lines contents)
  where
    startsWithUnifiedHierarchy value = take 3 value == "0::"
    trimLine = reverse . dropWhile (`elem` ['\r', '\n']) . reverse

firstFiniteLimit :: [FilePath] -> IO (Maybe Int)
firstFiniteLimit [] = pure Nothing
firstFiniteLimit (path : remaining) = do
  readResult <- try (readFile path)
  case readResult of
    Left (_ :: IOException) -> firstFiniteLimit remaining
    Right contents ->
      case parseFiniteMib contents of
        Just limitMib -> pure (Just limitMib)
        Nothing -> firstFiniteLimit remaining
