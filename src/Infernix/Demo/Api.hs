{-# LANGUAGE OverloadedStrings #-}

module Infernix.Demo.Api
  ( DemoApiOptions (..),
    runDemoApiServer,
  )
where

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
import Data.String (fromString)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Infernix.Config (Paths (..))
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Models (engineBindingForSelectedEngine)
import Infernix.Runtime
  ( evictCache,
    executeInference,
    listCacheManifests,
    loadInferenceResult,
    rebuildCache,
  )
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
    demoBindHost :: String,
    demoPort :: Int,
    demoConfigPath :: FilePath,
    demoPublicationPath :: FilePath
  }

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
    "harbor" : harborSegments
      | requestMethod request == methodGet ->
          serveHarborRoute harborSegments respond
    ["minio", "console"]
      | requestMethod request == methodGet ->
          respond (jsonResponse status200 (object ["status" .= ("ready" :: String), "targetUrl" .= ("minio-console" :: String), "rewrittenPath" .= ("/" :: String)]))
    "minio" : "console" : consoleSegments
      | requestMethod request == methodGet ->
          respond
            ( jsonResponse
                status200
                ( object
                    [ "label" .= ("minio-console" :: String),
                      "rewrittenPath" .= prefixedPath consoleSegments
                    ]
                )
            )
    ["minio", "s3"]
      | requestMethod request == methodGet ->
          respond (jsonResponse status200 (object ["status" .= ("ready" :: String), "targetUrl" .= ("minio-s3" :: String), "rewrittenPath" .= ("/" :: String)]))
    "minio" : "s3" : s3Segments
      | requestMethod request == methodGet ->
          respond
            ( jsonResponse
                status200
                ( object
                    [ "label" .= ("minio-s3" :: String),
                      "rewrittenPath" .= prefixedPath s3Segments
                    ]
                )
            )
    ["pulsar", "admin"]
      | requestMethod request == methodGet ->
          respond (jsonResponse status200 (object ["status" .= ("ready" :: String), "brokersHealth" .= ("ready" :: String), "rewrittenPath" .= ("/" :: String)]))
    "pulsar" : "admin" : adminSegments
      | requestMethod request == methodGet ->
          respond
            ( jsonResponse
                status200
                ( object
                    [ "label" .= ("pulsar-admin" :: String),
                      "rewrittenPath" .= prefixedPath adminSegments
                    ]
                )
            )
    ["pulsar", "ws"]
      | requestMethod request == methodGet ->
          respond (jsonResponse status200 (object ["status" .= ("ready" :: String), "brokersHealth" .= ("ready" :: String), "rewrittenPath" .= ("/" :: String)]))
    "pulsar" : "ws" : wsSegments
      | requestMethod request == methodGet ->
          respond
            ( jsonResponse
                status200
                ( object
                    [ "label" .= ("pulsar-http" :: String),
                      "rewrittenPath" .= prefixedPath wsSegments
                    ]
                )
            )
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
      result <- executeInference (demoPaths options) (demoRuntimeMode options) inferenceRequest
      case result of
        Left err ->
          respond (jsonResponse status400 err)
        Right inferenceResult ->
          respond (jsonResponse status200 inferenceResult)

handleCacheMutation :: DemoApiOptions -> Request -> CacheMutation -> (Response -> IO responseReceived) -> IO responseReceived
handleCacheMutation options request mutation respond = do
  maybeModelId <- decodeModelId request
  case mutation of
    EvictCache -> do
      evictedCount <- evictCache (demoPaths options) (demoRuntimeMode options) maybeModelId
      cachePayload <- buildCachePayload options
      respond
        ( jsonResponse
            status200
            (object ["evictedCount" .= evictedCount, "entries" .= cachePayload])
        )
    RebuildCache -> do
      rebuiltEntries <- rebuildCache (demoPaths options) (demoRuntimeMode options) maybeModelId
      cachePayload <- buildCachePayload options
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
  cachePayload <- buildCachePayload options
  respond (jsonResponse status200 cachePayload)

buildCachePayload :: DemoApiOptions -> IO [Value]
buildCachePayload options = do
  manifests <- listCacheManifests (demoPaths options) (demoRuntimeMode options)
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
          "sourceArtifactManifestUri" .= cacheDurableSourceUri manifest,
          "sourceArtifactSelectionMode" .= ("engine-specific-direct-artifact" :: String),
          "sourceArtifactAuthoritativeUri" .= cacheDurableSourceUri manifest,
          "sourceArtifactAuthoritativeKind" .= ("bundle" :: String),
          "sourceArtifactSelectedArtifacts" .= [object ["artifactKind" .= ("bundle" :: String), "uri" .= cacheDurableSourceUri manifest]]
        ]
    )

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

htmlResponse :: String -> Response
htmlResponse body =
  responseLBS status200 [(hContentType, "text/html; charset=utf-8")] (LazyByteString.fromStrict (ByteStringChar8.pack body))

fromStringHost :: String -> HostPreference
fromStringHost = fromString

serveHarborRoute :: [Text.Text] -> (Response -> IO responseReceived) -> IO responseReceived
serveHarborRoute segments respond =
  case segments of
    [] ->
      respond (htmlResponse "<!doctype html><title>Harbor</title><h1>Harbor</h1><p>Route published through Gateway/infernix-edge.</p>")
    "api" : apiSegments ->
      respond
        ( jsonResponse
            status200
            ( object
                [ "label" .= ("harbor-api" :: String),
                  "rewrittenPath" .= prefixedPath ("api" : apiSegments)
                ]
            )
        )
    _ ->
      respond
        ( jsonResponse
            status200
            ( object
                [ "label" .= ("harbor-ui" :: String),
                  "rewrittenPath" .= prefixedPath segments
                ]
            )
        )

prefixedPath :: [Text.Text] -> String
prefixedPath [] = "/"
prefixedPath segments = "/" <> joinPathSegments segments
