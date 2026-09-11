{-# LANGUAGE OverloadedStrings #-}

module Infernix.Runtime
  ( CacheEntryFacts (..),
    CacheEntryReport (..),
    CacheEntryState (..),
    CacheOperationOutcome (..),
    buildPayload,
    cacheEntryStateDetail,
    cacheEntryStateIsReady,
    cacheEntryStateLabel,
    evictCache,
    executeExecutableInferenceWithKVCache,
    inspectCacheEntry,
    listCacheEntryReports,
    listCacheManifests,
    loadInferenceResult,
    persistInferenceResult,
    rebuildCache,
  )
where

import Data.Char (isSpace)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, defaultTimeLocale, formatTime, getCurrentTime)
import Infernix.Config (Paths (..))
import Infernix.Conversation.Prefix qualified as Prefix
import Infernix.ExecutionPlan
  ( ExecutableModel,
    executableModelDescriptor,
    executableModelEngine,
    executableModelId,
  )
import Infernix.Models (resultFamilyForDescriptor)
import Infernix.Runtime.Cache
  ( CacheEntryFacts (..),
    CacheEntryReport (..),
    CacheEntryState (..),
    CacheOperationOutcome (..),
    cacheEntryStateDetail,
    cacheEntryStateIsReady,
    cacheEntryStateLabel,
    evictCache,
    inspectCacheEntry,
    listCacheEntryReports,
    listCacheManifests,
    materializeCache,
    rebuildCache,
    withModelCacheExecutionLease,
  )
import Infernix.Runtime.KVCache qualified as KVCache
import Infernix.Runtime.Worker
  ( WorkerFailure (WorkerError, WorkerTypedInferenceFailure),
    runExecutableInferenceWorker,
  )
import Infernix.Storage
  ( readInferenceResultProtoMaybe,
    writeInferenceResultProto,
  )
import Infernix.Types
import System.FilePath ((</>))

-- | Production execution boundary for daemon-routed work. Lookup and
-- refinement happen before this function; the opaque placement carries the
-- only model, engine binding, enforcer plan, and grant that may launch.
executeExecutableInferenceWithKVCache ::
  Paths ->
  Maybe KVCache.EngineKVCache ->
  Maybe KVCache.KVCacheRequestSeed ->
  Maybe Prefix.VerifiedConversationPrefix ->
  ExecutableModel ->
  InferenceRequest ->
  IO (Either ErrorResponse InferenceResult)
executeExecutableInferenceWithKVCache paths maybeEngineCache maybeCacheSeed maybeVerifiedPrefix executableModel request
  | requestModelId request /= executableModelId executableModel =
      pure (Left (requestModelMismatchError executableModel request))
  | Text.all isSpace (inputText request) =
      pure
        ( Left
            ErrorResponse
              { errorCode = "invalid_request",
                message = "The request input must not be blank."
              }
        )
  | otherwise = do
      now <- getCurrentTime
      let model = executableModelDescriptor executableModel
          modelRuntimeMode = runtimeMode model
          requestIdValue = Text.pack (formatTime defaultTimeLocale "req-%Y%m%d%H%M%S%q" now)
      -- Phase 4 Sprint 4.50: recording the manifest and observing the derived
      -- cache is bookkeeping; the engine's own hydration precondition remains
      -- the gate on whether those bytes are loadable. The shared lease held
      -- across the worker invocation is what keeps an operator eviction or
      -- rebuild from replacing the generation this execution is reading.
      _ <- materializeCache paths modelRuntimeMode model
      -- Phase 7 Sprint 7.31: the identity the engine's state is keyed on is
      -- completed here, where the admitted execution is in hand. The transport
      -- boundary knows the tenant, context, model, and verified prefix; the
      -- artifact, template, and execution shape are properties of this
      -- placement and are not guesses a decoder could make.
      let maybeCacheRequest = fmap (completeCacheRequest executableModel) maybeCacheSeed
      cacheObservation <-
        case (maybeEngineCache, maybeCacheRequest) of
          (Just engineCache, Just cacheRequest) -> Just <$> KVCache.observeKVCachePrefix engineCache cacheRequest
          _ -> pure Nothing
      workerResult <-
        withModelCacheExecutionLease paths modelRuntimeMode (modelId model) $
          runExecutableInferenceWorker
            paths
            executableModel
            request
            cacheObservation
            maybeVerifiedPrefix
      -- Validity is published only by a completed execution, and withdrawn by
      -- one that failed. The retired form wrote the requested hash at
      -- observation time, so a request that never reached an engine still left
      -- a hit behind for the next one.
      recordKVCacheOutcome maybeEngineCache maybeCacheRequest workerResult
      case workerResult of
        -- Phase 4 Sprint 4.37: the worker's own measurement is consumed, not
        -- re-derived. The retired arm matched a reserved error code and then
        -- dropped the worker's report whole, rebuilding the payload from the
        -- 'ExecutableModel' — so everything the sampler measured ended at that
        -- match, and a device breach was published against the resident host
        -- resource carrying the pod ceiling.
        Left (WorkerTypedInferenceFailure breach) -> do
          let result = failedMemoryResult now model breach
          persistInferenceResult paths result
          pure (Right result)
        Left (WorkerError workerError) -> pure (Left workerError)
        Right outputText -> do
          let result =
                InferenceResult
                  { requestId = requestIdValue,
                    resultModelId = modelId model,
                    resultMatrixRowId = matrixRowId model,
                    resultRuntimeMode = modelRuntimeMode,
                    resultSelectedEngine = selectedEngine model,
                    status = "completed",
                    payload = buildPayload (resultFamilyForDescriptor model) outputText,
                    createdAt = now,
                    resultUserId = "",
                    resultContextId = "",
                    resultCausalRef = ""
                  }
          persistInferenceResult paths result
          pure (Right result)

-- | Complete the transport-supplied seed with this placement's own identity.
completeCacheRequest :: ExecutableModel -> KVCache.KVCacheRequestSeed -> KVCache.KVCacheRequest
completeCacheRequest executableModel seed =
  KVCache.completeKVCacheRequest
    seed
    (artifactType model <> ":" <> modelId model)
    (engineBindingAdapterId (executableModelEngine executableModel))
    (renderExecutionShapeIdentity (modelExecutionShape model))
  where
    model = executableModelDescriptor executableModel

-- | The admitted shape, rendered so two different shapes cannot collide on one
-- cache entry.
renderExecutionShapeIdentity :: ModelExecutionShape -> Text
renderExecutionShapeIdentity shape =
  Text.intercalate
    "/"
    ( map
        (Text.pack . show)
        [ executionContextLength shape,
          executionBatchSize shape,
          executionGenerationBound shape,
          executionCacheElementWidth shape
        ]
    )

-- | Publish or withdraw the engine's claim on this identity from the execution
-- that just happened.
recordKVCacheOutcome ::
  Maybe KVCache.EngineKVCache ->
  Maybe KVCache.KVCacheRequest ->
  Either WorkerFailure Text ->
  IO ()
recordKVCacheOutcome (Just engineCache) (Just cacheRequest) workerResult =
  case workerResult of
    Right _ ->
      KVCache.publishKVCacheState
        engineCache
        (KVCache.kvCacheRequestIdentity cacheRequest)
        (KVCache.kvCacheRequestPrefixHash cacheRequest)
    Left _ ->
      KVCache.invalidateKVCacheState
        engineCache
        (KVCache.kvCacheRequestIdentity cacheRequest)
recordKVCacheOutcome _ _ _ = pure ()

requestModelMismatchError :: ExecutableModel -> InferenceRequest -> ErrorResponse
requestModelMismatchError executableModel request =
  ErrorResponse
    { errorCode = "request_model_mismatch",
      message =
        "The request model "
          <> requestModelId request
          <> " does not match the executable model "
          <> executableModelId executableModel
          <> "."
    }

-- | Build the @status=failed@ result carrying a typed
-- 'ModelMemoryLimitExceeded' payload for a runtime ceiling breach. Admission
-- rejection happens before refinement can produce an 'ExecutableModel'. The
-- timestamp is deterministic per request so duplicate redeliveries collapse
-- under producer dedup.
failedMemoryResult :: UTCTime -> ModelDescriptor -> InferenceError -> InferenceResult
failedMemoryResult now model errorValue =
  InferenceResult
    { requestId = Text.pack (formatTime defaultTimeLocale "req-%Y%m%d%H%M%S%q" now),
      resultModelId = modelId model,
      resultMatrixRowId = matrixRowId model,
      resultRuntimeMode = runtimeMode model,
      resultSelectedEngine = selectedEngine model,
      status = "failed",
      payload =
        ResultPayload
          { inlineOutput = Nothing,
            objectRef = Nothing,
            inferenceError = Just errorValue
          },
      createdAt = now,
      resultUserId = "",
      resultContextId = "",
      resultCausalRef = ""
    }

loadInferenceResult :: Paths -> Text -> IO (Maybe InferenceResult)
loadInferenceResult paths requestIdValue =
  readInferenceResultProtoMaybe (inferenceResultPath paths requestIdValue)

-- | Build a result payload, routing on the model's 'ResultFamily'
-- (Phase 4 Sprint 4.15). Text families (LLM, speech transcription) ride
-- inline in the Pulsar result message; every artifact family's worker
-- output is the @infernix-demo-objects@ object reference (bucket/key) the
-- engine adapter wrote, carried as an 'objectRef'. Phase 7 Sprint 7.7
-- retired the 80-character inline threshold and the
-- @./.data/object-store/results/@ overflow path that preceded this
-- contract.
buildPayload :: ResultFamily -> Text -> ResultPayload
buildPayload resultFamily workerOutput
  | resultFamilyIsArtifact resultFamily =
      ResultPayload
        { inlineOutput = Nothing,
          objectRef = Just workerOutput,
          inferenceError = Nothing
        }
  | otherwise =
      ResultPayload
        { inlineOutput = Just workerOutput,
          objectRef = Nothing,
          inferenceError = Nothing
        }

persistInferenceResult :: Paths -> InferenceResult -> IO ()
persistInferenceResult paths resultValue =
  writeInferenceResultProto (inferenceResultPath paths (requestId resultValue)) resultValue

inferenceResultPath :: Paths -> Text -> FilePath
inferenceResultPath paths requestIdValue =
  resultsRoot paths </> Text.unpack requestIdValue <> ".pb"
