{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Infernix.ExecutionPlan.Properties
  ( runExecutableLaunchBoundaryProperties,
    runExecutionPlanRefinementProperties,
  )
where

import Control.Monad (when)
import Data.ByteString qualified as ByteString
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.ProtoLens.Field (field)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Config (Paths (..))
import Infernix.ExecutionPlan
  ( ExecutableModel,
    RefinementError (..),
    RuntimePlan,
    executableModelDescriptor,
    executableModelEngine,
    executableModelGpuVramCeilingMib,
    executableModelId,
    executableModelResidentCeilingMib,
    linuxOuterEnvelopeHeadroomMib,
    lookupExecutableModel,
    refineRuntimePlan,
  )
import Infernix.ExecutionPlan.Internal
  ( CompiledDaemon (..),
    CompiledPlacement (..),
    CompiledResources (..),
    CompiledRuntimePlan (..),
    EnforcerPlan (..),
    EngineRoute (..),
    MemoryCeiling (..),
    MemoryGrant (..),
    PlacementObservation (..),
    RuntimeObservation (..),
  )
import Infernix.Models
  ( catalogForMode,
    engineBindingForSelectedEngine,
  )
import Infernix.Runtime (executeExecutableInferenceWithKVCache)
import Infernix.Runtime.CappedEngine qualified as CappedEngine
import Infernix.Runtime.Pulsar qualified as Pulsar
import Infernix.Runtime.Worker
  ( WorkerModelCacheConfig (..),
    buildWorkerRequest,
    runExecutableInferenceWorker,
    workerRequestModelCacheConfig,
  )
import Infernix.Types
  ( ConsumerSubscriptionType (ConsumerShared),
    DaemonConfig (..),
    DaemonRole (..),
    DemoConfig (..),
    EngineMember (..),
    EnginePool (..),
    HostMemoryPartition,
    InferenceMemoryBudget (HostEnforcedBudget),
    InferenceRequest (..),
    ModelDescriptor (modelId, runtimeMode, selectedEngine),
    PodMemoryLimit (..),
    PulsarConnectionMode (ConfiguredTransport),
    RuntimeMode (AppleSilicon),
    defaultModelBootstrapTopic,
    defaultModelsBucket,
    engineBindingAdapterId,
    errorCode,
    hostPartitionForCapacity,
    runtimeModeId,
  )
import Infernix.Types qualified as Types
import Lens.Family2 (view)
import System.Directory (createDirectoryIfMissing, doesFileExist, doesPathExist, removeFile, removePathForcibly)
import System.FilePath ((<.>), (</>))

runExecutionPlanRefinementProperties :: IO ()
runExecutionPlanRefinementProperties = do
  assertSuccessfulRefinements
  assertDaemonTopicCapabilityProperties
  assertRefinementFailure
    "duplicate observations"
    (DuplicatePlacementObservation sampleModelId)
    [validHostObservation, validHostObservation]
    hostPlan
  assertRefinementFailure
    "missing observation"
    (MissingPlacementObservation sampleModelId)
    []
    hostPlan
  assertRefinementFailure
    "unexpected observation"
    (UnexpectedPlacementObservation "unexpected-model")
    [HostPlacementObservation "unexpected-model" True (Just expectedHostPartition)]
    (compiledPlan Map.empty)
  assertRefinementFailure
    "resource mismatch"
    (PlacementObservationResourceMismatch sampleModelId)
    [validPodObservation]
    hostPlan
  assertRefinementFailure
    "physical-footprint sampler unavailable"
    (PhysicalFootprintSamplerUnavailable sampleModelId)
    [HostPlacementObservation sampleModelId False (Just expectedHostPartition)]
    hostPlan
  assertRefinementFailure
    "host partition observation unavailable"
    (HostPartitionObservationUnavailable sampleModelId)
    [HostPlacementObservation sampleModelId True Nothing]
    hostPlan
  assertRefinementFailure
    "host partition mismatch"
    (HostPartitionMismatch sampleModelId expectedHostPartition mismatchedHostPartition)
    [HostPlacementObservation sampleModelId True (Just mismatchedHostPartition)]
    hostPlan
  assertRefinementFailure
    "resident sampler unavailable"
    (ResidentSamplerUnavailable sampleModelId)
    [PodPlacementObservation sampleModelId False (Just requiredOuterEnvelopeMib)]
    podPlan
  assertRefinementFailure
    "outer envelope unavailable"
    (OuterEnvelopeUnavailable sampleModelId)
    [PodPlacementObservation sampleModelId True Nothing]
    podPlan
  assertRefinementFailure
    "outer envelope too small"
    (OuterEnvelopeTooSmall sampleModelId (toInteger requiredOuterEnvelopeMib) (toInteger (requiredOuterEnvelopeMib - 1)))
    [PodPlacementObservation sampleModelId True (Just (requiredOuterEnvelopeMib - 1))]
    podPlan
  assertRefinementFailure
    "outer envelope too large"
    (OuterEnvelopeTooLarge sampleModelId (toInteger requiredOuterEnvelopeMib) (toInteger (requiredOuterEnvelopeMib + 1)))
    [PodPlacementObservation sampleModelId True (Just (requiredOuterEnvelopeMib + 1))]
    podPlan
  assertRefinementFailure
    "NVIDIA sampler unavailable"
    (NvidiaSamplerUnavailable sampleModelId)
    [GpuPlacementObservation sampleModelId True (Just requiredOuterEnvelopeMib) False (Just gpuCeilingMib)]
    gpuPlan
  assertRefinementFailure
    "NVIDIA envelope unavailable"
    (NvidiaEnvelopeUnavailable sampleModelId)
    [GpuPlacementObservation sampleModelId True (Just requiredOuterEnvelopeMib) True Nothing]
    gpuPlan
  assertRefinementFailure
    "NVIDIA envelope too small"
    (NvidiaEnvelopeTooSmall sampleModelId (toInteger gpuCeilingMib) (toInteger (gpuCeilingMib - 1)))
    [GpuPlacementObservation sampleModelId True (Just requiredOuterEnvelopeMib) True (Just (gpuCeilingMib - 1))]
    gpuPlan
  putStrLn "execution-plan internal refinement coverage passed"

assertDaemonTopicCapabilityProperties :: IO ()
assertDaemonTopicCapabilityProperties = do
  runtimePlan <- requireCapabilityRuntimePlan
  capabilityAuthority <- CappedEngine.newEngineExecutionAuthority
  firstCapabilities <-
    either
      fail
      pure
      (Pulsar.engineTopicCapabilities sampleMemberId runtimePlan capabilityAuthority)
  secondCapabilities <-
    either
      fail
      pure
      (Pulsar.engineTopicCapabilities secondMemberId runtimePlan capabilityAuthority)
  firstCapability <-
    requireCapability sampleTopic firstCapabilities
  secondCapability <-
    requireCapability secondTopic secondCapabilities
  assert
    (Pulsar.daemonTopicCapabilityAuthorizesModel firstCapability sampleModelId)
    "an engine topic capability authorizes its exact member/topic executable route"
  assert
    (not (Pulsar.daemonTopicCapabilityAuthorizesModel firstCapability secondModelId))
    "an engine topic capability rejects a model routed to another member/topic"
  assert
    (Pulsar.daemonTopicCapabilityAuthorizesModel secondCapability secondModelId)
    "the second engine topic capability authorizes its exact executable route"
  assert
    (not (Pulsar.daemonTopicCapabilityAuthorizesModel secondCapability sampleModelId))
    "the second engine topic capability rejects the first member/topic route"
  case Pulsar.engineTopicCapabilities "unauthorized-member" runtimePlan capabilityAuthority of
    Left _ -> pure ()
    Right _ ->
      fail "an engine topic capability was minted for an unknown daemon member"
  case Pulsar.coordinatorTopicCapabilities capabilityPlan of
    capability : _ ->
      assert
        (not (Pulsar.daemonTopicCapabilityAuthorizesModel capability sampleModelId))
        "a coordinator capability cannot authorize engine execution"
    [] -> fail "the capability property plan omitted its coordinator topic"

requireCapability ::
  Text ->
  [Pulsar.DaemonTopicCapability] ->
  IO Pulsar.DaemonTopicCapability
requireCapability expectedTopic capabilities =
  case [ capability
       | capability <- capabilities,
         Pulsar.daemonTopicCapabilityTopic capability == expectedTopic
       ] of
    [capability] -> pure capability
    matches ->
      fail
        ( "expected exactly one capability for "
            <> show expectedTopic
            <> ", found "
            <> show (length matches)
        )

runExecutableLaunchBoundaryProperties :: Paths -> IO ()
runExecutableLaunchBoundaryProperties paths = do
  executable <- requireSampleExecutable
  let propertyRoot = buildRoot paths </> "launch-boundary-properties"
      propertyPaths = isolatedPropertyPaths paths propertyRoot
      mismatchedRequest =
        InferenceRequest
          { requestModelId = "poisoned-request-model",
            inputText = "launch boundary identity proof",
            inputObjectRef = Nothing,
            requestUserId = Just "unit-user",
            requestContextId = Just "unit-context"
          }
      cacheConfig =
        WorkerModelCacheConfig
          { workerModelCacheRoot = "/model-cache",
            workerModelCacheQuotaBytes = 123456,
            workerMinioEndpoint = "http://infernix-minio.platform.svc.cluster.local:9000",
            workerMinioModelsBucket = "infernix-models",
            workerMinioDemoArtifactsBucket = "infernix-demo-objects",
            workerMinioRegion = "us-east-1",
            workerMinioAccessKey = "unit-access-key",
            workerMinioSecretKey = "unit-secret-key"
          }
      workerRequest =
        buildWorkerRequest
          propertyPaths
          (Just cacheConfig)
          executable
          mismatchedRequest
      descriptor = executableModelDescriptor executable
      binding = executableModelEngine executable
  propertyRootPresent <- doesPathExist propertyRoot
  when propertyRootPresent (removePathForcibly propertyRoot)
  assert
    (view (field @"requestModelId") workerRequest == executableModelId executable)
    "worker request model identity is derived from the executable"
  assert
    (view (field @"runtimeMode") workerRequest == runtimeModeId (runtimeMode descriptor))
    "worker request runtime identity is derived from the executable"
  assert
    (view (field @"selectedEngine") workerRequest == selectedEngine descriptor)
    "worker request engine identity is derived from the executable"
  assert
    (view (field @"adapterId") workerRequest == engineBindingAdapterId binding)
    "worker request adapter identity is derived from the executable binding"
  assert
    (workerRequestModelCacheConfig workerRequest == Just cacheConfig)
    "worker request preserves the typed model-cache projection"
  runtimeResult <-
    executeExecutableInferenceWithKVCache
      propertyPaths
      Nothing
      Nothing
      executable
      mismatchedRequest
  assertRequestModelMismatch "runtime execution boundary" runtimeResult
  workerResult <-
    runExecutableInferenceWorker
      propertyPaths
      executable
      mismatchedRequest
      Nothing
  assertRequestModelMismatch "worker execution boundary" workerResult
  artifactsPresent <- doesPathExist propertyRoot
  assert
    (not artifactsPresent)
    "request-model mismatch guards run before cache, setup, result, or process artifacts are created"
  runtimePlan <- requireCapabilityRuntimePlan
  capabilityAuthority <- CappedEngine.newEngineExecutionAuthority
  engineCapabilities <-
    either
      fail
      pure
      (Pulsar.engineTopicCapabilities sampleMemberId runtimePlan capabilityAuthority)
  engineCapability <-
    requireCapability sampleTopic engineCapabilities
  let poisonRoot = buildRoot paths </> "engine-poison-message-properties"
      poisonPaths = isolatedPropertyPaths paths poisonRoot
  poisonRootPresent <- doesPathExist poisonRoot
  when poisonRootPresent (removePathForcibly poisonRoot)
  unauthorizedResult <-
    assertEnginePoisonRejection
      poisonPaths
      engineCapability
      secondModelId
      "engine topic capability rejects model"
  unknownResult <-
    assertEnginePoisonRejection
      poisonPaths
      engineCapability
      "unknown-model"
      "engine topic capability has no executable model"
  assert
    (Types.createdAt unauthorizedResult == Types.createdAt unknownResult)
    "engine poison-message rejections use the deterministic rejection timestamp"
  malformedResult <-
    assertMalformedEngineRejection
      poisonPaths
      engineCapability
  assert
    (Types.createdAt malformedResult == Types.createdAt unauthorizedResult)
    "malformed engine messages use the deterministic rejection timestamp"
  launchArtifactsPresent <-
    or
      <$> mapM
        doesPathExist
        [ dataRoot poisonPaths,
          modelCacheRoot poisonPaths,
          resultsRoot poisonPaths,
          repoRoot poisonPaths,
          buildRoot poisonPaths,
          kindRoot poisonPaths,
          helmConfigRoot poisonPaths,
          helmCacheRoot poisonPaths,
          helmDataRoot poisonPaths
        ]
  assert
    (not launchArtifactsPresent)
    "engine poison-message rejection runs before cache, setup, result-store, or process artifacts are created"
  putStrLn "executable launch-boundary properties passed"

assertEnginePoisonRejection ::
  Paths ->
  Pulsar.DaemonTopicCapability ->
  Text ->
  Text ->
  IO Types.InferenceResult
assertEnginePoisonRejection paths capability rejectedModelId expectedDiagnostic = do
  let capabilityCompiledPlan = capabilityPlan
  requestIdValue <-
    Pulsar.publishInferenceRequest
      paths
      capabilityCompiledPlan
      InferenceRequest
        { requestModelId = rejectedModelId,
          inputText = "reject before executable launch",
          inputObjectRef = Nothing,
          requestUserId = Nothing,
          requestContextId = Nothing
        }
  let publicationSourcePath =
        Pulsar.topicDirectoryPath paths sampleCoordinatorTopic
          </> Text.unpack requestIdValue
            <.> "pb"
      sourceDirectory =
        Pulsar.topicDirectoryPath paths (Pulsar.daemonTopicCapabilityTopic capability)
      sourcePath =
        sourceDirectory
          </> Text.unpack requestIdValue
            <.> "pb"
  encodedRequest <- ByteString.readFile publicationSourcePath
  createDirectoryIfMissing True sourceDirectory
  ByteString.writeFile sourcePath encodedRequest
  removeFile publicationSourcePath
  Pulsar.drainTopic paths capability
  sourceExists <- doesFileExist sourcePath
  maybeResult <-
    Pulsar.readPublishedInferenceResultMaybe
      paths
      capabilityCompiledPlan
      requestIdValue
  resultValue <-
    maybe
      (fail "engine poison-message rejection did not publish a terminal result")
      pure
      maybeResult
  assert
    (Types.status resultValue == "failed")
    "engine poison-message rejection publishes a failed terminal result"
  assert
    (Types.resultModelId resultValue == rejectedModelId)
    "engine poison-message rejection preserves the rejected model id"
  assert
    ( maybe
        False
        (Text.isInfixOf expectedDiagnostic)
        (Types.inlineOutput (Types.payload resultValue))
    )
    "engine poison-message rejection publishes the expected route diagnostic"
  assert
    ( isNothing (Types.objectRef (Types.payload resultValue))
        && isNothing (Types.inferenceError (Types.payload resultValue))
    )
    "engine poison-message rejection does not fabricate output or a memory error"
  assert
    (not sourceExists)
    "engine poison-message rejection removes the source request"
  Pulsar.drainTopic paths capability
  repeatedResult <-
    Pulsar.readPublishedInferenceResultMaybe
      paths
      capabilityCompiledPlan
      requestIdValue
  assert
    (repeatedResult == Just resultValue)
    "engine poison-message rejection is stable after the source message is removed"
  pure resultValue

assertMalformedEngineRejection ::
  Paths ->
  Pulsar.DaemonTopicCapability ->
  IO Types.InferenceResult
assertMalformedEngineRejection paths capability = do
  let malformedRequestId = "malformed-engine-request"
      sourceDirectory =
        Pulsar.topicDirectoryPath
          paths
          (Pulsar.daemonTopicCapabilityTopic capability)
      sourcePath =
        sourceDirectory
          </> Text.unpack malformedRequestId
            <.> "pb"
  createDirectoryIfMissing True sourceDirectory
  ByteString.writeFile sourcePath (ByteString.pack [0x80])
  Pulsar.drainTopic paths capability
  sourceExists <- doesFileExist sourcePath
  maybeResult <-
    Pulsar.readPublishedInferenceResultMaybe
      paths
      capabilityPlan
      malformedRequestId
  resultValue <-
    maybe
      (fail "malformed engine message did not publish a terminal result")
      pure
      maybeResult
  assert
    ( Types.status resultValue == "failed"
        && maybe
          False
          (Text.isInfixOf "malformed_inference_request")
          (Types.inlineOutput (Types.payload resultValue))
    )
    "malformed engine message publishes a typed failed result"
  assert
    (not sourceExists)
    "malformed engine message removes the source request"
  Pulsar.drainTopic paths capability
  repeatedResult <-
    Pulsar.readPublishedInferenceResultMaybe
      paths
      capabilityPlan
      malformedRequestId
  assert
    (repeatedResult == Just resultValue)
    "malformed engine rejection is stable after the source message is removed"
  pure resultValue

isolatedPropertyPaths :: Paths -> FilePath -> Paths
isolatedPropertyPaths paths propertyRoot =
  paths
    { repoRoot = propertyRoot </> "repo",
      buildRoot = propertyRoot </> "build",
      dataRoot = propertyRoot </> "data",
      runtimeRoot = propertyRoot </> "runtime",
      kindRoot = propertyRoot </> "kind",
      helmConfigRoot = propertyRoot </> "helm" </> "config",
      helmCacheRoot = propertyRoot </> "helm" </> "cache",
      helmDataRoot = propertyRoot </> "helm" </> "data",
      resultsRoot = propertyRoot </> "results",
      modelCacheRoot = propertyRoot </> "model-cache",
      pathsHostConfig = Nothing
    }

requireCapabilityRuntimePlan :: IO RuntimePlan
requireCapabilityRuntimePlan =
  case refineRuntimePlan
    (RuntimeObservation [validHostObservation, secondHostObservation])
    capabilityPlan of
    Left errors ->
      fail
        ( "could not refine the topic-capability property plan: "
            <> show (NonEmpty.toList errors)
        )
    Right refinedPlan -> pure refinedPlan

requireSampleExecutable :: IO ExecutableModel
requireSampleExecutable =
  case refineRuntimePlan (RuntimeObservation [validHostObservation]) hostPlan of
    Left errors ->
      fail
        ( "could not refine the launch-boundary sample executable: "
            <> show (NonEmpty.toList errors)
        )
    Right runtimePlan ->
      maybe
        (fail "refined launch-boundary plan omitted its sample executable")
        pure
        (lookupExecutableModel sampleModelId runtimePlan)

assertRequestModelMismatch ::
  String ->
  Either Types.ErrorResponse result ->
  IO ()
assertRequestModelMismatch label result =
  case result of
    Left err ->
      assert
        (errorCode err == "request_model_mismatch")
        (label <> " returned the wrong error code: " <> show err)
    Right _ ->
      fail (label <> " accepted a request for a different model")

assertSuccessfulRefinements :: IO ()
assertSuccessfulRefinements = do
  assertSuccessfulRefinement
    "host"
    validHostObservation
    hostPlan
    residentCeilingMib
    Nothing
  assertSuccessfulRefinement
    "pod"
    validPodObservation
    podPlan
    residentCeilingMib
    Nothing
  assertSuccessfulRefinement
    "GPU"
    validGpuObservation
    gpuPlan
    residentCeilingMib
    (Just gpuCeilingMib)

assertSuccessfulRefinement ::
  String ->
  PlacementObservation ->
  CompiledRuntimePlan ->
  Int ->
  Maybe Int ->
  IO ()
assertSuccessfulRefinement label observation plan expectedResidentMib expectedGpuMib =
  case refineRuntimePlan (RuntimeObservation [observation]) plan of
    Left errors ->
      fail
        ( label
            <> " refinement unexpectedly failed: "
            <> show (NonEmpty.toList errors)
        )
    Right runtimePlan ->
      case lookupExecutableModel sampleModelId runtimePlan of
        Nothing -> fail (label <> " refinement omitted its executable model")
        Just executable -> do
          assert
            (executableModelResidentCeilingMib executable == expectedResidentMib)
            (label <> " refinement changed the resident-memory grant")
          assert
            (executableModelGpuVramCeilingMib executable == expectedGpuMib)
            (label <> " refinement changed the GPU-memory grant")

assertRefinementFailure ::
  String ->
  RefinementError ->
  [PlacementObservation] ->
  CompiledRuntimePlan ->
  IO ()
assertRefinementFailure label expectedError observations plan =
  case refineRuntimePlan (RuntimeObservation observations) plan of
    Left errors ->
      assert
        (NonEmpty.toList errors == [expectedError])
        ( label
            <> " produced unexpected refinement errors: "
            <> show (NonEmpty.toList errors)
        )
    Right _ ->
      fail (label <> " unexpectedly refined into an executable runtime plan")

assert :: Bool -> String -> IO ()
assert condition message =
  if condition
    then pure ()
    else fail message

hostPlan :: CompiledRuntimePlan
hostPlan =
  compiledPlan
    ( Map.singleton
        sampleModelId
        (compiledPlacement hostResources)
    )

podPlan :: CompiledRuntimePlan
podPlan =
  compiledPlan
    ( Map.singleton
        sampleModelId
        (compiledPlacement podResources)
    )

gpuPlan :: CompiledRuntimePlan
gpuPlan =
  compiledPlan
    ( Map.singleton
        sampleModelId
        (compiledPlacement gpuResources)
    )

capabilityPlan :: CompiledRuntimePlan
capabilityPlan =
  ( compiledPlan
      ( Map.fromList
          [ (sampleModelId, compiledPlacement hostResources),
            (secondModelId, secondCompiledPlacement)
          ]
      )
  )
    { compiledEngineDaemonMap =
        Map.fromList
          [ (sampleMemberId, CompiledDaemon engineDaemonConfig),
            (secondMemberId, CompiledDaemon secondEngineDaemonConfig)
          ]
    }

compiledPlan :: Map Text CompiledPlacement -> CompiledRuntimePlan
compiledPlan placements =
  CompiledRuntimePlan
    { compiledConfig = sampleConfig,
      compiledCoordinator = CompiledDaemon coordinatorConfig,
      compiledWebapp = CompiledDaemon webappConfig,
      compiledEngineDaemonMap =
        Map.singleton sampleMemberId (CompiledDaemon engineDaemonConfig),
      compiledPlacements = placements,
      compiledUnavailable = Map.empty
    }

compiledPlacement :: CompiledResources -> CompiledPlacement
compiledPlacement resources =
  CompiledPlacement
    { placementDescriptor = sampleModel,
      placementEngine = sampleEngineBinding,
      placementRoutes = sampleRoute :| [],
      placementResources = resources
    }

hostResources :: CompiledResources
hostResources =
  CompiledHostResources
    (HostFootprintWatchdogPlan expectedHostPartition)
    (MemoryGrant (MemoryCeiling residentCeilingMib))

podResources :: CompiledResources
podResources =
  CompiledPodResources
    (LinuxProcessGroupRssWatchdogPlan residentPodLimit)
    (MemoryGrant (MemoryCeiling residentCeilingMib))

gpuResources :: CompiledResources
gpuResources =
  CompiledGpuResources
    (LinuxProcessGroupRssWatchdogPlan residentPodLimit)
    (MemoryGrant (MemoryCeiling residentCeilingMib))
    (NvidiaVramAccountingPlan gpuPodLimit)
    (MemoryGrant (MemoryCeiling gpuCeilingMib))

validHostObservation :: PlacementObservation
validHostObservation =
  HostPlacementObservation sampleModelId True (Just expectedHostPartition)

validPodObservation :: PlacementObservation
validPodObservation =
  PodPlacementObservation sampleModelId True (Just requiredOuterEnvelopeMib)

validGpuObservation :: PlacementObservation
validGpuObservation =
  GpuPlacementObservation
    sampleModelId
    True
    (Just requiredOuterEnvelopeMib)
    True
    (Just gpuCeilingMib)

secondHostObservation :: PlacementObservation
secondHostObservation =
  HostPlacementObservation secondModelId True (Just expectedHostPartition)

expectedHostPartition :: HostMemoryPartition
expectedHostPartition =
  requireHostPartition "expected" (hostPartitionForCapacity 8192)

mismatchedHostPartition :: HostMemoryPartition
mismatchedHostPartition =
  requireHostPartition "mismatched" (hostPartitionForCapacity 8193)

requireHostPartition ::
  String ->
  Either String HostMemoryPartition ->
  HostMemoryPartition
requireHostPartition label partitionResult =
  case partitionResult of
    Left partitionError ->
      error (label <> " test host partition is invalid: " <> partitionError)
    Right partition -> partition

residentCeilingMib :: Int
residentCeilingMib = 1024

gpuCeilingMib :: Int
gpuCeilingMib = 2048

requiredOuterEnvelopeMib :: Int
requiredOuterEnvelopeMib =
  residentCeilingMib + linuxOuterEnvelopeHeadroomMib

residentPodLimit :: PodMemoryLimit
residentPodLimit =
  PodMemoryLimit
    { podMemoryLimitResource = Types.PodRam,
      podMemoryLimitSource = "execution-plan-internal-test",
      podMemoryLimitMib = residentCeilingMib
    }

gpuPodLimit :: PodMemoryLimit
gpuPodLimit =
  PodMemoryLimit
    { podMemoryLimitResource = Types.GpuVram,
      podMemoryLimitSource = "execution-plan-internal-test",
      podMemoryLimitMib = gpuCeilingMib
    }

sampleModel :: ModelDescriptor
sampleModel =
  case catalogForMode AppleSilicon of
    model : _ -> model
    [] -> error "apple-silicon catalog unexpectedly has no model"

sampleModelId :: Text
sampleModelId = modelId sampleModel

sampleEngineBinding :: Types.EngineBinding
sampleEngineBinding =
  case engineBindingForSelectedEngine AppleSilicon (selectedEngine sampleModel) of
    Just binding -> binding
    Nothing ->
      error
        "apple-silicon sample model unexpectedly names an unsupported engine"

secondSampleModel :: ModelDescriptor
secondSampleModel =
  case catalogForMode AppleSilicon of
    _ : model : _ -> model
    _ -> error "apple-silicon catalog unexpectedly has fewer than two models"

secondModelId :: Text
secondModelId = modelId secondSampleModel

secondEngineBinding :: Types.EngineBinding
secondEngineBinding =
  case engineBindingForSelectedEngine AppleSilicon (selectedEngine secondSampleModel) of
    Just binding -> binding
    Nothing ->
      error
        "second apple-silicon sample model names an unsupported engine"

sampleMemberId :: Text
sampleMemberId = "execution-plan-internal-member"

secondMemberId :: Text
secondMemberId = "execution-plan-internal-member-second"

samplePoolId :: Text
samplePoolId = "execution-plan-internal-pool"

sampleTopic :: Text
sampleTopic =
  "persistent://infernix/demo/inference.batch.apple-silicon.pool.execution-plan-internal-pool.model."
    <> sampleModelId

secondTopic :: Text
secondTopic =
  "persistent://infernix/demo/inference.batch.apple-silicon.pool.execution-plan-internal-pool-second.model."
    <> secondModelId

sampleResultTopic :: Text
sampleResultTopic =
  "persistent://infernix/demo/inference.result.apple-silicon"

sampleCoordinatorTopic :: Text
sampleCoordinatorTopic =
  "persistent://infernix/demo/inference.request.apple-silicon"

sampleRoute :: EngineRoute
sampleRoute =
  EngineRoute
    { routePoolId = samplePoolId,
      routeMemberId = sampleMemberId,
      routeTopic = sampleTopic,
      routeSubscriptionType = ConsumerShared,
      routeMaxInflightPerMember = 1
    }

secondCompiledPlacement :: CompiledPlacement
secondCompiledPlacement =
  CompiledPlacement
    { placementDescriptor = secondSampleModel,
      placementEngine = secondEngineBinding,
      placementRoutes =
        EngineRoute
          { routePoolId = "execution-plan-internal-pool-second",
            routeMemberId = secondMemberId,
            routeTopic = secondTopic,
            routeSubscriptionType = ConsumerShared,
            routeMaxInflightPerMember = 1
          }
          :| [],
      placementResources = hostResources
    }

sampleConfig :: DemoConfig
sampleConfig =
  DemoConfig
    { configRuntimeMode = AppleSilicon,
      configEdgePort = 0,
      configMapName = "execution-plan-internal",
      generatedPath = ".build/execution-plan-internal.dhall",
      mountedPath = "/opt/infernix/execution-plan-internal.dhall",
      demoUiEnabled = False,
      activeDaemonRole = Engine,
      coordinatorDaemon = coordinatorConfig,
      webappDaemon = webappConfig,
      engineDaemons = [engineDaemonConfig],
      enginePools =
        [ EnginePool
            { enginePoolId = samplePoolId,
              enginePoolRuntimeMode = AppleSilicon,
              enginePoolModelIds = [sampleModelId],
              enginePoolMemberIds = [sampleMemberId],
              enginePoolSubscriptionType = ConsumerShared,
              enginePoolMaxInflightPerMember = 1
            }
        ],
      engineMembers =
        [ EngineMember
            { engineMemberId = sampleMemberId,
              engineMemberRuntimeMode = AppleSilicon,
              engineMemberLocation = "control-plane-host",
              engineMemberPoolIds = [samplePoolId]
            }
        ],
      requestTopics = [sampleCoordinatorTopic],
      resultTopic = sampleResultTopic,
      modelsBucket = defaultModelsBucket,
      modelBootstrapTopic = defaultModelBootstrapTopic,
      engines = [sampleEngineBinding],
      models = [sampleModel],
      inferenceMemoryBudget = HostEnforcedBudget expectedHostPartition
    }

coordinatorConfig :: DaemonConfig
coordinatorConfig =
  DaemonConfig
    { daemonConfigRole = Coordinator,
      daemonConfigLocation = "cluster-pod",
      daemonConfigMemberId = Nothing,
      daemonConfigRequestTopics = [sampleCoordinatorTopic],
      daemonConfigResultTopic = sampleResultTopic,
      daemonConfigPulsarConnectionMode = ConfiguredTransport,
      daemonConfigConsumerSubscriptionType = Just ConsumerShared
    }

webappConfig :: DaemonConfig
webappConfig =
  coordinatorConfig
    { daemonConfigRole = Webapp
    }

engineDaemonConfig :: DaemonConfig
engineDaemonConfig =
  coordinatorConfig
    { daemonConfigRole = Engine,
      daemonConfigLocation = "control-plane-host",
      daemonConfigMemberId = Just sampleMemberId,
      daemonConfigRequestTopics = [sampleTopic]
    }

secondEngineDaemonConfig :: DaemonConfig
secondEngineDaemonConfig =
  engineDaemonConfig
    { daemonConfigMemberId = Just secondMemberId,
      daemonConfigRequestTopics = [secondTopic]
    }
