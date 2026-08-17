{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}

module Infernix.Runtime.Worker
  ( WorkerModelCacheConfig (..),
    buildWorkerRequest,
    loadWorkerModelCacheConfig,
    nativeArtifactMarkerPathsForTest,
    nativeModelCacheObjectKeys,
    pythonEngineBootstrapManifestRequiredForTest,
    requireHydratedNativeModelCache,
    runExecutableInferenceWorker,
    workerRequestModelCacheConfig,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, displayException, throwIO, try)
import Control.Monad (filterM, unless, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as ByteString8
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.List (dropWhileEnd)
import Data.Maybe (fromMaybe)
import Data.ProtoLens (decodeMessage, defMessage, encodeMessage)
import Data.ProtoLens.Field (field)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time (defaultTimeLocale, formatTime, getCurrentTime)
import Data.Word (Word64)
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.ClusterConfig qualified as Cluster
import Infernix.Config (Paths (..))
import Infernix.Error (InfernixError (ClusterStateDecodeFailure))
import Infernix.ExecutionPlan
  ( ExecutableModel,
    executableModelDescriptor,
    executableModelEngine,
    executableModelId,
  )
import Infernix.Models (resultFamilyForDescriptor)
import Infernix.Objects.Layout qualified as ObjLayout
import Infernix.Objects.Upload qualified as ObjectUpload
import Infernix.Python qualified as Python
import Infernix.Runtime.CappedEngine
  ( EngineOutcome
      ( EngineEnforcementUnavailable,
        EngineExceededCeiling,
        EngineExited,
        EngineOutputCaptureFailed,
        EngineOutputLimitExceeded
      ),
    EngineOutputStream (EngineStandardError, EngineStandardOutput),
    NativeArtifactCache,
    NativeArtifactLaunchOutcome
      ( NativeArtifactBusy,
        NativeArtifactInvocationRejected,
        NativeArtifactLaunched,
        NativeArtifactRejected,
        NativeArtifactUnavailable,
        NativeArtifactUnsupported,
        NativeArtifactUseValidationFailed
      ),
    PythonWorkerLaunchOutcome
      ( PythonWorkerInvocationRejected,
        PythonWorkerLaunched
      ),
    nativeArtifactCache,
    nativeArtifactInvocation,
    runExecutableNativeArtifact,
    runExecutablePythonWorker,
  )
import Infernix.Runtime.KVCache qualified as KVCache
import Infernix.SecretsConfig qualified as Secrets
import Infernix.Storage (readClusterStateFile)
import Infernix.Types
import Infernix.Web.Contracts qualified as Contracts
import Lens.Family2 (set, view)
import Network.HTTP.Client (defaultManagerSettings, newManager)
import Proto.Infernix.Runtime.Inference qualified as ProtoInference
import Proto.Infernix.Runtime.Inference_Fields qualified as ProtoInferenceFields
import System.Directory (createDirectoryIfMissing, doesFileExist, getTemporaryDirectory, renamePath)
import System.Exit (ExitCode (ExitFailure, ExitSuccess))
import System.FilePath (takeDirectory, takeExtension, (</>))
import System.IO (IOMode (ReadMode), hFileSize, withFile)
import System.Posix.Process (getProcessID)

data WorkerModelCacheConfig = WorkerModelCacheConfig
  { workerModelCacheRoot :: Text,
    workerModelCacheQuotaBytes :: Word64,
    workerMinioEndpoint :: Text,
    workerMinioModelsBucket :: Text,
    workerMinioDemoArtifactsBucket :: Text,
    workerMinioRegion :: Text,
    workerMinioAccessKey :: Text,
    workerMinioSecretKey :: Text
  }
  deriving (Eq, Show)

-- | Production engine dispatch. The selected model, engine binding, and memory
-- grant are projected from one opaque 'ExecutableModel', so a caller cannot
-- combine independently decoded or mismatched values at the launch boundary.
runExecutableInferenceWorker ::
  Paths ->
  ExecutableModel ->
  InferenceRequest ->
  Maybe KVCache.KVCacheObservation ->
  IO (Either ErrorResponse Text)
runExecutableInferenceWorker paths executableModel request cacheObservation
  | requestModelId request /= executableModelId executableModel =
      pure (Left (requestModelMismatchError executableModel request))
  | otherwise =
      -- Phase 8 Sprint 8.9: the adapter type is a closed sum, so this dispatch
      -- is total and the former "unsupported engine runner" arm is gone. It
      -- used to be reachable only by a config that named an adapter the runtime
      -- cannot execute, which the wire language no longer expresses.
      case engineBindingAdapterType engineBinding of
        PythonStdio ->
          withPythonEngineSetupReady paths modelRuntimeMode engineBinding $ \readAuthority ->
            runPythonWorker readAuthority paths executableModel request cacheObservation
        NativeProcessRunner ->
          runNativeWorker paths executableModel request cacheObservation
  where
    model = executableModelDescriptor executableModel
    engineBinding = executableModelEngine executableModel
    modelRuntimeMode = runtimeMode model

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

-- | Phase 4 Sprint 4.30 — the 'ErrorResponse' the capped-engine kernel raises on
-- a runtime ceiling breach. The runtime rebuilds this into a typed
-- 'ModelMemoryLimitExceeded' result; the resident footprint that breached the
-- ceiling is named for the operator log.
modelCeilingBreachError :: ModelDescriptor -> Int -> ErrorResponse
modelCeilingBreachError model ceilingMib =
  ErrorResponse
    { errorCode = modelMemoryLimitExceededErrorCode,
      message =
        "inference for "
          <> modelId model
          <> " breached its admitted resident-memory ceiling of "
          <> Text.pack (show ceilingMib)
          <> " MiB and was terminated by the capped-engine kernel"
    }

modelEnforcementUnavailableError :: ModelDescriptor -> Text -> ErrorResponse
modelEnforcementUnavailableError model reason =
  ErrorResponse
    { errorCode = "engine_memory_enforcer_unavailable",
      message =
        "inference for "
          <> modelId model
          <> " was terminated because its live memory enforcer became unavailable: "
          <> reason
    }

modelOutputLimitExceededError ::
  ModelDescriptor ->
  EngineOutputStream ->
  ErrorResponse
modelOutputLimitExceededError model outputStream =
  ErrorResponse
    { errorCode = "engine_output_limit_exceeded",
      message =
        "inference for "
          <> modelId model
          <> " exceeded the capped-engine "
          <> engineOutputStreamLabel outputStream
          <> " capture limit and its process group was terminated"
    }

modelOutputCaptureFailedError ::
  ModelDescriptor ->
  EngineOutputStream ->
  Text ->
  ErrorResponse
modelOutputCaptureFailedError model outputStream reason =
  ErrorResponse
    { errorCode = "engine_output_capture_failed",
      message =
        "inference for "
          <> modelId model
          <> " was terminated because bounded "
          <> engineOutputStreamLabel outputStream
          <> " capture failed: "
          <> reason
    }

engineOutputStreamLabel :: EngineOutputStream -> Text
engineOutputStreamLabel outputStream =
  case outputStream of
    EngineStandardOutput -> "standard-output"
    EngineStandardError -> "standard-error"

runPythonWorker ::
  Python.PreparedPythonEnvironmentReadAuthority s ->
  Paths ->
  ExecutableModel ->
  InferenceRequest ->
  Maybe KVCache.KVCacheObservation ->
  IO (Either ErrorResponse Text)
runPythonWorker readAuthority paths executableModel request _cacheObservation = do
  maybeModelCacheConfig <- loadWorkerModelCacheConfig paths modelRuntimeMode
  let workerRequest = encodeMessage (buildWorkerRequest paths maybeModelCacheConfig executableModel request)
  workerResult <- runWorkerInvocation readAuthority paths executableModel model workerRequest
  pure (workerResultToOutput workerResult)
  where
    model = executableModelDescriptor executableModel
    modelRuntimeMode = runtimeMode model

workerResultToOutput :: Either ErrorResponse ByteString8.ByteString -> Either ErrorResponse Text
workerResultToOutput workerResult =
  case workerResult of
    Right encodedResponse ->
      decodedWorkerOutput encodedResponse
    -- The typed `ErrorResponse` (a ceiling breach carrying
    -- `modelMemoryLimitExceededErrorCode`, or a plain `worker_failed`) passes
    -- through unchanged so the runtime can discriminate on `errorCode`.
    Left errResponse ->
      Left errResponse

decodedWorkerOutput :: ByteString8.ByteString -> Either ErrorResponse Text
decodedWorkerOutput encodedResponse =
  case decodeMessage encodedResponse of
    Left decodeError ->
      Left
        ErrorResponse
          { errorCode = "worker_decode_failed",
            message = Text.pack ("Unable to decode worker response: " <> decodeError)
          }
    Right workerResponse ->
      workerOutputFromResponse workerResponse

withPythonEngineSetupReady ::
  Paths ->
  RuntimeMode ->
  EngineBinding ->
  (forall s. Python.PreparedPythonEnvironmentReadAuthority s -> IO result) ->
  IO result
withPythonEngineSetupReady paths runtimeMode engineBinding action = do
  when (pythonEngineBootstrapManifestRequired runtimeMode) $ do
    let installRoot = engineInstallRootPath paths engineBinding
        bootstrapManifest = installRoot </> "bootstrap.json"
    bootstrapReady <- doesFileExist bootstrapManifest
    unless bootstrapReady $
      ioError
        ( userError
            ( "prepared Python engine bootstrap manifest is missing for "
                <> Text.unpack (engineBindingAdapterId engineBinding)
                <> ": "
                <> bootstrapManifest
            )
        )
  -- Phase 1 Sprint 1.23: inference consumes the shared prepared-environment
  -- contract and has no Poetry/install repair path.
  Python.withPreparedPythonEngineEnvironmentReadAuthority
    paths
    runtimeMode
    engineBinding
    action

-- | Linux framework environments are immutable image payloads proven by their
-- fixed per-engine marker. Apple publishes both this bootstrap manifest and
-- the per-engine framework marker before the service accepts work.
pythonEngineBootstrapManifestRequired :: RuntimeMode -> Bool
pythonEngineBootstrapManifestRequired AppleSilicon = True
pythonEngineBootstrapManifestRequired LinuxCpu = False
pythonEngineBootstrapManifestRequired LinuxGpu = False

pythonEngineBootstrapManifestRequiredForTest :: RuntimeMode -> Bool
pythonEngineBootstrapManifestRequiredForTest =
  pythonEngineBootstrapManifestRequired

-- | Phase 4 Sprints 4.2/4.12 — invoke the real native engine binary
-- resolved from its repo-local engine install root (under @HostConfig@'s
-- @dataRoot@) by absolute path, instead of rendering a debug-metadata
-- string. The binary's stdout is the worker output: the transcript or
-- generation text for the text engines, or the @infernix-demo-objects@
-- object reference the engine wrote for the artifact engines. Unsupported
-- adapter ids fail fast (no generic-success fallback). The real engine
-- output is exercised on cohort hardware (Wave I Stage 2); here the
-- dispatch wiring and the binary-by-absolute-path contract compile and
-- unit-check.
runNativeWorker :: Paths -> ExecutableModel -> InferenceRequest -> Maybe KVCache.KVCacheObservation -> IO (Either ErrorResponse Text)
runNativeWorker paths executableModel request _cacheObservation = do
  preparation <- prepareNativeArtifactInvocation
  case preparation of
    Left preparationError -> pure (Left preparationError)
    Right (maybeModelCacheConfig, invocation, processEnvironment) -> do
      launchOutcome <-
        runExecutableNativeArtifact
          paths
          executableModel
          invocation
          processEnvironment
      case launchOutcome of
        NativeArtifactUnsupported unsupportedAdapter ->
          pure
            ( Left
                ErrorResponse
                  { errorCode = "unsupported_engine_runner",
                    message =
                      "No supported native runner is available for "
                        <> unsupportedAdapter
                        <> "."
                  }
            )
        NativeArtifactUnavailable ->
          pure
            ( Left
                ErrorResponse
                  { errorCode = "engine_binary_missing",
                    message =
                      "no exact native engine artifact is present in any supported install root for "
                        <> engineBindingAdapterId engineBinding
                        <> "; materialize it for the active substrate (Apple: infernix internal materialize-metal-engines; Linux: bake the native runner into the substrate image under /opt/infernix/engines) before running."
                  }
            )
        NativeArtifactRejected ->
          pure
            ( Left
                ErrorResponse
                  { errorCode = "engine_artifact_invalid",
                    message =
                      "native engine artifact validation failed for "
                        <> engineBindingAdapterId engineBinding
                  }
            )
        NativeArtifactBusy ->
          pure
            ( Left
                ErrorResponse
                  { errorCode = "engine_artifact_busy",
                    message =
                      "native engine artifact materialization is active for "
                        <> engineBindingAdapterId engineBinding
                  }
            )
        NativeArtifactInvocationRejected failure ->
          pure
            ( Left
                ErrorResponse
                  { errorCode = "engine_invocation_invalid",
                    message =
                      "native engine invocation is invalid for "
                        <> engineBindingAdapterId engineBinding
                        <> ": "
                        <> Text.pack failure
                  }
            )
        NativeArtifactUseValidationFailed ->
          pure
            ( Left
                ErrorResponse
                  { errorCode = "engine_artifact_invalid",
                    message =
                      "native engine artifact failed exact use-boundary validation for "
                        <> engineBindingAdapterId engineBinding
                  }
            )
        NativeArtifactLaunched outcome exitCode stdoutOutput stderrOutput ->
          case outcome of
            EngineExceededCeiling ceilingMib ->
              pure (Left (modelCeilingBreachError model ceilingMib))
            EngineEnforcementUnavailable reason ->
              pure (Left (modelEnforcementUnavailableError model reason))
            EngineOutputLimitExceeded outputStream ->
              pure (Left (modelOutputLimitExceededError model outputStream))
            EngineOutputCaptureFailed outputStream reason ->
              pure
                ( Left
                    (modelOutputCaptureFailedError model outputStream reason)
                )
            EngineExited _ ->
              nativeRunnerResult
                model
                engineBinding
                request
                maybeModelCacheConfig
                exitCode
                stdoutOutput
                stderrOutput
  where
    model = executableModelDescriptor executableModel
    modelRuntimeMode = runtimeMode model
    engineBinding = executableModelEngine executableModel
    prepareNativeArtifactInvocation = do
      maybeModelCacheConfig <- loadWorkerModelCacheConfig paths modelRuntimeMode
      cacheReady <- ensureNativeRunnerContractCacheReady model maybeModelCacheConfig
      inputFileResult <-
        case cacheReady of
          Left cacheError -> pure (Left cacheError)
          Right () -> nativeRunnerInputFile model request maybeModelCacheConfig
      case inputFileResult of
        Left inputError -> pure (Left inputError)
        Right maybeInputFile -> do
          maybeOutputDir <- nativeRunnerOutputDir model maybeModelCacheConfig
          processEnvironment <- Subprocess.clusterSubprocessEnv paths
          pure $
            case nativeArtifactInvocation
              executableModel
              request
              (nativeArtifactCacheFromWorker <$> maybeModelCacheConfig)
              maybeOutputDir
              maybeInputFile of
              Left failure ->
                Left
                  ErrorResponse
                    { errorCode = "engine_invocation_invalid",
                      message =
                        "native engine invocation preparation failed for "
                          <> engineBindingAdapterId engineBinding
                          <> ": "
                          <> Text.pack failure
                    }
              Right invocation ->
                Right
                  ( maybeModelCacheConfig,
                    invocation,
                    processEnvironment
                  )

-- | Native runners participate in the model-bootstrap protocol: the first
-- invocation reports a cache miss, the coordinator populates MinIO, and the
-- retry hydrates local model files before strict native execution. Keep MinIO
-- credentials in this Haskell worker, not in native process argv.
--
-- Phase 4 Sprint 4.35: this ends in one of two states, and silently proceeding
-- is no longer one of them. A native runner is the /only/ reporter of its own
-- cache miss, because unlike the Python adapters it has no exit-75 protocol:
-- a missing payload reaches @llama-completion@ or @whisper-cli@ as an ordinary
-- open failure, which classifies as @worker_failed@ and is therefore not
-- retryable, so the bootstrap-and-retry path never fires for it. The retired
-- form made that reachable: when the upstream @.ready@ sentinel was absent it
-- hydrated nothing, wrote no marker, raised nothing, and returned — and the
-- engine was then invoked against a payload that does not exist. Observed on
-- the @apple-silicon@ cohort as @whisper_init_from_file_with_params_no_state:
-- failed to open '…\/speech-whisper-small\/payload'@ after the coordinator's
-- eager sweep had skipped that one model and logged that "the lazy
-- per-inference fallback still covers this model". It did not: the fallback is
-- conditioned on the very sentinel the failed staging never wrote.
--
-- Proving hydration here instead is what makes the sweep's claim true. The
-- refusal is the classified @model_cache_not_populated@ code the retry path
-- already recognizes, so an eager-staging miss now publishes a bootstrap
-- request, waits for the durable sentinel, and hydrates on retry — the exact
-- protocol this function's contract describes.
ensureNativeRunnerContractCacheReady ::
  ModelDescriptor ->
  Maybe WorkerModelCacheConfig ->
  IO (Either ErrorResponse ())
ensureNativeRunnerContractCacheReady _ Nothing = pure (Right ())
ensureNativeRunnerContractCacheReady model (Just modelCacheConfig) = do
  let readyPath = nativeRunnerContractReadyPath modelCacheConfig (modelId model)
  localReady <- doesFileExist readyPath
  unless localReady $ do
    upstreamReady <- nativeModelReadySentinelExists modelCacheConfig (modelId model)
    when upstreamReady $ do
      createDirectoryIfMissing True (takeDirectory readyPath)
      hydrateNativeModelCache model modelCacheConfig
      writeFile readyPath "native-model-cache-ready\n"
  requireHydratedNativeModelCache model modelCacheConfig

-- | Prove every local file this model's native runner will open is present and
-- non-empty, or report the classified cache miss naming exactly what is absent.
--
-- A zero-byte entry counts as absent for the same reason the hydration staging
-- refuses one: it is never a valid model file, and treating it as present is
-- how an interrupted write became a permanently poisoned cache.
requireHydratedNativeModelCache ::
  ModelDescriptor ->
  WorkerModelCacheConfig ->
  IO (Either ErrorResponse ())
requireHydratedNativeModelCache model modelCacheConfig = do
  requiredKeys <- requiredNativeModelCacheKeys model modelCacheConfig
  missing <- filterM (fmap not . nativeModelCacheEntryPresent) (map localPath requiredKeys)
  pure $
    if null missing
      then Right ()
      else
        Left
          ErrorResponse
            { errorCode = "model_cache_not_populated",
              message =
                "native engine model cache is not populated for "
                  <> modelId model
                  <> "; absent or empty local "
                  <> (if length missing == 1 then "file" else "files")
                  <> ": "
                  <> Text.intercalate ", " (map Text.pack missing)
            }
  where
    localPath relativeKey =
      Text.unpack (workerModelCacheRoot modelCacheConfig)
        </> Text.unpack (modelId model)
        </> Text.unpack relativeKey

-- | The local relative paths hydration is expected to have produced.
--
-- Snapshot-backed models enumerate their own file set, so the index is
-- required first and its contents are required with it; a present index whose
-- listed files are absent is exactly the half-hydrated state this check exists
-- to catch. A model that declares no cache objects requires none.
requiredNativeModelCacheKeys ::
  ModelDescriptor ->
  WorkerModelCacheConfig ->
  IO [Text]
requiredNativeModelCacheKeys model modelCacheConfig
  | modelId model `elem` nativeSnapshotModelIds = do
      let indexPath =
            Text.unpack (workerModelCacheRoot modelCacheConfig)
              </> Text.unpack (modelId model)
              </> Text.unpack nativeSnapshotIndexName
      indexPresent <- nativeModelCacheEntryPresent indexPath
      if not indexPresent
        then pure [nativeSnapshotIndexName]
        else do
          indexPayload <- readFile indexPath
          pure
            ( nativeSnapshotIndexName
                : [ Text.pack relativeKey
                  | relativeKey <- lines indexPayload,
                    not (null relativeKey)
                  ]
            )
  | otherwise = pure (nativeModelCacheObjectKeys model)

nativeModelCacheEntryPresent :: FilePath -> IO Bool
nativeModelCacheEntryPresent path = do
  observed <- observedFileSize path
  pure (maybe False (> 0) observed)

hydrateNativeModelCache :: ModelDescriptor -> WorkerModelCacheConfig -> IO ()
hydrateNativeModelCache model modelCacheConfig =
  if modelId model `elem` nativeSnapshotModelIds
    then hydrateNativeModelSnapshotCache model modelCacheConfig
    else mapM_ (downloadNativeModelCacheObject modelCacheConfig (modelId model)) (nativeModelCacheObjectKeys model)

nativeModelCacheObjectKeys :: ModelDescriptor -> [Text]
nativeModelCacheObjectKeys model
  | modelId model `elem` ["audio-basic-pitch-coreml", "tool-audiveris"] =
      []
  | modelId model == "speech-faster-whisper-ct2" =
      [ "config.json",
        "model.bin",
        "tokenizer.json",
        "vocabulary.txt"
      ]
  | otherwise = ["payload"]

nativeSnapshotModelIds :: [Text]
nativeSnapshotModelIds =
  [ "image-apple-stable-diffusion-coreml",
    "llm-qwen15-mlx"
  ]

nativeSnapshotIndexName :: Text
nativeSnapshotIndexName = ".infernix-native-snapshot-files"

hydrateNativeModelSnapshotCache :: ModelDescriptor -> WorkerModelCacheConfig -> IO ()
hydrateNativeModelSnapshotCache model modelCacheConfig = do
  let modelIdValue = modelId model
      indexPath =
        Text.unpack (workerModelCacheRoot modelCacheConfig)
          </> Text.unpack modelIdValue
          </> Text.unpack nativeSnapshotIndexName
  downloadNativeModelCacheObject modelCacheConfig modelIdValue nativeSnapshotIndexName
  indexPayload <- readFile indexPath
  let relativeKeys =
        [ Text.pack relativeKey
        | relativeKey <- lines indexPayload,
          not (null relativeKey)
        ]
  mapM_ (downloadNativeModelCacheObject modelCacheConfig modelIdValue) relativeKeys

downloadNativeModelCacheObject :: WorkerModelCacheConfig -> Text -> Text -> IO ()
downloadNativeModelCacheObject modelCacheConfig modelIdValue relativeKey = do
  let destination =
        Text.unpack (workerModelCacheRoot modelCacheConfig)
          </> Text.unpack modelIdValue
          </> Text.unpack relativeKey
      objectRef =
        Contracts.ObjectRef
          { Contracts.objectBucket = workerMinioModelsBucket modelCacheConfig,
            Contracts.objectKey = modelIdValue <> "/" <> relativeKey
          }
  -- The retired form wrote the object straight to its final path and guarded
  -- the whole download behind `doesFileExist destination`. Neither half is
  -- safe on its own and together they fail open permanently: `writeFile` is
  -- not atomic, so a download interrupted by a container restart, an OOM kill,
  -- or a timeout leaves a short or empty file at the destination — and the
  -- existence check then treats that wreckage as a populated cache forever,
  -- because nothing ever re-downloads a path that exists. `.ready` is stamped
  -- immediately afterwards, so the cache reports itself populated while the
  -- model file is unusable. Observed on the `linux-cpu` cohort as
  -- `gguf_init_from_reader: failed to read magic` against a
  -- `/model-cache/<id>/payload` whose upstream MinIO object was verified
  -- intact.
  --
  -- Staging into a sibling and renaming makes the destination's existence mean
  -- what the existence check assumes: rename is atomic within one directory, so
  -- a destination is either absent or complete. An interrupted attempt leaves
  -- only the sibling, which the next attempt discards.
  destinationBytes <- observedFileSize destination
  case destinationBytes of
    Just presentBytes | presentBytes > 0 -> pure ()
    _ -> do
      manager <- newManager defaultManagerSettings
      now <- getCurrentTime
      payload <- ObjectUpload.getObjectWithPresignedUrl (workerObjectUploadConfig modelCacheConfig) manager now objectRef
      createDirectoryIfMissing True (takeDirectory destination)
      -- An empty object is never a valid model file, and publishing one costs a
      -- whole cohort cycle to diagnose. Refuse it here, where the bucket, key,
      -- and destination are all still in hand, rather than letting the engine
      -- discover it as an unreadable magic number.
      when (ByteString.null payload) $
        ioError
          ( userError
              ( "native model cache hydration refused an empty object: s3://"
                  <> Text.unpack (workerMinioModelsBucket modelCacheConfig)
                  <> "/"
                  <> Text.unpack modelIdValue
                  <> "/"
                  <> Text.unpack relativeKey
                  <> " -> "
                  <> destination
              )
          )
      let stagingPath = destination <> ".incoming"
      ByteString.writeFile stagingPath payload
      stagedBytes <- observedFileSize stagingPath
      unless (stagedBytes == Just (ByteString.length payload)) $
        ioError
          ( userError
              ( "native model cache hydration wrote "
                  <> show stagedBytes
                  <> " bytes for "
                  <> destination
                  <> " but the fetched object is "
                  <> show (ByteString.length payload)
                  <> " bytes"
              )
          )
      renamePath stagingPath destination

-- | The size of a regular file, or 'Nothing' when it is absent. Used to tell
-- an absent cache entry from a present-but-empty one, which the retired
-- existence check could not distinguish.
observedFileSize :: FilePath -> IO (Maybe Int)
observedFileSize path = do
  present <- doesFileExist path
  if present
    then do
      sizeResult <- try @SomeException (withFile path ReadMode hFileSize)
      pure (either (const Nothing) (Just . fromIntegral) sizeResult)
    else pure Nothing

nativeRunnerContractReadyPath :: WorkerModelCacheConfig -> Text -> FilePath
nativeRunnerContractReadyPath modelCacheConfig modelIdValue =
  Text.unpack (workerModelCacheRoot modelCacheConfig)
    </> Text.unpack modelIdValue
    </> ".ready"

nativeModelReadySentinelExists :: WorkerModelCacheConfig -> Text -> IO Bool
nativeModelReadySentinelExists modelCacheConfig modelIdValue = do
  manager <- newManager defaultManagerSettings
  now <- getCurrentTime
  let objectRef =
        Contracts.ObjectRef
          { Contracts.objectBucket = workerMinioModelsBucket modelCacheConfig,
            Contracts.objectKey = modelIdValue <> "/.ready"
          }
  responseResult <-
    try @SomeException
      (ObjectUpload.objectExistsViaPresignedGet (workerObjectUploadConfig modelCacheConfig) manager now objectRef)
  case responseResult of
    Right objectPresent -> pure objectPresent
    Left _ -> pure False

nativeArtifactCacheFromWorker ::
  WorkerModelCacheConfig ->
  NativeArtifactCache
nativeArtifactCacheFromWorker modelCacheConfig =
  nativeArtifactCache
    (Text.unpack (workerModelCacheRoot modelCacheConfig))
    (workerModelCacheQuotaBytes modelCacheConfig)
    (workerMinioEndpoint modelCacheConfig)
    (workerMinioModelsBucket modelCacheConfig)
    (workerMinioDemoArtifactsBucket modelCacheConfig)
    (workerMinioRegion modelCacheConfig)

nativeRunnerInputFile :: ModelDescriptor -> InferenceRequest -> Maybe WorkerModelCacheConfig -> IO (Either ErrorResponse (Maybe FilePath))
nativeRunnerInputFile _model request maybeModelCacheConfig =
  case (inputObjectRef request, maybeModelCacheConfig) of
    (Just rawObjectRef, Just modelCacheConfig) ->
      case objectRefFromText rawObjectRef of
        Nothing ->
          pure
            ( Left
                ErrorResponse
                  { errorCode = "invalid_input_object_ref",
                    message = "native engine input object ref is not bucket/key: " <> rawObjectRef
                  }
            )
        Just objectRef -> do
          result <- try @SomeException (downloadNativeInputObject modelCacheConfig objectRef)
          pure $
            case result of
              Right inputPath -> Right (Just inputPath)
              Left err ->
                Left
                  ErrorResponse
                    { errorCode = "input_object_fetch_failed",
                      message = Text.pack ("native engine input object download failed: " <> displayException err)
                    }
    _ -> pure (Right Nothing)

downloadNativeInputObject :: WorkerModelCacheConfig -> Contracts.ObjectRef -> IO FilePath
downloadNativeInputObject modelCacheConfig objectRef = do
  payload <- downloadNativeInputPayload modelCacheConfig objectRef
  tempRoot <- getTemporaryDirectory
  pid <- getProcessID
  nowForPath <- getCurrentTime
  let extension =
        case takeExtension (Text.unpack (Contracts.objectKey objectRef)) of
          "" -> ".bin"
          value -> value
      inputPath =
        tempRoot
          </> "infernix-native-input"
          </> ( safePathSegment (Text.unpack (Contracts.objectBucket objectRef <> "-" <> Contracts.objectKey objectRef))
                  <> "-"
                  <> show pid
                  <> "-"
                  <> formatTime defaultTimeLocale "%s%q" nowForPath
                  <> extension
              )
  createDirectoryIfMissing True (takeDirectory inputPath)
  ByteString.writeFile inputPath payload
  pure inputPath

downloadNativeInputPayload :: WorkerModelCacheConfig -> Contracts.ObjectRef -> IO ByteString.ByteString
downloadNativeInputPayload modelCacheConfig objectRef = go (1 :: Int)
  where
    maxAttempts = 3 :: Int
    retryDelayMicros = 5000000
    go attemptNumber = do
      manager <- newManager defaultManagerSettings
      now <- getCurrentTime
      result <-
        try @SomeException
          (ObjectUpload.getObjectWithPresignedUrl (workerObjectUploadConfig modelCacheConfig) manager now objectRef)
      case result of
        Right payload -> pure payload
        Left err
          | attemptNumber < maxAttempts -> do
              threadDelay retryDelayMicros
              go (attemptNumber + 1)
          | otherwise -> throwIO err

objectRefFromText :: Text -> Maybe Contracts.ObjectRef
objectRefFromText raw =
  let (bucket, rawKey) = Text.breakOn "/" raw
      key = Text.drop 1 rawKey
   in if Text.null bucket || Text.null key || Text.null rawKey
        then Nothing
        else
          Just
            Contracts.ObjectRef
              { Contracts.objectBucket = bucket,
                Contracts.objectKey = key
              }

nativeRunnerOutputDir :: ModelDescriptor -> Maybe WorkerModelCacheConfig -> IO (Maybe FilePath)
nativeRunnerOutputDir model maybeModelCacheConfig =
  case maybeModelCacheConfig of
    Just _
      | resultFamilyIsArtifact (resultFamilyForDescriptor model) -> do
          tempRoot <- getTemporaryDirectory
          pid <- getProcessID
          now <- getCurrentTime
          let outputDir =
                tempRoot
                  </> "infernix-native-output"
                  </> ( safePathSegment (Text.unpack (modelId model))
                          <> "-"
                          <> show pid
                          <> "-"
                          <> formatTime defaultTimeLocale "%s%q" now
                      )
          createDirectoryIfMissing True outputDir
          pure (Just outputDir)
    _ -> pure Nothing

nativeRunnerResult :: ModelDescriptor -> EngineBinding -> InferenceRequest -> Maybe WorkerModelCacheConfig -> ExitCode -> String -> String -> IO (Either ErrorResponse Text)
nativeRunnerResult model engineBinding request maybeModelCacheConfig exitCode stdoutOutput stderrOutput =
  case exitCode of
    ExitSuccess ->
      case trimWhitespace stdoutOutput of
        Just trimmed -> nativeRunnerSuccessOutput model request maybeModelCacheConfig (Text.pack trimmed)
        Nothing ->
          pure
            ( Left
                ErrorResponse
                  { errorCode = "worker_empty_output",
                    message = "native engine " <> engineBindingAdapterId engineBinding <> " returned no output."
                  }
            )
    ExitFailure 75 ->
      pure
        ( Left
            ErrorResponse
              { errorCode = "model_cache_not_populated",
                message =
                  "native engine "
                    <> engineBindingAdapterId engineBinding
                    <> " could not load populated model cache state"
                    <> Text.pack (stderrSuffix (ByteString8.pack stderrOutput))
              }
        )
    ExitFailure failureCode ->
      pure
        ( Left
            ErrorResponse
              { errorCode = "worker_failed",
                message =
                  "native engine worker failed: "
                    <> engineBindingAdapterId engineBinding
                    <> " (exit code "
                    <> Text.pack (show failureCode)
                    <> ")"
                    <> Text.pack (capturedStreamSuffix "stderr" stderrOutput)
                    <> Text.pack (capturedStreamSuffix "stdout" stdoutOutput)
              }
        )

nativeArtifactOutputPrefix :: Text
nativeArtifactOutputPrefix = "infernix-native-artifact-file:"

-- | The artifact marker is a line of the runner's standard output, not the
-- whole stream.
--
-- A native runner is a real upstream program and prints what it prints: the
-- Core ML basic-pitch runner announces the file it is predicting and the shape
-- of each tensor before it announces the artifact it wrote. Matching the marker
-- as a prefix of the entire trimmed stream therefore recognised it only for the
-- runners that happen to say nothing else, and the ones that do had their marker
-- carried into the result as if it were an object reference — a local path in a
-- field whose contract is a bucket key.
--
-- Exactly one marker line is the contract. None means the runner returned
-- inline output. More than one is a runner that produced several artifacts
-- through a protocol that names one, and that fails closed rather than picking.
nativeArtifactMarkerPaths :: Text -> [Text]
nativeArtifactMarkerPaths outputText =
  [ path
  | line <- Text.lines outputText,
    Just path <- [Text.stripPrefix nativeArtifactOutputPrefix (Text.strip line)]
  ]

-- | Test seam over the pure marker scan above.
nativeArtifactMarkerPathsForTest :: Text -> [Text]
nativeArtifactMarkerPathsForTest = nativeArtifactMarkerPaths

nativeRunnerSuccessOutput :: ModelDescriptor -> InferenceRequest -> Maybe WorkerModelCacheConfig -> Text -> IO (Either ErrorResponse Text)
nativeRunnerSuccessOutput model request maybeModelCacheConfig outputText =
  case nativeArtifactMarkerPaths outputText of
    [] -> pure (Right outputText)
    _ : _ : _ ->
      pure
        ( Left
            ErrorResponse
              { errorCode = "native_artifact_marker_ambiguous",
                message = "native engine announced more than one artifact file through a protocol that names one."
              }
        )
    [artifactPathText] ->
      case maybeModelCacheConfig of
        Nothing ->
          pure
            ( Left
                ErrorResponse
                  { errorCode = "native_artifact_upload_unconfigured",
                    message = "native engine returned a local artifact file, but model-cache MinIO wiring is unavailable."
                  }
            )
        Just modelCacheConfig ->
          case generatedOutputObjectPrefixForRequest request of
            Nothing ->
              pure
                ( Left
                    ErrorResponse
                      { errorCode = "native_artifact_output_target_missing",
                        message = "native engine returned a local artifact file, but the request did not carry durable user/context ownership."
                      }
                )
            Just generatedPrefix -> do
              let artifactPath = Text.unpack artifactPathText
              artifactExists <- doesFileExist artifactPath
              if not artifactExists
                then
                  pure
                    ( Left
                        ErrorResponse
                          { errorCode = "native_artifact_missing",
                            message = "native engine returned an artifact path that does not exist: " <> artifactPathText
                          }
                    )
                else do
                  uploadResult <- try @SomeException (nativeArtifactObjectRefFromFile model modelCacheConfig generatedPrefix artifactPath)
                  case uploadResult of
                    Right objectRef -> pure (Right (renderObjectRef objectRef))
                    Left err ->
                      pure
                        ( Left
                            ErrorResponse
                              { errorCode = "native_artifact_upload_failed",
                                message = Text.pack ("native artifact upload failed: " <> displayException err)
                              }
                        )

nativeArtifactObjectRefFromFile :: ModelDescriptor -> WorkerModelCacheConfig -> Text -> FilePath -> IO Contracts.ObjectRef
nativeArtifactObjectRefFromFile model modelCacheConfig generatedPrefix artifactPath = do
  payload <- ByteString.readFile artifactPath
  let objectRef = nativeArtifactObjectRef modelCacheConfig model generatedPrefix artifactPath payload
      uploadConfig = workerObjectUploadConfig modelCacheConfig
  manager <- newManager defaultManagerSettings
  now <- getCurrentTime
  ObjectUpload.putObjectWithPresignedUrl uploadConfig manager now objectRef payload
  pure objectRef

nativeArtifactObjectRef :: WorkerModelCacheConfig -> ModelDescriptor -> Text -> FilePath -> ByteString.ByteString -> Contracts.ObjectRef
nativeArtifactObjectRef modelCacheConfig model generatedPrefix artifactPath payload =
  Contracts.ObjectRef
    { Contracts.objectBucket = workerMinioDemoArtifactsBucket modelCacheConfig,
      Contracts.objectKey =
        generatedPrefix
          <> Text.intercalate
            "-"
            [ resultFamilyId (resultFamilyForDescriptor model),
              safeObjectKeySegment (modelId model),
              "sha256-" <> sha256Hex payload
            ]
          <> artifactExtension artifactPath
    }

workerObjectUploadConfig :: WorkerModelCacheConfig -> ObjectUpload.ObjectUploadConfig
workerObjectUploadConfig modelCacheConfig =
  let (scheme, hostPort) = splitMinioEndpoint (workerMinioEndpoint modelCacheConfig)
   in ObjectUpload.ObjectUploadConfig
        { ObjectUpload.objectUploadScheme = scheme,
          ObjectUpload.objectUploadEndpoint = hostPort,
          ObjectUpload.objectUploadPathPrefix = "",
          ObjectUpload.objectUploadRegion = workerMinioRegion modelCacheConfig,
          ObjectUpload.objectUploadAccessKeyId = workerMinioAccessKey modelCacheConfig,
          ObjectUpload.objectUploadSecretAccessKey = workerMinioSecretKey modelCacheConfig,
          ObjectUpload.objectUploadExpirySeconds = 60
        }

splitMinioEndpoint :: Text -> (Text, Text)
splitMinioEndpoint raw =
  case Text.stripPrefix "https://" raw of
    Just hostPort -> ("https", hostPort)
    Nothing ->
      case Text.stripPrefix "http://" raw of
        Just hostPort -> ("http", hostPort)
        Nothing -> ("http", raw)

renderObjectRef :: Contracts.ObjectRef -> Text
renderObjectRef objectRef =
  Contracts.objectBucket objectRef <> "/" <> Contracts.objectKey objectRef

sha256Hex :: ByteString.ByteString -> Text
sha256Hex payload =
  TextEncoding.decodeUtf8 (Base16.encode (SHA256.hash payload))

artifactExtension :: FilePath -> Text
artifactExtension artifactPath =
  case takeExtension artifactPath of
    "" -> ".bin"
    extension -> Text.pack extension

safeObjectKeySegment :: Text -> Text
safeObjectKeySegment =
  Text.map safeObjectKeyChar

safePathSegment :: String -> String
safePathSegment rawValue =
  case map safePathChar rawValue of
    "" -> "artifact"
    value -> value

safeObjectKeyChar :: Char -> Char
safeObjectKeyChar character
  | safeSegmentChar character = character
  | otherwise = '-'

safePathChar :: Char -> Char
safePathChar character
  | safeSegmentChar character = character
  | otherwise = '-'

safeSegmentChar :: Char -> Bool
safeSegmentChar character =
  isAsciiLower character
    || isAsciiUpper character
    || isDigit character
    || character == '-'
    || character == '_'
    || character == '.'

-- | Phase 4 Sprint 4.30 — the Python stdio engine subprocess runs only through
-- the capped-engine kernel under the admitted grant. A ceiling breach surfaces
-- with the reserved 'modelMemoryLimitExceededErrorCode' marker so the runtime
-- rebuilds a typed 'ModelMemoryLimitExceeded' result rather than a generic
-- worker failure.
runWorkerInvocation ::
  Python.PreparedPythonEnvironmentReadAuthority s ->
  Paths ->
  ExecutableModel ->
  ModelDescriptor ->
  ByteString.ByteString ->
  IO (Either ErrorResponse ByteString.ByteString)
runWorkerInvocation readAuthority paths executableModel model inputPayload = do
  processEnvironment <- Subprocess.clusterSubprocessEnv paths
  launchOutcome <-
    runExecutablePythonWorker
      readAuthority
      paths
      executableModel
      processEnvironment
      inputPayload
  pure $
    case launchOutcome of
      PythonWorkerInvocationRejected reason ->
        Left
          ErrorResponse
            { errorCode = "engine_invocation_invalid",
              message =
                "Python engine invocation was rejected for "
                  <> modelId model
                  <> ": "
                  <> reason
            }
      PythonWorkerLaunched outcome _exitCode stdoutOutput stderrOutput ->
        case outcome of
          -- A ceiling breach carries the reserved
          -- `modelMemoryLimitExceededErrorCode` in the `ErrorResponse` (via
          -- `modelCeilingBreachError`), exactly like the native path, so the
          -- runtime rebuilds the typed `ModelMemoryLimitExceeded` result rather
          -- than a generic worker failure.
          EngineExceededCeiling ceilingMib ->
            Left (modelCeilingBreachError model ceilingMib)
          EngineEnforcementUnavailable reason ->
            Left (modelEnforcementUnavailableError model reason)
          EngineOutputLimitExceeded outputStream ->
            Left (modelOutputLimitExceededError model outputStream)
          EngineOutputCaptureFailed outputStream reason ->
            Left (modelOutputCaptureFailedError model outputStream reason)
          EngineExited ExitSuccess ->
            Right stdoutOutput
          EngineExited _ ->
            Left
              ErrorResponse
                { errorCode = "worker_failed",
                  message =
                    "Python engine worker failed for "
                      <> modelId model
                      <> Text.pack (stderrSuffix stderrOutput)
                }

-- Phase 7 Sprint 7.17: Poetry virtualenv placement is owned by
-- @python/poetry.toml@. The worker no longer injects Poetry or
-- adapter configuration through the process environment.

-- | Sprint 4.28 (managed-state-transition doctrine): build the native-runner /
-- adapter process environment as a typed 'Subprocess.SubprocessEnv' so it always
-- carries @HOME@ and @TMPDIR@ (and a real @PATH@), rather than the previous empty
-- @env = Just []@ that spawned native runners with no environment. Caller
-- @overrides@ are appended so they take precedence. Fails closed when the host
-- manifest is absent instead of spawning with a minimal/empty environment.
stderrSuffix :: ByteString.ByteString -> String
stderrSuffix stderrOutput =
  case trimWhitespace (ByteString8.unpack stderrOutput) of
    Just message -> "\n" <> message
    Nothing -> ""

-- | Bound on each captured stream republished in a native-runner failure.
nativeFailureCaptureChars :: Int
nativeFailureCaptureChars = 4096

-- | Labelled, bounded capture for a failed native runner.
--
-- The retired failure message carried exactly one bit — that the child exited
-- non-zero. It discarded the exit code, discarded stdout entirely, and relied
-- on stderr, which some runners do not use for diagnostics at all: llama.cpp
-- b9704 prints its model-load failure to stdout, and under the retired
-- `--log-disable` argv wrote nothing to either stream. A `linux-cpu` cohort
-- failure was therefore undiagnosable from the published result, and the
-- cluster that produced it is gone by the time anyone reads the message.
--
-- Truncation is never synthesis: absent output stays absent, and a truncated
-- slice says so.
capturedStreamSuffix :: String -> String -> String
capturedStreamSuffix label captured =
  case trimWhitespace captured of
    Nothing -> ""
    Just message ->
      case splitAt nativeFailureCaptureChars message of
        (bounded, []) -> "\n" <> label <> ":\n" <> bounded
        (bounded, _) -> "\n" <> label <> " (truncated):\n" <> bounded

buildWorkerRequest :: Paths -> Maybe WorkerModelCacheConfig -> ExecutableModel -> InferenceRequest -> ProtoInference.WorkerRequest
buildWorkerRequest paths maybeModelCacheConfig executableModel request =
  set (field @"requestModelId") (modelId model) $
    set (field @"inputText") (inputText request) $
      set (field @"runtimeMode") (runtimeModeId (runtimeMode model)) $
        set (field @"selectedEngine") (selectedEngine model) $
          set (field @"adapterId") (engineBindingAdapterId engineBinding) $
            set (field @"displayName") (displayName model) $
              set (field @"family") (family model) $
                set (field @"artifactType") (artifactType model) $
                  set (field @"runtimeLane") (runtimeLaneId (runtimeLane model)) $
                    set (field @"inputObjectRef") (fromMaybe "" (inputObjectRef request)) $
                      set (field @"generatedOutputObjectPrefix") (fromMaybe "" (generatedOutputObjectPrefixForRequest request)) $
                        set (field @"engineInstallRoot") (Text.pack (engineInstallRootPath paths engineBinding)) $
                          setWorkerModelCacheFields maybeModelCacheConfig defMessage
  where
    model = executableModelDescriptor executableModel
    engineBinding = executableModelEngine executableModel

generatedOutputObjectPrefixForRequest :: InferenceRequest -> Maybe Text
generatedOutputObjectPrefixForRequest request = do
  userIdValue <- requestUserId request
  contextIdValue <- requestContextId request
  if Text.null userIdValue || Text.null contextIdValue
    then Nothing
    else
      Just
        ( ObjLayout.generatedObjectPrefix
            (Contracts.UserId userIdValue)
            (Contracts.ContextId contextIdValue)
        )

setWorkerModelCacheFields :: Maybe WorkerModelCacheConfig -> ProtoInference.WorkerRequest -> ProtoInference.WorkerRequest
setWorkerModelCacheFields maybeModelCacheConfig workerRequest =
  case maybeModelCacheConfig of
    Nothing -> workerRequest
    Just modelCacheConfig ->
      set (field @"modelCacheRoot") (workerModelCacheRoot modelCacheConfig) $
        set (field @"modelCacheQuotaBytes") (workerModelCacheQuotaBytes modelCacheConfig) $
          set (field @"minioEndpoint") (workerMinioEndpoint modelCacheConfig) $
            set (field @"minioModelsBucket") (workerMinioModelsBucket modelCacheConfig) $
              set (field @"minioDemoArtifactsBucket") (workerMinioDemoArtifactsBucket modelCacheConfig) $
                set (field @"minioRegion") (workerMinioRegion modelCacheConfig) $
                  set (field @"minioAccessKey") (workerMinioAccessKey modelCacheConfig) $
                    set (field @"minioSecretKey") (workerMinioSecretKey modelCacheConfig) workerRequest

workerRequestModelCacheConfig :: ProtoInference.WorkerRequest -> Maybe WorkerModelCacheConfig
workerRequestModelCacheConfig workerRequest =
  if emptyModelCacheConfig
    then Nothing
    else
      Just
        WorkerModelCacheConfig
          { workerModelCacheRoot = view ProtoInferenceFields.modelCacheRoot workerRequest,
            workerModelCacheQuotaBytes = view ProtoInferenceFields.modelCacheQuotaBytes workerRequest,
            workerMinioEndpoint = view ProtoInferenceFields.minioEndpoint workerRequest,
            workerMinioModelsBucket = view ProtoInferenceFields.minioModelsBucket workerRequest,
            workerMinioDemoArtifactsBucket = view ProtoInferenceFields.minioDemoArtifactsBucket workerRequest,
            workerMinioRegion = view ProtoInferenceFields.minioRegion workerRequest,
            workerMinioAccessKey = view ProtoInferenceFields.minioAccessKey workerRequest,
            workerMinioSecretKey = view ProtoInferenceFields.minioSecretKey workerRequest
          }
  where
    emptyModelCacheConfig =
      Text.null (view ProtoInferenceFields.modelCacheRoot workerRequest)
        && view ProtoInferenceFields.modelCacheQuotaBytes workerRequest == 0
        && Text.null (view ProtoInferenceFields.minioEndpoint workerRequest)
        && Text.null (view ProtoInferenceFields.minioModelsBucket workerRequest)
        && Text.null (view ProtoInferenceFields.minioDemoArtifactsBucket workerRequest)
        && Text.null (view ProtoInferenceFields.minioRegion workerRequest)
        && Text.null (view ProtoInferenceFields.minioAccessKey workerRequest)
        && Text.null (view ProtoInferenceFields.minioSecretKey workerRequest)

loadWorkerModelCacheConfig :: Paths -> RuntimeMode -> IO (Maybe WorkerModelCacheConfig)
loadWorkerModelCacheConfig paths runtimeMode = do
  clusterExists <- doesFileExist Cluster.defaultClusterConfigMountPath
  secretsExists <- doesFileExist Secrets.defaultClusterSecretsMountPath
  case (clusterExists, secretsExists) of
    (True, True) -> do
      clusterConfig <- Cluster.decodeClusterConfigFile Cluster.defaultClusterConfigMountPath
      secretsConfig <- Secrets.decodeSecretsConfigFile Secrets.defaultClusterSecretsMountPath
      Just <$> workerModelCacheConfigFromCluster clusterConfig secretsConfig
    (False, False) -> loadHostWorkerModelCacheConfig paths runtimeMode
    _ ->
      ioError
        ( userError
            ( "worker model-cache wiring requires both "
                <> Cluster.defaultClusterConfigMountPath
                <> " and "
                <> Secrets.defaultClusterSecretsMountPath
                <> " when either cluster-side manifest is present"
            )
        )

workerModelCacheConfigFromCluster :: Cluster.ClusterConfig -> Secrets.SecretsConfig -> IO WorkerModelCacheConfig
workerModelCacheConfigFromCluster clusterConfig secretsConfig = do
  minioCreds <- Secrets.readMinioCredentials (Secrets.secretsMinio secretsConfig)
  let engineConfig = Cluster.clusterEngine clusterConfig
      minioConfig = Cluster.clusterMinio clusterConfig
  pure
    WorkerModelCacheConfig
      { workerModelCacheRoot = Cluster.engineModelCacheRoot engineConfig,
        workerModelCacheQuotaBytes = fromIntegral (Cluster.engineModelCacheQuotaBytes engineConfig),
        workerMinioEndpoint = Cluster.minioEndpoint minioConfig,
        workerMinioModelsBucket = Cluster.minioModelsBucket minioConfig,
        workerMinioDemoArtifactsBucket = Cluster.minioDemoArtifactsBucket minioConfig,
        workerMinioRegion = Cluster.minioRegion minioConfig,
        workerMinioAccessKey = Secrets.minioAccessKey minioCreds,
        workerMinioSecretKey = Secrets.minioSecretKey minioCreds
      }

loadHostWorkerModelCacheConfig :: Paths -> RuntimeMode -> IO (Maybe WorkerModelCacheConfig)
loadHostWorkerModelCacheConfig paths runtimeMode = do
  maybeState <- loadWorkerClusterState paths runtimeMode
  case maybeState of
    Nothing -> pure Nothing
    Just _state -> do
      secretsConfig <- loadHostWorkerSecrets paths
      minioCreds <- Secrets.readMinioCredentials (Secrets.secretsMinio secretsConfig)
      pure
        ( Just
            WorkerModelCacheConfig
              { workerModelCacheRoot = Text.pack (modelCacheRoot paths),
                workerModelCacheQuotaBytes = 34359738368,
                workerMinioEndpoint = "http://127.0.0.1:30011",
                workerMinioModelsBucket = "infernix-models",
                workerMinioDemoArtifactsBucket = "infernix-demo-objects",
                workerMinioRegion = "us-east-1",
                workerMinioAccessKey = Secrets.minioAccessKey minioCreds,
                workerMinioSecretKey = Secrets.minioSecretKey minioCreds
              }
        )

-- | Sprint 2.14: read the recorded cluster state through the fail-closed
-- versioned aeson codec. A present-but-undecodable state file is a loud
-- 'ClusterStateDecodeFailure' rather than a silent "no cluster"; an absent,
-- blank, mismatched-mode, or not-yet-present state resolves to 'Nothing'.
loadWorkerClusterState :: Paths -> RuntimeMode -> IO (Maybe ClusterState)
loadWorkerClusterState paths runtimeMode = do
  let statePath = runtimeRoot paths </> "cluster-state.state"
  result <- readClusterStateFile statePath
  case result of
    Left detail -> throwIO (ClusterStateDecodeFailure statePath detail)
    Right (Just state)
      | clusterPresent state && clusterRuntimeMode state == runtimeMode ->
          pure (Just state)
    Right _ -> pure Nothing

-- | Phase 8 Sprint 8.3: load the host worker secrets, failing fast when the
-- manifest is absent. Creation is owned by `infernix init`
-- (`materializeHostSecrets`); there is no lazy auto-generate-if-absent
-- backstop here.
loadHostWorkerSecrets :: Paths -> IO Secrets.SecretsConfig
loadHostWorkerSecrets paths = do
  let secretsRoot = runtimeRoot paths </> "secrets"
      manifestPath = secretsRoot </> "InfernixSecrets.dhall"
  manifestExists <- doesFileExist manifestPath
  unless manifestExists $
    ioError
      ( userError
          ( "host worker secrets manifest missing at "
              <> manifestPath
              <> "; run `infernix init` to create the runtime config and host secrets"
          )
      )
  Secrets.decodeSecretsConfigFile manifestPath

-- | Decode the worker output from a 'WorkerResponse'. Phase 4 Sprint 4.15:
-- artifact adapters return an @infernix-demo-objects@ object reference in
-- @object_ref@; text adapters return @output_text@. The non-empty
-- @object_ref@ takes precedence; 'Infernix.Runtime.buildPayload' then
-- routes the value to 'inlineOutput' or 'objectRef' by the model's family.
workerOutputFromResponse :: ProtoInference.WorkerResponse -> Either ErrorResponse Text
workerOutputFromResponse workerResponse =
  case trimWhitespace (Text.unpack (view ProtoInferenceFields.errorCode workerResponse)) of
    Just errorCodeValue ->
      Left
        ErrorResponse
          { errorCode = Text.pack errorCodeValue,
            message = responseMessage
          }
    Nothing
      | not (Text.null objectRefValue) -> Right objectRefValue
      | not (Text.null outputText) -> Right outputText
      | otherwise ->
          Left
            ErrorResponse
              { errorCode = "worker_empty_output",
                message = "Python adapter returned an empty worker response."
              }
  where
    objectRefValue = view ProtoInferenceFields.objectRef workerResponse
    outputText = view ProtoInferenceFields.outputText workerResponse
    responseMessage =
      maybe
        "Python adapter returned an error."
        Text.pack
        (trimWhitespace (Text.unpack (view ProtoInferenceFields.errorMessage workerResponse)))

trimWhitespace :: String -> Maybe String
trimWhitespace rawValue =
  let trimmed = dropWhileEnd (`elem` [' ', '\n', '\r', '\t']) (dropWhile (`elem` [' ', '\n', '\r', '\t']) rawValue)
   in if null trimmed then Nothing else Just trimmed

engineInstallRootPath :: Paths -> EngineBinding -> FilePath
engineInstallRootPath paths engineBinding =
  dataRoot paths </> "engines" </> Text.unpack (engineBindingAdapterId engineBinding)
