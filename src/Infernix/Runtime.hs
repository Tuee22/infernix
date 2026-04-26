{-# LANGUAGE OverloadedStrings #-}

module Infernix.Runtime
  ( evictCache,
    executeInference,
    listCacheManifests,
    loadInferenceResult,
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
    readStateFileMaybe,
    writeInferenceResultProto,
    writeTextFile,
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
            payload <- buildPayload paths requestIdValue outputText
            let result =
                  InferenceResult
                    { requestId = requestIdValue,
                      resultModelId = modelId model,
                      resultMatrixRowId = matrixRowId model,
                      resultRuntimeMode = runtimeMode,
                      resultSelectedEngine = selectedEngine model,
                      status = "completed",
                      payload = payload,
                      createdAt = now
                    }
            writeInferenceResultProto (inferenceResultPath paths requestIdValue) result
            pure (Right result)

loadInferenceResult :: Paths -> Text -> IO (Maybe InferenceResult)
loadInferenceResult paths requestIdValue = do
  maybeProtoResult <- readInferenceResultProtoMaybe (inferenceResultPath paths requestIdValue)
  case maybeProtoResult of
    Just result -> pure (Just result)
    Nothing -> readStateFileMaybe (legacyInferenceResultPath paths requestIdValue)

buildPayload :: Paths -> Text -> Text -> IO ResultPayload
buildPayload paths requestIdValue outputText
  | Text.length outputText > 80 = do
      let relativePath = "results/" <> requestIdValue <> ".txt"
          fullPath = objectStoreRoot paths </> Text.unpack relativePath
      writeTextFile fullPath outputText
      pure
        ResultPayload
          { inlineOutput = Nothing,
            objectRef = Just relativePath
          }
  | otherwise =
      pure
        ResultPayload
          { inlineOutput = Just outputText,
            objectRef = Nothing
          }

inferenceResultPath :: Paths -> Text -> FilePath
inferenceResultPath paths requestIdValue =
  resultsRoot paths </> Text.unpack requestIdValue <> ".pb"

legacyInferenceResultPath :: Paths -> Text -> FilePath
legacyInferenceResultPath paths requestIdValue =
  resultsRoot paths </> Text.unpack requestIdValue <> ".state"
