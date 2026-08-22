{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Infernix.ExecutionPlan.Properties
  ( runExecutableLaunchBoundaryProperties,
    runExecutionPlanRefinementProperties,
  )
where

import Control.Monad (when)
import Data.Bifunctor (first)
import Data.ByteString qualified as ByteString
import Data.Either (fromRight)
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
    compiledPlanPlacementEnforcedResources,
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
    ModelRequirementObservation (..),
    PlacementObservation (..),
    RuntimeObservation (..),
  )
import Infernix.Models
  ( catalogForMode,
    engineBindingForSelectedEngine,
  )
import Infernix.Models.Requirement
  ( keyValueCacheBytes,
    modelRequirementBytesToMib,
  )
import Infernix.Runtime (executeExecutableInferenceWithKVCache)
import Infernix.Runtime.CappedEngine qualified as CappedEngine
import Infernix.Runtime.CappedEngine.Ceiling qualified as Ceiling
import Infernix.Runtime.Pulsar qualified as Pulsar
import Infernix.Runtime.Worker
  ( WorkerFailure (WorkerTypedInferenceFailure),
    WorkerModelCacheConfig (..),
    buildWorkerRequest,
    modelCeilingBreachError,
    modelCeilingRefusalError,
    runExecutableInferenceWorker,
    workerFailureResponse,
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
    ModelDescriptor (modelId, runtimeMode, selectedEngine),
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
import System.Exit (ExitCode (ExitFailure, ExitSuccess))
import System.FilePath ((<.>), (</>))

runExecutionPlanRefinementProperties :: IO ()
runExecutionPlanRefinementProperties = do
  assertSuccessfulRefinements
  assertBreachPayloadFidelity
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
  assertRefinementFailureWith
    gpuFixtureRequirementObservations
    "NVIDIA sampler unavailable"
    (NvidiaSamplerUnavailable sampleModelId)
    [GpuPlacementObservation sampleModelId True (Just requiredOuterEnvelopeMib) False (Just gpuVramLimitMib)]
    gpuPlan
  assertRefinementFailureWith
    gpuFixtureRequirementObservations
    "NVIDIA envelope unavailable"
    (NvidiaEnvelopeUnavailable sampleModelId)
    [GpuPlacementObservation sampleModelId True (Just requiredOuterEnvelopeMib) True Nothing]
    gpuPlan
  assertRefinementFailureWith
    gpuFixtureRequirementObservations
    "NVIDIA envelope too small"
    (NvidiaEnvelopeTooSmall sampleModelId (toInteger modelFootprintMib) (toInteger (modelFootprintMib - 1)))
    [GpuPlacementObservation sampleModelId True (Just requiredOuterEnvelopeMib) True (Just (modelFootprintMib - 1))]
    gpuPlan
  -- Phase 4 Sprint 4.34: a machine that placed models and can fund none of them
  -- refuses to start rather than reporting ready and rejecting every request.
  -- The refusal lives here, not in the compiler, because admission is a fact
  -- about the machine that will execute.
  assertRefinementFailureWith
    overCapacityOnlyRequirementObservations
    "no admissible placement"
    (NoAdmissiblePlacement [sampleModelId])
    [validHostObservation]
    noAdmissiblePlan
  -- Phase 4 Sprint 4.39: a machine that can derive no requirement at all for its
  -- only placed model refuses in the same way, and the retained entry names the
  -- artifact family and the derivation's own reason rather than a quantity it
  -- could not establish.
  assertUnderivableRequirementRefusal
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
    ( RuntimeObservation
        [validHostObservation, secondHostObservation]
        partialAdmissionRequirementObservations
    )
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

-- | Phase 4 Sprint 4.39 — a row whose requirement could not be derived is
-- retained as an explicit unavailable placement naming the artifact family whose
-- reader is absent, rather than admitted on a constant or silently dropped.
assertUnderivableRequirementRefusal :: IO ()
assertUnderivableRequirementRefusal =
  case refineRuntimePlan
    (RuntimeObservation [validHostObservation] underivableRequirementObservations)
    noAdmissiblePlan of
    Right _ ->
      fail "a model with no derivable requirement was admitted"
    Left errors ->
      assert
        (NonEmpty.toList errors == [NoAdmissiblePlacement [sampleModelId]])
        ( "an underivable requirement produced unexpected refinement errors: "
            <> show (NonEmpty.toList errors)
        )

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
  assertRequestModelMismatch
    "worker execution boundary"
    (first workerFailureResponse workerResult)
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
      -- The end-to-end admission lane: this block publishes a request for
      -- 'secondModelId' and asserts the drain refuses it with
      -- 'overCapacityAdmissionError'. That refusal only exists if the second
      -- model's *derived* requirement outruns the machine, so the observation
      -- list has to be the partial-admission one. The all-fundable fixture
      -- funds both models, and a funded model is launched rather than refused.
      ( RuntimeObservation
          [validHostObservation, secondHostObservation]
          partialAdmissionRequirementObservations
      )
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
      pathsHostConfig = Nothing,
      pathsHostConfigPath = Nothing
    }

requireCapabilityRuntimePlan :: IO RuntimePlan
requireCapabilityRuntimePlan =
  case refineRuntimePlan
    (RuntimeObservation [validHostObservation, secondHostObservation] fixtureRequirementObservations)
    capabilityPlan of
    Left errors ->
      fail
        ( "could not refine the topic-capability property plan: "
            <> show (NonEmpty.toList errors)
        )
    Right refinedPlan -> pure refinedPlan

requireSampleExecutable :: IO ExecutableModel
requireSampleExecutable =
  case refineRuntimePlan (RuntimeObservation [validHostObservation] fixtureRequirementObservations) hostPlan of
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

-- | Phase 4 Sprint 4.37 — the published breach payload is built from the
-- measurement rather than from the executable model.
--
-- The GPU fixture is the case the retired reconstruction got wrong: a
-- @RuntimeGpuResources@ placement's resident arm is pod RAM by construction, so
-- rebuilding the payload from the executable answered @pod-ram@ for a device
-- breach no matter which loop measured it. Here the resource is the resource the
-- watchdog reported and @requiredMib@ is the footprint it observed, so required
-- strictly exceeds available on every breach instead of the two being equal —
-- the self-contradicting shape a limit-exceeded error can never truthfully have.
assertBreachPayloadFidelity :: IO ()
assertBreachPayloadFidelity =
  case refineRuntimePlan
    (RuntimeObservation [validGpuObservation] gpuFixtureRequirementObservations)
    gpuPlan of
    Left errors ->
      fail
        ( "breach-payload fidelity fixture failed to refine: "
            <> show (NonEmpty.toList errors)
        )
    Right runtimePlan ->
      case lookupExecutableModel sampleModelId runtimePlan of
        Nothing -> fail "breach-payload fidelity fixture omitted its executable"
        Just executable -> do
          let model = executableModelDescriptor executable
              deviceCeilingMib = modelFootprintMib
              observedMib = deviceCeilingMib + 37
              breach =
                modelCeilingBreachError
                  model
                  Types.NvidiaVram
                  deviceCeilingMib
                  observedMib
          assert
            (gpuFixtureEnforcedResources == [Types.PodRam, Types.NvidiaVram])
            ( "a device-using placement's resident arm is pod RAM, which is what "
                <> "made the retired reconstruction publish the wrong resource"
            )
          assert
            (Types.inferenceErrorResource breach == Types.NvidiaVram)
            "Sprint 4.37: a device breach publishes the device resource, not the resident one"
          assert
            (Types.inferenceErrorAvailableMib breach == deviceCeilingMib)
            "Sprint 4.37: availableMib is the ceiling installed for the resource that breached"
          assert
            (Types.inferenceErrorRequiredMib breach == observedMib)
            "Sprint 4.37: requiredMib is the footprint the sampler observed"
          assert
            (Types.inferenceErrorRequiredMib breach > Types.inferenceErrorAvailableMib breach)
            "Sprint 4.37: requiredMib strictly exceeds availableMib on every runtime breach payload"
          assert
            (Types.inferenceErrorSource breach == Types.cappedEngineResidentCeilingSource)
            "Sprint 4.37: a runtime breach names the capped-engine ceiling as its source"
          assert
            ( errorCode (workerFailureResponse (WorkerTypedInferenceFailure breach))
                == Types.modelMemoryLimitExceededErrorCode
            )
            "Sprint 4.37: the rendered breach response keeps the reserved memory-limit code"
          assert
            ( Text.isInfixOf
                (Types.resourceText Types.NvidiaVram)
                (Types.message (workerFailureResponse (WorkerTypedInferenceFailure breach)))
            )
            ( "Sprint 4.37: the operator log line names the same resource the typed "
                <> "payload carries, so the two cannot disagree"
            )
          mapM_ (assertBreachCarriesResource model) breachReportableResources
          -- Phase 4 Sprint 4.42: the ceiling the conformance path compares
          -- against is the one the launch region installs, not a second
          -- derivation taken with a guessed resource. A device-lane placement's
          -- resident arm is pod RAM, and its installed ceiling must say so.
          assert
            ( Ceiling.installedCeilingResource
                ( CappedEngine.executableEngineCeiling
                    Ceiling.NoEngineProjection
                    executable
                )
                == Types.PodRam
            )
            ( "Sprint 4.42: the acknowledgement comparison reads the launch's own "
                <> "installed ceiling, so its resource is the one the region bound"
            )
          runCeilingRefusalAssertions model executable

-- | Phase 4 Sprint 4.44 — a kernel-refused allocation is a typed breach.
--
-- The Wave Z run that produced this sprint published @status=failed@ with no
-- typed error at all: the payload read @native engine worker failed:
-- llama-cpp-cli (exit code 1)@ while the ceiling was what caused that exit.
-- Neither existing layer caught it, so an operator could not tell "the bound I
-- installed was too tight" from "the engine is broken" — and the two demand
-- opposite responses.
runCeilingRefusalAssertions :: ModelDescriptor -> ExecutableModel -> IO ()
runCeilingRefusalAssertions model executable = do
  let laneCeiling =
        CappedEngine.executableEngineCeiling Ceiling.NoEngineProjection executable
      installedMib = Ceiling.installedCeilingMib laneCeiling
      -- This fixture's descriptor is an `apple-silicon` catalog row, whose lane
      -- installs nothing by construction. The classifier is a property of the
      -- lane that /does/ install, so it is exercised against that lane's own
      -- resolved ceiling at the same admitted quantity, and the detection-only
      -- lane is asserted separately as the negative it is.
      installed =
        Ceiling.resolveEngineCeiling
          Types.LinuxCpu
          Types.PodRam
          installedMib
          Ceiling.NoEngineProjection
      marginMib = CappedEngine.accountedAllocationMarginMibForTest executable
      shape = Types.modelExecutionShape model
      expectedMarginMib =
        case Types.modelGeometry model of
          Nothing -> 0
          Just geometry ->
            modelRequirementBytesToMib
              ( keyValueCacheBytes
                  geometry
                  (Types.executionContextLength shape)
                  (Types.executionCacheElementWidth shape)
              )
      classify =
        CappedEngine.classifyCeilingRefusalForTest executable installed
      failedExit = CappedEngine.EngineExited (ExitFailure 1)
      refusalAt peakMib =
        CappedEngine.EngineRefusedAtCeiling
          Types.PodRam
          installedMib
          peakMib
          (ExitFailure 1)
      refusalPeakMib = max 0 (installedMib - 2)
      refusal =
        modelCeilingRefusalError model Types.PodRam installedMib refusalPeakMib
      breachPayload =
        modelCeilingBreachError model Types.PodRam installedMib (installedMib + 5)
  assert
    (marginMib == expectedMarginMib && marginMib > 0)
    ( "Sprint 4.44: the classification margin is the model's own derived cache "
        <> "term, which is a quantity the plan already computed rather than an "
        <> "authored constant"
    )
  assert
    (classify [(Types.PodRam, installedMib)] failedExit == refusalAt installedMib)
    ( "Sprint 4.44: a non-zero exit whose peak reached the installed ceiling is "
        <> "classified as a refusal naming the resource and the ceiling"
    )
  assert
    ( classify [(Types.PodRam, installedMib - marginMib)] failedExit
        == refusalAt (installedMib - marginMib)
    )
    ( "Sprint 4.44: a peak within the accounted allocation of the ceiling is a "
        <> "refusal for an allocation the plan itself knew about"
    )
  -- The load-bearing negative. A classifier that fired on any non-zero exit
  -- would pass every assertion above and replace a missing diagnosis with a
  -- wrong one, which is the defect pointing the other way.
  assert
    (classify [(Types.PodRam, installedMib - marginMib - 1)] failedExit == failedExit)
    ( "Sprint 4.44: an exit whose peak stayed clear of the ceiling is left an "
        <> "ordinary engine failure rather than guessed at"
    )
  assert
    ( classify [] failedExit == failedExit
        && classify [(Types.NvidiaVram, installedMib)] failedExit == failedExit
    )
    ( "Sprint 4.44: a peak on another resource, or no peak at all, is not "
        <> "evidence about the resource the ceiling bound"
    )
  assert
    ( classify [(Types.PodRam, installedMib)] (CappedEngine.EngineExited ExitSuccess)
        == CappedEngine.EngineExited ExitSuccess
    )
    "Sprint 4.44: a successful engine is never reclassified as a memory failure"
  assert
    ( CappedEngine.classifyCeilingRefusalForTest
        executable
        laneCeiling
        [(Types.PodRam, installedMib)]
        failedExit
        == failedExit
    )
    ( "Sprint 4.44: a detection-only lane installed no ceiling, so nothing there "
        <> "can have been refused by one"
    )
  assert
    ( classify
        [(Types.PodRam, installedMib)]
        (CappedEngine.EngineExceededCeiling Types.PodRam installedMib (installedMib + 5))
        == CappedEngine.EngineExceededCeiling Types.PodRam installedMib (installedMib + 5)
    )
    ( "Sprint 4.44: a sampled overrun keeps its own shape and is not rewritten "
        <> "as a refusal"
    )
  assert
    ( Types.inferenceErrorSource refusal == Types.cappedEngineRefusedAtCeilingSource
        && Types.inferenceErrorSource breachPayload
          == Types.cappedEngineResidentCeilingSource
    )
    ( "Sprint 4.44: the payload distinguishes a refusal at the boundary from an "
        <> "overrun above it by naming its own source"
    )
  assert
    ( Types.inferenceErrorAvailableMib refusal == installedMib
        && Types.inferenceErrorRequiredMib refusal == refusalPeakMib
        && Types.inferenceErrorRequiredMib refusal
          <= Types.inferenceErrorAvailableMib refusal
    )
    ( "Sprint 4.44: the refusal reports the ceiling it installed and the peak "
        <> "that was actually observed, inventing no number above the limit"
    )
  assert
    ( Text.isInfixOf
        "was refused an allocation"
        (Types.message (workerFailureResponse (WorkerTypedInferenceFailure refusal)))
        && Text.isInfixOf
          "breached its admitted"
          ( Types.message
              (workerFailureResponse (WorkerTypedInferenceFailure breachPayload))
          )
    )
    "Sprint 4.44: the two shapes render operator lines a reader can tell apart"
  assert
    ( errorCode (workerFailureResponse (WorkerTypedInferenceFailure refusal))
        == Types.modelMemoryLimitExceededErrorCode
    )
    "Sprint 4.44: a refusal is still a memory-limit outcome on the reserved code"
  -- Phase 4 Sprint 4.43: an underivable projection renders its own code and
  -- reads no quantity out of a payload that deliberately carries none.
  let underivable =
        Types.ModelRequirementUnderivable
          { Types.inferenceErrorModelId = modelId model,
            Types.inferenceErrorArtifactType = "gguf",
            Types.inferenceErrorReason = "the projection probe exited 2"
          }
  assert
    ( errorCode (workerFailureResponse (WorkerTypedInferenceFailure underivable))
        == Types.modelRequirementUnderivableErrorCode
        && Text.isInfixOf
          "the projection probe exited 2"
          ( Types.message
              (workerFailureResponse (WorkerTypedInferenceFailure underivable))
          )
    )
    ( "Sprint 4.43: an underivable requirement renders its own code and reason "
        <> "rather than a limit-exceeded payload with invented quantities"
    )
  runWatchdogCeilingAgreementAssertions executable installedMib

-- | Phase 4 Sprint 4.43 — prevention and detection watch the same quantity.
--
-- Measured on the cohort lane before this correction: an engine launched under a
-- 507 MiB installed ceiling was terminated at 54 MiB by a sampler still watching
-- the 52 MiB artifact-derived grant. A projection that widens only the kernel
-- limit leaves the backstop killing a model the ceiling permits, which is
-- Sprint 4.40's prevention-and-detection agreement reopened from the other side.
runWatchdogCeilingAgreementAssertions :: ExecutableModel -> Int -> IO ()
runWatchdogCeilingAgreementAssertions executable derivedMib = do
  let projectedMib = derivedMib + 455
      widened =
        Ceiling.resolveEngineCeiling
          Types.LinuxCpu
          Types.PodRam
          derivedMib
          (Ceiling.EngineProjectedMib projectedMib)
      unprojected =
        Ceiling.resolveEngineCeiling
          Types.LinuxCpu
          Types.PodRam
          derivedMib
          Ceiling.NoEngineProjection
      ceilingsFor installed =
        fromRight [] (CappedEngine.executableWatchdogCeilingsForTest installed executable)
  assert
    (lookup Types.PodRam (ceilingsFor widened) == Just projectedMib)
    ( "Sprint 4.43: the sampled backstop watches the quantity that was installed, "
        <> "so a projection that widens the kernel limit widens detection with it"
    )
  assert
    (lookup Types.PodRam (ceilingsFor unprojected) == Just derivedMib)
    ( "Sprint 4.43: with no projection the sampled ceiling is the artifact-derived "
        <> "grant, unchanged"
    )
  -- A device grant keeps its own ceiling: no ceiling was installed for it, so
  -- there is nothing for the installed quantity to widen.
  assert
    ( lookup Types.NvidiaVram (ceilingsFor widened)
        == lookup Types.NvidiaVram (ceilingsFor unprojected)
    )
    ( "Sprint 4.43: a host projection does not move the device backstop, which "
        <> "watches a resource no ceiling binds"
    )

-- | The three physical resources a watchdog can report a breach on. Every one
-- of them must survive the translation from the sampler's measurement to the
-- published payload; a resource that is only carried on one arm is a resource
-- the next reader will re-derive.
breachReportableResources :: [Types.Resource]
breachReportableResources =
  [Types.HostRam, Types.PodRam, Types.NvidiaVram]

assertBreachCarriesResource :: ModelDescriptor -> Types.Resource -> IO ()
assertBreachCarriesResource model resource = do
  assert
    (Types.inferenceErrorResource breach == resource)
    ( "Sprint 4.37: a breach on "
        <> Text.unpack (Types.resourceText resource)
        <> " publishes that resource"
    )
  assert
    (Types.inferenceErrorRequiredMib breach > Types.inferenceErrorAvailableMib breach)
    ( "Sprint 4.37: a breach on "
        <> Text.unpack (Types.resourceText resource)
        <> " reports an observation strictly above the ceiling it breached"
    )
  assert
    ( Text.isInfixOf
        (Types.resourceText resource)
        (Types.message (workerFailureResponse (WorkerTypedInferenceFailure breach)))
    )
    ( "Sprint 4.37: the operator log line for a breach on "
        <> Text.unpack (Types.resourceText resource)
        <> " names that resource"
    )
  where
    breach = modelCeilingBreachError model resource breachCeilingMib breachObservedMib

-- | The resources the device fixture's placement is bound to, in enforcement
-- order. Its resident arm is pod RAM, which is exactly the value the retired
-- reconstruction read for a device breach.
gpuFixtureEnforcedResources :: [Types.Resource]
gpuFixtureEnforcedResources =
  case Map.elems (compiledPlacements gpuPlan) of
    [placement] -> compiledPlanPlacementEnforcedResources gpuPlan placement
    _ -> []

breachCeilingMib :: Int
breachCeilingMib = 512

breachObservedMib :: Int
breachObservedMib = breachCeilingMib + 129

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
  -- Phase 4 Sprint 4.38: the expected ceilings are read off the requirement's
  -- own terms rather than restated as literals, so a grant whose index or
  -- quantity drifted from the requirement it was admitted against fails here
  -- instead of agreeing with a number written twice.
  assertSuccessfulRefinementWith
    gpuFixtureRequirementObservations
    "GPU"
    validGpuObservation
    gpuPlan
    (Types.modelResourceRequirementHostMib gpuFixtureRequirement)
    (Types.modelResourceRequirementDeviceMib gpuFixtureRequirement)

assertSuccessfulRefinement ::
  String ->
  PlacementObservation ->
  CompiledRuntimePlan ->
  Int ->
  Maybe Int ->
  IO ()
assertSuccessfulRefinement = assertSuccessfulRefinementWith fixtureRequirementObservations

assertSuccessfulRefinementWith ::
  [ModelRequirementObservation] ->
  String ->
  PlacementObservation ->
  CompiledRuntimePlan ->
  Int ->
  Maybe Int ->
  IO ()
assertSuccessfulRefinementWith requirements label observation plan expectedResidentMib expectedGpuMib =
  case refineRuntimePlan (RuntimeObservation [observation] requirements) plan of
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
assertRefinementFailure = assertRefinementFailureWith fixtureRequirementObservations

assertRefinementFailureWith ::
  [ModelRequirementObservation] ->
  String ->
  RefinementError ->
  [PlacementObservation] ->
  CompiledRuntimePlan ->
  IO ()
assertRefinementFailureWith requirements label expectedError observations plan =
  case refineRuntimePlan (RuntimeObservation observations requirements) plan of
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
        (compiledPlacement sampleModel)
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
    { podMemoryLimitResource = Types.NvidiaVram,
      podMemoryLimitSource = Types.ClusterEnginePodMemoryLimit,
      podMemoryLimitMib = gpuVramLimitMib
    }

fixtureRequirement :: Types.ModelResourceRequirement
fixtureRequirement = requireHostResidentRequirement "fixture model" modelFootprintMib

-- | The device-lane twin of 'fixtureRequirement'. Both terms carry the same
-- quantity, which is what the retired single scalar admitted against both
-- limits, so the fixture's admission arithmetic is unchanged by the indexing.
gpuFixtureRequirement :: Types.ModelResourceRequirement
gpuFixtureRequirement =
  case Types.mkHostAndDeviceRequirement modelFootprintMib modelFootprintMib of
    Left requirementError ->
      error ("device fixture requirement is invalid: " <> requirementError)
    Right requirement -> requirement

requireHostResidentRequirement :: String -> Int -> Types.ModelResourceRequirement
requireHostResidentRequirement label hostMib =
  case Types.mkHostResidentRequirement hostMib of
    Left requirementError ->
      error (label <> " requirement is invalid: " <> requirementError)
    Right requirement -> requirement

hostInferenceCapacityMib :: Int
hostInferenceCapacityMib =
  Types.hostPartitionInferenceCapacityMib expectedHostPartition

overCapacityFootprintMib :: Int
overCapacityFootprintMib = hostInferenceCapacityMib + 1

-- | One MiB past what this machine's declared partition can fund, so admission
-- rejects it by exactly one MiB and the rejection payload is unambiguous.
overCapacityRequirement :: Types.ModelResourceRequirement
overCapacityRequirement =
  requireHostResidentRequirement "over-capacity fixture" overCapacityFootprintMib

overCapacitySecondModel :: ModelDescriptor
overCapacitySecondModel = secondSampleModel

-- | Phase 4 Sprint 4.39: the derived requirements this machine reports for the
-- fixture catalog.
--
-- They arrive with the observation because the derivation runs on the machine
-- that holds the artifact; the fixtures supply them directly rather than staging
-- a checkpoint, which is what keeps this suite machine-independent.
fixtureRequirementObservations :: [ModelRequirementObservation]
fixtureRequirementObservations =
  [ ModelRequirementObservation sampleModelId (Right fixtureRequirement),
    ModelRequirementObservation secondModelId (Right fixtureRequirement)
  ]

-- | The lane where the machine's only placed model has a derived requirement it
-- cannot fund.
overCapacityOnlyRequirementObservations :: [ModelRequirementObservation]
overCapacityOnlyRequirementObservations =
  [ModelRequirementObservation sampleModelId (Right overCapacityRequirement)]

-- | The lane where no requirement could be derived at all.
underivableRequirementObservations :: [ModelRequirementObservation]
underivableRequirementObservations =
  [ ModelRequirementObservation
      sampleModelId
      (Left "the artifact declares a tensor table this reader does not understand")
  ]

-- | The partial-admission lane: one fundable model beside one whose derived
-- requirement exceeds this machine's capacity by exactly one MiB.
partialAdmissionRequirementObservations :: [ModelRequirementObservation]
partialAdmissionRequirementObservations =
  [ ModelRequirementObservation sampleModelId (Right fixtureRequirement),
    ModelRequirementObservation secondModelId (Right overCapacityRequirement)
  ]

-- | The device lane's derived requirements. The device fixture deliberately
-- shares 'sampleModelId' with the host fixture — only the enforcement shape
-- differs between the lanes — so its observation list is separate rather than
-- keyed apart.
gpuFixtureRequirementObservations :: [ModelRequirementObservation]
gpuFixtureRequirementObservations =
  [ModelRequirementObservation sampleModelId (Right gpuFixtureRequirement)]

overCapacityAdmissionError :: Types.InferenceError
overCapacityAdmissionError =
  Types.ModelMemoryLimitExceeded
    { Types.inferenceErrorModelId = secondModelId,
      Types.inferenceErrorRequiredMib = overCapacityFootprintMib,
      Types.inferenceErrorAvailableMib = hostInferenceCapacityMib,
      Types.inferenceErrorResource = Types.HostRam,
      Types.inferenceErrorSource =
        Types.inferenceMemoryBudgetSource (HostEnforcedBudget expectedHostPartition)
    }

sampleModel :: ModelDescriptor
sampleModel =
  case catalogForMode AppleSilicon of
    model : _ -> model
    [] -> error "apple-silicon catalog unexpectedly has no model"

-- | The same model on the device lane. Sharing 'sampleModelId' is deliberate:
-- the observation fixtures are keyed by model id, and only the enforcement
-- shape differs between the lanes.
gpuSampleModel :: ModelDescriptor
gpuSampleModel = sampleModel {Types.modelExecutionShape = deviceExecutionShape}

-- | The device-lane execution shape: same declared window, weights streaming to
-- the device, which is what makes 'Types.requiresGpu' true for this fixture.
deviceExecutionShape :: Types.ModelExecutionShape
deviceExecutionShape =
  (Types.modelExecutionShape sampleModel)
    { Types.executionLoadStrategy = Types.StreamWeightsToDevice
    }

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
