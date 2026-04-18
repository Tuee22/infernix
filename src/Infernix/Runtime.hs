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
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (defaultTimeLocale, formatTime, getCurrentTime)
import Infernix.Config (Paths (..))
import Infernix.Models (findModel)
import Infernix.Storage
  ( readCacheManifestProtoMaybe,
    readInferenceResultProtoMaybe,
    readStateFileMaybe,
    writeCacheManifestProto,
    writeInferenceResultProto,
    writeTextFile,
  )
import Infernix.Types
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory, removePathForcibly)
import System.FilePath ((</>))
import System.IO.Error (catchIOError, isDoesNotExistError)

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
            outputText = runModel model request
        materializeCache paths runtimeMode model
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

listCacheManifests :: Paths -> RuntimeMode -> IO [CacheManifest]
listCacheManifests paths runtimeMode = do
  let manifestRoot = cacheManifestRoot paths runtimeMode
  rootExists <- doesDirectoryExist manifestRoot
  if not rootExists
    then pure []
    else do
      modelDirectories <- listDirectory manifestRoot
      catMaybes <$> mapM (readManifestIfPresent . (manifestRoot </>)) modelDirectories
  where
    readManifestIfPresent modelDirectory = do
      let manifestPath = modelDirectory </> "default.pb"
      manifestExists <- doesFileExist manifestPath
      if manifestExists
        then readCacheManifestProtoMaybe manifestPath
        else readStateFileMaybe (modelDirectory </> "default.state")

evictCache :: Paths -> RuntimeMode -> Maybe Text -> IO Int
evictCache paths runtimeMode maybeModelId = do
  manifests <- listCacheManifests paths runtimeMode
  let targets = filter (matchesModel maybeModelId) manifests
  mapM_ (removeCacheRootIfPresent . cacheModelId) targets
  pure (length targets)
  where
    matchesModel Nothing _ = True
    matchesModel (Just wantedModelId) manifest = cacheModelId manifest == wantedModelId
    removeCacheRootIfPresent modelName =
      catchIOError
        (removePathForcibly (cacheRootFor paths runtimeMode modelName))
        (\err -> if isDoesNotExistError err then pure () else ioError err)

rebuildCache :: Paths -> RuntimeMode -> Maybe Text -> IO [CacheManifest]
rebuildCache paths runtimeMode maybeModelId = do
  manifests <- listCacheManifests paths runtimeMode
  let targets = filter (matchesModel maybeModelId) manifests
  mapM_ rebuildFromManifest targets
  pure targets
  where
    matchesModel Nothing _ = True
    matchesModel (Just wantedModelId) manifest = cacheModelId manifest == wantedModelId
    rebuildFromManifest manifest = do
      let cacheRoot = cacheRootFor paths runtimeMode (cacheModelId manifest)
          markerContents =
            "materialized from "
              <> cacheDurableSourceUri manifest
              <> " via "
              <> cacheSelectedEngine manifest
      createDirectoryIfMissing True cacheRoot
      writeTextFile (cacheRoot </> "materialized.txt") markerContents

runModel :: ModelDescriptor -> InferenceRequest -> Text
runModel model request = case family model of
  "llm" ->
    selectedEngine model <> " generated: " <> inputText request
  "speech" ->
    "Transcript via " <> selectedEngine model <> ": " <> inputText request
  "audio" ->
    "Audio workflow via " <> selectedEngine model <> ": " <> inputText request
  "music" ->
    "Music workflow via " <> selectedEngine model <> ": " <> inputText request
  "image" ->
    "Image prompt accepted by " <> selectedEngine model <> ": " <> inputText request
  "video" ->
    "Video prompt accepted by " <> selectedEngine model <> ": " <> inputText request
  "tool" ->
    "Tool workflow via " <> selectedEngine model <> ": " <> inputText request
  _ ->
    inputText request

materializeCache :: Paths -> RuntimeMode -> ModelDescriptor -> IO ()
materializeCache paths runtimeMode model = do
  let cacheRoot = cacheRootFor paths runtimeMode (modelId model)
      manifest =
        CacheManifest
          { cacheRuntimeMode = runtimeMode,
            cacheModelId = modelId model,
            cacheSelectedEngine = selectedEngine model,
            cacheDurableSourceUri = downloadUrl model,
            cacheCacheKey = "default"
          }
  createDirectoryIfMissing True cacheRoot
  writeTextFile
    (cacheRoot </> "materialized.txt")
    ("materialized from " <> downloadUrl model <> " via " <> selectedEngine model)
  writeCacheManifestProto (cacheManifestPath paths runtimeMode (modelId model)) cacheRoot manifest

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

cacheRootFor :: Paths -> RuntimeMode -> Text -> FilePath
cacheRootFor paths runtimeMode modelName =
  modelCacheRoot paths
    </> Text.unpack (runtimeModeId runtimeMode)
    </> Text.unpack modelName
    </> "default"

cacheManifestRoot :: Paths -> RuntimeMode -> FilePath
cacheManifestRoot paths runtimeMode =
  objectStoreRoot paths
    </> "manifests"
    </> Text.unpack (runtimeModeId runtimeMode)

cacheManifestPath :: Paths -> RuntimeMode -> Text -> FilePath
cacheManifestPath paths runtimeMode modelName =
  cacheManifestRoot paths runtimeMode
    </> Text.unpack modelName
    </> "default.pb"

inferenceResultPath :: Paths -> Text -> FilePath
inferenceResultPath paths requestIdValue =
  resultsRoot paths </> Text.unpack requestIdValue <> ".pb"

legacyInferenceResultPath :: Paths -> Text -> FilePath
legacyInferenceResultPath paths requestIdValue =
  resultsRoot paths </> Text.unpack requestIdValue <> ".state"
