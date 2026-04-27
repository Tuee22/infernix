{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Infernix.Runtime.Pulsar
  ( publishInferenceRequest,
    readPublishedInferenceResultMaybe,
    runProductionDaemon,
    schemaMarkerPath,
    topicDirectoryPath,
  )
where

import Control.Concurrent (threadDelay)
import Control.Monad (forM_, forever, unless)
import Data.ByteString qualified as ByteString
import Data.List (intercalate, sort)
import Data.Maybe (fromMaybe)
import Data.ProtoLens (decodeMessage, defMessage, encodeMessage)
import Data.ProtoLens.Field (field)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Infernix.Config
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Runtime (executeInference)
import Infernix.Types
import Lens.Family2 (set, view)
import Proto.Infernix.Runtime.Inference qualified as ProtoInference
import Proto.Infernix.Runtime.Inference_Fields qualified as ProtoInferenceFields
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    listDirectory,
    removeFile,
  )
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory, (<.>), (</>))

runProductionDaemon :: Paths -> RuntimeMode -> IO ()
runProductionDaemon paths runtimeMode = do
  maybeControlPlaneOverride <- lookupEnv "INFERNIX_CONTROL_PLANE_CONTEXT"
  maybeDaemonLocationOverride <- lookupEnv "INFERNIX_DAEMON_LOCATION"
  maybeCatalogSourceOverride <- lookupEnv "INFERNIX_CATALOG_SOURCE"
  maybeDemoConfigOverride <- lookupEnv "INFERNIX_DEMO_CONFIG_PATH"
  let controlPlane = fromMaybe (controlPlaneContext paths) maybeControlPlaneOverride
      daemonLocation =
        fromMaybe
          ( if controlPlane == "host-native"
              then "control-plane-host"
              else "cluster-pod"
          )
          maybeDaemonLocationOverride
      catalogSource =
        fromMaybe
          ( case maybeDemoConfigOverride of
              Just _ -> "env-config-override"
              Nothing -> "generated-build-root"
          )
          maybeCatalogSourceOverride
      selectedDemoConfigPath =
        fromMaybe (Infernix.Config.generatedDemoConfigPath paths runtimeMode) maybeDemoConfigOverride
  demoConfig <- decodeDemoConfigFile selectedDemoConfigPath
  ensureSchemaMarkers paths demoConfig
  putStrLn ("serviceControlPlaneContext: " <> controlPlane)
  putStrLn ("serviceDaemonLocation: " <> daemonLocation)
  putStrLn ("serviceCatalogSource: " <> catalogSource)
  putStrLn ("serviceRuntimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("serviceDemoConfigPath: " <> selectedDemoConfigPath)
  putStrLn ("serviceMountedDemoConfigPath: " <> watchedDemoConfigPath runtimeMode)
  putStrLn ("serviceRequestTopics: " <> intercalate "," (map Text.unpack (requestTopics demoConfig)))
  putStrLn ("serviceResultTopic: " <> Text.unpack (resultTopic demoConfig))
  putStrLn ("serviceEngineBindingCount: " <> show (length (engines demoConfig)))
  putStrLn "serviceSubscriptionMode: filesystem-pulsar-simulation"
  putStrLn "serviceHttpListener: disabled"
  forever $ do
    forM_ (requestTopics demoConfig) (drainTopic paths runtimeMode (resultTopic demoConfig))
    threadDelay 500000

publishInferenceRequest :: Paths -> RuntimeMode -> Text.Text -> InferenceRequest -> IO FilePath
publishInferenceRequest paths runtimeMode topic requestValue = do
  createDirectoryIfMissing True (topicDirectoryPath paths topic)
  let requestIdValue = requestModelId requestValue <> "-request"
      outputPath = topicDirectoryPath paths topic </> Text.unpack requestIdValue <.> "pb"
      protoPayload =
        set (field @"requestId") requestIdValue $
          set (field @"requestModelId") (requestModelId requestValue) $
            set (field @"inputText") (inputText requestValue) $
              set (field @"runtimeMode") (runtimeModeId runtimeMode) defMessage
  writeInferenceRequestFile outputPath protoPayload
  pure outputPath

readPublishedInferenceResultMaybe :: Paths -> Text.Text -> Text.Text -> IO (Maybe InferenceResult)
readPublishedInferenceResultMaybe paths topic requestIdValue = do
  let outputPath = topicDirectoryPath paths topic </> Text.unpack requestIdValue <.> "pb"
  exists <- doesFileExist outputPath
  if not exists
    then pure Nothing
    else do
      encoded <- readFileBytes outputPath
      case decodeMessage encoded of
        Left err ->
          ioError (userError ("failed to decode inference result from " <> outputPath <> ": " <> err))
        Right protoResult ->
          pure (protoResultToDomain protoResult)

drainTopic :: Paths -> RuntimeMode -> Text.Text -> Text.Text -> IO ()
drainTopic paths runtimeMode resultTopicValue requestTopicValue = do
  let requestDirectory = topicDirectoryPath paths requestTopicValue
  requestDirectoryPresent <- doesDirectoryExist requestDirectory
  unless requestDirectoryPresent (createDirectoryIfMissing True requestDirectory)
  requestFiles <- sort <$> listDirectory requestDirectory
  forM_ (filter (".pb" `endsWith`) requestFiles) $ \requestFile -> do
    let requestPath = requestDirectory </> requestFile
    encodedRequest <- readFileBytes requestPath
    case decodeMessage encodedRequest of
      Left err ->
        ioError (userError ("failed to decode inference request from " <> requestPath <> ": " <> err))
      Right protoRequest -> do
        domainResult <- executeInference paths runtimeMode (protoRequestToDomain protoRequest)
        now <- getCurrentTime
        let publishedResult =
              case domainResult of
                Right resultValue ->
                  resultValue
                    { requestId = view ProtoInferenceFields.requestId protoRequest
                    }
                Left errorValue ->
                  InferenceResult
                    { requestId = view ProtoInferenceFields.requestId protoRequest,
                      resultModelId = view ProtoInferenceFields.requestModelId protoRequest,
                      resultMatrixRowId = "",
                      resultRuntimeMode = runtimeMode,
                      resultSelectedEngine = "",
                      status = "failed",
                      payload = ResultPayload {inlineOutput = Just (message errorValue), objectRef = Nothing},
                      createdAt = now
                    }
        createDirectoryIfMissing True (topicDirectoryPath paths resultTopicValue)
        writeInferenceResultFile
          (topicDirectoryPath paths resultTopicValue </> Text.unpack (requestId publishedResult) <.> "pb")
          (domainResultToProto publishedResult)
        removeFile requestPath

ensureSchemaMarkers :: Paths -> DemoConfig -> IO ()
ensureSchemaMarkers paths demoConfig = do
  let topics = requestTopics demoConfig <> [resultTopic demoConfig]
  forM_ topics $ \topicValue -> do
    createDirectoryIfMissing True (topicDirectoryPath paths topicValue)
    createDirectoryIfMissing True (takeDirectory (schemaMarkerPath paths topicValue))
    writeFile
      (schemaMarkerPath paths topicValue)
      (unlines ["schema: protobuf", "topic: " <> Text.unpack topicValue])

schemaMarkerPath :: Paths -> Text.Text -> FilePath
schemaMarkerPath paths topicValue =
  runtimeRoot paths </> "pulsar" </> "schemas" </> sanitizeTopic topicValue <.> "schema"

topicDirectoryPath :: Paths -> Text.Text -> FilePath
topicDirectoryPath paths topicValue =
  runtimeRoot paths </> "pulsar" </> "topics" </> sanitizeTopic topicValue

sanitizeTopic :: Text.Text -> FilePath
sanitizeTopic =
  map replaceSeparator . Text.unpack
  where
    replaceSeparator '/' = '_'
    replaceSeparator ':' = '_'
    replaceSeparator '.' = '_'
    replaceSeparator character = character

protoRequestToDomain :: ProtoInference.InferenceRequest -> InferenceRequest
protoRequestToDomain protoRequest =
  InferenceRequest
    { requestModelId = view ProtoInferenceFields.requestModelId protoRequest,
      inputText = view ProtoInferenceFields.inputText protoRequest
    }

domainResultToProto :: InferenceResult -> ProtoInference.InferenceResult
domainResultToProto resultValue =
  set (field @"requestId") (requestId resultValue) $
    set (field @"resultModelId") (resultModelId resultValue) $
      set (field @"matrixRowId") (resultMatrixRowId resultValue) $
        set (field @"runtimeMode") (runtimeModeId (resultRuntimeMode resultValue)) $
          set (field @"selectedEngine") (resultSelectedEngine resultValue) $
            set (field @"status") (status resultValue) $
              set (field @"payload") (resultPayloadToProto (payload resultValue)) $
                set (field @"createdAt") (Text.pack (show (createdAt resultValue))) defMessage

protoResultToDomain :: ProtoInference.InferenceResult -> Maybe InferenceResult
protoResultToDomain protoResult = do
  parsedRuntimeMode <- parseRuntimeMode (view ProtoInferenceFields.runtimeMode protoResult)
  parsedPayload <- protoPayloadToDomain (view ProtoInferenceFields.payload protoResult)
  pure
    InferenceResult
      { requestId = view ProtoInferenceFields.requestId protoResult,
        resultModelId = view ProtoInferenceFields.resultModelId protoResult,
        resultMatrixRowId = view ProtoInferenceFields.matrixRowId protoResult,
        resultRuntimeMode = parsedRuntimeMode,
        resultSelectedEngine = view ProtoInferenceFields.selectedEngine protoResult,
        status = view ProtoInferenceFields.status protoResult,
        payload = parsedPayload,
        createdAt = read (Text.unpack (view ProtoInferenceFields.createdAt protoResult))
      }

resultPayloadToProto :: ResultPayload -> ProtoInference.ResultPayload
resultPayloadToProto payloadValue =
  case objectRef payloadValue of
    Just objectRefValue -> set (field @"objectRef") objectRefValue defMessage
    Nothing -> set (field @"inlineOutput") (fromMaybe "" (inlineOutput payloadValue)) defMessage

protoPayloadToDomain :: ProtoInference.ResultPayload -> Maybe ResultPayload
protoPayloadToDomain protoPayload =
  case view ProtoInferenceFields.maybe'output protoPayload of
    Just (ProtoInference.ResultPayload'InlineOutput inlineOutputValue) ->
      Just (ResultPayload {inlineOutput = Just inlineOutputValue, objectRef = Nothing})
    Just (ProtoInference.ResultPayload'ObjectRef objectRefValue) ->
      Just (ResultPayload {inlineOutput = Nothing, objectRef = Just objectRefValue})
    Nothing ->
      Just (ResultPayload {inlineOutput = Just "", objectRef = Nothing})

writeInferenceRequestFile :: FilePath -> ProtoInference.InferenceRequest -> IO ()
writeInferenceRequestFile filePath value = do
  createDirectoryIfMissing True (takeDirectory filePath)
  writeFileBytes filePath (encodeMessage value)

writeInferenceResultFile :: FilePath -> ProtoInference.InferenceResult -> IO ()
writeInferenceResultFile filePath value = do
  createDirectoryIfMissing True (takeDirectory filePath)
  writeFileBytes filePath (encodeMessage value)

readFileBytes :: FilePath -> IO ByteString.ByteString
readFileBytes = ByteString.readFile

writeFileBytes :: FilePath -> ByteString.ByteString -> IO ()
writeFileBytes = ByteString.writeFile

endsWith :: String -> String -> Bool
endsWith suffix value = reverse suffix `startsWith` reverse value

startsWith :: String -> String -> Bool
startsWith [] _ = True
startsWith _ [] = False
startsWith (expected : expectedRest) (actual : actualRest) =
  expected == actual && startsWith expectedRest actualRest
