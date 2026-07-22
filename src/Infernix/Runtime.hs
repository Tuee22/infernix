{-# LANGUAGE OverloadedStrings #-}

module Infernix.Runtime
  ( buildPayload,
    evictCache,
    executeInference,
    executeInferenceWithKVCache,
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
import Infernix.DemoConfig (resolveInferenceMemoryBudget)
import Infernix.Models (findModel, resultFamilyForDescriptor)
import Infernix.Runtime.Cache (evictCache, listCacheManifests, materializeCache, rebuildCache)
import Infernix.Runtime.KVCache qualified as KVCache
import Infernix.Runtime.Worker (EngineCommandOverrideMap, runInferenceWorker)
import Infernix.Storage
  ( readInferenceResultProtoMaybe,
    writeInferenceResultProto,
  )
import Infernix.Types
import System.FilePath ((</>))

executeInference :: Paths -> RuntimeMode -> EngineCommandOverrideMap -> InferenceRequest -> IO (Either ErrorResponse InferenceResult)
executeInference paths runtimeMode overrides request = do
  budget <- resolveInferenceMemoryBudget paths runtimeMode
  executeInferenceWithKVCache paths runtimeMode budget overrides Nothing Nothing request

-- | Phase 4 Sprint 4.30 — every execution path admits before it spawns.
-- 'admitModelMemory' mints the 'MemoryGrant' the capped-engine kernel requires;
-- an over-budget request never reaches the engine and is returned as a typed
-- @status=failed@ 'ModelMemoryLimitExceeded' result, and a runtime ceiling
-- breach (the capped-engine kernel killed the subprocess) is rebuilt into the
-- same typed terminal failure rather than a generic worker error.
executeInferenceWithKVCache ::
  Paths ->
  RuntimeMode ->
  InferenceMemoryBudget ->
  EngineCommandOverrideMap ->
  Maybe KVCache.EngineKVCache ->
  Maybe KVCache.KVCacheRequest ->
  InferenceRequest ->
  IO (Either ErrorResponse InferenceResult)
executeInferenceWithKVCache paths runtimeMode budget overrides maybeEngineCache maybeCacheRequest request = case findModel runtimeMode (requestModelId request) of
  Nothing ->
    pure $
      Left $
        ErrorResponse
          { errorCode = "unknown_model",
            message = "The requested model is not registered."
          }
  Just model
    | Text.all isSpace (inputText request) ->
        pure $
          Left $
            ErrorResponse
              { errorCode = "invalid_request",
                message = "The request input must not be blank."
              }
    | otherwise ->
        runAdmittedInference paths runtimeMode budget overrides maybeEngineCache maybeCacheRequest request model

-- | Phase 4 Sprint 4.30 — admit the model against the budget, then run it under
-- the minted grant. A grant is the capped-engine kernel's precondition, so a
-- rejection (over-budget) never reaches the engine and is returned as a typed
-- @status=failed@ result; a runtime ceiling breach reported by the kernel is
-- rebuilt into the same typed terminal failure.
runAdmittedInference ::
  Paths ->
  RuntimeMode ->
  InferenceMemoryBudget ->
  EngineCommandOverrideMap ->
  Maybe KVCache.EngineKVCache ->
  Maybe KVCache.KVCacheRequest ->
  InferenceRequest ->
  ModelDescriptor ->
  IO (Either ErrorResponse InferenceResult)
runAdmittedInference paths runtimeMode budget overrides maybeEngineCache maybeCacheRequest request model =
  case admitModelMemory budget model of
    Left admissionError -> do
      now <- getCurrentTime
      let result = failedMemoryResult now runtimeMode model admissionError
      persistInferenceResult paths result
      pure (Right result)
    Right grant -> do
      now <- getCurrentTime
      let requestIdValue = Text.pack (formatTime defaultTimeLocale "req-%Y%m%d%H%M%S%q" now)
      materializeCache paths runtimeMode model
      cacheObservation <-
        case (maybeEngineCache, maybeCacheRequest) of
          (Just engineCache, Just cacheRequest) -> Just <$> KVCache.observeKVCachePrefix engineCache cacheRequest
          _ -> pure Nothing
      workerResult <- runInferenceWorker paths runtimeMode overrides grant model request cacheObservation
      case workerResult of
        Left workerError
          | errorCode workerError == modelMemoryLimitExceededErrorCode -> do
              -- The engine was admitted (footprint fit the budget) but its actual
              -- resident memory breached the admitted ceiling and the capped-engine
              -- kernel terminated it. Surface the clean typed terminal failure,
              -- never a host OOM.
              let result = failedMemoryResult now runtimeMode model (ceilingBreachError budget model)
              persistInferenceResult paths result
              pure (Right result)
          | otherwise -> pure (Left workerError)
        Right outputText -> do
          let result =
                InferenceResult
                  { requestId = requestIdValue,
                    resultModelId = modelId model,
                    resultMatrixRowId = matrixRowId model,
                    resultRuntimeMode = runtimeMode,
                    resultSelectedEngine = selectedEngine model,
                    status = "completed",
                    payload = buildPayload (resultFamilyForDescriptor model) outputText,
                    createdAt = now,
                    -- Legacy / Phase 4 manual-inference path: no durable context
                    -- routing, so the bridge fields stay empty. Phase 7 Sprint 7.8
                    -- fills these in when the engine receives the request via the
                    -- durable-context dispatcher.
                    resultUserId = "",
                    resultContextId = "",
                    resultCausalRef = ""
                  }
          persistInferenceResult paths result
          pure (Right result)

-- | Build the @status=failed@ result carrying a typed 'ModelMemoryLimitExceeded'
-- payload for a memory rejection (pre-admission over-budget) or a runtime ceiling
-- breach. The timestamp is deterministic per request so duplicate redeliveries
-- collapse under producer dedup.
failedMemoryResult :: UTCTime -> RuntimeMode -> ModelDescriptor -> InferenceError -> InferenceResult
failedMemoryResult now runtimeMode model errorValue =
  InferenceResult
    { requestId = Text.pack (formatTime defaultTimeLocale "req-%Y%m%d%H%M%S%q" now),
      resultModelId = modelId model,
      resultMatrixRowId = matrixRowId model,
      resultRuntimeMode = runtimeMode,
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

-- | The typed error for a runtime resident-memory ceiling breach: the model was
-- admitted, so its footprint fit the budget, but the engine's actual resident
-- memory exceeded that admitted footprint (its 'MemoryCeiling') and the kernel
-- terminated it. Reported against the model footprint with the enforcing source.
ceilingBreachError :: InferenceMemoryBudget -> ModelDescriptor -> InferenceError
ceilingBreachError budget model =
  ModelMemoryLimitExceeded
    { inferenceErrorModelId = modelId model,
      inferenceErrorRequiredMib = footprintMib,
      inferenceErrorAvailableMib = footprintMib,
      inferenceErrorResource = inferenceMemoryBudgetResource budget,
      inferenceErrorSource = cappedEngineResidentCeilingSource
    }
  where
    footprintMib = modelMemoryFootprintMib (modelRamFootprint model)

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
