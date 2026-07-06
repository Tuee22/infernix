{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Infernix.Runtime.Worker
  ( EngineCommandOverrideMap,
    WorkerModelCacheConfig (..),
    buildWorkerRequest,
    lookupEngineCommandOverride,
    loadWorkerModelCacheConfig,
    nativeEngineInstallRootCandidates,
    nativeModelCacheObjectKeys,
    nativeRunnerArgs,
    runInferenceWorker,
    workerRequestModelCacheConfig,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, displayException, throwIO, try)
import Control.Monad (unless, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as ByteString8
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.List (dropWhileEnd, find, intercalate)
import Data.Maybe (catMaybes, fromMaybe, listToMaybe)
import Data.ProtoLens (decodeMessage, defMessage, encodeMessage)
import Data.ProtoLens.Field (field)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time (defaultTimeLocale, formatTime, getCurrentTime)
import Data.Word (Word64)
import Infernix.ClusterConfig qualified as Cluster
import Infernix.Config (Paths (..))
import Infernix.Models (engineBindingForSelectedEngine, resultFamilyForDescriptor)
import Infernix.Objects.Layout qualified as ObjLayout
import Infernix.Objects.Upload qualified as ObjectUpload
import Infernix.Python (ensurePoetryExecutable, ensurePoetryProjectInstalledWithGroups, ensurePoetryProjectReady)
import Infernix.Runtime.KVCache qualified as KVCache
import Infernix.SecretsConfig qualified as Secrets
import Infernix.Types
import Infernix.Web.Contracts qualified as Contracts
import Lens.Family2 (set, view)
import Network.HTTP.Client (defaultManagerSettings, newManager)
import Proto.Infernix.Runtime.Inference qualified as ProtoInference
import Proto.Infernix.Runtime.Inference_Fields qualified as ProtoInferenceFields
import System.Directory (createDirectoryIfMissing, doesFileExist, getTemporaryDirectory, renameFile)
import System.Exit (ExitCode (ExitFailure, ExitSuccess))
import System.FilePath (takeDirectory, takeExtension, (</>))
import System.IO (hClose, openTempFile)
import System.Info qualified as SystemInfo
import System.Posix.Process (getProcessID)
import System.Process
  ( CreateProcess (cwd, env, std_err, std_in, std_out),
    StdStream (CreatePipe),
    createProcess,
    proc,
    readCreateProcessWithExitCode,
    shell,
    waitForProcess,
  )
import Text.Read (readMaybe)

-- | Phase 4 Sprint 4.13 — engine-command override lookup keyed by the
-- engine binding's adapter id. The supported source is the
-- @ClusterConfig.engine.commandOverrides@ Dhall map (rendered into
-- @ConfigMap/infernix-cluster-config@). Empty list = no overrides; the
-- worker uses the default Poetry-run invocation.
type EngineCommandOverrideMap = [(Text, Text)]

-- | Look up an override entry by the engine binding's adapter id.
lookupEngineCommandOverride :: EngineCommandOverrideMap -> EngineBinding -> Maybe String
lookupEngineCommandOverride overrides engineBinding =
  fmap
    (Text.unpack . snd)
    (find (\(adapterIdKey, _) -> adapterIdKey == engineBindingAdapterId engineBinding) overrides)

data WorkerInvocation
  = DirectWorkerInvocation FilePath FilePath [String]
  | ShellWorkerInvocation FilePath String

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

runInferenceWorker ::
  Paths ->
  RuntimeMode ->
  EngineCommandOverrideMap ->
  ModelDescriptor ->
  InferenceRequest ->
  Maybe KVCache.KVCacheObservation ->
  IO (Either ErrorResponse Text)
runInferenceWorker paths runtimeMode overrides model request cacheObservation =
  case engineBindingAdapterType engineBinding of
    "python-stdio" ->
      ensurePythonEngineSetupReady paths runtimeMode engineBinding
        >> runPythonWorker paths runtimeMode overrides model engineBinding request cacheObservation
    "native-process-runner" ->
      runNativeWorker paths runtimeMode model engineBinding request cacheObservation
    adapterType ->
      pure (unsupportedEngineRunner engineBinding adapterType)
  where
    engineBinding = engineBindingForSelectedEngine runtimeMode (selectedEngine model)

unsupportedEngineRunner :: EngineBinding -> Text -> Either ErrorResponse Text
unsupportedEngineRunner engineBinding adapterType =
  Left
    ErrorResponse
      { errorCode = "unsupported_engine_runner",
        message =
          "Unsupported engine adapter type for "
            <> engineBindingAdapterId engineBinding
            <> ": "
            <> adapterType
      }

runPythonWorker ::
  Paths ->
  RuntimeMode ->
  EngineCommandOverrideMap ->
  ModelDescriptor ->
  EngineBinding ->
  InferenceRequest ->
  Maybe KVCache.KVCacheObservation ->
  IO (Either ErrorResponse Text)
runPythonWorker paths runtimeMode overrides model engineBinding request _cacheObservation = do
  let maybeOverride = lookupEngineCommandOverride overrides engineBinding
  invocation <- resolvePythonInvocation paths engineBinding maybeOverride
  maybeModelCacheConfig <- loadWorkerModelCacheConfig paths runtimeMode
  let workerRequest = encodeMessage (buildWorkerRequest paths runtimeMode maybeModelCacheConfig model engineBinding request)
  workerResult <- runWorkerInvocation paths invocation workerRequest
  pure (workerResultToOutput workerResult)

workerResultToOutput :: Either String ByteString8.ByteString -> Either ErrorResponse Text
workerResultToOutput workerResult =
  case workerResult of
    Right encodedResponse ->
      decodedWorkerOutput encodedResponse
    Left message ->
      Left
        ErrorResponse
          { errorCode = "worker_failed",
            message = Text.pack message
          }

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

ensurePythonEngineSetupReady :: Paths -> RuntimeMode -> EngineBinding -> IO ()
ensurePythonEngineSetupReady paths runtimeMode engineBinding = do
  let installRoot = engineInstallRootPath paths engineBinding
      bootstrapManifest = installRoot </> "bootstrap.json"
      projectDirectory = repoRoot paths </> engineBindingProjectDirectory engineBinding
  bootstrapReady <- doesFileExist bootstrapManifest
  if bootstrapReady
    then pure ()
    else do
      poetryExecutable <- ensurePoetryExecutable paths
      ensurePoetryProjectReady paths projectDirectory
      runSetupInvocation paths poetryExecutable projectDirectory installRoot runtimeMode engineBinding
  ensurePerEngineFrameworkVenvReady paths runtimeMode engineBinding

ensurePerEngineFrameworkVenvReady :: Paths -> RuntimeMode -> EngineBinding -> IO ()
ensurePerEngineFrameworkVenvReady paths runtimeMode engineBinding =
  case perEngineFrameworkGroups runtimeMode engineBinding of
    [] -> pure ()
    groups -> do
      let projectDirectory = perEngineProjectDirectory paths engineBinding
          markerPath = perEngineFrameworkMarkerPath paths runtimeMode engineBinding groups
      expectedMarker <- perEngineFrameworkMarkerContents projectDirectory runtimeMode engineBinding groups
      markerPresent <- doesFileExist markerPath
      markerMatches <-
        if markerPresent
          then (== expectedMarker) <$> readStrictUtf8File markerPath
          else pure False
      maybeVenvPython <- perEngineVenvPython paths engineBinding
      case maybeVenvPython of
        Just _
          | markerMatches -> pure ()
        _ -> do
          ensurePoetryProjectInstalledWithGroups paths projectDirectory groups
          refreshedVenvPython <- perEngineVenvPython paths engineBinding
          case refreshedVenvPython of
            Just _ ->
              writeStrictUtf8File markerPath expectedMarker
            Nothing ->
              ioError
                ( userError
                    ( "per-engine framework venv install completed but no python interpreter was found at "
                        <> perEnginePythonPath paths engineBinding
                    )
                )

perEngineFrameworkGroups :: RuntimeMode -> EngineBinding -> [String]
perEngineFrameworkGroups runtimeMode engineBinding =
  case runtimeMode of
    AppleSilicon
      | SystemInfo.os == "darwin"
          && engineBindingAdapterId engineBinding `elem` appleSiliconFrameworkAdapterIds ->
          ["apple-silicon"]
    LinuxCpu
      | SystemInfo.os == "linux"
          && engineBindingAdapterId engineBinding `elem` linuxCpuFrameworkAdapterIds ->
          ["linux-cpu"]
    _ -> []

appleSiliconFrameworkAdapterIds :: [Text]
appleSiliconFrameworkAdapterIds =
  [ "transformers-python",
    "pytorch-python",
    "diffusers-python"
  ]

linuxCpuFrameworkAdapterIds :: [Text]
linuxCpuFrameworkAdapterIds =
  [ "transformers-python",
    "pytorch-python"
  ]

perEngineFrameworkMarkerPath :: Paths -> RuntimeMode -> EngineBinding -> [String] -> FilePath
perEngineFrameworkMarkerPath paths runtimeMode engineBinding groups =
  perEngineProjectDirectory paths engineBinding
    </> ".venv"
    </> ( ".infernix-framework-groups-"
            <> Text.unpack (runtimeModeId runtimeMode)
            <> "-"
            <> intercalate "-" groups
        )

perEngineFrameworkMarkerContents :: FilePath -> RuntimeMode -> EngineBinding -> [String] -> IO String
perEngineFrameworkMarkerContents projectDirectory runtimeMode engineBinding groups = do
  projectDigest <- perEngineFrameworkProjectDigest projectDirectory
  pure
    ( unlines
        [ "runtimeMode=" <> Text.unpack (runtimeModeId runtimeMode),
          "adapterId=" <> Text.unpack (engineBindingAdapterId engineBinding),
          "groups=" <> intercalate "," groups,
          "projectDigest=" <> projectDigest
        ]
    )

readStrictUtf8File :: FilePath -> IO String
readStrictUtf8File path =
  ByteString8.unpack <$> ByteString.readFile path

writeStrictUtf8File :: FilePath -> String -> IO ()
writeStrictUtf8File path contents = do
  createDirectoryIfMissing True (takeDirectory path)
  (temporaryPath, handle) <- openTempFile (takeDirectory path) ".infernix-framework-groups.tmp"
  hClose handle
  ByteString.writeFile temporaryPath (ByteString8.pack contents)
  renameFile temporaryPath path

perEngineFrameworkProjectDigest :: FilePath -> IO String
perEngineFrameworkProjectDigest projectDirectory = do
  let pyprojectPath = projectDirectory </> "pyproject.toml"
      lockPath = projectDirectory </> "poetry.lock"
  pyprojectBytes <- ByteString.readFile pyprojectPath
  lockPresent <- doesFileExist lockPath
  lockBytes <-
    if lockPresent
      then ByteString.readFile lockPath
      else pure ""
  pure
    ( Text.unpack
        ( TextEncoding.decodeUtf8
            (Base16.encode (SHA256.hash (ByteString.concat [pyprojectBytes, ByteString8.pack "\n", lockBytes])))
        )
    )

runSetupInvocation :: Paths -> FilePath -> FilePath -> FilePath -> RuntimeMode -> EngineBinding -> IO ()
runSetupInvocation paths poetryExecutable projectDirectory installRoot _runtimeMode engineBinding = do
  -- Phase 5 Sprint 5.9 follow-on (May 26, 2026): @--install-root@ is
  -- passed as a typed CLI argument to the setup entrypoint instead
  -- of via the legacy engine-install-root env. The supported Python
  -- adapter's @setup()@ routes through @run_setup_from_argv@ which
  -- parses argv with argparse. The previous repo-root and active-substrate
  -- env overrides are retired: the
  -- adapter resolves its repo root via @Path(__file__)@-anchored
  -- traversal (canonical Poetry invocation always runs from
  -- @<repoRoot>/python@), and the bootstrap manifest no longer
  -- records a @runtimeMode@ field.
  let setupArgs =
        [ "--directory",
          projectDirectory,
          "run",
          Text.unpack (engineBindingSetupEntrypoint engineBinding),
          "--install-root",
          installRoot
        ]
  processEnvironment <- workerProcessEnvironment paths []
  (_, _, maybeWorkerError, workerHandle) <-
    createProcess
      (proc poetryExecutable setupArgs)
        { cwd = Just projectDirectory,
          env = Just processEnvironment,
          std_err = CreatePipe
        }
  stderrOutput <-
    case maybeWorkerError of
      Just workerError -> ByteString.hGetContents workerError
      Nothing -> pure ""
  exitCode <- waitForProcess workerHandle
  case exitCode of
    ExitSuccess -> pure ()
    _ ->
      ioError
        ( userError
            ( "engine setup failed: "
                <> Text.unpack (engineBindingSetupEntrypoint engineBinding)
                <> stderrSuffix stderrOutput
            )
        )

resolvePythonInvocation :: Paths -> EngineBinding -> Maybe String -> IO WorkerInvocation
resolvePythonInvocation paths engineBinding maybeOverride = do
  let projectDirectory = repoRoot paths </> engineBindingProjectDirectory engineBinding
  maybePerEngineVenvPython <- perEngineVenvPython paths engineBinding
  case (trimWhitespace =<< maybeOverride, maybePerEngineVenvPython) of
    (Nothing, Just venvPython) ->
      -- Phase 4 Sprint 4.16: a per-engine isolated framework venv exists
      -- (baked by the image build's `poetry install --directory
      -- python/engines/<engine> --with <substrate>`). Invoke its venv python
      -- with `-m adapters.<module>` rather than the console script, because
      -- in-project venvs install console scripts with a relative shebang that
      -- only resolves from the project directory; the venv python is an
      -- absolute interpreter symlink that runs from any cwd. No shared-project
      -- install and no Poetry at runtime — the venv already carries the
      -- framework plus the shared `adapters` package via the path dependency.
      pure
        ( DirectWorkerInvocation
            venvPython
            (repoRoot paths)
            ["-m", perEngineAdapterModule engineBinding]
        )
    (Just overrideCommand, _) ->
      do
        poetryExecutable <- ensurePoetryExecutable paths
        ensurePoetryProjectReady paths projectDirectory
        pure
          ( ShellWorkerInvocation
              projectDirectory
              ( overrideCommand
                  <> " "
                  <> shellQuote poetryExecutable
                  <> " --directory "
                  <> shellQuote projectDirectory
                  <> " run "
                  <> shellQuote (Text.unpack (engineBindingAdapterEntrypoint engineBinding))
              )
          )
    (Nothing, Nothing) ->
      do
        poetryExecutable <- ensurePoetryExecutable paths
        ensurePoetryProjectReady paths projectDirectory
        pure
          ( DirectWorkerInvocation
              poetryExecutable
              projectDirectory
              [ "--directory",
                projectDirectory,
                "run",
                Text.unpack (engineBindingAdapterEntrypoint engineBinding)
              ]
          )

-- | Phase 4 Sprint 4.16 — resolve the per-engine isolated framework venv's
-- python interpreter, when present. The image build populates
-- @python/engines/<engine>/.venv@ with the substrate's framework wheels plus
-- the shared @adapters@ package (editable path dependency). When the
-- per-engine venv is absent (e.g. the machine-independent unit environment),
-- the worker falls back to the shared framework-free project so
-- unsupported/absent frameworks fail fast.
perEngineVenvPython :: Paths -> EngineBinding -> IO (Maybe FilePath)
perEngineVenvPython paths engineBinding = do
  let pythonPath = perEnginePythonPath paths engineBinding
  present <- doesFileExist pythonPath
  pure (if present then Just pythonPath else Nothing)

perEngineProjectDirectory :: Paths -> EngineBinding -> FilePath
perEngineProjectDirectory paths engineBinding =
  repoRoot paths
    </> "python"
    </> "engines"
    </> perEngineName engineBinding

perEnginePythonPath :: Paths -> EngineBinding -> FilePath
perEnginePythonPath paths engineBinding =
  perEngineProjectDirectory paths engineBinding
    </> ".venv"
    </> "bin"
    </> "python"

perEngineName :: EngineBinding -> String
perEngineName engineBinding =
  Text.unpack (Text.replace "-python" "" (engineBindingAdapterId engineBinding))

-- | The @adapters.<module>@ import path for an engine's adapter (run via
-- @python -m@ in the per-engine venv). @transformers-python@ -> @adapters.transformers_python@.
perEngineAdapterModule :: EngineBinding -> String
perEngineAdapterModule engineBinding =
  "adapters." <> Text.unpack (Text.replace "-" "_" (engineBindingAdapterId engineBinding))

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
runNativeWorker :: Paths -> RuntimeMode -> ModelDescriptor -> EngineBinding -> InferenceRequest -> Maybe KVCache.KVCacheObservation -> IO (Either ErrorResponse Text)
runNativeWorker paths _runtimeMode model engineBinding request _cacheObservation =
  case nativeRunnerBinaryRelPath (engineBindingAdapterId engineBinding) of
    Nothing ->
      pure
        ( Left
            ErrorResponse
              { errorCode = "unsupported_engine_runner",
                message =
                  "No supported native runner is available for "
                    <> engineBindingAdapterId engineBinding
                    <> "."
              }
        )
    Just binaryRelPath -> do
      maybeNativeRunner <- firstPresentNativeRunner paths engineBinding binaryRelPath
      case maybeNativeRunner of
        Nothing ->
          let checkedPaths =
                map
                  (Text.pack . (</> binaryRelPath))
                  (nativeEngineInstallRootCandidates paths engineBinding)
           in pure
                ( Left
                    ErrorResponse
                      { errorCode = "engine_binary_missing",
                        message =
                          "native engine binary is not present in any supported install root for "
                            <> engineBindingAdapterId engineBinding
                            <> ": "
                            <> Text.intercalate ", " checkedPaths
                            <> "; materialize it for the active substrate (Apple: infernix internal materialize-metal-engines; Linux: bake the native runner into the substrate image under /opt/infernix/engines) before running."
                      }
                )
        Just (installRoot, binaryPath) -> do
          maybeModelCacheConfig <- loadWorkerModelCacheConfig paths _runtimeMode
          ensureNativeRunnerContractCacheReady model maybeModelCacheConfig
          inputFileResult <- nativeRunnerInputFile model request maybeModelCacheConfig
          case inputFileResult of
            Left inputError -> pure (Left inputError)
            Right maybeInputFile -> do
              maybeOutputDir <- nativeRunnerOutputDir model maybeModelCacheConfig
              processEnvironment <- workerProcessEnvironment paths []
              (exitCode, stdoutOutput, stderrOutput) <-
                readCreateProcessWithExitCode
                  ( (proc binaryPath (nativeRunnerArgsWithInputFile model request installRoot maybeModelCacheConfig maybeOutputDir maybeInputFile))
                      { cwd = Just installRoot,
                        env = Just processEnvironment
                      }
                  )
                  ""
              nativeRunnerResult model engineBinding request binaryPath maybeModelCacheConfig exitCode stdoutOutput stderrOutput

-- | Native runners participate in the model-bootstrap protocol: the first
-- invocation reports a cache miss, the coordinator populates MinIO, and the
-- retry hydrates local model files before strict native execution. Keep MinIO
-- credentials in this Haskell worker, not in native process argv.
ensureNativeRunnerContractCacheReady :: ModelDescriptor -> Maybe WorkerModelCacheConfig -> IO ()
ensureNativeRunnerContractCacheReady _ Nothing = pure ()
ensureNativeRunnerContractCacheReady model (Just modelCacheConfig) = do
  let readyPath = nativeRunnerContractReadyPath modelCacheConfig (modelId model)
  localReady <- doesFileExist readyPath
  unless localReady $ do
    upstreamReady <- nativeModelReadySentinelExists modelCacheConfig (modelId model)
    when upstreamReady $ do
      createDirectoryIfMissing True (takeDirectory readyPath)
      hydrateNativeModelCache model modelCacheConfig
      writeFile readyPath "native-model-cache-ready\n"

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
  destinationPresent <- doesFileExist destination
  unless destinationPresent $ do
    manager <- newManager defaultManagerSettings
    now <- getCurrentTime
    payload <- ObjectUpload.getObjectWithPresignedUrl (workerObjectUploadConfig modelCacheConfig) manager now objectRef
    createDirectoryIfMissing True (takeDirectory destination)
    ByteString.writeFile destination payload

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

firstPresentNativeRunner :: Paths -> EngineBinding -> FilePath -> IO (Maybe (FilePath, FilePath))
firstPresentNativeRunner paths engineBinding binaryRelPath = do
  candidates <-
    mapM
      candidateIfPresent
      (nativeEngineInstallRootCandidates paths engineBinding)
  pure (listToMaybe (catMaybes candidates))
  where
    candidateIfPresent installRoot = do
      let binaryPath = installRoot </> binaryRelPath
      binaryPresent <- doesFileExist binaryPath
      pure (if binaryPresent then Just (installRoot, binaryPath) else Nothing)

nativeEngineInstallRootCandidates :: Paths -> EngineBinding -> [FilePath]
nativeEngineInstallRootCandidates paths engineBinding =
  [ engineInstallRootPath paths engineBinding,
    "/opt/infernix/engines" </> Text.unpack (engineBindingAdapterId engineBinding)
  ]

-- | Resolve the native engine binary's path relative to its engine
-- install root. The adapter id is the closed set of native-process-runner
-- bindings; an unknown id returns 'Nothing' and the caller fails fast.
nativeRunnerBinaryRelPath :: Text -> Maybe FilePath
nativeRunnerBinaryRelPath adapterId =
  case adapterId of
    "whisper-cpp-cli" -> Just "bin/whisper-cli"
    "llama-cpp-cli" -> Just "bin/llama-cli"
    "onnx-runtime-native" -> Just "bin/onnx-runner"
    "coreml-native" -> Just "bin/coreml-runner"
    "ctranslate2-native" -> Just "bin/ct2-runner"
    "mlx-native" -> Just "bin/mlx-runner"
    "jvm-native" -> Just "bin/audiveris"
    _ -> Nothing

-- | Pure argument vector for a native engine binary (unit-tested). Text
-- families pass @--input-text@; the audio and image input families pass
-- the @--input-object-ref@ that points into @infernix-demo-objects@.
-- Artifact-producing invocations may also receive an @--output-dir@; the
-- runner writes a local file there and prints an artifact-file marker while
-- this worker owns the credentialed MinIO upload.
nativeRunnerArgs :: ModelDescriptor -> InferenceRequest -> FilePath -> Maybe WorkerModelCacheConfig -> Maybe FilePath -> [String]
nativeRunnerArgs model request installRoot maybeModelCacheConfig maybeOutputDir =
  nativeRunnerArgsWithInputFile model request installRoot maybeModelCacheConfig maybeOutputDir Nothing

nativeRunnerArgsWithInputFile :: ModelDescriptor -> InferenceRequest -> FilePath -> Maybe WorkerModelCacheConfig -> Maybe FilePath -> Maybe FilePath -> [String]
nativeRunnerArgsWithInputFile model request installRoot maybeModelCacheConfig maybeOutputDir maybeInputFile =
  [ "--model",
    Text.unpack (modelId model),
    "--engine",
    Text.unpack (selectedEngine model),
    "--family",
    Text.unpack (family model),
    "--install-root",
    installRoot,
    "--require-native-payload"
  ]
    <> case inputObjectRef request of
      Just ref -> ["--input-object-ref", Text.unpack ref]
      Nothing -> ["--input-text", Text.unpack (inputText request)]
    <> nativeRunnerModelCacheArgs maybeModelCacheConfig
    <> nativeRunnerOutputArgs maybeOutputDir
    <> nativeRunnerInputFileArgs maybeInputFile

nativeRunnerModelCacheArgs :: Maybe WorkerModelCacheConfig -> [String]
nativeRunnerModelCacheArgs maybeModelCacheConfig =
  case maybeModelCacheConfig of
    Nothing -> []
    Just modelCacheConfig ->
      [ "--model-cache-root",
        Text.unpack (workerModelCacheRoot modelCacheConfig),
        "--model-cache-quota-bytes",
        show (workerModelCacheQuotaBytes modelCacheConfig),
        "--minio-endpoint",
        Text.unpack (workerMinioEndpoint modelCacheConfig),
        "--minio-models-bucket",
        Text.unpack (workerMinioModelsBucket modelCacheConfig),
        "--minio-demo-artifacts-bucket",
        Text.unpack (workerMinioDemoArtifactsBucket modelCacheConfig),
        "--minio-region",
        Text.unpack (workerMinioRegion modelCacheConfig)
      ]

nativeRunnerOutputArgs :: Maybe FilePath -> [String]
nativeRunnerOutputArgs maybeOutputDir =
  case maybeOutputDir of
    Nothing -> []
    Just outputDir -> ["--output-dir", outputDir]

nativeRunnerInputFileArgs :: Maybe FilePath -> [String]
nativeRunnerInputFileArgs maybeInputFile =
  case maybeInputFile of
    Nothing -> []
    Just inputFile -> ["--input-file", inputFile]

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

nativeRunnerResult :: ModelDescriptor -> EngineBinding -> InferenceRequest -> FilePath -> Maybe WorkerModelCacheConfig -> ExitCode -> String -> String -> IO (Either ErrorResponse Text)
nativeRunnerResult model engineBinding request binaryPath maybeModelCacheConfig exitCode stdoutOutput stderrOutput =
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
    _ ->
      pure
        ( Left
            ErrorResponse
              { errorCode = "worker_failed",
                message =
                  "native engine worker failed: "
                    <> Text.pack binaryPath
                    <> Text.pack (stderrSuffix (ByteString8.pack stderrOutput))
              }
        )

nativeArtifactOutputPrefix :: Text
nativeArtifactOutputPrefix = "infernix-native-artifact-file:"

nativeRunnerSuccessOutput :: ModelDescriptor -> InferenceRequest -> Maybe WorkerModelCacheConfig -> Text -> IO (Either ErrorResponse Text)
nativeRunnerSuccessOutput model request maybeModelCacheConfig outputText =
  case Text.stripPrefix nativeArtifactOutputPrefix outputText of
    Nothing -> pure (Right outputText)
    Just artifactPathText ->
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

runWorkerInvocation :: Paths -> WorkerInvocation -> ByteString.ByteString -> IO (Either String ByteString.ByteString)
runWorkerInvocation paths invocation inputPayload = do
  processEnvironment <- workerProcessEnvironment paths []
  let processValue =
        (processFor invocation)
          { cwd = Just (workerInvocationCwd invocation),
            env = Just processEnvironment
          }
  (maybeWorkerInput, maybeWorkerOutput, maybeWorkerError, workerHandle) <-
    createProcess
      processValue
        { std_in = CreatePipe,
          std_out = CreatePipe,
          std_err = CreatePipe
        }
  case (maybeWorkerInput, maybeWorkerOutput, maybeWorkerError) of
    (Just workerInput, Just workerOutput, Just workerError) -> do
      ByteString.hPut workerInput inputPayload
      hClose workerInput
      stdoutOutput <- ByteString.hGetContents workerOutput
      stderrOutput <- ByteString.hGetContents workerError
      exitCode <- waitForProcess workerHandle
      pure $
        case exitCode of
          ExitSuccess ->
            Right stdoutOutput
          _ ->
            Left
              ( "engine worker failed: "
                  <> describeInvocation invocation
                  <> stderrSuffix stderrOutput
              )
    _ ->
      pure (Left ("engine worker failed: " <> describeInvocation invocation <> "\nfailed to create worker stdio pipes"))

processFor :: WorkerInvocation -> CreateProcess
processFor invocation =
  case invocation of
    DirectWorkerInvocation command _workingDirectory args -> proc command args
    ShellWorkerInvocation _workingDirectory command -> shell command

workerInvocationCwd :: WorkerInvocation -> FilePath
workerInvocationCwd invocation =
  case invocation of
    DirectWorkerInvocation _command workingDirectory _args -> workingDirectory
    ShellWorkerInvocation workingDirectory _command -> workingDirectory

-- Phase 7 Sprint 7.17: Poetry virtualenv placement is owned by
-- @python/poetry.toml@. The worker no longer injects Poetry or
-- adapter configuration through the process environment.
workerProcessEnvironment :: Paths -> [(String, String)] -> IO [(String, String)]
workerProcessEnvironment _paths = pure

describeInvocation :: WorkerInvocation -> String
describeInvocation invocation =
  case invocation of
    DirectWorkerInvocation command _workingDirectory args -> unwords (command : args)
    ShellWorkerInvocation _workingDirectory command -> command

stderrSuffix :: ByteString.ByteString -> String
stderrSuffix stderrOutput =
  case trimWhitespace (ByteString8.unpack stderrOutput) of
    Just message -> "\n" <> message
    Nothing -> ""

buildWorkerRequest :: Paths -> RuntimeMode -> Maybe WorkerModelCacheConfig -> ModelDescriptor -> EngineBinding -> InferenceRequest -> ProtoInference.WorkerRequest
buildWorkerRequest paths runtimeMode maybeModelCacheConfig model engineBinding request =
  set (field @"requestModelId") (requestModelId request) $
    set (field @"inputText") (inputText request) $
      set (field @"runtimeMode") (runtimeModeId runtimeMode) $
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

loadWorkerClusterState :: Paths -> RuntimeMode -> IO (Maybe ClusterState)
loadWorkerClusterState paths runtimeMode = do
  let statePath = runtimeRoot paths </> "cluster-state.state"
  stateExists <- doesFileExist statePath
  if not stateExists
    then pure Nothing
    else do
      rawState <- readFile statePath
      case readMaybe rawState of
        Just state
          | clusterPresent state && clusterRuntimeMode state == runtimeMode ->
              pure (Just state)
        _ -> pure Nothing

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

shellQuote :: String -> String
shellQuote rawValue =
  "'" <> concatMap escapeCharacter rawValue <> "'"
  where
    escapeCharacter '\'' = "'\\''"
    escapeCharacter character = [character]

trimWhitespace :: String -> Maybe String
trimWhitespace rawValue =
  let trimmed = dropWhileEnd (`elem` [' ', '\n', '\r', '\t']) (dropWhile (`elem` [' ', '\n', '\r', '\t']) rawValue)
   in if null trimmed then Nothing else Just trimmed

engineInstallRootPath :: Paths -> EngineBinding -> FilePath
engineInstallRootPath paths engineBinding =
  dataRoot paths </> "engines" </> Text.unpack (engineBindingAdapterId engineBinding)
