{-# LANGUAGE OverloadedStrings #-}

module Infernix.Runtime
  ( buildPayload,
    evictCache,
    executeExecutableInferenceWithKVCache,
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
import Infernix.ExecutionPlan
  ( ExecutableModel,
    executableModelDescriptor,
    executableModelId,
    executableModelResidentCeilingMib,
    executableModelResidentResource,
  )
import Infernix.Models (resultFamilyForDescriptor)
import Infernix.Runtime.Cache (evictCache, listCacheManifests, materializeCache, rebuildCache)
import Infernix.Runtime.KVCache qualified as KVCache
import Infernix.Runtime.Worker (runExecutableInferenceWorker)
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
  Maybe KVCache.KVCacheRequest ->
  ExecutableModel ->
  InferenceRequest ->
  IO (Either ErrorResponse InferenceResult)
executeExecutableInferenceWithKVCache paths maybeEngineCache maybeCacheRequest executableModel request
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
      materializeCache paths modelRuntimeMode model
      cacheObservation <-
        case (maybeEngineCache, maybeCacheRequest) of
          (Just engineCache, Just cacheRequest) -> Just <$> KVCache.observeKVCachePrefix engineCache cacheRequest
          _ -> pure Nothing
      workerResult <-
        runExecutableInferenceWorker
          paths
          executableModel
          request
          cacheObservation
      case workerResult of
        Left workerError
          | errorCode workerError == modelMemoryLimitExceededErrorCode -> do
              let result = failedMemoryResult now model (ceilingBreachError executableModel)
              persistInferenceResult paths result
              pure (Right result)
          | otherwise -> pure (Left workerError)
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

-- | The typed error for a runtime resident-memory ceiling breach: the model was
-- admitted, so its footprint fit the budget, but the engine's actual resident
-- memory exceeded that admitted footprint (its 'MemoryCeiling') and the kernel
-- terminated it. Reported against the model footprint with the enforcing source.
ceilingBreachError :: ExecutableModel -> InferenceError
ceilingBreachError executableModel =
  ModelMemoryLimitExceeded
    { inferenceErrorModelId = modelId model,
      inferenceErrorRequiredMib = ceilingMib,
      inferenceErrorAvailableMib = ceilingMib,
      inferenceErrorResource = executableModelResidentResource executableModel,
      inferenceErrorSource = cappedEngineResidentCeilingSource
    }
  where
    model = executableModelDescriptor executableModel
    ceilingMib = executableModelResidentCeilingMib executableModel

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
