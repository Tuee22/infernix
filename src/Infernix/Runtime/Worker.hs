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
import Infernix.Python (ensurePoetryProjectReady)
import Infernix.Types
import Lens.Family2 (set, view)
import Proto.Infernix.Runtime.Inference qualified as ProtoInference
import Proto.Infernix.Runtime.Inference_Fields qualified as ProtoInferenceFields
import System.Directory (findExecutable)
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
  = DirectWorkerInvocation FilePath [String]
  | ShellWorkerInvocation String

runInferenceWorker :: Paths -> RuntimeMode -> ModelDescriptor -> InferenceRequest -> IO (Either ErrorResponse Text)
runInferenceWorker paths runtimeMode model request =
  let engineBinding = engineBindingForSelectedEngine runtimeMode (selectedEngine model)
      fallbackOutput = renderInferenceOutput model request
   in case engineBindingAdapterType engineBinding of
        "python-stdio" ->
          runPythonWorker paths runtimeMode model engineBinding request fallbackOutput
        _ ->
          pure (Right fallbackOutput)

engineCommandOverrideEnvironmentName :: EngineBinding -> String
engineCommandOverrideEnvironmentName engineBinding =
  "INFERNIX_ENGINE_COMMAND_" <> map normalize (Text.unpack (engineBindingAdapterId engineBinding))
  where
    normalize character
      | isAlphaNum character = toUpper character
      | otherwise = '_'

runPythonWorker :: Paths -> RuntimeMode -> ModelDescriptor -> EngineBinding -> InferenceRequest -> Text -> IO (Either ErrorResponse Text)
runPythonWorker paths runtimeMode model engineBinding request fallbackOutput = do
  maybeOverride <- lookupEnv (engineCommandOverrideEnvironmentName engineBinding)
  maybeInvocation <- resolvePythonInvocation paths engineBinding maybeOverride
  case maybeInvocation of
    Nothing ->
      pure (Right fallbackOutput)
    Just invocation -> do
      let workerRequest = encodeMessage (buildWorkerRequest runtimeMode model engineBinding request)
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

resolvePythonInvocation :: Paths -> EngineBinding -> Maybe String -> IO (Maybe WorkerInvocation)
resolvePythonInvocation paths engineBinding maybeOverride = do
  let projectDirectory = repoRoot paths </> engineBindingProjectDirectory engineBinding
  case trimWhitespace =<< maybeOverride of
    Just overrideCommand ->
      withPoetryExecutable $ \poetryExecutable -> do
        ensurePoetryProjectReady paths projectDirectory
        pure
          ( Just
              ( ShellWorkerInvocation
                  ( overrideCommand
                      <> " "
                      <> shellQuote poetryExecutable
                      <> " --directory "
                      <> shellQuote projectDirectory
                      <> " run "
                      <> shellQuote (Text.unpack (engineBindingAdapterEntrypoint engineBinding))
                  )
              )
          )
    Nothing ->
      withPoetryExecutable $ \poetryExecutable -> do
        ensurePoetryProjectReady paths projectDirectory
        pure
          ( Just
              ( DirectWorkerInvocation
                  poetryExecutable
                  [ "--directory",
                    projectDirectory,
                    "run",
                    Text.unpack (engineBindingAdapterEntrypoint engineBinding)
                  ]
              )
          )
  where
    withPoetryExecutable action = do
      maybePoetry <- findExecutable "poetry"
      case maybePoetry of
        Just poetryExecutable -> action poetryExecutable
        Nothing -> pure Nothing

runWorkerInvocation :: Paths -> WorkerInvocation -> ByteString.ByteString -> IO (Either String ByteString.ByteString)
runWorkerInvocation paths invocation inputPayload = do
  processEnvironment <- workerProcessEnvironment paths
  let processValue = (processFor invocation) {env = Just processEnvironment}
  (maybeWorkerInput, maybeWorkerOutput, maybeWorkerError, workerHandle) <-
    createProcess
      processValue
        { cwd = Just (repoRoot paths),
          std_in = CreatePipe,
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
    DirectWorkerInvocation command args -> proc command args
    ShellWorkerInvocation command -> shell command

workerProcessEnvironment :: Paths -> IO [(String, String)]
workerProcessEnvironment paths =
  pure
    [ ("POETRY_VIRTUALENVS_IN_PROJECT", "true"),
      ("INFERNIX_REPO_ROOT", repoRoot paths)
    ]

describeInvocation :: WorkerInvocation -> String
describeInvocation invocation =
  case invocation of
    DirectWorkerInvocation command args -> unwords (command : args)
    ShellWorkerInvocation command -> command

stderrSuffix :: ByteString.ByteString -> String
stderrSuffix stderrOutput =
  case trimWhitespace (ByteString8.unpack stderrOutput) of
    Just message -> "\n" <> message
    Nothing -> ""

buildWorkerRequest :: RuntimeMode -> ModelDescriptor -> EngineBinding -> InferenceRequest -> ProtoInference.WorkerRequest
buildWorkerRequest runtimeMode model engineBinding request =
  set (field @"requestModelId") (requestModelId request) $
    set (field @"inputText") (inputText request) $
      set (field @"runtimeMode") (runtimeModeId runtimeMode) $
        set (field @"selectedEngine") (selectedEngine model) $
          set (field @"adapterId") (engineBindingAdapterId engineBinding) defMessage

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

renderInferenceOutput :: ModelDescriptor -> InferenceRequest -> Text
renderInferenceOutput model requestValue =
  Text.unlines
    [ "model=" <> modelId model,
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
