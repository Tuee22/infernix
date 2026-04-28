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

import Control.Concurrent (forkIO, threadDelay)
import Control.Exception (SomeException, displayException, try)
import Control.Monad (forM_, forever, unless, when)
import Data.Aeson
  ( FromJSON (parseJSON),
    Value,
    eitherDecodeStrict',
    encode,
    object,
    withObject,
    (.:),
    (.:?),
    (.=),
  )
import Data.ByteString qualified as ByteString
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy qualified as Lazy
import Data.List (intercalate, sort)
import Data.Maybe (fromMaybe)
import Data.ProtoLens (Message, decodeMessage, defMessage, encodeMessage)
import Data.ProtoLens.Field (field)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time (getCurrentTime)
import Infernix.Config
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Runtime (executeInference)
import Infernix.Types
import Lens.Family2 (set, view)
import Network.HTTP.Client
  ( Manager,
    RequestBody (RequestBodyLBS),
    defaultManagerSettings,
    httpLbs,
    method,
    newManager,
    parseRequest,
    requestBody,
    requestHeaders,
    responseBody,
    responseStatus,
  )
import Network.HTTP.Types.Status (statusCode)
import Network.WebSockets qualified as WebSockets
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
import System.IO (hPutStrLn, stderr)
import System.Timeout (timeout)

data PulsarTransport = PulsarTransport
  { pulsarAdminBaseUrl :: Maybe String,
    pulsarWebSocketBase :: PulsarWebSocketBase
  }

data PulsarWebSocketBase = PulsarWebSocketBase
  { pulsarWsHost :: String,
    pulsarWsPort :: Int,
    pulsarWsPathPrefix :: String
  }

data TopicRef = TopicRef
  { topicDomain :: Text.Text,
    topicTenant :: Text.Text,
    topicNamespace :: Text.Text,
    topicName :: Text.Text
  }

data ProducerResponse = ProducerResponse
  { producerResult :: Text.Text,
    producerErrorMessage :: Maybe Text.Text
  }

data PulsarEnvelope = PulsarEnvelope
  { envelopeMessageId :: Text.Text,
    envelopePayload :: Text.Text
  }

instance FromJSON ProducerResponse where
  parseJSON = withObject "ProducerResponse" $ \value ->
    ProducerResponse
      <$> value .: "result"
      <*> value .:? "errorMsg"

instance FromJSON PulsarEnvelope where
  parseJSON = withObject "PulsarEnvelope" $ \value ->
    PulsarEnvelope
      <$> value .: "messageId"
      <*> value .: "payload"

runProductionDaemon :: Paths -> RuntimeMode -> IO ()
runProductionDaemon paths runtimeMode = do
  maybeControlPlaneOverride <- lookupEnv "INFERNIX_CONTROL_PLANE_CONTEXT"
  maybeDaemonLocationOverride <- lookupEnv "INFERNIX_DAEMON_LOCATION"
  maybeCatalogSourceOverride <- lookupEnv "INFERNIX_CATALOG_SOURCE"
  maybeDemoConfigOverride <- lookupEnv "INFERNIX_DEMO_CONFIG_PATH"
  maybeTransport <- discoverPulsarTransport
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
  putStrLn ("serviceControlPlaneContext: " <> controlPlane)
  putStrLn ("serviceDaemonLocation: " <> daemonLocation)
  putStrLn ("serviceCatalogSource: " <> catalogSource)
  putStrLn ("serviceRuntimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("serviceDemoConfigPath: " <> selectedDemoConfigPath)
  putStrLn ("serviceMountedDemoConfigPath: " <> watchedDemoConfigPath runtimeMode)
  putStrLn ("serviceRequestTopics: " <> intercalate "," (map Text.unpack (requestTopics demoConfig)))
  putStrLn ("serviceResultTopic: " <> Text.unpack (resultTopic demoConfig))
  putStrLn ("serviceEngineBindingCount: " <> show (length (engines demoConfig)))
  putStrLn "serviceHttpListener: disabled"
  clearServiceReadinessMarker paths
  case maybeTransport of
    Nothing -> do
      ensureSchemaMarkers paths demoConfig
      writeServiceReadinessMarker paths
      putStrLn "serviceSubscriptionMode: filesystem-pulsar-simulation"
      forever $ do
        forM_ (requestTopics demoConfig) (drainTopic paths runtimeMode (resultTopic demoConfig))
        threadDelay 500000
    Just transport -> do
      ensureSchemaMarkers paths demoConfig
      ensureRegisteredSchemasWithRetry paths transport demoConfig
      writeServiceReadinessMarker paths
      putStrLn "serviceSubscriptionMode: websocket-pulsar"
      putStrLn ("servicePulsarWsBaseUrl: " <> renderPulsarWebSocketBase (pulsarWebSocketBase transport))
      forM_
        (requestTopics demoConfig)
        (forkIO . consumeTopicForever transport paths runtimeMode (resultTopic demoConfig))
      forever (threadDelay 60000000)

publishInferenceRequest :: Paths -> RuntimeMode -> Text.Text -> InferenceRequest -> IO FilePath
publishInferenceRequest paths runtimeMode topic requestValue = do
  maybeTransport <- discoverPulsarTransport
  let requestIdValue = requestModelId requestValue <> "-request"
      protoPayload =
        set (field @"requestId") requestIdValue $
          set (field @"requestModelId") (requestModelId requestValue) $
            set (field @"inputText") (inputText requestValue) $
              set (field @"runtimeMode") (runtimeModeId runtimeMode) defMessage
  case maybeTransport of
    Nothing -> do
      createDirectoryIfMissing True (topicDirectoryPath paths topic)
      let outputPath = topicDirectoryPath paths topic </> Text.unpack requestIdValue <.> "pb"
      writeInferenceRequestFile outputPath protoPayload
      pure outputPath
    Just transport -> do
      publishTopicPayload transport topic requestIdValue (encodeMessage protoPayload)
      pure ("pulsar://" <> Text.unpack topic <> "/" <> Text.unpack requestIdValue)

readPublishedInferenceResultMaybe :: Paths -> Text.Text -> Text.Text -> IO (Maybe InferenceResult)
readPublishedInferenceResultMaybe paths topic requestIdValue = do
  maybeTransport <- discoverPulsarTransport
  case maybeTransport of
    Nothing -> do
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
    Just transport ->
      readPublishedInferenceResultViaPulsar transport topic requestIdValue

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
        publishedResult <- publishedResultFromRequest paths runtimeMode protoRequest
        createDirectoryIfMissing True (topicDirectoryPath paths resultTopicValue)
        writeInferenceResultFile
          (topicDirectoryPath paths resultTopicValue </> Text.unpack (requestId publishedResult) <.> "pb")
          (domainResultToProto publishedResult)
        removeFile requestPath

ensureSchemaMarkers :: Paths -> DemoConfig -> IO ()
ensureSchemaMarkers paths demoConfig = do
  let topics = requestTopics demoConfig <> [resultTopic demoConfig]
  forM_ topics writeSchemaMarker
  where
    writeSchemaMarker topicValue = do
      createDirectoryIfMissing True (topicDirectoryPath paths topicValue)
      createDirectoryIfMissing True (takeDirectory (schemaMarkerPath paths topicValue))
      writeFile
        (schemaMarkerPath paths topicValue)
        (unlines ["schema: protobuf", "topic: " <> Text.unpack topicValue])

serviceReadinessMarkerPath :: Paths -> FilePath
serviceReadinessMarkerPath paths =
  runtimeRoot paths </> "service" </> "subscription.ready"

clearServiceReadinessMarker :: Paths -> IO ()
clearServiceReadinessMarker paths = do
  let markerPath = serviceReadinessMarkerPath paths
  markerPresent <- doesFileExist markerPath
  when markerPresent (removeFile markerPath)

writeServiceReadinessMarker :: Paths -> IO ()
writeServiceReadinessMarker paths = do
  let markerPath = serviceReadinessMarkerPath paths
  createDirectoryIfMissing True (takeDirectory markerPath)
  writeFile markerPath "ready\n"

schemaMarkerPath :: Paths -> Text.Text -> FilePath
schemaMarkerPath paths topicValue =
  runtimeRoot paths </> "pulsar" </> "schemas" </> sanitizeTopic topicValue <.> "schema"

topicDirectoryPath :: Paths -> Text.Text -> FilePath
topicDirectoryPath paths topicValue =
  runtimeRoot paths </> "pulsar" </> "topics" </> sanitizeTopic topicValue

discoverPulsarTransport :: IO (Maybe PulsarTransport)
discoverPulsarTransport = do
  maybeWebSocketBase <- lookupEnv "INFERNIX_PULSAR_WS_BASE_URL"
  maybeAdminBase <- lookupEnv "INFERNIX_PULSAR_ADMIN_URL"
  case trimWhitespace =<< maybeWebSocketBase of
    Nothing -> pure Nothing
    Just rawWebSocketBase ->
      case parsePulsarWebSocketBase rawWebSocketBase of
        Left err ->
          ioError (userError ("invalid INFERNIX_PULSAR_WS_BASE_URL: " <> err))
        Right parsedWebSocketBase ->
          pure
            ( Just
                PulsarTransport
                  { pulsarAdminBaseUrl = trimWhitespace =<< maybeAdminBase,
                    pulsarWebSocketBase = parsedWebSocketBase
                  }
            )

ensureRegisteredSchemas :: Paths -> PulsarTransport -> DemoConfig -> IO ()
ensureRegisteredSchemas paths transport demoConfig = do
  ensureSchemaMarkers paths demoConfig
  adminBaseUrl <- requirePulsarAdminBaseUrl transport
  manager <- newManager defaultManagerSettings
  forM_ (requestTopics demoConfig) $ \topicValue ->
    ensureRemoteSchema manager adminBaseUrl topicValue "infernix.runtime.InferenceRequest"
  ensureRemoteSchema manager adminBaseUrl (resultTopic demoConfig) "infernix.runtime.InferenceResult"

ensureRegisteredSchemasWithRetry :: Paths -> PulsarTransport -> DemoConfig -> IO ()
ensureRegisteredSchemasWithRetry paths transport demoConfig =
  retry (1 :: Int)
  where
    retry attempt = do
      registrationResult <- try @SomeException (ensureRegisteredSchemas paths transport demoConfig)
      case registrationResult of
        Right _ -> pure ()
        Left err -> do
          hPutStrLn
            stderr
            ( "pulsar schema registration attempt "
                <> show attempt
                <> " failed:\n"
                <> displayException err
            )
          threadDelay 1000000
          retry (attempt + 1)

requirePulsarAdminBaseUrl :: PulsarTransport -> IO String
requirePulsarAdminBaseUrl transport =
  case pulsarAdminBaseUrl transport of
    Just adminBaseUrl -> pure adminBaseUrl
    Nothing ->
      ioError
        ( userError
            "INFERNIX_PULSAR_ADMIN_URL must be set whenever INFERNIX_PULSAR_WS_BASE_URL enables the real Pulsar transport."
        )

ensureRemoteSchema :: Manager -> String -> Text.Text -> String -> IO ()
ensureRemoteSchema manager adminBaseUrl topicValue messageTypeName = do
  topicRef <- requireTopicRef topicValue
  requestValue <- parseRequest (schemaUrl adminBaseUrl topicRef)
  existingResponse <- httpLbs requestValue manager
  case statusCode (responseStatus existingResponse) of
    200 -> pure ()
    404 -> createSchema requestValue
    code ->
      ioError
        ( userError
            ( "unexpected Pulsar schema response for "
                <> Text.unpack topicValue
                <> " (status "
                <> show code
                <> "):\n"
                <> lazyBodyToString (responseBody existingResponse)
            )
        )
  where
    createSchema requestValue = do
      let schemaPayload =
            encode $
              object
                [ "type" .= ("BYTES" :: String),
                  "schema" .= ("" :: String),
                  "properties"
                    .= object
                      [ "contentType" .= ("application/protobuf" :: String),
                        "messageType" .= messageTypeName
                      ]
                ]
          createRequest =
            requestValue
              { method = "POST",
                requestHeaders = [("Content-Type", "application/json")],
                requestBody = RequestBodyLBS schemaPayload
              }
      createResponse <- httpLbs createRequest manager
      let code = statusCode (responseStatus createResponse)
      unless (code `elem` [200, 201, 204, 409]) $
        ioError
          ( userError
              ( "failed to register Pulsar schema for "
                  <> Text.unpack topicValue
                  <> " (status "
                  <> show code
                  <> "):\n"
                  <> lazyBodyToString (responseBody createResponse)
              )
          )

consumeTopicForever :: PulsarTransport -> Paths -> RuntimeMode -> Text.Text -> Text.Text -> IO ()
consumeTopicForever transport paths runtimeMode resultTopicValue requestTopicValue =
  forever $ do
    sessionResult <- try @SomeException (consumeTopicSession transport paths runtimeMode resultTopicValue requestTopicValue)
    case sessionResult of
      Right _ -> threadDelay 1000000
      Left err -> do
        hPutStrLn
          stderr
          ( "pulsar consumer loop failed for "
              <> Text.unpack requestTopicValue
              <> ":\n"
              <> displayException err
          )
        threadDelay 1000000

consumeTopicSession :: PulsarTransport -> Paths -> RuntimeMode -> Text.Text -> Text.Text -> IO ()
consumeTopicSession transport paths runtimeMode resultTopicValue requestTopicValue = do
  topicRef <- requireTopicRef requestTopicValue
  let subscriptionName = "infernix-service-" <> sanitizeTopic requestTopicValue
      consumerName = subscriptionName <> "-consumer"
      consumerPath =
        buildConsumerSocketPath
          (pulsarWebSocketBase transport)
          topicRef
          subscriptionName
          consumerName
  runPulsarWebSocketClient (pulsarWebSocketBase transport) consumerPath $ \connection ->
    forever $ do
      rawEnvelope <- receiveJsonFrame "Pulsar consumer message" connection
      envelope <- decodeJsonText "Pulsar consumer message" rawEnvelope
      handled <- try @SomeException (handleConsumerEnvelope connection envelope)
      case handled of
        Right _ -> pure ()
        Left err -> do
          sendNegativeAck connection (envelopeMessageId envelope)
          hPutStrLn
            stderr
            ( "pulsar message handling failed for "
                <> Text.unpack requestTopicValue
                <> ":\n"
                <> displayException err
            )
  where
    handleConsumerEnvelope connection envelope = do
      decodedRequest <- decodeEnvelopePayload "inference request" envelope
      publishedResult <- publishedResultFromRequest paths runtimeMode decodedRequest
      publishTopicPayload
        transport
        resultTopicValue
        (requestId publishedResult)
        (encodeMessage (domainResultToProto publishedResult))
      sendAck connection (envelopeMessageId envelope)

publishTopicPayload :: PulsarTransport -> Text.Text -> Text.Text -> ByteString.ByteString -> IO ()
publishTopicPayload transport topicValue contextValue payload = do
  topicRef <- requireTopicRef topicValue
  let producerPath = buildProducerSocketPath (pulsarWebSocketBase transport) topicRef
      producerPayload =
        object
          [ "payload" .= TextEncoding.decodeUtf8 (Base64.encode payload),
            "context" .= contextValue
          ]
  runPulsarWebSocketClient (pulsarWebSocketBase transport) producerPath $ \connection -> do
    sendJsonFrame connection producerPayload
    rawResponse <- receiveJsonFrame "Pulsar producer response" connection
    producerResponse <- decodeJsonText "Pulsar producer response" rawResponse
    when (producerResult producerResponse /= "ok") $
      ioError
        ( userError
            ( "failed to publish Pulsar message for "
                <> Text.unpack topicValue
                <> ":\n"
                <> Text.unpack (fromMaybe "unknown producer error" (producerErrorMessage producerResponse))
            )
        )

readPublishedInferenceResultViaPulsar :: PulsarTransport -> Text.Text -> Text.Text -> IO (Maybe InferenceResult)
readPublishedInferenceResultViaPulsar transport topicValue wantedRequestId = do
  topicRef <- requireTopicRef topicValue
  let readerName = "infernix-read-" <> sanitizeTopic wantedRequestId
      readerPath = buildReaderSocketPath (pulsarWebSocketBase transport) topicRef readerName
  runPulsarWebSocketClient (pulsarWebSocketBase transport) readerPath $ \connection ->
    readMatchingResult connection (100 :: Int)
  where
    readMatchingResult _ remainingMessages
      | remainingMessages <= 0 = pure Nothing
    readMatchingResult connection remainingMessages = do
      maybeRawEnvelope <- timeout 200000 (receiveJsonFrame "Pulsar reader message" connection)
      case maybeRawEnvelope of
        Nothing -> pure Nothing
        Just rawEnvelope -> do
          envelope <- decodeJsonText "Pulsar reader message" rawEnvelope
          sendAck connection (envelopeMessageId envelope)
          protoResult <- decodeEnvelopePayload "inference result" envelope
          case protoResultToDomain protoResult of
            Just resultValue
              | requestId resultValue == wantedRequestId ->
                  pure (Just resultValue)
            _ ->
              readMatchingResult connection (remainingMessages - 1)

publishedResultFromRequest :: Paths -> RuntimeMode -> ProtoInference.InferenceRequest -> IO InferenceResult
publishedResultFromRequest paths runtimeMode protoRequest = do
  domainResult <- executeInference paths runtimeMode (protoRequestToDomain protoRequest)
  now <- getCurrentTime
  pure $
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

decodeEnvelopePayload :: (Message a) => String -> PulsarEnvelope -> IO a
decodeEnvelopePayload payloadLabel envelope = do
  encodedPayload <-
    either
      ( \err ->
          ioError
            ( userError
                ( "failed to decode base64 "
                    <> payloadLabel
                    <> " payload for message "
                    <> Text.unpack (envelopeMessageId envelope)
                    <> ":\n"
                    <> err
                )
            )
      )
      pure
      (Base64.decode (TextEncoding.encodeUtf8 (envelopePayload envelope)))
  case decodeMessage encodedPayload of
    Left err ->
      ioError
        ( userError
            ( "failed to decode protobuf "
                <> payloadLabel
                <> " payload for message "
                <> Text.unpack (envelopeMessageId envelope)
                <> ":\n"
                <> err
            )
        )
    Right decodedValue -> pure decodedValue

sendAck :: WebSockets.Connection -> Text.Text -> IO ()
sendAck connection messageIdValue =
  sendJsonFrame connection (object ["messageId" .= messageIdValue])

sendNegativeAck :: WebSockets.Connection -> Text.Text -> IO ()
sendNegativeAck connection messageIdValue =
  sendJsonFrame
    connection
    ( object
        [ "type" .= ("negativeAcknowledge" :: String),
          "messageId" .= messageIdValue
        ]
    )

sendJsonFrame :: WebSockets.Connection -> Value -> IO ()
sendJsonFrame connection value =
  WebSockets.sendTextData connection (TextEncoding.decodeUtf8 (Lazy.toStrict (encode value)))

receiveJsonFrame :: String -> WebSockets.Connection -> IO Text.Text
receiveJsonFrame _label = WebSockets.receiveData

decodeJsonText :: (FromJSON a) => String -> Text.Text -> IO a
decodeJsonText label rawValue =
  case eitherDecodeStrict' (TextEncoding.encodeUtf8 rawValue) of
    Left err -> ioError (userError ("failed to decode " <> label <> ":\n" <> err))
    Right decodedValue -> pure decodedValue

runPulsarWebSocketClient :: PulsarWebSocketBase -> String -> (WebSockets.Connection -> IO a) -> IO a
runPulsarWebSocketClient websocketBase =
  WebSockets.runClient (pulsarWsHost websocketBase) (pulsarWsPort websocketBase)

buildProducerSocketPath :: PulsarWebSocketBase -> TopicRef -> String
buildProducerSocketPath websocketBase topicRef =
  buildSocketPath
    websocketBase
    ("producer/" <> renderTopicPath topicRef)
    []

buildConsumerSocketPath :: PulsarWebSocketBase -> TopicRef -> String -> String -> String
buildConsumerSocketPath websocketBase topicRef subscriptionName consumerName =
  buildSocketPath
    websocketBase
    ("consumer/" <> renderTopicPath topicRef <> "/" <> subscriptionName)
    [ ("subscriptionType", "Exclusive"),
      ("receiverQueueSize", "1"),
      ("consumerName", consumerName)
    ]

buildReaderSocketPath :: PulsarWebSocketBase -> TopicRef -> String -> String
buildReaderSocketPath websocketBase topicRef readerName =
  buildSocketPath
    websocketBase
    ("reader/" <> renderTopicPath topicRef)
    [ ("messageId", "earliest"),
      ("receiverQueueSize", "1"),
      ("readerName", readerName)
    ]

buildSocketPath :: PulsarWebSocketBase -> String -> [(String, String)] -> String
buildSocketPath websocketBase relativePath =
  appendQueryParameters
    (joinSocketPath (pulsarWsPathPrefix websocketBase) relativePath)

renderTopicPath :: TopicRef -> String
renderTopicPath topicRef =
  Text.unpack (topicDomain topicRef)
    <> "/"
    <> Text.unpack (topicTenant topicRef)
    <> "/"
    <> Text.unpack (topicNamespace topicRef)
    <> "/"
    <> Text.unpack (topicName topicRef)

schemaUrl :: String -> TopicRef -> String
schemaUrl adminBaseUrl topicRef =
  trimTrailingSlash adminBaseUrl
    <> "/schemas/"
    <> Text.unpack (topicTenant topicRef)
    <> "/"
    <> Text.unpack (topicNamespace topicRef)
    <> "/"
    <> Text.unpack (topicName topicRef)
    <> "/schema"

requireTopicRef :: Text.Text -> IO TopicRef
requireTopicRef topicValue =
  case parseTopicRef topicValue of
    Just topicRef -> pure topicRef
    Nothing ->
      ioError
        (userError ("unsupported Pulsar topic name: " <> Text.unpack topicValue))

parseTopicRef :: Text.Text -> Maybe TopicRef
parseTopicRef topicValue = do
  (domainValue, remainder) <- splitOnce "://" topicValue
  case Text.splitOn "/" remainder of
    tenantValue : namespaceValue : topicSegments
      | not (Text.null tenantValue)
          && not (Text.null namespaceValue)
          && not (null topicSegments) ->
          Just
            TopicRef
              { topicDomain = domainValue,
                topicTenant = tenantValue,
                topicNamespace = namespaceValue,
                topicName = Text.intercalate "/" topicSegments
              }
    _ -> Nothing

splitOnce :: Text.Text -> Text.Text -> Maybe (Text.Text, Text.Text)
splitOnce needle haystack =
  let (prefix, suffix) = Text.breakOn needle haystack
   in if Text.null suffix
        then Nothing
        else Just (prefix, Text.drop (Text.length needle) suffix)

parsePulsarWebSocketBase :: String -> Either String PulsarWebSocketBase
parsePulsarWebSocketBase rawValue =
  case trimWhitespace rawValue of
    Nothing -> Left "the value is blank"
    Just trimmedValue ->
      case stripPrefix "ws://" trimmedValue of
        Just valueWithoutScheme -> parseAuthorityAndPath valueWithoutScheme
        Nothing ->
          case stripPrefix "wss://" trimmedValue of
            Just _ ->
              Left "wss:// URLs are not supported by the current runtime; use the ws:// Pulsar proxy endpoint"
            Nothing ->
              Left "expected a ws:// URL"
  where
    parseAuthorityAndPath valueWithoutScheme =
      let (authorityValue, rawPathPrefix) = break (== '/') valueWithoutScheme
          pathPrefixValue = trimTrailingSlash rawPathPrefix
       in case authorityAndPort authorityValue of
            Left err -> Left err
            Right (hostValue, portValue) ->
              Right
                PulsarWebSocketBase
                  { pulsarWsHost = hostValue,
                    pulsarWsPort = portValue,
                    pulsarWsPathPrefix =
                      if null pathPrefixValue
                        then ""
                        else pathPrefixValue
                  }

authorityAndPort :: String -> Either String (String, Int)
authorityAndPort rawAuthority =
  case break (== ':') rawAuthority of
    ("", _) -> Left "missing host"
    (hostValue, "") -> Right (hostValue, 80)
    (hostValue, ':' : rawPort)
      | null rawPort -> Left "missing port"
      | otherwise ->
          case reads rawPort of
            [(portValue, "")] -> Right (hostValue, portValue)
            _ -> Left ("invalid port: " <> rawPort)
    _ -> Left "invalid authority"

renderPulsarWebSocketBase :: PulsarWebSocketBase -> String
renderPulsarWebSocketBase websocketBase =
  "ws://"
    <> pulsarWsHost websocketBase
    <> ":"
    <> show (pulsarWsPort websocketBase)
    <> if null (pulsarWsPathPrefix websocketBase)
      then ""
      else pulsarWsPathPrefix websocketBase

joinSocketPath :: String -> String -> String
joinSocketPath basePath relativePath =
  let normalizedBase =
        case trimTrailingSlash basePath of
          "" -> ""
          value ->
            case value of
              '/' : _ -> value
              _ -> '/' : value
      normalizedRelative = dropWhile (== '/') relativePath
   in case normalizedBase of
        "" -> '/' : normalizedRelative
        _ -> normalizedBase <> "/" <> normalizedRelative

appendQueryParameters :: String -> [(String, String)] -> String
appendQueryParameters basePath [] = basePath
appendQueryParameters basePath queryParameters =
  basePath <> "?" <> intercalate "&" (map (\(key, value) -> key <> "=" <> value) queryParameters)

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

trimWhitespace :: String -> Maybe String
trimWhitespace rawValue =
  let trimmed = dropWhileEnd (`elem` [' ', '\n', '\r', '\t']) (dropWhile (`elem` [' ', '\n', '\r', '\t']) rawValue)
   in if null trimmed then Nothing else Just trimmed

trimTrailingSlash :: String -> String
trimTrailingSlash = reverse . dropWhile (== '/') . reverse

dropWhileEnd :: (Char -> Bool) -> String -> String
dropWhileEnd predicate = reverse . dropWhile predicate . reverse

stripPrefix :: String -> String -> Maybe String
stripPrefix [] value = Just value
stripPrefix _ [] = Nothing
stripPrefix (expected : expectedRest) (actual : actualRest)
  | expected == actual = stripPrefix expectedRest actualRest
  | otherwise = Nothing

lazyBodyToString :: Lazy.ByteString -> String
lazyBodyToString = ByteString8.unpack . Lazy.toStrict
