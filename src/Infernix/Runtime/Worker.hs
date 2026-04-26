{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Infernix.Runtime.Worker
  ( engineCommandOverrideEnvironmentName,
    runInferenceWorker,
  )
where

import Control.Applicative ((<|>))
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString8
import Data.Char (isAlphaNum, toUpper)
import Data.List (dropWhileEnd, intercalate)
import Data.ProtoLens (decodeMessage, defMessage, encodeMessage)
import Data.ProtoLens.Field (field)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Config (Paths (..))
import Infernix.Models (engineBindingForSelectedEngine)
import Infernix.Types
import Lens.Family2 (set, view)
import Proto.Infernix.Runtime.Inference qualified as ProtoInference
import Proto.Infernix.Runtime.Inference_Fields qualified as ProtoInferenceFields
import System.Directory (doesFileExist, findExecutable)
import System.Environment (getEnvironment, lookupEnv)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath (isAbsolute, (</>))
import System.IO (hClose)
import System.Process
  ( CreateProcess (cwd, env, std_err, std_in, std_out),
    StdStream (CreatePipe),
    createProcess,
    proc,
    readProcessWithExitCode,
    shell,
    waitForProcess,
  )

data WorkerInvocation
  = DirectWorkerInvocation FilePath [String]
  | ShellWorkerInvocation String

runInferenceWorker :: Paths -> RuntimeMode -> ModelDescriptor -> InferenceRequest -> IO (Either ErrorResponse Text)
runInferenceWorker paths runtimeMode model request =
  let engineBinding = engineBindingForSelectedEngine (selectedEngine model)
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
  maybeAdapterScript <- resolvePythonAdapterScript paths engineBinding
  case trimWhitespace =<< maybeOverride of
    Just overrideCommand ->
      pure (ShellWorkerInvocation . (\adapterScript -> overrideCommand <> " " <> shellQuote adapterScript) <$> maybeAdapterScript)
    Nothing ->
      case maybeAdapterScript of
        Nothing -> pure Nothing
        Just adapterScript -> do
          let repoLocalPython = repoRoot paths </> "python" </> ".venv" </> "bin" </> "python"
          repoLocalPythonExists <- doesFileExist repoLocalPython
          maybePython <-
            if repoLocalPythonExists
              then pure (Just repoLocalPython)
              else do
                maybePoetryPython <- discoverPoetryPython paths
                case maybePoetryPython of
                  Just poetryPython -> pure (Just poetryPython)
                  Nothing -> findExecutable "python3" <|> findExecutable "python"
          pure (DirectWorkerInvocation <$> maybePython <*> pure [adapterScript])

resolvePythonAdapterScript :: Paths -> EngineBinding -> IO (Maybe FilePath)
resolvePythonAdapterScript paths engineBinding = do
  configuredExists <- doesFileExist configuredScriptPath
  pure (if configuredExists then Just configuredScriptPath else Nothing)
  where
    configuredScriptPath = resolveAdapterPath paths (Text.unpack (engineBindingAdapterLocator engineBinding))

resolveAdapterPath :: Paths -> FilePath -> FilePath
resolveAdapterPath paths adapterPath
  | isAbsolute adapterPath = adapterPath
  | otherwise = repoRoot paths </> adapterPath

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
workerProcessEnvironment paths = do
  upsertEnvironmentValue "PYTHONPATH" pythonPathValue <$> getEnvironment
  where
    pythonPathValue =
      intercalate
        ":"
        [ repoRoot paths </> "python" </> "adapters",
          repoRoot paths </> "tools" </> "generated_proto"
        ]

upsertEnvironmentValue :: String -> String -> [(String, String)] -> [(String, String)]
upsertEnvironmentValue key value environment =
  (key, mergedValue) : filter ((/= key) . fst) environment
  where
    mergedValue =
      case lookup key environment of
        Just existingValue
          | null existingValue -> value
          | otherwise -> value <> ":" <> existingValue
        Nothing -> value

discoverPoetryPython :: Paths -> IO (Maybe FilePath)
discoverPoetryPython paths = do
  maybePoetry <- findExecutable "poetry"
  case maybePoetry of
    Nothing -> pure Nothing
    Just poetryExecutable -> do
      (exitCode, stdoutOutput, _) <-
        readProcessWithExitCode
          poetryExecutable
          ["--directory", repoRoot paths </> "python", "env", "info", "--path"]
          ""
      case exitCode of
        ExitSuccess ->
          case trimWhitespace stdoutOutput of
            Nothing -> pure Nothing
            Just environmentRoot -> do
              let pythonBinary = environmentRoot </> "bin" </> "python"
              pythonExists <- doesFileExist pythonBinary
              pure (if pythonExists then Just pythonBinary else Nothing)
        _ -> pure Nothing

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
