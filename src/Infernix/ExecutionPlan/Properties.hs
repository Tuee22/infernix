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
import Data.Maybe (isJust, isNothing)
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
    lookupRuntimeUnavailableModel,
    refineRuntimePlan,
    unavailableModelDescriptor,
    unavailableModelReason,
  )
import Infernix.ExecutionPlan.Internal
  ( CompiledDaemon (..),
    CompiledPlacement (..),
    CompiledRuntimePlan (..),
    EngineRoute (..),
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
    InferenceMemoryBudget
      ( DualEnforcedBudget,
        HostEnforcedBudget,
        SubstrateEnforcedBudget
      ),
    InferenceRequest (..),
    ModelDescriptor (modelId, modelRamFootprint, requiresGpu, runtimeMode, selectedEngine),
    PodMemoryLimit (..),
    PulsarConnectionMode (ConfiguredTransport),
    RuntimeMode (AppleSilicon, LinuxCpu, LinuxGpu),
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
    [GpuPlacementObservation sampleModelId True (Just requiredOuterEnvelopeMib) False (Just gpuVramLimitMib)]
    gpuPlan
  assertRefinementFailure
    "NVIDIA envelope unavailable"
    (NvidiaEnvelopeUnavailable sampleModelId)
    [GpuPlacementObservation sampleModelId True (Just requiredOuterEnvelopeMib) True Nothing]
    gpuPlan
  assertRefinementFailure
    "NVIDIA envelope too small"
    (NvidiaEnvelopeTooSmall sampleModelId (toInteger modelFootprintMib) (toInteger (modelFootprintMib - 1)))
    [GpuPlacementObservation sampleModelId True (Just requiredOuterEnvelopeMib) True (Just (modelFootprintMib - 1))]
    gpuPlan
  -- Phase 4 Sprint 4.34: a machine that placed models and can fund none of them
  -- refuses to start rather than reporting ready and rejecting every request.
  -- The refusal lives here, not in the compiler, because admission is a fact
  -- about the machine that will execute.
  assertRefinementFailure
    "no admissible placement"
    (NoAdmissiblePlacement [sampleModelId])
    [validHostObservation]
    noAdmissiblePlan
  assertPartialAdmission
  putStrLn "execution-plan internal refinement coverage passed"

-- | A plan with one fundable and one over-capacity model refines into both
-- accountings at once: the fundable model becomes an executable, and the
-- over-capacity one is retained with the exact typed admission failure.
--
-- The over-capacity placement still receives an observation, because the
-- enforcer probes before it knows the admission result. Tolerating that is the
-- reason the unexpected-observation check is measured against every placement
-- rather than against the admitted ones.
assertPartialAdmission :: IO ()
assertPartialAdmission =
  case refineRuntimePlan
    (RuntimeObservation [validHostObservation, secondHostObservation])
    admissionCapabilityPlan of
    Left errors ->
      fail
        ( "partial-admission plan unexpectedly failed to refine: "
            <> show (NonEmpty.toList errors)
        )
    Right runtimePlan -> do
      assert
        (isJust (lookupExecutableModel sampleModelId runtimePlan))
        "a fundable model survives admission alongside an over-capacity sibling"
      assert
        (isNothing (lookupExecutableModel secondModelId runtimePlan))
        "an over-capacity model is absent from the refined executables"
      case lookupRuntimeUnavailableModel secondModelId runtimePlan of
        Nothing ->
          fail "an over-capacity model was dropped instead of retained as unavailable"
        Just unavailable -> do
          assert
            (unavailableModelDescriptor unavailable == overCapacitySecondModel)
            "the retained unavailable entry keeps the exact placed model"
          assert
            (unavailableModelReason unavailable == overCapacityAdmissionError)
            "the retained unavailable entry carries the exact typed admission failure"

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
  assertEngineMemoryAdmissionRejection paths
  putStrLn "executable launch-boundary properties passed"

-- | Phase 4 Sprint 4.34: the typed memory rejection is published by the engine,
-- on the machine that refused the work, and it stays typed rather than
-- degrading to the untyped @model_not_executable@ route diagnostic. The
-- coordinator forwards a placed-but-unfundable model precisely so this path is
-- the one that answers.
assertEngineMemoryAdmissionRejection :: Paths -> IO ()
assertEngineMemoryAdmissionRejection paths = do
  runtimePlan <-
    case refineRuntimePlan
      (RuntimeObservation [validHostObservation, secondHostObservation])
      admissionCapabilityPlan of
      Left errors ->
        fail
          ( "could not refine the engine-admission property plan: "
              <> show (NonEmpty.toList errors)
          )
      Right refined -> pure refined
  admissionAuthority <- CappedEngine.newEngineExecutionAuthority
  capabilities <-
    either
      fail
      pure
      (Pulsar.engineTopicCapabilities secondMemberId runtimePlan admissionAuthority)
  capability <- requireCapability secondTopic capabilities
  let admissionRoot = buildRoot paths </> "engine-admission-properties"
      admissionPaths = isolatedPropertyPaths paths admissionRoot
  admissionRootPresent <- doesPathExist admissionRoot
  when admissionRootPresent (removePathForcibly admissionRoot)
  requestIdValue <-
    Pulsar.publishInferenceRequest
      admissionPaths
      admissionCapabilityPlan
      InferenceRequest
        { requestModelId = secondModelId,
          inputText = "reject on the machine that will execute",
          inputObjectRef = Nothing,
          requestUserId = Nothing,
          requestContextId = Nothing
        }
  let publicationSourcePath =
        Pulsar.topicDirectoryPath admissionPaths sampleCoordinatorTopic
          </> Text.unpack requestIdValue
            <.> "pb"
      sourceDirectory = Pulsar.topicDirectoryPath admissionPaths secondTopic
      sourcePath = sourceDirectory </> Text.unpack requestIdValue <.> "pb"
  encodedRequest <- ByteString.readFile publicationSourcePath
  createDirectoryIfMissing True sourceDirectory
  ByteString.writeFile sourcePath encodedRequest
  removeFile publicationSourcePath
  Pulsar.drainTopic admissionPaths capability
  sourceExists <- doesFileExist sourcePath
  maybeResult <-
    Pulsar.readPublishedInferenceResultMaybe
      admissionPaths
      admissionCapabilityPlan
      requestIdValue
  resultValue <-
    maybe
      (fail "engine memory-admission rejection did not publish a terminal result")
      pure
      maybeResult
  assert
    (Types.status resultValue == "failed")
    "engine memory-admission rejection publishes a failed terminal result"
  assert
    (Types.resultModelId resultValue == secondModelId)
    "engine memory-admission rejection preserves the rejected model id"
  assert
    (Types.inferenceError (Types.payload resultValue) == Just overCapacityAdmissionError)
    "engine memory-admission rejection publishes the executing machine's typed admission error"
  assert
    ( isNothing (Types.inlineOutput (Types.payload resultValue))
        && isNothing (Types.objectRef (Types.payload resultValue))
    )
    "engine memory-admission rejection does not masquerade as real output"
  assert
    (not sourceExists)
    "engine memory-admission rejection removes the source request"
  removePathForcibly admissionRoot

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
    modelFootprintMib
    Nothing
  assertSuccessfulRefinement
    "pod"
    validPodObservation
    podPlan
    modelFootprintMib
    Nothing
  assertSuccessfulRefinement
    "GPU"
    validGpuObservation
    gpuPlan
    modelFootprintMib
    (Just modelFootprintMib)

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

-- Phase 4 Sprint 4.34: a placement no longer carries its resources, so the
-- three refinement lanes are now distinguished by the plan's own runtime mode
-- and declared budget rather than by a hand-built 'CompiledResources'. Every
-- admitted ceiling below is the model's declared footprint, because that is
-- what admission grants; the declared limits only gate whether it is granted at
-- all.
hostPlan :: CompiledRuntimePlan
hostPlan =
  compiledPlanFor
    sampleConfig
    ( Map.singleton
        sampleModelId
        (compiledPlacement sampleModel)
    )

podPlan :: CompiledRuntimePlan
podPlan =
  compiledPlanFor
    podConfig
    ( Map.singleton
        sampleModelId
        (compiledPlacement sampleModel)
    )

gpuPlan :: CompiledRuntimePlan
gpuPlan =
  compiledPlanFor
    gpuConfig
    ( Map.singleton
        sampleModelId
        (compiledPlacement gpuSampleModel)
    )

-- | The capability graph with its second model made unfundable by this
-- machine's declared partition. Only the descriptor changes: the routes, the
-- daemons, and the pool membership are the compiler's, and they stay put,
-- because placement is graph validation and admission is not.
admissionCapabilityPlan :: CompiledRuntimePlan
admissionCapabilityPlan =
  capabilityPlan
    { compiledPlacements =
        Map.fromList
          [ (sampleModelId, compiledPlacement sampleModel),
            ( secondModelId,
              secondCompiledPlacement {placementDescriptor = overCapacitySecondModel}
            )
          ]
    }

-- | A plan whose only model this machine cannot fund.
noAdmissiblePlan :: CompiledRuntimePlan
noAdmissiblePlan =
  compiledPlanFor
    sampleConfig
    ( Map.singleton
        sampleModelId
        (compiledPlacement (sampleModel {modelRamFootprint = overCapacityFootprint}))
    )

capabilityPlan :: CompiledRuntimePlan
capabilityPlan =
  ( compiledPlan
      ( Map.fromList
          [ (sampleModelId, compiledPlacement sampleModel),
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
compiledPlan = compiledPlanFor sampleConfig

compiledPlanFor :: DemoConfig -> Map Text CompiledPlacement -> CompiledRuntimePlan
compiledPlanFor config placements =
  CompiledRuntimePlan
    { compiledConfig = config,
      compiledCoordinator = CompiledDaemon coordinatorConfig,
      compiledWebapp = CompiledDaemon webappConfig,
      compiledEngineDaemonMap =
        Map.singleton sampleMemberId (CompiledDaemon engineDaemonConfig),
      compiledPlacements = placements
    }

compiledPlacement :: ModelDescriptor -> CompiledPlacement
compiledPlacement descriptor =
  CompiledPlacement
    { placementDescriptor = descriptor,
      placementEngine = sampleEngineBinding,
      placementRoutes = sampleRoute :| []
    }

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
    (Just gpuVramLimitMib)

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

-- | The declared footprint every fixture model carries, and therefore the
-- ceiling every admitted grant holds — resident and VRAM alike.
modelFootprintMib :: Int
modelFootprintMib = 1024

-- | The declared limits admission gates against. Both are deliberately larger
-- than 'modelFootprintMib' so the fixtures exercise a successful admission and
-- so a grant ceiling can never be confused with the limit that admitted it.
residentPodLimitMib :: Int
residentPodLimitMib = 2048

gpuVramLimitMib :: Int
gpuVramLimitMib = 4096

requiredOuterEnvelopeMib :: Int
requiredOuterEnvelopeMib =
  residentPodLimitMib + linuxOuterEnvelopeHeadroomMib

residentPodLimit :: PodMemoryLimit
residentPodLimit =
  PodMemoryLimit
    { podMemoryLimitResource = Types.PodRam,
      podMemoryLimitSource = Types.ClusterEnginePodMemoryLimit,
      podMemoryLimitMib = residentPodLimitMib
    }

gpuPodLimit :: PodMemoryLimit
gpuPodLimit =
  PodMemoryLimit
    { podMemoryLimitResource = Types.GpuVram,
      podMemoryLimitSource = Types.ClusterEnginePodMemoryLimit,
      podMemoryLimitMib = gpuVramLimitMib
    }

fixtureFootprint :: Types.ModelMemoryFootprint
fixtureFootprint =
  case Types.mkModelMemoryFootprint modelFootprintMib of
    Left footprintError ->
      error ("fixture model footprint is invalid: " <> footprintError)
    Right footprint -> footprint

hostInferenceCapacityMib :: Int
hostInferenceCapacityMib =
  Types.hostPartitionInferenceCapacityMib expectedHostPartition

overCapacityFootprintMib :: Int
overCapacityFootprintMib = hostInferenceCapacityMib + 1

-- | One MiB past what this machine's declared partition can fund, so admission
-- rejects it by exactly one MiB and the rejection payload is unambiguous.
overCapacityFootprint :: Types.ModelMemoryFootprint
overCapacityFootprint =
  case Types.mkModelMemoryFootprint overCapacityFootprintMib of
    Left footprintError ->
      error ("over-capacity fixture footprint is invalid: " <> footprintError)
    Right footprint -> footprint

overCapacitySecondModel :: ModelDescriptor
overCapacitySecondModel =
  secondSampleModel {modelRamFootprint = overCapacityFootprint}

overCapacityAdmissionError :: Types.InferenceError
overCapacityAdmissionError =
  Types.ModelMemoryLimitExceeded
    { Types.inferenceErrorModelId = secondModelId,
      Types.inferenceErrorRequiredMib = overCapacityFootprintMib,
      Types.inferenceErrorAvailableMib = hostInferenceCapacityMib,
      Types.inferenceErrorResource = Types.UnifiedHostRam,
      Types.inferenceErrorSource =
        Types.inferenceMemoryBudgetSource (HostEnforcedBudget expectedHostPartition)
    }

sampleModel :: ModelDescriptor
sampleModel =
  case catalogForMode AppleSilicon of
    model : _ -> model {modelRamFootprint = fixtureFootprint}
    [] -> error "apple-silicon catalog unexpectedly has no model"

-- | The same model on the device lane. Sharing 'sampleModelId' is deliberate:
-- the observation fixtures are keyed by model id, and only the enforcement
-- shape differs between the lanes.
gpuSampleModel :: ModelDescriptor
gpuSampleModel = sampleModel {requiresGpu = True}

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
    _ : model : _ -> model {modelRamFootprint = fixtureFootprint}
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
          :| []
    }

sampleConfig :: DemoConfig
sampleConfig =
  DemoConfig
    { configRuntimeMode = AppleSilicon,
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

-- | The same graph on the portable Linux lane, so the pod-resident enforcement
-- shape is selected by the config rather than by a hand-built resource.
podConfig :: DemoConfig
podConfig =
  sampleConfig
    { configRuntimeMode = LinuxCpu,
      inferenceMemoryBudget = SubstrateEnforcedBudget residentPodLimit
    }

-- | The same graph on the device lane, with a model that actually uses the
-- device, so both independent grants are minted.
gpuConfig :: DemoConfig
gpuConfig =
  sampleConfig
    { configRuntimeMode = LinuxGpu,
      inferenceMemoryBudget = DualEnforcedBudget residentPodLimit gpuPodLimit,
      models = [gpuSampleModel]
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
