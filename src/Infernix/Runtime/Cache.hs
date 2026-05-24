{-# LANGUAGE OverloadedStrings #-}

module Infernix.Runtime.Cache
  ( evictCache,
    listCacheManifests,
    materializeCache,
    rebuildCache,
  )
where

import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Config (Paths (..))
import Infernix.Storage
  ( readCacheManifestProtoMaybe,
    writeCacheManifestProto,
    writeTextFile,
  )
import Infernix.Types
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    listDirectory,
    removePathForcibly,
  )
import System.FilePath ((</>))
import System.IO.Error (catchIOError, isDoesNotExistError)

-- Phase 7 Sprint 7.7: the cache CLI commands operate on the local
-- model-cache root only. Manifests sit beside the cached model files at
-- @modelCacheRoot/<runtimeMode>/<modelId>/manifest.pb@; the @./.data/object-store/@
-- tree, the @s3://infernix-runtime/@ URI scheme, and the synthetic
-- artifact-bundle / source-manifest JSON files are retired.
--
-- In the supported target topology, model weights live in MinIO
-- @infernix-models@; engine pods pull on demand into the @/model-cache@
-- @emptyDir@ mount, and @adapters/model_cache.get_model_path@ owns the
-- lazy population + LRU eviction loop. The local cache CLI commands
-- remain useful as a diagnostic surface for the host-engine daemon on
-- Apple silicon (where the model-cache lives under
-- @./.data/runtime/model-cache/@) and for unit-test fixtures.

listCacheManifests :: Paths -> RuntimeMode -> IO [CacheManifest]
listCacheManifests paths runtimeMode = do
  let runtimeRootDir = modelCacheRoot paths </> Text.unpack (runtimeModeId runtimeMode)
  rootExists <- doesDirectoryExist runtimeRootDir
  if not rootExists
    then pure []
    else do
      modelDirectories <- listDirectory runtimeRootDir
      catMaybes <$> mapM (readManifestIfPresent . (runtimeRootDir </>)) modelDirectories
  where
    readManifestIfPresent modelDirectory = do
      let manifestPath = manifestProtoPathForModelDirectory modelDirectory
      manifestExists <- doesFileExist manifestPath
      if manifestExists
        then readCacheManifestProtoMaybe manifestPath
        else pure Nothing

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

materializeCache :: Paths -> RuntimeMode -> ModelDescriptor -> IO ()
materializeCache paths runtimeMode model = do
  let cacheRoot = cacheRootFor paths runtimeMode (modelId model)
      modelDirectory = modelDirectoryFor paths runtimeMode (modelId model)
      manifestPath = manifestProtoPathForModelDirectory modelDirectory
      durableArtifactUri =
        "minio://infernix-models/" <> modelId model <> "/"
      markerContents =
        "materialized from "
          <> durableArtifactUri
          <> " via "
          <> selectedEngine model
      manifest =
        CacheManifest
          { cacheRuntimeMode = runtimeMode,
            cacheModelId = modelId model,
            cacheSelectedEngine = selectedEngine model,
            cacheDurableSourceUri = durableArtifactUri,
            cacheCacheKey = "default"
          }
  createDirectoryIfMissing True cacheRoot
  writeTextFile (cacheRoot </> "materialized.txt") markerContents
  writeCacheManifestProto manifestPath cacheRoot manifest

-- The cache root @<modelCacheRoot>/<runtimeMode>/<modelId>/default/@ holds
-- the actual cached weight files an engine adapter loads; the parent
-- @<modelCacheRoot>/<runtimeMode>/<modelId>/manifest.pb@ records the
-- bookkeeping the @infernix cache@ commands surface.
cacheRootFor :: Paths -> RuntimeMode -> Text -> FilePath
cacheRootFor paths runtimeMode modelName =
  modelDirectoryFor paths runtimeMode modelName </> "default"

modelDirectoryFor :: Paths -> RuntimeMode -> Text -> FilePath
modelDirectoryFor paths runtimeMode modelName =
  modelCacheRoot paths
    </> Text.unpack (runtimeModeId runtimeMode)
    </> Text.unpack modelName

manifestProtoPathForModelDirectory :: FilePath -> FilePath
manifestProtoPathForModelDirectory modelDirectory = modelDirectory </> "manifest.pb"
