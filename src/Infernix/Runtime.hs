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
    writeInferenceResultProto,
    writeTextFile,
  )
import Infernix.Types
import System.Directory (copyFile, createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory, removePathForcibly)
import System.FilePath ((</>))
import System.IO.Error (catchIOError, isDoesNotExistError)
import System.Process (readProcess)

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
        outputText <- runModelWorker paths runtimeMode model request
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
      copyDurableArtifactToCache cacheRoot (cacheDurableSourceUri manifest)
      writeTextFile (cacheRoot </> "materialized.txt") markerContents

runModelWorker :: Paths -> RuntimeMode -> ModelDescriptor -> InferenceRequest -> IO Text
runModelWorker paths runtimeMode model request = do
  let artifactBundlePath = cacheBundlePath paths runtimeMode (modelId model)
  rawOutput <-
    readProcess
      "python3"
      [ repoRoot paths </> "tools" </> "runtime_worker.py",
        "--artifact-bundle",
        artifactBundlePath,
        "--once",
        "--input-text",
        Text.unpack (inputText request)
      ]
      ""
  pure (Text.stripEnd (Text.pack rawOutput))

materializeCache :: Paths -> RuntimeMode -> ModelDescriptor -> IO ()
materializeCache paths runtimeMode model = do
  let helperScript = repoRoot paths </> "tools" </> "runtime_fixture_backend.py"
  _ <-
    readProcess
      "python3"
      [ helperScript,
        "--data-root",
        dataRoot paths,
        "--runtime-mode",
        Text.unpack (runtimeModeId runtimeMode)
      ]
      (renderModelJson runtimeMode model)
  pure ()

copyDurableArtifactToCache :: FilePath -> Text -> IO ()
copyDurableArtifactToCache cacheRoot durableSourceUriValue = do
  let durableArtifactPath = localPathFromUri durableSourceUriValue
      cacheBundleFilePath = cacheRoot </> "artifact-bundle.json"
  artifactExists <- doesFileExist durableArtifactPath
  if artifactExists
    then copyFile durableArtifactPath cacheBundleFilePath
    else pure ()

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

cacheBundlePath :: Paths -> RuntimeMode -> Text -> FilePath
cacheBundlePath paths runtimeMode modelName =
  cacheRootFor paths runtimeMode modelName
    </> "artifact-bundle.json"

renderModelJson :: RuntimeMode -> ModelDescriptor -> String
renderModelJson runtimeMode model =
  unlines
    [ "{",
      "  \"matrixRowId\": " <> jsonString (matrixRowId model) <> ",",
      "  \"modelId\": " <> jsonString (modelId model) <> ",",
      "  \"displayName\": " <> jsonString (displayName model) <> ",",
      "  \"family\": " <> jsonString (family model) <> ",",
      "  \"artifactType\": " <> jsonString (artifactType model) <> ",",
      "  \"referenceModel\": " <> jsonString (referenceModel model) <> ",",
      "  \"selectedEngine\": " <> jsonString (selectedEngine model) <> ",",
      "  \"runtimeLane\": " <> jsonString (runtimeLane model) <> ",",
      "  \"runtimeMode\": " <> jsonString (runtimeModeId runtimeMode) <> ",",
      "  \"downloadUrl\": " <> jsonString (downloadUrl model),
      "}"
    ]

localPathFromUri :: Text -> FilePath
localPathFromUri rawUri =
  case Text.stripPrefix "file://" rawUri of
    Just localPath -> Text.unpack localPath
    Nothing -> Text.unpack rawUri

jsonString :: Text -> String
jsonString = show . Text.unpack

inferenceResultPath :: Paths -> Text -> FilePath
inferenceResultPath paths requestIdValue =
  resultsRoot paths </> Text.unpack requestIdValue <> ".pb"

legacyInferenceResultPath :: Paths -> Text -> FilePath
legacyInferenceResultPath paths requestIdValue =
  resultsRoot paths </> Text.unpack requestIdValue <> ".state"
