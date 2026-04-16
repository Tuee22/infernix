{-# LANGUAGE OverloadedStrings #-}

module Infernix.Runtime
  ( executeInference,
    loadInferenceResult,
  )
where

import Data.Char (isSpace)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (defaultTimeLocale, formatTime, getCurrentTime)
import Infernix.Config (Paths (..))
import Infernix.Models (findModel)
import Infernix.Storage (readStateFileMaybe, writeStateFile, writeTextFile)
import Infernix.Types
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))

executeInference :: Paths -> InferenceRequest -> IO (Either ErrorResponse InferenceResult)
executeInference paths request = case findModel (requestModelId request) of
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
            outputText = runModel model request
        materializeCache paths (modelId model)
        payload <- buildPayload paths requestIdValue outputText
        let result =
              InferenceResult
                { requestId = requestIdValue,
                  resultModelId = modelId model,
                  status = "completed",
                  payload = payload,
                  createdAt = now
                }
        writeStateFile (resultsRoot paths </> Text.unpack requestIdValue <> ".state") result
        pure (Right result)

loadInferenceResult :: Paths -> Text -> IO (Maybe InferenceResult)
loadInferenceResult paths requestIdValue =
  readStateFileMaybe (resultsRoot paths </> Text.unpack requestIdValue <> ".state")

runModel :: ModelDescriptor -> InferenceRequest -> Text
runModel model request = case family model of
  "text" | modelId model == "uppercase-text" -> Text.toUpper (inputText request)
  "analysis" -> Text.pack (show (length (Text.words (inputText request))))
  _ -> inputText request

materializeCache :: Paths -> Text -> IO ()
materializeCache paths modelName = do
  let cacheRoot = modelCacheRoot paths </> Text.unpack modelName </> "default"
  createDirectoryIfMissing True cacheRoot
  writeTextFile (cacheRoot </> "materialized.txt") "materialized"

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
