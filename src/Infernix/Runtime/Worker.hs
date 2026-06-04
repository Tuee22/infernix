{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Infernix.Runtime.Worker
  ( EngineCommandOverrideMap,
    lookupEngineCommandOverride,
    runInferenceWorker,
  )
where

import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString8
import Data.List (dropWhileEnd, find)
import Data.ProtoLens (decodeMessage, defMessage, encodeMessage)
import Data.ProtoLens.Field (field)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Config (Paths (..))
import Infernix.Conversation.Hash (PrefixHash (..))
import Infernix.Models (engineBindingForSelectedEngine)
import Infernix.Python (ensurePoetryExecutable, ensurePoetryProjectReady)
import Infernix.Runtime.KVCache qualified as KVCache
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
      runNativeWorker runtimeMode model engineBinding request cacheObservation
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
  let workerRequest = encodeMessage (buildWorkerRequest paths runtimeMode model engineBinding request)
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

runNativeWorker :: RuntimeMode -> ModelDescriptor -> EngineBinding -> InferenceRequest -> Maybe KVCache.KVCacheObservation -> IO (Either ErrorResponse Text)
runNativeWorker runtimeMode model engineBinding request cacheObservation =
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
                cacheObservation
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

buildWorkerRequest :: Paths -> RuntimeMode -> ModelDescriptor -> EngineBinding -> InferenceRequest -> ProtoInference.WorkerRequest
buildWorkerRequest paths runtimeMode model engineBinding request =
  set (field @"requestModelId") (requestModelId request) $
    set (field @"inputText") (inputText request) $
      set (field @"runtimeMode") (runtimeModeId runtimeMode) $
        set (field @"selectedEngine") (selectedEngine model) $
          set (field @"adapterId") (engineBindingAdapterId engineBinding) $
            set (field @"displayName") (displayName model) $
              set (field @"family") (family model) $
                set (field @"artifactType") (artifactType model) $
                  set (field @"runtimeLane") (runtimeLaneId (runtimeLane model)) $
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

renderNativeRunnerOutput :: RuntimeMode -> ModelDescriptor -> InferenceRequest -> Text -> Text -> Maybe KVCache.KVCacheObservation -> Text
renderNativeRunnerOutput runtimeMode model requestValue adapterId runnerLabel cacheObservation =
  Text.unlines
    ( [ "adapter=" <> adapterId,
        "runner=" <> runnerLabel,
        "runtime=" <> runtimeModeId runtimeMode,
        "model=" <> modelId model,
        "engine=" <> selectedEngine model,
        "family=" <> family model,
        "input=" <> inputText requestValue
      ]
        <> nativeKvCacheLines cacheObservation
    )

nativeKvCacheLines :: Maybe KVCache.KVCacheObservation -> [Text]
nativeKvCacheLines Nothing = []
nativeKvCacheLines (Just observation) =
  let decision = KVCache.kvCacheObservationDecision observation
      PrefixHash prefixHash = KVCache.kvCacheRequestPrefixHash (KVCache.kvCacheObservationRequest observation)
   in [ "kv-cache=" <> KVCache.kvCacheDecisionLabel decision,
        "kv-prefix-hash=" <> prefixHash
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

engineInstallRootPath :: Paths -> EngineBinding -> FilePath
engineInstallRootPath paths engineBinding =
  dataRoot paths </> "engines" </> Text.unpack (engineBindingAdapterId engineBinding)
