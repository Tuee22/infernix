module Infernix.Runtime.Enforcer
  ( EngineExecutionPlan,
    refineCompiledRuntimePlan,
    selectStagedCheckpointKeyForTest,
  )
where

import Control.Exception (bracket)
import Control.Monad (filterM)
import Data.ByteString qualified as ByteString
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Infernix.Config (Paths, modelCacheRoot)
import Infernix.DemoConfig (observeAppleHostMemoryPartition)
import Infernix.ExecutionPlan
  ( CompiledRuntimePlan,
    RefinementErrors,
    compiledPlanPlacementEnforcementShape,
    compiledPlanRuntimeMode,
    refineRuntimePlan,
  )
import Infernix.ExecutionPlan.Internal
  ( CompiledPlacement (placementDescriptor),
    CompiledRuntimePlan (compiledPlacements),
    ModelRequirementObservation (ModelRequirementObservation),
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
import Infernix.Models.Artifact (artifactHeaderStagedPrefixBytes)
import Infernix.Models.Requirement
  ( deriveModelRequirement,
    deriveModelRequirementFromStagedPrefix,
    derivedRequirement,
  )
import Infernix.Objects.Layout qualified as ObjLayout
import Infernix.Objects.Upload qualified as ObjectUpload
import Infernix.Runtime.CappedEngine
  ( EngineExecutionPlan,
    newEngineExecutionPlan,
    observeNvidiaDeviceVramMib,
    probeNvidiaVramSampler,
    verifyPhysicalFootprintSampler,
    verifyProcessGroupRssSampler,
  )
import Infernix.Runtime.CappedEngine.Ceiling qualified as Ceiling
import Infernix.Runtime.Enforcer.Internal (readCgroupMemoryLimitMib)
import Infernix.Runtime.Worker
  ( WorkerModelCacheConfig (workerModelCacheRoot),
    loadWorkerModelCacheConfig,
    workerObjectUploadConfig,
  )
import Infernix.Types (HostMemoryPartition, ModelDescriptor (modelId))
import Infernix.Web.Contracts (ObjectRef (objectBucket, objectKey))
import Network.HTTP.Client (defaultManagerSettings, newManager)
import System.Directory
  ( doesDirectoryExist,
    doesFileExist,
    getTemporaryDirectory,
    listDirectory,
    removeFile,
  )
import System.FilePath ((</>))
import System.IO (hClose, hPutStrLn, openBinaryTempFile, stderr)

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
  IO (Either RefinementErrors EngineExecutionPlan)
refineCompiledRuntimePlan paths compiledPlan = do
  -- Phase 4 Sprint 4.41: readiness consumes the lane's declared strength
  -- before probing or minting execution authority. A production contract that
  -- requires prevention cannot become ready through a detection-only resolver;
  -- this check runs before the daemon writes either readiness sentinel.
  case Ceiling.validateRuntimeCeilingReadiness (compiledPlanRuntimeMode compiledPlan) of
    Left reason ->
      ioError
        ( userError
            ( "runtime memory-enforcement readiness refused: "
                <> Text.unpack reason
            )
        )
    Right () -> pure ()
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
  -- Phase 4 Sprint 4.39: the requirement is derived here, on the machine that
  -- holds the artifact and will execute the work, from that artifact's own
  -- bytes. A model this machine cannot derive a requirement for is refused by
  -- name inside 'refineRuntimePlan' rather than admitted on a constant.
  requirementObservations <- observeModelRequirements paths compiledPlan
  case refineRuntimePlan
    (RuntimeObservation observations requirementObservations)
    compiledPlan of
    Left errors -> pure (Left errors)
    Right runtimePlan ->
      Right <$> newEngineExecutionPlan runtimePlan

-- | Derive one memory requirement per placed model from the artifact this
-- machine has staged for it.
observeModelRequirements ::
  Paths ->
  CompiledRuntimePlan ->
  IO [ModelRequirementObservation]
observeModelRequirements paths compiledPlan = do
  maybeCacheConfig <- loadWorkerModelCacheConfig paths (compiledPlanRuntimeMode compiledPlan)
  let cacheRoot =
        maybe
          (modelCacheRoot paths)
          (Text.unpack . workerModelCacheRoot)
          maybeCacheConfig
  traverse (observeOne cacheRoot maybeCacheConfig) (Map.elems (compiledPlacements compiledPlan))
  where
    observeOne cacheRoot maybeCacheConfig placement = do
      let model = placementDescriptor placement
      selection <- resolveStagedArtifact cacheRoot (Text.unpack (modelId model))
      derived <-
        case selection of
          -- The local cache is hydrated per request, so at daemon start it is
          -- usually empty. The coordinator has already staged the object,
          -- though, and a tensor table lives in the artifact's first few
          -- kilobytes, so the requirement is derived from a ranged read of the
          -- staged object rather than by downloading a checkpoint this machine
          -- may never run.
          StagedArtifactAbsent -> deriveFromStagedObject maybeCacheConfig model
          StagedArtifactSelected artifactPath -> deriveModelRequirement model artifactPath
          -- Phase 4 Sprint 4.50: the local and remote paths now refuse the same
          -- layouts for the same reasons. A warm cache holding several shards
          -- used to select the first one by sort order and report its tensor
          -- table as the whole requirement, so the same model admitted against a
          -- smaller number once its cache was populated than it did cold — the
          -- one condition under which the admission mattered least.
          StagedArtifactRefused reason -> pure (Left reason)
      pure
        ( ModelRequirementObservation
            (modelId model)
            (fmap derivedRequirement derived)
        )

    deriveFromStagedObject maybeCacheConfig model =
      case maybeCacheConfig of
        Nothing ->
          pure
            ( Left
                ( Text.pack
                    "this machine holds no model-cache configuration, so no artifact could be read"
                )
            )
        Just cacheConfig -> do
          manager <- newManager defaultManagerSettings
          now <- getCurrentTime
          let uploadConfig = workerObjectUploadConfig cacheConfig
              payloadRef =
                ObjLayout.modelObjectKey (modelId model) (Text.pack "payload")
          -- The single-file layout is asked for directly, because its key is
          -- known without a listing and a listing is a capability this process
          -- may not have. Only a model that is /not/ staged that way needs the
          -- prefix enumerated, and a listing that cannot be performed then says
          -- so rather than reporting an absent object.
          payloadPresent <-
            ObjectUpload.objectExistsViaPresignedGet uploadConfig manager now payloadRef
          selected <-
            if payloadPresent
              then pure (Right (objectKey payloadRef))
              else do
                listed <-
                  ObjectUpload.listObjectKeysWithPresignedUrl
                    uploadConfig
                    manager
                    now
                    (objectBucket payloadRef)
                    (modelId model <> Text.pack "/")
                pure (listed >>= selectStagedCheckpointKey)
          case selected of
            Left reason -> pure (Left reason)
            Right checkpointKey -> do
              fetched <-
                ObjectUpload.getObjectPrefixWithPresignedUrl
                  uploadConfig
                  manager
                  now
                  payloadRef {objectKey = checkpointKey}
                  artifactHeaderStagedPrefixBytes
              case fetched of
                Nothing ->
                  pure
                    ( Left
                        ( Text.pack "the staged object "
                            <> checkpointKey
                            <> Text.pack " could not be read"
                        )
                    )
                Just (prefixBytes, artifactBytes) ->
                  withArtifactPrefixFile prefixBytes $ \prefixPath ->
                    deriveModelRequirementFromStagedPrefix model prefixPath artifactBytes

-- | Phase 4 Sprint 4.43 — choose the checkpoint among a model's staged objects.
--
-- A model is staged one of two ways and the derivation has to read both. A
-- single upstream file becomes one @payload@ object; a multi-file repository is
-- mirrored under the upstream repository's own file names. Asking for @payload@
-- and stopping there reported every snapshot-layout model as having no staged
-- object at all — a refusal that named the wrong proposition, because the object
-- was there under a name this reader never asked for.
--
-- The selection is fail-closed in both directions a guess could be wrong. A
-- prefix holding no checkpoint this repository's readers understand yields the
-- family-absent refusal, which is the honest statement for an ONNX graph or a
-- CTranslate2 blob. A prefix holding /more than one/ checkpoint is a sharded
-- snapshot, and summing one shard's tensor table would understate the
-- requirement by the other shards, so it is refused by name rather than
-- silently under-derived.
selectStagedCheckpointKey :: [Text.Text] -> Either Text.Text Text.Text
selectStagedCheckpointKey stagedKeys =
  case checkpointCandidates stagedKeys of
    [checkpointKey] -> Right checkpointKey
    [] ->
      Left
        ( if null stagedKeys
            then Text.pack "the coordinator has staged no object for the model"
            else
              Text.pack
                "the coordinator's staged objects hold no checkpoint this reader understands"
        )
    shards -> Left (shardedSnapshotRefusal shards)

-- | The one shard-count refusal both the staged-object path and the local cache
-- report. A sharded snapshot has no complete inventory this reader can prove, so
-- it is refused by name on either path rather than summed from whichever shard
-- happened to be looked at first.
shardedSnapshotRefusal :: [Text.Text] -> Text.Text
shardedSnapshotRefusal shards =
  Text.pack "the model is staged as "
    <> Text.pack (show (length shards))
    <> Text.pack
      " checkpoint shards, and a requirement summed from one shard understates the rest"

-- | The checkpoint names among a set of staged keys or cached file names.
checkpointCandidates :: [Text.Text] -> [Text.Text]
checkpointCandidates candidates =
  [ candidate
  | candidate <- candidates,
    isStagedCheckpointName candidate
  ]

-- | The names the two landed readers understand. @payload@ carries no extension
-- because the single-file bootstrap names it that regardless of what the
-- upstream file was called; it is matched both as a bare cached file name and as
-- the last segment of an object key.
isStagedCheckpointName :: Text.Text -> Bool
isStagedCheckpointName candidate =
  candidate == Text.pack "payload"
    || any (`Text.isSuffixOf` candidate) stagedCheckpointSuffixes

stagedCheckpointSuffixes :: [Text.Text]
stagedCheckpointSuffixes =
  [ Text.pack "/payload",
    Text.pack ".safetensors",
    Text.pack ".gguf"
  ]

-- | Test seam over the pure selection above.
selectStagedCheckpointKeyForTest :: [Text.Text] -> Either Text.Text Text.Text
selectStagedCheckpointKeyForTest = selectStagedCheckpointKey

-- | Hold a fetched artifact prefix in a temporary file for exactly the duration
-- of one derivation, and remove it afterwards whatever happens.
withArtifactPrefixFile :: ByteString.ByteString -> (FilePath -> IO a) -> IO a
withArtifactPrefixFile prefixBytes action =
  bracket acquire release (action . fst)
  where
    acquire = do
      temporaryRoot <- getTemporaryDirectory
      (prefixPath, handle) <- openBinaryTempFile temporaryRoot "infernix-artifact-prefix"
      ByteString.hPut handle prefixBytes
      hClose handle
      pure (prefixPath, ())
    release (prefixPath, _) = removeFile prefixPath

-- | What this machine's own cache offers for one model.
--
-- The single-payload layout writes @\<cacheRoot>\/\<modelId>\/payload@; the
-- snapshot layout writes the upstream repository's own file names into the same
-- directory. Both are read through the same selection policy the staged-object
-- path uses, so a layout that is refused cold is refused warm.
data StagedArtifactSelection
  = -- | This machine holds no checkpoint for the model; the coordinator's
    -- staged object is the place to look.
    StagedArtifactAbsent
  | -- | Exactly one checkpoint, which is the artifact the requirement is
    -- derived from.
    StagedArtifactSelected FilePath
  | -- | A layout the shared policy refuses, carrying the same reason the
    -- staged-object path would give.
    StagedArtifactRefused Text.Text
  deriving (Eq, Show)

resolveStagedArtifact :: FilePath -> FilePath -> IO StagedArtifactSelection
resolveStagedArtifact cacheRoot modelIdValue = do
  let modelRoot = cacheRoot </> modelIdValue
  modelRootPresent <- doesDirectoryExist modelRoot
  if not modelRootPresent
    then pure StagedArtifactAbsent
    else do
      entries <- listDirectory modelRoot
      presentEntries <- filterM (doesFileExist . (modelRoot </>)) entries
      case checkpointCandidates (sort (map Text.pack presentEntries)) of
        [checkpoint] -> pure (StagedArtifactSelected (modelRoot </> Text.unpack checkpoint))
        [] -> pure StagedArtifactAbsent
        shards -> pure (StagedArtifactRefused (shardedSnapshotRefusal shards))

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
