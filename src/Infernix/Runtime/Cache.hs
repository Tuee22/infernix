{-# LANGUAGE OverloadedStrings #-}

module Infernix.Runtime.Cache
  ( evictCache,
    listCacheManifests,
    materializeCache,
    rebuildCache,
  )
where

import Control.Monad (when)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Config (Paths (..))
import Infernix.Models (engineBindingForSelectedEngine)
import Infernix.Storage
  ( readCacheManifestProtoMaybe,
    readStateFileMaybe,
    writeCacheManifestProto,
    writeTextFile,
  )
import Infernix.Types
import System.Directory
  ( copyFile,
    createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    listDirectory,
    removePathForcibly,
  )
import System.FilePath ((</>))
import System.IO.Error (catchIOError, isDoesNotExistError)

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
      copyDurableArtifactToCache paths cacheRoot (cacheDurableSourceUri manifest)
      writeTextFile (cacheRoot </> "materialized.txt") markerContents

materializeCache :: Paths -> RuntimeMode -> ModelDescriptor -> IO ()
materializeCache paths runtimeMode model = do
  let runtimeModeName = Text.unpack (runtimeModeId runtimeMode)
      modelName = Text.unpack (modelId model)
      cacheRoot = cacheRootFor paths runtimeMode (modelId model)
      sourceManifestPath = sourceManifestPathFor paths runtimeMode (modelId model)
      durableArtifactPath = durableArtifactPathFor paths runtimeMode (modelId model)
      durableArtifactUri = "s3://infernix-runtime/artifacts/" <> Text.pack runtimeModeName <> "/" <> modelId model <> "/bundle.json"
      markerContents =
        "materialized from "
          <> durableArtifactUri
          <> " via "
          <> selectedEngine model
      sourceManifestContents =
        Text.pack . unlines $
          [ "{",
            "  \"runtimeMode\": " <> jsonString (runtimeModeId runtimeMode) <> ",",
            "  \"modelId\": " <> jsonString (modelId model) <> ",",
            "  \"selectionMode\": \"engine-specific-direct-artifact\",",
            "  \"fetchStatus\": \"materialized\",",
            "  \"acquisitionMode\": \"local-file-copy\",",
            "  \"selectedArtifacts\": [",
            "    {",
            "      \"artifactId\": " <> jsonString (modelId model) <> ",",
            "      \"artifactKind\": \"bundle\",",
            "      \"uri\": " <> jsonString durableArtifactUri <> ",",
            "      \"required\": true",
            "    }",
            "  ]",
            "}"
          ]
      durableArtifactContents =
        let engineBinding = engineBindingForSelectedEngine (selectedEngine model)
         in Text.pack . unlines $
              [ "{",
                "  \"artifactKind\": \"infernix-runtime-bundle\",",
                "  \"schemaVersion\": 1,",
                "  \"runtimeMode\": " <> jsonString (runtimeModeId runtimeMode) <> ",",
                "  \"matrixRowId\": " <> jsonString (matrixRowId model) <> ",",
                "  \"modelId\": " <> jsonString (modelId model) <> ",",
                "  \"displayName\": " <> jsonString (displayName model) <> ",",
                "  \"family\": " <> jsonString (family model) <> ",",
                "  \"artifactType\": " <> jsonString (artifactType model) <> ",",
                "  \"referenceModel\": " <> jsonString (referenceModel model) <> ",",
                "  \"selectedEngine\": " <> jsonString (selectedEngine model) <> ",",
                "  \"runtimeLane\": " <> jsonString (runtimeLane model) <> ",",
                "  \"sourceDownloadUrl\": " <> jsonString (downloadUrl model) <> ",",
                "  \"engineAdapterId\": " <> jsonString (engineBindingAdapterId engineBinding) <> ",",
                "  \"engineAdapterType\": " <> jsonString (engineBindingAdapterType engineBinding) <> ",",
                "  \"engineAdapterLocator\": " <> jsonString (engineBindingAdapterLocator engineBinding) <> ",",
                "  \"artifactAcquisitionMode\": \"engine-ready-artifact-manifests\",",
                "  \"sourceArtifactManifestPath\": " <> jsonString (Text.pack ("source-artifacts/" <> runtimeModeName <> "/" <> modelName <> "/source.json")) <> ",",
                "  \"sourceArtifactSelectionMode\": \"engine-specific-direct-artifact\",",
                "  \"sourceArtifactAuthoritativeUri\": " <> jsonString durableArtifactUri <> ",",
                "  \"sourceArtifactAuthoritativeKind\": \"bundle\"",
                "}"
              ]
      manifest =
        CacheManifest
          { cacheRuntimeMode = runtimeMode,
            cacheModelId = modelId model,
            cacheSelectedEngine = selectedEngine model,
            cacheDurableSourceUri = durableArtifactUri,
            cacheCacheKey = "default"
          }
  createDirectoryIfMissing True cacheRoot
  writeTextFile sourceManifestPath sourceManifestContents
  writeTextFile durableArtifactPath durableArtifactContents
  writeTextFile (cacheRoot </> "materialized.txt") markerContents
  copyFile durableArtifactPath (cacheRoot </> "artifact-bundle.json")
  writeCacheManifestProto (cacheManifestProtoPath paths runtimeMode (modelId model)) cacheRoot manifest

copyDurableArtifactToCache :: Paths -> FilePath -> Text -> IO ()
copyDurableArtifactToCache paths cacheRoot durableSourceUriValue = do
  let durableArtifactPath = localPathFromUri paths durableSourceUriValue
      cacheBundleFilePath = cacheRoot </> "artifact-bundle.json"
  artifactExists <- doesFileExist durableArtifactPath
  when artifactExists (copyFile durableArtifactPath cacheBundleFilePath)

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

localPathFromUri :: Paths -> Text -> FilePath
localPathFromUri paths rawUri =
  case Text.stripPrefix "file://" rawUri of
    Just localPath -> Text.unpack localPath
    Nothing ->
      case Text.stripPrefix "s3://infernix-runtime/" rawUri of
        Just objectPath -> objectStoreRoot paths </> Text.unpack objectPath
        Nothing -> Text.unpack rawUri

cacheManifestProtoPath :: Paths -> RuntimeMode -> Text -> FilePath
cacheManifestProtoPath paths runtimeMode modelName =
  objectStoreRoot paths
    </> "manifests"
    </> Text.unpack (runtimeModeId runtimeMode)
    </> Text.unpack modelName
    </> "default.pb"

sourceManifestPathFor :: Paths -> RuntimeMode -> Text -> FilePath
sourceManifestPathFor paths runtimeMode modelName =
  objectStoreRoot paths
    </> "source-artifacts"
    </> Text.unpack (runtimeModeId runtimeMode)
    </> Text.unpack modelName
    </> "source.json"

durableArtifactPathFor :: Paths -> RuntimeMode -> Text -> FilePath
durableArtifactPathFor paths runtimeMode modelName =
  objectStoreRoot paths
    </> "artifacts"
    </> Text.unpack (runtimeModeId runtimeMode)
    </> Text.unpack modelName
    </> "bundle.json"

jsonString :: Text -> String
jsonString = show . Text.unpack
