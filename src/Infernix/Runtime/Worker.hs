{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Infernix.Runtime.Worker
  ( EngineCommandOverrideMap,
    WorkerModelCacheConfig (..),
    buildWorkerRequest,
    lookupEngineCommandOverride,
    nativeEngineInstallRootCandidates,
    runInferenceWorker,
    workerRequestModelCacheConfig,
  )
where

import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString8
import Data.List (dropWhileEnd, find)
import Data.Maybe (catMaybes, fromMaybe, listToMaybe)
import Data.ProtoLens (decodeMessage, defMessage, encodeMessage)
import Data.ProtoLens.Field (field)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Infernix.ClusterConfig qualified as Cluster
import Infernix.Config (Paths (..))
import Infernix.Models (engineBindingForSelectedEngine)
import Infernix.Python (ensurePoetryExecutable, ensurePoetryProjectReady)
import Infernix.Runtime.KVCache qualified as KVCache
import Infernix.SecretsConfig qualified as Secrets
import Infernix.Types
import Lens.Family2 (set, view)
import Proto.Infernix.Runtime.Inference qualified as ProtoInference
import Proto.Infernix.Runtime.Inference_Fields qualified as ProtoInferenceFields
import System.Directory (doesFileExist)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.IO (hClose)
import System.Process
  ( CreateProcess (cwd, env, std_err, std_in, std_out),
    StdStream (CreatePipe),
    createProcess,
    proc,
    readCreateProcessWithExitCode,
    shell,
    waitForProcess,
  )

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
  maybeModelCacheConfig <- loadWorkerModelCacheConfig
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
  let engineName = Text.unpack (Text.replace "-python" "" (engineBindingAdapterId engineBinding))
      pythonPath =
        repoRoot paths
          </> "python"
          </> "engines"
          </> engineName
          </> ".venv"
          </> "bin"
          </> "python"
  present <- doesFileExist pythonPath
  pure (if present then Just pythonPath else Nothing)

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
          processEnvironment <- workerProcessEnvironment paths []
          (exitCode, stdoutOutput, stderrOutput) <-
            readCreateProcessWithExitCode
              ( (proc binaryPath (nativeRunnerArgs model request installRoot))
                  { cwd = Just installRoot,
                    env = Just processEnvironment
                  }
              )
              ""
          pure (nativeRunnerResult engineBinding binaryPath exitCode stdoutOutput stderrOutput)

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
nativeRunnerArgs :: ModelDescriptor -> InferenceRequest -> FilePath -> [String]
nativeRunnerArgs model request installRoot =
  [ "--model",
    Text.unpack (modelId model),
    "--engine",
    Text.unpack (selectedEngine model),
    "--family",
    Text.unpack (family model),
    "--install-root",
    installRoot
  ]
    <> case inputObjectRef request of
      Just ref -> ["--input-object-ref", Text.unpack ref]
      Nothing -> ["--input-text", Text.unpack (inputText request)]

nativeRunnerResult :: EngineBinding -> FilePath -> ExitCode -> String -> String -> Either ErrorResponse Text
nativeRunnerResult engineBinding binaryPath exitCode stdoutOutput stderrOutput =
  case exitCode of
    ExitSuccess ->
      case trimWhitespace stdoutOutput of
        Just trimmed -> Right (Text.pack trimmed)
        Nothing ->
          Left
            ErrorResponse
              { errorCode = "worker_empty_output",
                message = "native engine " <> engineBindingAdapterId engineBinding <> " returned no output."
              }
    _ ->
      Left
        ErrorResponse
          { errorCode = "worker_failed",
            message =
              "native engine worker failed: "
                <> Text.pack binaryPath
                <> Text.pack (stderrSuffix (ByteString8.pack stderrOutput))
          }

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
                      set (field @"engineInstallRoot") (Text.pack (engineInstallRootPath paths engineBinding)) $
                        setWorkerModelCacheFields maybeModelCacheConfig defMessage

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

loadWorkerModelCacheConfig :: IO (Maybe WorkerModelCacheConfig)
loadWorkerModelCacheConfig = do
  clusterExists <- doesFileExist Cluster.defaultClusterConfigMountPath
  secretsExists <- doesFileExist Secrets.defaultClusterSecretsMountPath
  case (clusterExists, secretsExists) of
    (False, False) -> pure Nothing
    (True, True) -> do
      clusterConfig <- Cluster.decodeClusterConfigFile Cluster.defaultClusterConfigMountPath
      secretsConfig <- Secrets.decodeSecretsConfigFile Secrets.defaultClusterSecretsMountPath
      minioCreds <- Secrets.readMinioCredentials (Secrets.secretsMinio secretsConfig)
      let engineConfig = Cluster.clusterEngine clusterConfig
          minioConfig = Cluster.clusterMinio clusterConfig
      pure
        ( Just
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
        )
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
