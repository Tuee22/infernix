{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Infernix.Runtime.Cache
  ( CacheAction (..),
    CacheEntryFacts (..),
    CacheEntryReport (..),
    CacheEntryState (..),
    CacheOperationOutcome (..),
    cacheEntryStateLabel,
    cacheEntryStateDetail,
    cacheEntryStateIsReady,
    cacheEligibleOwnerMembers,
    cacheOutcomeMatchesAction,
    evictCache,
    executeOwnedCacheAction,
    inspectCacheEntry,
    listCacheEntryReports,
    listCacheManifests,
    materializeCache,
    observeCacheEntry,
    modelCacheMutationLockPath,
    rebuildCache,
  )
where

import Control.Exception (SomeAsyncException, SomeException, fromException, tryJust)
import Control.Monad (filterM, foldM)
import Data.Aeson (FromJSON (parseJSON), ToJSON (toJSON), object, withObject, withText, (.:), (.=))
import Data.Aeson.Types qualified as Aeson
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (catMaybes)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Cluster.LifecycleLock
  ( kernelFileLockIsHeld,
    withKernelFileLock,
  )
import Infernix.Config (Paths (..))
import Infernix.ExecutionPlan qualified as ExecutionPlan
import Infernix.Models (findModel)
import Infernix.Models.Artifact
  ( ArtifactHeaderError (..),
    artifactHeaderErrorText,
    readArtifactHeader,
  )
import Infernix.Runtime.ModelCacheIdentity qualified as Identity
import Infernix.Runtime.ModelCacheLease (modelCacheMutationLockPath, prepareCacheRootLockPath, prepareMutationLockPath)
import Infernix.Runtime.ModelCacheReplacement qualified as Replacement
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

-- | Closed engine-local operations supported by the owner control path.
data CacheAction = ObserveCache | EvictOwnedCache | RebuildOwnedCache
  deriving (Eq, Show)

instance ToJSON CacheAction where
  toJSON action =
    toJSON $ case action of
      ObserveCache -> ("observe" :: Text)
      EvictOwnedCache -> "evict"
      RebuildOwnedCache -> "rebuild"

instance FromJSON CacheAction where
  parseJSON = withText "CacheAction" $ \case
    "observe" -> pure ObserveCache
    "evict" -> pure EvictOwnedCache
    "rebuild" -> pure RebuildOwnedCache
    _ -> fail "unknown cache action"

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

-- The wire representation carries observed facts, not a readiness assertion
-- supplied by the caller. Invalid or incomplete ready facts are refused.
instance ToJSON CacheEntryState where
  toJSON state =
    case state of
      CacheVerifiedReady facts ->
        object
          [ "state" .= ("verified-ready" :: Text),
            "fileCount" .= cacheEntryFileCount facts,
            "bytes" .= cacheEntryBytes facts
          ]
      _ -> object ["state" .= cacheEntryStateLabel state, "detail" .= cacheEntryStateDetail state]

instance FromJSON CacheEntryState where
  parseJSON = withObject "CacheEntryState" $ \value -> do
    label <- value .: "state" :: Aeson.Parser Text
    case label of
      "verified-ready" -> do
        fileCount <- value .: "fileCount"
        bytes <- value .: "bytes"
        if fileCount > 0 && bytes > 0
          then pure (CacheVerifiedReady (CacheEntryFacts fileCount bytes))
          else fail "verified cache facts must be positive"
      "missing" -> CacheMissing <$> value .: "detail"
      "incomplete" -> CacheIncomplete <$> value .: "detail"
      "corrupt" -> CacheCorrupt <$> value .: "detail"
      "unobservable" -> CacheUnobservable <$> value .: "detail"
      "in-use" -> CacheInUse <$> value .: "detail"
      _ -> fail "unknown cache state"

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

instance ToJSON CacheOperationOutcome where
  toJSON outcome =
    object
      [ "modelId" .= cacheOutcomeModelId outcome,
        "state" .= cacheOutcomeState outcome,
        "changed" .= cacheOutcomeChanged outcome
      ]

instance FromJSON CacheOperationOutcome where
  parseJSON = withObject "CacheOperationOutcome" $ \value ->
    CacheOperationOutcome
      <$> value .: "modelId"
      <*> value .: "state"
      <*> value .: "changed"

-- | A remote response can count a mutation only when its observed state is
-- consistent with the requested operation. Malformed replies fail closed.
cacheOutcomeMatchesAction :: CacheAction -> CacheOperationOutcome -> Bool
cacheOutcomeMatchesAction action outcome =
  case action of
    ObserveCache -> not changed
    EvictOwnedCache -> not changed || isMissing state
    RebuildOwnedCache -> changed == cacheEntryStateIsReady state
  where
    changed = cacheOutcomeChanged outcome
    state = cacheOutcomeState outcome
    isMissing (CacheMissing _) = True
    isMissing _ = False

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

-- | Resolve every engine member eligible to own a configured model's derived
-- cache from the validated placement graph. A missing placement is not an
-- empty cache: callers must report it as unobservable and must not mutate a
-- different member's local filesystem. Multiple pool routes to one member name
-- the same owner and are deliberately deduplicated.
cacheEligibleOwnerMembers :: ExecutionPlan.CompiledRuntimePlan -> Text -> Either Text [Text]
cacheEligibleOwnerMembers compiledPlan modelName =
  case ExecutionPlan.lookupCompiledPlacement modelName compiledPlan of
    Nothing -> Left ("no eligible engine cache owner is configured for " <> modelName)
    Just placement ->
      Right
        ( Set.toAscList
            ( Set.fromList
                [ ExecutionPlan.engineRouteMemberId route
                | route <- NonEmpty.toList (ExecutionPlan.compiledPlacementRoutes placement)
                ]
            )
        )

-- | Execute only against a model assigned to this member by the compiled
-- placement graph. The cache configuration is discovered on the executing
-- machine, and mutations retain the same per-model lease as inference. The
-- broker-side member claim is held by the engine consumer that calls this
-- operation; a remote caller cannot supply filesystem paths or a descriptor.
executeOwnedCacheAction ::
  Paths ->
  ExecutionPlan.CompiledRuntimePlan ->
  Text ->
  Text ->
  CacheAction ->
  IO CacheOperationOutcome
executeOwnedCacheAction paths compiledPlan memberIdValue modelName action =
  case (cacheEligibleOwnerMembers compiledPlan modelName, ExecutionPlan.lookupCompiledPlacement modelName compiledPlan) of
    (Right owners, Just placement)
      | memberIdValue `elem` owners -> do
          let mode = ExecutionPlan.compiledPlanRuntimeMode compiledPlan
              model = ExecutionPlan.compiledPlacementDescriptor placement
          loaded <- trySynchronous (loadWorkerModelCacheConfig paths mode)
          case loaded of
            Left err -> pure (unobservable ("the engine cache configuration could not be read: " <> Text.pack (show err)))
            Right Nothing -> pure (unobservable "the engine cache configuration is unavailable")
            Right (Just cacheConfig) ->
              case action of
                ObserveCache ->
                  withCacheMutationLease paths mode cacheConfig model $ do
                    state <- observeCacheEntry cacheConfig model
                    pure (CacheOperationOutcome modelName state False)
                EvictOwnedCache -> evictOwnedModelCache paths mode cacheConfig model
                RebuildOwnedCache -> rebuildOwnedModelCache paths mode cacheConfig model
    _ -> pure (unobservable ("the model is not assigned to engine member " <> memberIdValue))
  where
    unobservable reason = CacheOperationOutcome modelName (CacheUnobservable reason) False

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
  loaded <- trySynchronous (loadWorkerModelCacheConfig paths runtimeMode)
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
  observed <- trySynchronous observe
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
                      let artifactKeys = filter (/= ".infernix-native-snapshot-files") requiredKeys
                      inventoryPresent <- doesFileExist (modelDirectory </> ".infernix-artifact-inventory.json")
                      if null artifactKeys || not inventoryPresent
                        then pure (CacheUnobservable "the cache has no artifact identity inventory to verify")
                        else do
                          verified <- Identity.verifyModelCacheIdentity modelDirectory artifactKeys
                          case verified of
                            Left reason -> pure (CacheCorrupt reason)
                            Right () -> CacheVerifiedReady <$> measureCacheEntry modelDirectory requiredKeys

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
      (> 0) <$> getFileSize path

trySynchronous :: IO a -> IO (Either SomeException a)
trySynchronous = tryJust selectSynchronous
  where
    selectSynchronous failure =
      case fromException failure :: Maybe SomeAsyncException of
        Just _ -> Nothing
        Nothing -> Just failure

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
  forSelectedCacheTargets paths runtimeMode maybeModelId (evictOwnedModelCache paths runtimeMode)

-- | The caller supplies the engine owner's actual cache configuration and
-- configured model. Selection does not depend on a webapp-local manifest.
evictOwnedModelCache :: Paths -> RuntimeMode -> WorkerModelCacheConfig -> ModelDescriptor -> IO CacheOperationOutcome
evictOwnedModelCache paths runtimeMode cacheConfig model =
  withCacheMutationLease paths runtimeMode cacheConfig model (evictOwnedModelCacheLocked cacheConfig model)

evictOwnedModelCacheLocked :: WorkerModelCacheConfig -> ModelDescriptor -> IO CacheOperationOutcome
evictOwnedModelCacheLocked cacheConfig model = do
  let cacheRoot = Text.unpack (workerModelCacheRoot cacheConfig)
      modelDirectory = modelCacheDirectory cacheConfig (modelId model)
  Replacement.recoverCacheReplacement cacheRoot (modelId model)
  presentBefore <- doesDirectoryExist modelDirectory
  removeIfPresent modelDirectory
  state <- observeCacheEntry cacheConfig model
  pure
    CacheOperationOutcome
      { cacheOutcomeModelId = modelId model,
        cacheOutcomeState = state,
        cacheOutcomeChanged = presentBefore
      }

-- | Hydrate a candidate from durable MinIO artifacts and retain the prior
-- generation until the candidate passes the cache's readiness observation.
rebuildCache :: Paths -> RuntimeMode -> Maybe Text -> IO [CacheOperationOutcome]
rebuildCache paths runtimeMode maybeModelId =
  forSelectedCacheTargets paths runtimeMode maybeModelId (rebuildOwnedModelCache paths runtimeMode)

rebuildOwnedModelCache :: Paths -> RuntimeMode -> WorkerModelCacheConfig -> ModelDescriptor -> IO CacheOperationOutcome
rebuildOwnedModelCache paths runtimeMode cacheConfig model =
  withCacheMutationLease paths runtimeMode cacheConfig model (rebuildOwnedModelCacheLocked cacheConfig model)

rebuildOwnedModelCacheLocked :: WorkerModelCacheConfig -> ModelDescriptor -> IO CacheOperationOutcome
rebuildOwnedModelCacheLocked cacheConfig model = do
  let cacheRoot = Text.unpack (workerModelCacheRoot cacheConfig)
  hydrated <-
    trySynchronous
      ( Replacement.replaceCacheGeneration
          cacheRoot
          (modelId model)
          (toInteger (workerModelCacheQuotaBytes cacheConfig))
          ( \candidateRoot -> do
              let candidateConfig = cacheConfig {workerModelCacheRoot = Text.pack candidateRoot}
              ready <- ensureNativeRunnerContractCacheReady model (Just candidateConfig)
              case ready of
                Left failure -> pure (Left (CacheUnobservable ("candidate hydration failed: " <> message failure)))
                Right () -> do
                  candidateState <- observeCacheEntry candidateConfig model
                  pure (if cacheEntryStateIsReady candidateState then Right () else Left candidateState)
          )
      )
  state <-
    case hydrated of
      Left err ->
        pure
          ( CacheUnobservable
              ( "hydration from the durable artifacts failed: "
                  <> Text.pack (show err)
              )
          )
      Right (Left refusal) -> pure refusal
      Right (Right ()) -> observeCacheEntry cacheConfig model
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
  case (maybeModelId, targets) of
    (Just wantedModelId, [])
      | Just _ <- findModel runtimeMode wantedModelId ->
          pure
            [ CacheOperationOutcome
                { cacheOutcomeModelId = wantedModelId,
                  cacheOutcomeState =
                    CacheUnobservable
                      "the selected model has no cache manifest visible to this process",
                  cacheOutcomeChanged = False
                }
            ]
    _ -> mapM runOne targets
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
        Right (cacheConfig, model) -> mutate cacheConfig model

withCacheMutationLease :: Paths -> RuntimeMode -> WorkerModelCacheConfig -> ModelDescriptor -> IO CacheOperationOutcome -> IO CacheOperationOutcome
withCacheMutationLease paths runtimeMode cacheConfig model action = do
  lockPath <- prepareMutationLockPath paths runtimeMode (modelId model)
  cacheLockPath <- prepareCacheRootLockPath (Text.unpack (workerModelCacheRoot cacheConfig)) (modelId model)
  held <- kernelFileLockIsHeld lockPath
  cacheHeld <- kernelFileLockIsHeld cacheLockPath
  if held || cacheHeld
    then
      pure
        CacheOperationOutcome
          { cacheOutcomeModelId = modelId model,
            cacheOutcomeState = CacheInUse ("an execution holds the cache lease for " <> modelId model),
            cacheOutcomeChanged = False
          }
    else
      withKernelFileLock "model cache mutation" lockPath $
        withKernelFileLock "model cache root mutation" cacheLockPath action

removeIfPresent :: FilePath -> IO ()
removeIfPresent path =
  catchIOError
    (removePathForcibly path)
    (\err -> if isDoesNotExistError err then pure () else ioError err)

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
