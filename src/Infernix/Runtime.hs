{-# LANGUAGE OverloadedStrings #-}

module Infernix.Runtime
  ( buildPayload,
    evictCache,
    executeInference,
    listCacheManifests,
    loadInferenceResult,
    persistInferenceResult,
    rebuildCache,
  )
where

import Data.Char (isSpace)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (defaultTimeLocale, formatTime, getCurrentTime)
import Infernix.Config (Paths (..))
import Infernix.Models (findModel)
import Infernix.Runtime.Cache (evictCache, listCacheManifests, materializeCache, rebuildCache)
import Infernix.Runtime.Worker (runInferenceWorker)
import Infernix.Storage
  ( readInferenceResultProtoMaybe,
    writeInferenceResultProto,
  )
import Infernix.Types
import System.FilePath ((</>))

executeInference :: Paths -> RuntimeMode -> InferenceRequest -> IO (Either ErrorResponse InferenceResult)
executeInference paths runtimeMode request = case findModel runtimeMode (requestModelId request) of
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
    | otherwise -> do
        now <- getCurrentTime
        let requestIdValue = Text.pack (formatTime defaultTimeLocale "req-%Y%m%d%H%M%S%q" now)
        materializeCache paths runtimeMode model
        workerResult <- runInferenceWorker paths runtimeMode model request
        case workerResult of
          Left workerError ->
            pure (Left workerError)
          Right outputText -> do
            let result =
                  InferenceResult
                    { requestId = requestIdValue,
                      resultModelId = modelId model,
                      resultMatrixRowId = matrixRowId model,
                      resultRuntimeMode = runtimeMode,
                      resultSelectedEngine = selectedEngine model,
                      status = "completed",
                      payload = buildPayload outputText,
                      createdAt = now
                    }
            persistInferenceResult paths result
            pure (Right result)

loadInferenceResult :: Paths -> Text -> IO (Maybe InferenceResult)
loadInferenceResult paths requestIdValue =
  readInferenceResultProtoMaybe (inferenceResultPath paths requestIdValue)

-- | Build a result payload. Text outputs always ride inline in the Pulsar
-- result message; binary outputs are written directly to the demo MinIO
-- bucket by the engine adapter and carry an 'objectRef' (bucket + key) in
-- the result envelope. Phase 7 Sprint 7.7 retired the 80-character inline
-- threshold and the @./.data/object-store/results/@ overflow path that
-- preceded this contract.
buildPayload :: Text -> ResultPayload
buildPayload outputText =
  ResultPayload
    { inlineOutput = Just outputText,
      objectRef = Nothing
    }

persistInferenceResult :: Paths -> InferenceResult -> IO ()
persistInferenceResult paths resultValue =
  writeInferenceResultProto (inferenceResultPath paths (requestId resultValue)) resultValue

inferenceResultPath :: Paths -> Text -> FilePath
inferenceResultPath paths requestIdValue =
  resultsRoot paths </> Text.unpack requestIdValue <> ".pb"
