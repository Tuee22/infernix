{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Infernix.Runtime.Worker
  ( engineCommandOverrideEnvironmentName,
    runInferenceWorker,
  )
where

import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString8
import Data.Char (isAlphaNum, toUpper)
import Data.List (dropWhileEnd)
import Data.ProtoLens (decodeMessage, defMessage, encodeMessage)
import Data.ProtoLens.Field (field)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Config (Paths (..))
import Infernix.Models (engineBindingForSelectedEngine)
import Infernix.Python (ensurePoetryExecutable, ensurePoetryProjectReady)
import Infernix.Types
import Lens.Family2 (set, view)
import Proto.Infernix.Runtime.Inference qualified as ProtoInference
import Proto.Infernix.Runtime.Inference_Fields qualified as ProtoInferenceFields
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.IO (hClose)
import System.Process
  ( CreateProcess (cwd, env, std_err, std_in, std_out),
    StdStream (CreatePipe),
    createProcess,
    proc,
    shell,
    waitForProcess,
  )

data WorkerInvocation
  = DirectWorkerInvocation FilePath FilePath [String]
  | ShellWorkerInvocation FilePath String

runInferenceWorker :: Paths -> RuntimeMode -> ModelDescriptor -> InferenceRequest -> IO (Either ErrorResponse Text)
runInferenceWorker paths runtimeMode model request =
  let engineBinding = engineBindingForSelectedEngine runtimeMode (selectedEngine model)
   in case engineBindingAdapterType engineBinding of
        "python-stdio" ->
          ensurePythonEngineSetupReady paths runtimeMode engineBinding
            >> runPythonWorker paths runtimeMode model engineBinding request
        "native-process-runner" ->
          runNativeWorker runtimeMode model engineBinding request
        adapterType ->
          pure
            ( Left
                ErrorResponse
                  { errorCode = "unsupported_engine_runner",
                    message =
                      "Unsupported engine adapter type for "
                        <> engineBindingAdapterId engineBinding
                        <> ": "
                        <> adapterType
                  }
            )

engineCommandOverrideEnvironmentName :: EngineBinding -> String
engineCommandOverrideEnvironmentName engineBinding =
  "INFERNIX_ENGINE_COMMAND_" <> map normalize (Text.unpack (engineBindingAdapterId engineBinding))
  where
    normalize character
      | isAlphaNum character = toUpper character
      | otherwise = '_'

runPythonWorker :: Paths -> RuntimeMode -> ModelDescriptor -> EngineBinding -> InferenceRequest -> IO (Either ErrorResponse Text)
runPythonWorker paths runtimeMode model engineBinding request = do
  maybeOverride <- lookupEnv (engineCommandOverrideEnvironmentName engineBinding)
  invocation <- resolvePythonInvocation paths engineBinding maybeOverride
  let workerRequest = encodeMessage (buildWorkerRequest paths runtimeMode model engineBinding request)
  workerResult <- runWorkerInvocation paths invocation workerRequest
  pure
    ( case workerResult of
        Right encodedResponse ->
          case decodeMessage encodedResponse of
            Left decodeError ->
              Left
                ErrorResponse
                  { errorCode = "worker_decode_failed",
                    message = Text.pack ("Unable to decode worker response: " <> decodeError)
                  }
            Right workerResponse ->
              workerOutputFromResponse workerResponse
        Left message ->
          Left
            ErrorResponse
              { errorCode = "worker_failed",
                message = Text.pack message
              }
    )

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
runSetupInvocation paths poetryExecutable projectDirectory installRoot runtimeMode engineBinding = do
  let setupArgs =
        [ "--directory",
          projectDirectory,
          "run",
          Text.unpack (engineBindingSetupEntrypoint engineBinding)
        ]
      envOverrides =
        [ ("POETRY_VIRTUALENVS_IN_PROJECT", "true"),
          ("INFERNIX_REPO_ROOT", repoRoot paths),
          ("INFERNIX_ENGINE_INSTALL_ROOT", installRoot),
          ("INFERNIX_ACTIVE_SUBSTRATE", Text.unpack (runtimeModeId runtimeMode))
        ]
  processEnvironment <- workerProcessEnvironment paths envOverrides
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
  case trimWhitespace =<< maybeOverride of
    Just overrideCommand ->
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
    Nothing ->
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

runNativeWorker :: RuntimeMode -> ModelDescriptor -> EngineBinding -> InferenceRequest -> IO (Either ErrorResponse Text)
runNativeWorker runtimeMode model engineBinding request =
  case nativeRunnerLabel (engineBindingAdapterId engineBinding) of
    Just runnerLabel ->
      pure
        ( Right
            ( renderNativeRunnerOutput
                runtimeMode
                model
                request
                (engineBindingAdapterId engineBinding)
                runnerLabel
            )
        )
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

nativeRunnerLabel :: Text -> Maybe Text
nativeRunnerLabel adapterId =
  case adapterId of
    "whisper-cpp-cli" -> Just "whisper.cpp transcription lane"
    "llama-cpp-cli" -> Just "llama.cpp generation lane"
    "onnx-runtime-native" -> Just "onnx-runtime execution lane"
    "coreml-native" -> Just "coreml execution lane"
    "ctranslate2-native" -> Just "ctranslate2 decoding lane"
    "mlx-native" -> Just "mlx execution lane"
    "jvm-native" -> Just "jvm workflow lane"
    _ -> Nothing

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

workerProcessEnvironment :: Paths -> [(String, String)] -> IO [(String, String)]
workerProcessEnvironment paths extraEnvironment =
  pure
    ( [ ("POETRY_VIRTUALENVS_IN_PROJECT", "true"),
        ("INFERNIX_REPO_ROOT", repoRoot paths)
      ]
        <> extraEnvironment
    )

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

buildWorkerRequest :: Paths -> RuntimeMode -> ModelDescriptor -> EngineBinding -> InferenceRequest -> ProtoInference.WorkerRequest
buildWorkerRequest paths runtimeMode model engineBinding request =
  set (field @"requestModelId") (requestModelId request) $
    set (field @"inputText") (inputText request) $
      set (field @"runtimeMode") (runtimeModeId runtimeMode) $
        set (field @"selectedEngine") (selectedEngine model) $
          set (field @"adapterId") (engineBindingAdapterId engineBinding) $
            set (field @"artifactBundlePath") (Text.pack (artifactBundlePathFor paths runtimeMode model)) $
              set (field @"sourceManifestPath") (Text.pack (sourceManifestPathFor paths runtimeMode model)) $
                set (field @"cacheManifestPath") (Text.pack (cacheManifestPathFor paths runtimeMode model)) $
                  set (field @"engineInstallRoot") (Text.pack (engineInstallRootPath paths engineBinding)) defMessage

workerOutputFromResponse :: ProtoInference.WorkerResponse -> Either ErrorResponse Text
workerOutputFromResponse workerResponse =
  case trimWhitespace (Text.unpack (view ProtoInferenceFields.errorCode workerResponse)) of
    Just errorCodeValue ->
      Left
        ErrorResponse
          { errorCode = Text.pack errorCodeValue,
            message = responseMessage
          }
    Nothing ->
      if Text.null outputText
        then
          Left
            ErrorResponse
              { errorCode = "worker_empty_output",
                message = "Python adapter returned an empty worker response."
              }
        else Right outputText
  where
    outputText = view ProtoInferenceFields.outputText workerResponse
    responseMessage =
      maybe
        "Python adapter returned an error."
        Text.pack
        (trimWhitespace (Text.unpack (view ProtoInferenceFields.errorMessage workerResponse)))

renderNativeRunnerOutput :: RuntimeMode -> ModelDescriptor -> InferenceRequest -> Text -> Text -> Text
renderNativeRunnerOutput runtimeMode model requestValue adapterId runnerLabel =
  Text.unlines
    [ "adapter=" <> adapterId,
      "runner=" <> runnerLabel,
      "runtime=" <> runtimeModeId runtimeMode,
      "model=" <> modelId model,
      "engine=" <> selectedEngine model,
      "family=" <> family model,
      "input=" <> inputText requestValue
    ]

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

artifactBundlePathFor :: Paths -> RuntimeMode -> ModelDescriptor -> FilePath
artifactBundlePathFor paths runtimeMode model =
  objectStoreRoot paths
    </> "artifacts"
    </> Text.unpack (runtimeModeId runtimeMode)
    </> Text.unpack (modelId model)
    </> "bundle.json"

sourceManifestPathFor :: Paths -> RuntimeMode -> ModelDescriptor -> FilePath
sourceManifestPathFor paths runtimeMode model =
  objectStoreRoot paths
    </> "source-artifacts"
    </> Text.unpack (runtimeModeId runtimeMode)
    </> Text.unpack (modelId model)
    </> "source.json"

cacheManifestPathFor :: Paths -> RuntimeMode -> ModelDescriptor -> FilePath
cacheManifestPathFor paths runtimeMode model =
  objectStoreRoot paths
    </> "manifests"
    </> Text.unpack (runtimeModeId runtimeMode)
    </> Text.unpack (modelId model)
    </> "default.pb"

engineInstallRootPath :: Paths -> EngineBinding -> FilePath
engineInstallRootPath paths engineBinding =
  dataRoot paths </> "engines" </> Text.unpack (engineBindingAdapterId engineBinding)
