{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Infernix.Runtime.Cache
  ( CacheEntryFacts (..),
    CacheEntryReport (..),
    CacheEntryState (..),
    CacheOperationOutcome (..),
    cacheEntryStateLabel,
    cacheEntryStateDetail,
    cacheEntryStateIsReady,
    evictCache,
    inspectCacheEntry,
    listCacheEntryReports,
    listCacheManifests,
    materializeCache,
    observeCacheEntry,
    modelCacheMutationLockPath,
    rebuildCache,
    withModelCacheExecutionLease,
  )
where

import Control.Exception (SomeException, try)
import Control.Monad (filterM, foldM)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Cluster.LifecycleLock
  ( kernelFileLockIsHeld,
    withKernelFileLock,
    withKernelSharedFileLock,
  )
import Infernix.Config (Paths (..))
import Infernix.Models (findModel)
import Infernix.Models.Artifact
  ( ArtifactHeaderError (..),
    artifactHeaderErrorText,
    readArtifactHeader,
  )
import Infernix.Runtime.Worker
  ( WorkerModelCacheConfig (..),
    ensureNativeRunnerContractCacheReady,
    loadWorkerModelCacheConfig,
    nativeModelCacheRelativeKeys,
  )
import Infernix.Storage
  ( readCacheManifestProtoMaybe,
    writeCacheManifestProto,
  )
import Infernix.Types
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    getFileSize,
    listDirectory,
    removePathForcibly,
  )
import System.FilePath (takeExtension, takeFileName, (</>))
import System.IO.Error (catchIOError, isDoesNotExistError)

-- Phase 4 Sprint 4.50: the cache commands address the cache an engine actually
-- loads from, and readiness is an observation of that cache rather than a
-- marker this module wrote.
--
-- The retired form created @<modelCacheRoot>/<runtimeMode>/<modelId>/default/@
-- and wrote a @materialized.txt@ line into it. Nothing ever read that directory:
-- Linux engine pods and the Apple host daemon both load
-- @<modelCacheRoot>/<modelId>/<file>@, populated from MinIO @infernix-models@.
-- So @cache status@ reported a directory this repository invented, @cache evict@
-- deleted it without touching a byte the engine would open, and @cache rebuild@
-- rewrote the marker and called that a rebuild. Every one of those answers was
-- about the wrong tree.
--
-- What replaces it is an observation of the engine-consumed tree: the model's
-- own required file inventory (a per-engine key list, or the snapshot index the
-- hydration wrote), each file's observed extent, and — where a checkpoint reader
-- understands the container — the artifact header's own declared extent compared
-- with the file on disk. A truncated weight file therefore reports corrupt
-- rather than ready, which a size-greater-than-zero check cannot do.
--
-- Manifests stay where the governed model-lifecycle contract puts them, at
-- @<modelCacheRoot>/<runtimeMode>/<modelId>/manifest.pb@. They are bookkeeping
-- about the durable source, not evidence that the cache is usable.

-- | What one model's derived cache is, as observed. Every arm other than
-- 'CacheVerifiedReady' names what was wrong; none of them is a weaker success.
data CacheEntryState
  = -- | Every required file is present and, where a reader understands the
    -- container, its header agrees with the bytes on disk.
    CacheVerifiedReady CacheEntryFacts
  | -- | No cache generation exists for this model on this machine.
    CacheMissing Text
  | -- | A generation exists but does not hold the complete required inventory,
    -- or has not published its readiness sentinel.
    CacheIncomplete Text
  | -- | A required file is present but its own header disagrees with it.
    CacheCorrupt Text
  | -- | This machine cannot observe the cache at all: it owns no model-cache
    -- configuration, the model is not in the active catalog, or the read failed.
    -- An unobservable owner is not an empty cache.
    CacheUnobservable Text
  | -- | An execution holds the model's cache lease, so a mutation was refused
    -- rather than racing the engine reading those bytes.
    CacheInUse Text
  deriving (Eq, Show)

-- | The measured facts a verified cache reports: how many files it holds and
-- how many bytes they occupy. Both are observations, never declarations.
data CacheEntryFacts = CacheEntryFacts
  { cacheEntryFileCount :: Int,
    cacheEntryBytes :: Integer
  }
  deriving (Eq, Show)

-- | One model's manifest paired with the observed state of its cache.
data CacheEntryReport = CacheEntryReport
  { cacheReportManifest :: CacheManifest,
    cacheReportState :: CacheEntryState
  }
  deriving (Eq, Show)

-- | The truthful result of one eviction or rebuild: which model it addressed,
-- what the cache is afterwards, and whether this operation changed anything.
-- A refused or unobservable target reports itself instead of being counted as
-- a success.
data CacheOperationOutcome = CacheOperationOutcome
  { cacheOutcomeModelId :: Text,
    cacheOutcomeState :: CacheEntryState,
    cacheOutcomeChanged :: Bool
  }
  deriving (Eq, Show)

cacheEntryStateLabel :: CacheEntryState -> Text
cacheEntryStateLabel state =
  case state of
    CacheVerifiedReady _ -> "verified-ready"
    CacheMissing _ -> "missing"
    CacheIncomplete _ -> "incomplete"
    CacheCorrupt _ -> "corrupt"
    CacheUnobservable _ -> "unobservable"
    CacheInUse _ -> "in-use"

cacheEntryStateDetail :: CacheEntryState -> Text
cacheEntryStateDetail state =
  case state of
    CacheVerifiedReady facts ->
      Text.pack (show (cacheEntryFileCount facts))
        <> " files, "
        <> Text.pack (show (cacheEntryBytes facts))
        <> " bytes"
    CacheMissing reason -> reason
    CacheIncomplete reason -> reason
    CacheCorrupt reason -> reason
    CacheUnobservable reason -> reason
    CacheInUse reason -> reason

cacheEntryStateIsReady :: CacheEntryState -> Bool
cacheEntryStateIsReady state =
  case state of
    CacheVerifiedReady _ -> True
    _ -> False

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

-- | Every recorded manifest with the observed state of the cache it names.
listCacheEntryReports :: Paths -> RuntimeMode -> IO [CacheEntryReport]
listCacheEntryReports paths runtimeMode = do
  manifests <- listCacheManifests paths runtimeMode
  mapM report manifests
  where
    report manifest = do
      state <- inspectCacheEntry paths runtimeMode (cacheModelId manifest)
      pure (CacheEntryReport manifest state)

-- | Observe one model's engine-consumed cache.
inspectCacheEntry :: Paths -> RuntimeMode -> Text -> IO CacheEntryState
inspectCacheEntry paths runtimeMode modelIdValue = do
  owner <- cacheOwnerFor modelIdValue paths runtimeMode
  case owner of
    Left reason -> pure (CacheUnobservable reason)
    Right (cacheConfig, model) -> observeCacheEntry cacheConfig model

-- | Resolve the machine's cache owner and the catalog descriptor together. An
-- absent owner and an unknown model are separate unobservable reasons; neither
-- is an empty cache.
cacheOwnerFor ::
  Text ->
  Paths ->
  RuntimeMode ->
  IO (Either Text (WorkerModelCacheConfig, ModelDescriptor))
cacheOwnerFor modelIdValue paths runtimeMode = do
  loaded <- try @SomeException (loadWorkerModelCacheConfig paths runtimeMode)
  case loaded of
    Left err ->
      pure
        ( Left
            ( "the model-cache owner could not be read on this machine: "
                <> Text.pack (show err)
            )
        )
    Right Nothing ->
      pure
        ( Left
            "this machine holds no model-cache configuration, so no cache owner could be contacted"
        )
    Right (Just cacheConfig) ->
      case findModel runtimeMode modelIdValue of
        Nothing ->
          pure
            ( Left
                ( "model "
                    <> modelIdValue
                    <> " is not in the active "
                    <> runtimeModeId runtimeMode
                    <> " catalog"
                )
            )
        Just model -> pure (Right (cacheConfig, model))

observeCacheEntry :: WorkerModelCacheConfig -> ModelDescriptor -> IO CacheEntryState
observeCacheEntry cacheConfig model = do
  observed <- try @SomeException observe
  pure (either (CacheUnobservable . Text.pack . show) id observed)
  where
    modelDirectory = modelCacheDirectory cacheConfig (modelId model)
    readyPath = modelDirectory </> Text.unpack readySentinelName
    observe = do
      directoryPresent <- doesDirectoryExist modelDirectory
      if not directoryPresent
        then
          pure
            ( CacheMissing
                ( "no cache generation exists at "
                    <> Text.pack modelDirectory
                )
            )
        else do
          requiredKeys <- nativeModelCacheRelativeKeys model cacheConfig
          missing <-
            filterM
              (fmap not . regularFileWithBytes . (modelDirectory </>) . Text.unpack)
              requiredKeys
          if not (null missing)
            then
              pure
                ( CacheIncomplete
                    ( "the cache at "
                        <> Text.pack modelDirectory
                        <> " is missing or holds empty required "
                        <> (if length missing == 1 then "file: " else "files: ")
                        <> Text.intercalate ", " missing
                    )
                )
            else do
              readyPresent <- doesFileExist readyPath
              if not readyPresent && not (null requiredKeys)
                then
                  pure
                    ( CacheIncomplete
                        ( "the cache at "
                            <> Text.pack modelDirectory
                            <> " has not published its "
                            <> readySentinelName
                            <> " sentinel"
                        )
                    )
                else do
                  corruption <- firstCorruptCheckpoint modelDirectory requiredKeys
                  case corruption of
                    Just reason -> pure (CacheCorrupt reason)
                    Nothing -> do
                      facts <- measureCacheEntry modelDirectory requiredKeys
                      pure (CacheVerifiedReady facts)

-- | Compare each checkpoint the repository has a reader for against its own
-- header. A truncated or overwritten weight file fails here; a container no
-- reader understands is not evidence of corruption and falls back to the
-- present-and-nonempty observation already made.
firstCorruptCheckpoint :: FilePath -> [Text] -> IO (Maybe Text)
firstCorruptCheckpoint modelDirectory requiredKeys =
  foldM step Nothing checkpointKeys
  where
    checkpointKeys = filter isCheckpointKey requiredKeys
    step found@(Just _) _ = pure found
    step Nothing relativeKey = do
      let checkpointPath = modelDirectory </> Text.unpack relativeKey
      header <- readArtifactHeader checkpointPath
      pure $
        case header of
          Right _ -> Nothing
          Left headerError
            | headerErrorIsCorruption headerError ->
                Just
                  ( "cached checkpoint "
                      <> Text.pack checkpointPath
                      <> " disagrees with its own header: "
                      <> artifactHeaderErrorText headerError
                  )
            | otherwise -> Nothing

-- | Which header refusals mean the bytes are wrong, and which only mean this
-- repository has no reader for that container.
headerErrorIsCorruption :: ArtifactHeaderError -> Bool
headerErrorIsCorruption headerError =
  case headerError of
    ArtifactUnreadable _ -> True
    ArtifactFamilyUnsupported _ -> False
    ArtifactHeaderBudgetExceeded _ _ -> False
    ArtifactHeaderMalformed _ -> True
    ArtifactExtentMismatch _ _ -> True
    ArtifactTensorExtentMismatch {} -> True
    ArtifactTensorTilingBroken {} -> True
    ArtifactPrefixDigestMismatch _ _ -> True

isCheckpointKey :: Text -> Bool
isCheckpointKey relativeKey =
  takeExtension (Text.unpack relativeKey) `elem` [".safetensors", ".gguf"]
    || takeFileName (Text.unpack relativeKey) == "payload"

measureCacheEntry :: FilePath -> [Text] -> IO CacheEntryFacts
measureCacheEntry modelDirectory requiredKeys = do
  sizes <- mapM (getFileSize . (modelDirectory </>) . Text.unpack) requiredKeys
  pure
    CacheEntryFacts
      { cacheEntryFileCount = length requiredKeys,
        cacheEntryBytes = sum sizes
      }

regularFileWithBytes :: FilePath -> IO Bool
regularFileWithBytes path = do
  present <- doesFileExist path
  if not present
    then pure False
    else do
      observed <- try @SomeException (getFileSize path)
      pure (either (const False) (> 0) observed)

-- | Record the model's cache manifest and report the observed state of the
-- cache that manifest names. Publication of readiness belongs to the engine
-- precondition path, which hydrates and verifies before it writes the sentinel;
-- this function never invents readiness of its own.
materializeCache :: Paths -> RuntimeMode -> ModelDescriptor -> IO CacheEntryState
materializeCache paths runtimeMode model = do
  let modelDirectory = manifestDirectoryFor paths runtimeMode (modelId model)
      manifestPath = manifestProtoPathForModelDirectory modelDirectory
      durableArtifactUri = "minio://infernix-models/" <> modelId model <> "/"
      manifest =
        CacheManifest
          { cacheRuntimeMode = runtimeMode,
            cacheModelId = modelId model,
            cacheSelectedEngine = selectedEngine model,
            cacheDurableSourceUri = durableArtifactUri,
            cacheCacheKey = "default"
          }
  createDirectoryIfMissing True modelDirectory
  writeCacheManifestProto manifestPath modelDirectory manifest
  inspectCacheEntry paths runtimeMode (modelId model)

-- | Remove selected derived cache generations. Durable MinIO objects are never
-- touched, and a generation an execution currently holds is refused rather than
-- deleted from under the engine reading it.
evictCache :: Paths -> RuntimeMode -> Maybe Text -> IO [CacheOperationOutcome]
evictCache paths runtimeMode maybeModelId =
  forSelectedCacheTargets paths runtimeMode maybeModelId $ \cacheConfig model -> do
    let modelDirectory = modelCacheDirectory cacheConfig (modelId model)
    presentBefore <- doesDirectoryExist modelDirectory
    removeIfPresent modelDirectory
    state <- inspectCacheEntry paths runtimeMode (modelId model)
    pure
      CacheOperationOutcome
        { cacheOutcomeModelId = modelId model,
          cacheOutcomeState = state,
          cacheOutcomeChanged = presentBefore
        }

-- | Discard the selected generations and hydrate them again from the durable
-- MinIO artifacts, verifying the result before readiness is published. The
-- outcome reports what the cache is afterwards, including a hydration that
-- could not complete.
rebuildCache :: Paths -> RuntimeMode -> Maybe Text -> IO [CacheOperationOutcome]
rebuildCache paths runtimeMode maybeModelId =
  forSelectedCacheTargets paths runtimeMode maybeModelId $ \cacheConfig model -> do
    let modelDirectory = modelCacheDirectory cacheConfig (modelId model)
    removeIfPresent modelDirectory
    -- Staging siblings from an interrupted attempt are the only temporary
    -- space this path holds; a fresh generation starts from none of them.
    removeStagingResidue modelDirectory
    hydrated <-
      try @SomeException
        (ensureNativeRunnerContractCacheReady model (Just cacheConfig))
    state <-
      case hydrated of
        Left err ->
          pure
            ( CacheUnobservable
                ( "hydration from the durable artifacts failed: "
                    <> Text.pack (show err)
                )
            )
        Right _ -> inspectCacheEntry paths runtimeMode (modelId model)
    pure
      CacheOperationOutcome
        { cacheOutcomeModelId = modelId model,
          cacheOutcomeState = state,
          cacheOutcomeChanged = cacheEntryStateIsReady state
        }

-- | Run one mutation per selected model while holding that model's exclusive
-- cache lease. A model whose lease an execution holds reports 'CacheInUse' and
-- is not mutated; a model with no observable owner reports that instead of
-- being silently skipped.
forSelectedCacheTargets ::
  Paths ->
  RuntimeMode ->
  Maybe Text ->
  (WorkerModelCacheConfig -> ModelDescriptor -> IO CacheOperationOutcome) ->
  IO [CacheOperationOutcome]
forSelectedCacheTargets paths runtimeMode maybeModelId mutate = do
  manifests <- listCacheManifests paths runtimeMode
  let targets = filter (matchesModel maybeModelId) manifests
  mapM runOne targets
  where
    matchesModel Nothing _ = True
    matchesModel (Just wantedModelId) manifest = cacheModelId manifest == wantedModelId
    runOne manifest = do
      owner <- cacheOwnerFor (cacheModelId manifest) paths runtimeMode
      case owner of
        Left reason ->
          pure
            CacheOperationOutcome
              { cacheOutcomeModelId = cacheModelId manifest,
                cacheOutcomeState = CacheUnobservable reason,
                cacheOutcomeChanged = False
              }
        Right (cacheConfig, model) -> do
          lockPath <- prepareMutationLockPath paths runtimeMode (modelId model)
          held <- kernelFileLockIsHeld lockPath
          if held
            then
              pure
                CacheOperationOutcome
                  { cacheOutcomeModelId = modelId model,
                    cacheOutcomeState =
                      CacheInUse
                        ( "an execution holds the cache lease for "
                            <> modelId model
                        ),
                    cacheOutcomeChanged = False
                  }
            else
              withKernelFileLock "model cache mutation" lockPath (mutate cacheConfig model)

-- | Hold the shared cache lease for the duration of one execution, so an
-- eviction or rebuild cannot replace the bytes the engine is reading.
withModelCacheExecutionLease :: Paths -> RuntimeMode -> Text -> IO a -> IO a
withModelCacheExecutionLease paths runtimeMode modelIdValue action = do
  lockPath <- prepareMutationLockPath paths runtimeMode modelIdValue
  withKernelSharedFileLock "model cache execution" lockPath action

modelCacheMutationLockPath :: Paths -> RuntimeMode -> Text -> FilePath
modelCacheMutationLockPath paths runtimeMode modelIdValue =
  runtimeRoot paths
    </> "locks"
    </> ( "model-cache-"
            <> Text.unpack (runtimeModeId runtimeMode)
            <> "-"
            <> Text.unpack modelIdValue
            <> ".held"
        )

prepareMutationLockPath :: Paths -> RuntimeMode -> Text -> IO FilePath
prepareMutationLockPath paths runtimeMode modelIdValue = do
  let lockPath = modelCacheMutationLockPath paths runtimeMode modelIdValue
  createDirectoryIfMissing True (runtimeRoot paths </> "locks")
  pure lockPath

removeIfPresent :: FilePath -> IO ()
removeIfPresent path =
  catchIOError
    (removePathForcibly path)
    (\err -> if isDoesNotExistError err then pure () else ioError err)

removeStagingResidue :: FilePath -> IO ()
removeStagingResidue modelDirectory = do
  present <- doesDirectoryExist modelDirectory
  if not present
    then pure ()
    else do
      entries <- listDirectory modelDirectory
      mapM_
        (removeIfPresent . (modelDirectory </>))
        [entry | entry <- entries, ".incoming" `Text.isSuffixOf` Text.pack entry]

-- | The tree an engine actually loads from: @<modelCacheRoot>/<modelId>/@ on
-- every substrate, populated from MinIO @infernix-models/<modelId>/@.
modelCacheDirectory :: WorkerModelCacheConfig -> Text -> FilePath
modelCacheDirectory cacheConfig modelIdValue =
  Text.unpack (workerModelCacheRoot cacheConfig) </> Text.unpack modelIdValue

readySentinelName :: Text
readySentinelName = ".ready"

-- | Manifests keep the governed model-lifecycle location. They record the
-- durable source a generation came from; they are not readiness evidence.
manifestDirectoryFor :: Paths -> RuntimeMode -> Text -> FilePath
manifestDirectoryFor paths runtimeMode modelName =
  modelCacheRoot paths
    </> Text.unpack (runtimeModeId runtimeMode)
    </> Text.unpack modelName

manifestProtoPathForModelDirectory :: FilePath -> FilePath
manifestProtoPathForModelDirectory modelDirectory = modelDirectory </> "manifest.pb"
