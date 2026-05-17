{-# LANGUAGE OverloadedStrings #-}

module Infernix.Demo.Api
  ( DemoApiOptions (..),
    DemoBridgeMode (..),
    runDemoApiServer,
  )
where

import Control.Concurrent (threadDelay)
import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON,
    Value,
    decodeStrict',
    encode,
    object,
    withObject,
    (.:?),
    (.=),
  )
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteStringChar8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (isSpace)
import Data.Maybe (fromMaybe)
import Data.String (fromString)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Infernix.Config (Paths (..))
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Models (engineBindingForSelectedEngine, findModel)
import Infernix.Runtime
  ( buildPayload,
    evictCache,
    executeInference,
    listCacheManifests,
    loadInferenceResult,
    persistInferenceResult,
    rebuildCache,
  )
import Infernix.Runtime.Cache (materializeCache)
import Infernix.Runtime.Pulsar (publishInferenceRequest, readPublishedInferenceResultMaybe)
import Infernix.Types
import Network.HTTP.Types
  ( Status,
    hContentType,
    methodGet,
    methodPost,
    status200,
    status400,
    status404,
    status500,
  )
import Network.Wai
  ( Application,
    Request,
    Response,
    pathInfo,
    requestMethod,
    responseFile,
    responseLBS,
    strictRequestBody,
  )
import Network.Wai.Handler.Warp (HostPreference, defaultSettings, runSettings, setHost, setPort)
import System.Directory (doesDirectoryExist, doesFileExist)
import System.FilePath (takeExtension, (</>))

data DemoApiOptions = DemoApiOptions
  { demoPaths :: Paths,
    demoRuntimeMode :: RuntimeMode,
    demoBridgeMode :: DemoBridgeMode,
    demoBindHost :: String,
    demoPort :: Int,
    demoConfigPath :: FilePath,
    demoPublicationPath :: FilePath
  }

data DemoBridgeMode
  = DirectDemoInference
  | PulsarDaemonBridge
  deriving (Eq, Show)

type InferenceResponse = Either (Status, ErrorResponse) InferenceResult

runDemoApiServer :: DemoApiOptions -> IO ()
runDemoApiServer options = do
  -- Fail fast when the generated catalog is invalid so cluster/test flows surface the error early.
  _ <- decodeDemoConfigFile (demoConfigPath options)
  let settings =
        setHost (fromStringHost (demoBindHost options)) $
          setPort (demoPort options) defaultSettings
  runSettings settings (application options)

application :: DemoApiOptions -> Application
application options request respond = do
  demoEnabled <- demoUiEnabled <$> decodeDemoConfigFile (demoConfigPath options)
  case pathInfo request of
    ["healthz"]
      | requestMethod request == methodGet && demoEnabled ->
          respond (textResponse status200 "ok")
    []
      | requestMethod request == methodGet && demoEnabled ->
          serveStaticAsset options "index.html" respond
    ["api", "publication"]
      | requestMethod request == methodGet && demoEnabled ->
          servePublication options respond
    ["api", "demo-config"]
      | requestMethod request == methodGet && demoEnabled ->
          serveDemoConfig options respond
    ["api", "models"]
      | requestMethod request == methodGet && demoEnabled ->
          serveModels options respond
    ["api", "models", modelIdValue]
      | requestMethod request == methodGet && demoEnabled ->
          serveModel options modelIdValue respond
    ["api", "inference", requestIdValue]
      | requestMethod request == methodGet && demoEnabled ->
          serveInferenceResult options requestIdValue respond
    ["api", "inference"]
      | requestMethod request == methodPost && demoEnabled ->
          handleInference options request respond
    ["api", "cache"]
      | requestMethod request == methodGet && demoEnabled ->
          serveCacheStatus options respond
    ["api", "cache", "evict"]
      | requestMethod request == methodPost && demoEnabled ->
          handleCacheMutation options request EvictCache respond
    ["api", "cache", "rebuild"]
      | requestMethod request == methodPost && demoEnabled ->
          handleCacheMutation options request RebuildCache respond
    "objects" : objectSegments
      | requestMethod request == methodGet && demoEnabled ->
          serveObject options objectSegments respond
    staticSegments
      | requestMethod request == methodGet && demoEnabled ->
          serveStaticSegments options staticSegments respond
    _ ->
      respond (textResponse status404 "route not found")

data CacheMutation = EvictCache | RebuildCache

newtype CacheMutationRequest = CacheMutationRequest
  { requestedModelId :: Maybe Text.Text
  }

instance FromJSON CacheMutationRequest where
  parseJSON = withObject "CacheMutationRequest" $ \value ->
    CacheMutationRequest <$> value .:? "modelId"

handleInference :: DemoApiOptions -> Request -> (Response -> IO responseReceived) -> IO responseReceived
handleInference options request respond = do
  body <- strictRequestBody request
  case decodeStrict' (LazyByteString.toStrict body) of
    Nothing ->
      respond (jsonResponse status400 (ErrorResponse "invalid_request" "Unable to decode JSON request body."))
    Just inferenceRequest -> do
      activeRuntimeMode <- currentDemoRuntimeMode options
      case demoBridgeMode options of
        DirectDemoInference -> do
          result <- executeInference (demoPaths options) activeRuntimeMode inferenceRequest
          case result of
            Left err ->
              respond (jsonResponse status400 err)
            Right inferenceResult ->
              respond (jsonResponse status200 inferenceResult)
        PulsarDaemonBridge ->
          handleInferenceViaPulsar options activeRuntimeMode inferenceRequest respond

handleInferenceViaPulsar :: DemoApiOptions -> RuntimeMode -> InferenceRequest -> (Response -> IO responseReceived) -> IO responseReceived
handleInferenceViaPulsar options runtimeMode inferenceRequest respond = do
  inferenceResponse <- runPulsarInference options runtimeMode inferenceRequest
  respond $
    case inferenceResponse of
      Left (responseStatus, err) -> jsonResponse responseStatus err
      Right resultValue -> jsonResponse status200 resultValue

runPulsarInference :: DemoApiOptions -> RuntimeMode -> InferenceRequest -> IO InferenceResponse
runPulsarInference options runtimeMode inferenceRequest =
  case validateInferenceRequest runtimeMode inferenceRequest of
    Left err ->
      pure (Left (status400, err))
    Right model ->
      runValidatedPulsarInference options runtimeMode model inferenceRequest

runValidatedPulsarInference :: DemoApiOptions -> RuntimeMode -> ModelDescriptor -> InferenceRequest -> IO InferenceResponse
runValidatedPulsarInference options runtimeMode model inferenceRequest = do
  demoConfig <- decodeDemoConfigFile (demoConfigPath options)
  case firstRequestTopic demoConfig of
    Left err -> pure (Left err)
    Right requestTopic -> do
      materializeCache (demoPaths options) runtimeMode model
      requestIdValue <- publishInferenceRequest (demoPaths options) runtimeMode requestTopic inferenceRequest
      maybePublishedResult <- waitForPublishedResult (demoPaths options) runtimeMode (resultTopic demoConfig) requestIdValue
      resolvePublishedInferenceResult options maybePublishedResult

firstRequestTopic :: DemoConfig -> Either (Status, ErrorResponse) Text.Text
firstRequestTopic demoConfig =
  case requestTopics demoConfig of
    requestTopic : _ -> Right requestTopic
    [] ->
      Left
        ( status500,
          ErrorResponse "missing_request_topic" "The active demo config does not declare any request topics."
        )

resolvePublishedInferenceResult :: DemoApiOptions -> Maybe InferenceResult -> IO InferenceResponse
resolvePublishedInferenceResult options maybePublishedResult =
  case maybePublishedResult of
    Nothing ->
      pure
        ( Left
            ( status500,
              ErrorResponse "daemon_timeout" "The inference daemon did not publish a result in time."
            )
        )
    Just publishedResult
      | status publishedResult /= "completed" ->
          pure (Left (status400, publishedResultError publishedResult))
      | otherwise -> do
          localizedResult <- localizePublishedResult options publishedResult
          case localizedResult of
            Left err ->
              pure (Left (status500, err))
            Right resultValue -> do
              persistInferenceResult (demoPaths options) resultValue
              pure (Right resultValue)

validateInferenceRequest :: RuntimeMode -> InferenceRequest -> Either ErrorResponse ModelDescriptor
validateInferenceRequest runtimeMode inferenceRequest =
  case findModel runtimeMode (requestModelId inferenceRequest) of
    Nothing ->
      Left (ErrorResponse "unknown_model" "The requested model is not registered.")
    Just model
      | Text.all isSpace (inputText inferenceRequest) ->
          Left (ErrorResponse "invalid_request" "The request input must not be blank.")
      | otherwise ->
          Right model

waitForPublishedResult :: Paths -> RuntimeMode -> Text.Text -> Text.Text -> IO (Maybe InferenceResult)
waitForPublishedResult paths runtimeMode topic requestIdValue = go (120 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 = pure Nothing
      | otherwise = do
          maybeResult <- readPublishedInferenceResultMaybe paths runtimeMode topic requestIdValue
          case maybeResult of
            Just resultValue -> pure (Just resultValue)
            Nothing -> do
              threadDelay 250000
              go (remainingAttempts - 1)

localizePublishedResult :: DemoApiOptions -> InferenceResult -> IO (Either ErrorResponse InferenceResult)
localizePublishedResult options publishedResult =
  case objectRef (payload publishedResult) of
    Just _ ->
      pure
        ( Left
            ( ErrorResponse
                "unsupported_result_payload"
                "The daemon returned an external object reference that the clustered demo surface cannot serve."
            )
        )
    Nothing -> do
      localizedPayload <-
        buildPayload
          (demoPaths options)
          (requestId publishedResult)
          (fromMaybe "" (inlineOutput (payload publishedResult)))
      pure (Right publishedResult {payload = localizedPayload})

publishedResultError :: InferenceResult -> ErrorResponse
publishedResultError resultValue =
  ErrorResponse
    { errorCode = "worker_failed",
      message =
        fromMaybe
          "The inference daemon reported a failure."
          (inlineOutput (payload resultValue))
    }

handleCacheMutation :: DemoApiOptions -> Request -> CacheMutation -> (Response -> IO responseReceived) -> IO responseReceived
handleCacheMutation options request mutation respond = do
  maybeModelId <- decodeModelId request
  activeRuntimeMode <- currentDemoRuntimeMode options
  case mutation of
    EvictCache -> do
      evictedCount <- evictCache (demoPaths options) activeRuntimeMode maybeModelId
      cachePayload <- buildCachePayload options activeRuntimeMode
      respond
        ( jsonResponse
            status200
            (object ["evictedCount" .= evictedCount, "entries" .= cachePayload])
        )
    RebuildCache -> do
      rebuiltEntries <- rebuildCache (demoPaths options) activeRuntimeMode maybeModelId
      cachePayload <- buildCachePayload options activeRuntimeMode
      respond
        ( jsonResponse
            status200
            (object ["rebuiltCount" .= length rebuiltEntries, "entries" .= cachePayload])
        )

decodeModelId :: Request -> IO (Maybe Text.Text)
decodeModelId request = do
  body <- strictRequestBody request
  case decodeStrict' (LazyByteString.toStrict body) of
    Just cacheRequest ->
      pure (requestedModelId (cacheRequest :: CacheMutationRequest))
    _ -> pure Nothing

servePublication :: DemoApiOptions -> (Response -> IO responseReceived) -> IO responseReceived
servePublication options respond = do
  publicationExists <- doesFileExist (demoPublicationPath options)
  if publicationExists
    then respond (responseFile status200 [(hContentType, "application/json; charset=utf-8")] (demoPublicationPath options) Nothing)
    else respond (jsonResponse status200 (object ["clusterPresent" .= False]))

serveDemoConfig :: DemoApiOptions -> (Response -> IO responseReceived) -> IO responseReceived
serveDemoConfig options respond = do
  demoConfig <- decodeDemoConfigFile (demoConfigPath options)
  respond (jsonResponse status200 demoConfig)

serveModels :: DemoApiOptions -> (Response -> IO responseReceived) -> IO responseReceived
serveModels options respond = do
  demoConfig <- decodeDemoConfigFile (demoConfigPath options)
  respond (jsonResponse status200 (models demoConfig))

serveModel :: DemoApiOptions -> Text.Text -> (Response -> IO responseReceived) -> IO responseReceived
serveModel options requestedModelId respond = do
  demoConfig <- decodeDemoConfigFile (demoConfigPath options)
  case filter ((== requestedModelId) . modelId) (models demoConfig) of
    modelDescriptor : _ -> respond (jsonResponse status200 modelDescriptor)
    [] -> respond (jsonResponse status404 (ErrorResponse "unknown_model" "The requested model is not registered."))

serveInferenceResult :: DemoApiOptions -> Text.Text -> (Response -> IO responseReceived) -> IO responseReceived
serveInferenceResult options requestIdValue respond = do
  maybeResult <- loadInferenceResult (demoPaths options) requestIdValue
  case maybeResult of
    Just inferenceResult -> respond (jsonResponse status200 inferenceResult)
    Nothing -> respond (jsonResponse status404 (ErrorResponse "unknown_request" "The requested result was not found."))

serveCacheStatus :: DemoApiOptions -> (Response -> IO responseReceived) -> IO responseReceived
serveCacheStatus options respond = do
  activeRuntimeMode <- currentDemoRuntimeMode options
  cachePayload <- buildCachePayload options activeRuntimeMode
  respond (jsonResponse status200 cachePayload)

currentDemoRuntimeMode :: DemoApiOptions -> IO RuntimeMode
currentDemoRuntimeMode options =
  configRuntimeMode <$> decodeDemoConfigFile (demoConfigPath options)

buildCachePayload :: DemoApiOptions -> RuntimeMode -> IO [Value]
buildCachePayload options runtimeMode = do
  manifests <- listCacheManifests (demoPaths options) runtimeMode
  mapM (cacheEntryValue options) manifests

cacheEntryValue :: DemoApiOptions -> CacheManifest -> IO Value
cacheEntryValue options manifest = do
  let cacheRoot =
        modelCacheRoot (demoPaths options)
          </> Text.unpack (runtimeModeId (cacheRuntimeMode manifest))
          </> Text.unpack (cacheModelId manifest)
          </> "default"
  materialized <- doesDirectoryExist cacheRoot
  pure
    ( object
        [ "runtimeMode" .= cacheRuntimeMode manifest,
          "modelId" .= cacheModelId manifest,
          "selectedEngine" .= cacheSelectedEngine manifest,
          "durableSourceUri" .= cacheDurableSourceUri manifest,
          "cacheKey" .= cacheCacheKey manifest,
          "materialized" .= materialized,
          "engineAdapterId" .= engineBindingAdapterId (engineBindingForSelectedEngine (cacheRuntimeMode manifest) (cacheSelectedEngine manifest)),
          "engineAdapterAvailability" .= ("available" :: String),
          "sourceArtifactManifestUri" .= sourceArtifactManifestUri manifest,
          "sourceArtifactSelectionMode" .= ("engine-specific-direct-artifact" :: String),
          "sourceArtifactAuthoritativeUri" .= cacheDurableSourceUri manifest,
          "sourceArtifactAuthoritativeKind" .= ("bundle" :: String),
          "sourceArtifactSelectedArtifacts" .= [object ["artifactKind" .= ("bundle" :: String), "uri" .= cacheDurableSourceUri manifest]]
        ]
    )

sourceArtifactManifestUri :: CacheManifest -> Text.Text
sourceArtifactManifestUri manifest =
  "s3://infernix-runtime/source-artifacts/"
    <> runtimeModeId (cacheRuntimeMode manifest)
    <> "/"
    <> cacheModelId manifest
    <> "/source.json"

serveObject :: DemoApiOptions -> [Text.Text] -> (Response -> IO responseReceived) -> IO responseReceived
serveObject options objectSegments respond = do
  let relativePath = joinPathSegments objectSegments
      fullPath = objectStoreRoot (demoPaths options) </> relativePath
  objectExists <- doesFileExist fullPath
  if objectExists
    then respond (responseFile status200 [(hContentType, "text/plain; charset=utf-8")] fullPath Nothing)
    else respond (textResponse status404 "object not found")

serveStaticSegments :: DemoApiOptions -> [Text.Text] -> (Response -> IO responseReceived) -> IO responseReceived
serveStaticSegments options staticSegments respond = do
  let relativePath = joinPathSegments staticSegments
  serveStaticAsset options relativePath respond

serveStaticAsset :: DemoApiOptions -> FilePath -> (Response -> IO responseReceived) -> IO responseReceived
serveStaticAsset options relativePath respond = do
  let assetPath = webDistRoot (demoPaths options) relativePath
  assetExists <- doesFileExist assetPath
  if assetExists
    then respond (responseFile status200 [(hContentType, contentTypeForPath relativePath)] assetPath Nothing)
    else respond (textResponse status500 ("missing web asset: " <> relativePath))

webDistRoot :: Paths -> FilePath -> FilePath
webDistRoot paths relativePath = repoRoot paths </> "web" </> "dist" </> relativePath

joinPathSegments :: [Text.Text] -> FilePath
joinPathSegments = foldr appendSegment ""
  where
    appendSegment segmentValue suffix =
      let current = Text.unpack segmentValue
       in if null suffix then current else current </> suffix

contentTypeForPath :: FilePath -> ByteString.ByteString
contentTypeForPath relativePath =
  case takeExtension relativePath of
    ".css" -> TextEncoding.encodeUtf8 "text/css; charset=utf-8"
    ".html" -> TextEncoding.encodeUtf8 "text/html; charset=utf-8"
    ".js" -> TextEncoding.encodeUtf8 "application/javascript; charset=utf-8"
    ".json" -> TextEncoding.encodeUtf8 "application/json; charset=utf-8"
    ".map" -> TextEncoding.encodeUtf8 "application/json; charset=utf-8"
    ".svg" -> TextEncoding.encodeUtf8 "image/svg+xml"
    _ -> TextEncoding.encodeUtf8 "text/plain; charset=utf-8"

jsonResponse :: (ToJSON a) => Status -> a -> Response
jsonResponse responseStatus payload =
  responseLBS responseStatus [(hContentType, "application/json; charset=utf-8")] (encode payload)

textResponse :: Status -> String -> Response
textResponse responseStatus body =
  responseLBS responseStatus [(hContentType, "text/plain; charset=utf-8")] (LazyByteString.fromStrict (ByteStringChar8.pack body))

fromStringHost :: String -> HostPreference
fromStringHost = fromString
