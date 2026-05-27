{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Infernix.Demo.Api
  ( DemoApiOptions (..),
    DemoBridgeMode (..),
    runDemoApiServer,
  )
where

import Control.Exception (SomeException, try)
import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON,
    Value,
    decodeStrict',
    eitherDecode,
    encode,
    object,
    withObject,
    (.:?),
    (.=),
  )
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteStringChar8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.String (fromString)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time.Clock (NominalDiffTime, UTCTime, diffUTCTime, getCurrentTime)
import Infernix.Auth.Jwt
  ( Jwks,
    JwtError,
    parseJwks,
    verifyAndParseJwt,
  )
import Infernix.Auth.Jwt qualified as Jwt
import Infernix.ClusterConfig qualified as ClusterConfig
import Infernix.Config (Paths (..))
import Infernix.Demo.Auth
  ( KeycloakRealmConfig (..),
    loadRealmConfigFromCluster,
    realmJwksUrl,
    realmValidationConfig,
  )
import Infernix.Demo.WebSocket qualified as DemoWebSocket
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Models (engineBindingForSelectedEngine)
import Infernix.Objects.Layout
  ( pathBelongsToUser,
    uploadObjectKey,
  )
import Infernix.Objects.Presigned
  ( HttpMethod (..),
    PresignedRequest (..),
    PresignedUrl (..),
    PresignedUrlConfig (..),
    isoExpiryFor,
    presignedUrlForRequest,
  )
import Infernix.Runtime
  ( evictCache,
    listCacheManifests,
    rebuildCache,
  )
import Infernix.Runtime.Pulsar qualified as RuntimePulsar
import Infernix.SecretsConfig qualified as SecretsConfig
import Infernix.Types
import Infernix.Web.Contracts
  ( ArtifactDownloadGrant (..),
    ArtifactMimeType,
    ArtifactRenderDisposition (..),
    ArtifactUploadGrant (..),
    ArtifactUploadRequest (..),
    ObjectRef (..),
    UserId (..),
  )
import Network.HTTP.Client
  ( defaultManagerSettings,
    httpLbs,
    newManager,
    parseRequest,
    responseBody,
    responseStatus,
  )
import Network.HTTP.Types
  ( Status,
    hAuthorization,
    hContentType,
    methodGet,
    methodPost,
    status200,
    status400,
    status401,
    status403,
    status404,
    status500,
    status503,
  )
import Network.HTTP.Types.Status (statusCode)
import Network.Wai
  ( Application,
    Request,
    Response,
    pathInfo,
    requestHeaders,
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

-- | Phase 7 Sprint 7.9: the demo API process holds one JWKS cache for
-- the lifetime of the process. Build it once in 'runDemoApiServer' so
-- the per-request handlers and the WebSocket handshake share the same
-- TTL-cached fetch path instead of each request triggering an upstream
-- JWKS round-trip.
newtype JwksCache = JwksCache (IORef (Maybe (UTCTime, Jwks)))

newJwksCache :: IO JwksCache
newJwksCache = JwksCache <$> newIORef Nothing

-- | Keycloak realms typically rotate keys on the order of hours. A
-- 5-minute TTL keeps the demo backend snappy while still surfacing a
-- newly rotated kid quickly enough that the legitimate user-facing
-- error window stays under one TTL cycle.
jwksCacheTtl :: NominalDiffTime
jwksCacheTtl = 300

loadJwksCached :: JwksCache -> KeycloakRealmConfig -> IO (Either String Jwks)
loadJwksCached (JwksCache cacheRef) realmConfig = do
  cached <- readIORef cacheRef
  now <- getCurrentTime
  case cached of
    Just (lastFetched, jwks)
      | diffUTCTime now lastFetched < jwksCacheTtl ->
          pure (Right jwks)
    _ -> do
      result <- loadJwksFromKeycloak realmConfig
      case result of
        Right jwks -> do
          writeIORef cacheRef (Just (now, jwks))
          pure (Right jwks)
        Left err -> pure (Left err)

runDemoApiServer :: DemoApiOptions -> IO ()
runDemoApiServer options = do
  -- Fail fast when the generated catalog is invalid so cluster/test flows surface the error early.
  _ <- decodeDemoConfigFile (demoConfigPath options)
  jwksCache <- newJwksCache
  -- Phase 7 Sprint 7.17: realm wiring now comes from the typed
  -- @ClusterConfig.keycloak.*@ fields when the chart ConfigMap is
  -- mounted; host-native + unit-test flows that don't mount the
  -- manifest fall back to 'defaultInfernixRealmConfig'.
  maybeClusterConfig <- tryLoadClusterConfig
  let realmConfig = loadRealmConfigFromCluster maybeClusterConfig
      settings =
        setHost (fromStringHost (demoBindHost options)) $
          setPort (demoPort options) defaultSettings
  runSettings settings (application options jwksCache realmConfig maybeClusterConfig)

-- | Phase 7 Sprint 7.17: best-effort load of the cluster manifest
-- mounted by the chart at the supported path. The demo daemon pod
-- has this ConfigMap-mounted; host-native and unit-test flows do
-- not, so absence is silently tolerated.
tryLoadClusterConfig :: IO (Maybe ClusterConfig.ClusterConfig)
tryLoadClusterConfig = do
  let path = ClusterConfig.defaultClusterConfigMountPath
  exists <- doesFileExist path
  if exists
    then Just <$> ClusterConfig.decodeClusterConfigFile path
    else pure Nothing

-- type Application = Request -> (Response -> IO ResponseReceived) -> IO ResponseReceived
application :: DemoApiOptions -> JwksCache -> KeycloakRealmConfig -> Maybe ClusterConfig.ClusterConfig -> Application
application options jwksCache realmConfig maybeClusterConfig request respond = do
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
    ["api", "cache"]
      | requestMethod request == methodGet && demoEnabled ->
          serveCacheStatus options respond
    ["api", "cache", "evict"]
      | requestMethod request == methodPost && demoEnabled ->
          handleCacheMutation options request EvictCache respond
    ["api", "cache", "rebuild"]
      | requestMethod request == methodPost && demoEnabled ->
          handleCacheMutation options request RebuildCache respond
    ["api", "objects", "upload"]
      | requestMethod request == methodPost && demoEnabled ->
          handleObjectsGrant jwksCache realmConfig request ObjectsUpload respond
    ["api", "objects", "download"]
      | requestMethod request == methodPost && demoEnabled ->
          handleObjectsGrant jwksCache realmConfig request ObjectsDownload respond
    ["ws"]
      | demoEnabled ->
          DemoWebSocket.wsApplication
            ( webSocketOptions
                options
                maybeClusterConfig
                (loadJwksCached jwksCache realmConfig)
            )
            request
            respond
    staticSegments
      | requestMethod request == methodGet && demoEnabled ->
          serveStaticSegments options staticSegments respond
    _ ->
      respond (textResponse status404 "route not found")

webSocketOptions ::
  DemoApiOptions ->
  Maybe ClusterConfig.ClusterConfig ->
  IO (Either String Jwks) ->
  DemoWebSocket.WebSocketOptions
webSocketOptions options maybeClusterConfig loadJwks =
  (DemoWebSocket.defaultWebSocketOptions loadJwks)
    { DemoWebSocket.wsRealmConfig = loadRealmConfigFromCluster maybeClusterConfig,
      DemoWebSocket.wsDispatchClientMessage =
        \userIdValue clientMessage ->
          mapDispatchError
            ( RuntimePulsar.publishDemoClientMessage
                (demoPaths options)
                (demoRuntimeMode options)
                maybeClusterConfig
                userIdValue
                clientMessage
            )
    }

mapDispatchError :: IO () -> IO (Either String ())
mapDispatchError action = do
  result <- try @SomeException action
  case result of
    Right () -> pure (Right ())
    Left err -> pure (Left (show err))

-- | Phase 7 Sprint 7.9: /api/objects upload-grant + download-grant
-- handlers. Both endpoints consume a Keycloak-signed JWT in the
-- @Authorization: Bearer ...@ header, derive the @UserId@ from the
-- token's @sub@ claim, scope the requested artifact to
-- @users/<userId>/contexts/<contextId>/{uploads,generated}/@, and mint a
-- presigned PUT or GET URL the browser uses to talk to MinIO directly.
-- The demo backend never proxies the binary bytes.
data ObjectsAction = ObjectsUpload | ObjectsDownload

handleObjectsGrant ::
  JwksCache ->
  KeycloakRealmConfig ->
  Request ->
  ObjectsAction ->
  (Response -> IO responseReceived) ->
  IO responseReceived
handleObjectsGrant jwksCache realmConfig request action respond = do
  case extractBearerToken request of
    Nothing -> respond (textResponse status401 "missing bearer token")
    Just token -> do
      jwksResult <- loadJwksCached jwksCache realmConfig
      case jwksResult of
        Left jwksError ->
          respond (textResponse status503 ("JWKS fetch failed: " <> jwksError))
        Right jwks -> do
          now <- getCurrentTime
          case verifyAndParseJwt (realmValidationConfig realmConfig) now jwks token of
            Left jwtError ->
              respond (textResponse status401 ("invalid JWT: " <> renderJwtError jwtError))
            Right claims -> do
              bodyBytes <- strictRequestBody request
              case eitherDecode bodyBytes of
                Left decodeError ->
                  respond (textResponse status400 ("invalid request body: " <> decodeError))
                Right uploadRequest -> do
                  presignedResult <- loadPresignedConfig
                  case presignedResult of
                    Left configError ->
                      respond (textResponse status503 ("presigned URL config missing: " <> configError))
                    Right presigned -> do
                      let userId = UserId (Jwt.jwtClaimSubject claims)
                          contextId = artifactUploadRequestContextId uploadRequest
                          displayName = artifactUploadRequestDisplayName uploadRequest
                          mimeType = artifactUploadRequestMimeType uploadRequest
                          objectReference = uploadObjectKey userId contextId displayName
                      if not (pathBelongsToUser userId (objectKey objectReference))
                        then respond (textResponse status403 "object key is outside the caller's scope")
                        else mintAndRespond action presigned objectReference mimeType now respond

-- | Mint a presigned URL for the requested action and respond with the
-- matching upload-or-download grant JSON.
mintAndRespond ::
  ObjectsAction ->
  PresignedUrlConfig ->
  ObjectRef ->
  ArtifactMimeType ->
  UTCTime ->
  (Response -> IO responseReceived) ->
  IO responseReceived
mintAndRespond action presigned objectReference mimeType now respond =
  case action of
    ObjectsUpload ->
      let signed =
            presignedUrlForRequest
              presigned
              PresignedRequest
                { presignedRequestMethod = HttpPut,
                  presignedRequestObject = objectReference,
                  presignedRequestNow = now
                }
          grant =
            ArtifactUploadGrant
              { artifactUploadGrantObjectRef = objectReference,
                artifactUploadGrantPresignedUrl = unPresignedUrl signed,
                artifactUploadGrantExpiresAtIso8601 = isoExpiryFor presigned now
              }
       in respond (jsonResponse status200 grant)
    ObjectsDownload ->
      let signed =
            presignedUrlForRequest
              presigned
              PresignedRequest
                { presignedRequestMethod = HttpGet,
                  presignedRequestObject = objectReference,
                  presignedRequestNow = now
                }
          grant =
            ArtifactDownloadGrant
              { artifactDownloadGrantObjectRef = objectReference,
                artifactDownloadGrantPresignedUrl = unPresignedUrl signed,
                artifactDownloadGrantMimeType = mimeType,
                artifactDownloadGrantRenderDisposition = renderDispositionForMime mimeType,
                artifactDownloadGrantExpiresAtIso8601 = isoExpiryFor presigned now
              }
       in respond (jsonResponse status200 grant)

-- | Pull the bearer token out of the @Authorization@ header. Returns
-- 'Nothing' if the header is absent, malformed, or carries a non-@Bearer@
-- scheme.
extractBearerToken :: Request -> Maybe Text
extractBearerToken request =
  authorizationHeader request >>= bearerToken

authorizationHeader :: Request -> Maybe Text
authorizationHeader request =
  TextEncoding.decodeUtf8 <$> lookup hAuthorization (requestHeaders request)

bearerToken :: Text -> Maybe Text
bearerToken headerValue =
  case Text.stripPrefix "Bearer " headerValue of
    Just token | not (Text.null token) -> Just token
    _ -> Nothing

-- | Phase 7 Sprint 7.17: fetch the Keycloak realm JWKS via the
-- typed `ClusterConfig.keycloak.jwksUrl` field when the cluster
-- manifest is mounted; fall back to the realm-config-derived URL
-- (host-native + unit-test flows). The retired
-- @INFERNIX_KEYCLOAK_JWKS_URL@ env override is gone.
loadJwksFromKeycloak :: KeycloakRealmConfig -> IO (Either String Jwks)
loadJwksFromKeycloak realmConfig = do
  maybeClusterConfig <- tryLoadClusterConfig
  let jwksUrl = case maybeClusterConfig of
        Just clusterConfig ->
          let configured = ClusterConfig.keycloakJwksUrl (ClusterConfig.clusterKeycloak clusterConfig)
           in if Text.null configured then realmJwksUrl realmConfig else configured
        Nothing -> realmJwksUrl realmConfig
  manager <- newManager defaultManagerSettings
  fetchAttempt <- try @SomeException $ do
    requestValue <- parseRequest (Text.unpack jwksUrl)
    httpLbs requestValue manager
  case fetchAttempt of
    Left err -> pure (Left (show err))
    Right response
      | statusCode (responseStatus response) == 200 ->
          case parseJwks (responseBody response) of
            Left parseError -> pure (Left ("JWKS parse failed: " <> show parseError))
            Right jwks -> pure (Right jwks)
      | otherwise ->
          pure (Left ("JWKS endpoint returned HTTP " <> show (statusCode (responseStatus response))))

-- | Phase 7 Sprint 7.17: pull MinIO endpoint / region / presign
-- expiry from the mounted `ClusterConfig.minio.*` fields and
-- credentials from the file path declared by the mounted
-- `SecretsConfig.minio.credentialsPath`. The retired `INFERNIX_MINIO_*`
-- env reads are gone; cluster-resident deployments mount both
-- ConfigMaps + Secret at the supported paths, and the function
-- surfaces a typed diagnostic when either is absent.
loadPresignedConfig :: IO (Either String PresignedUrlConfig)
loadPresignedConfig = do
  clusterExists <- doesFileExist ClusterConfig.defaultClusterConfigMountPath
  secretsExists <- doesFileExist SecretsConfig.defaultClusterSecretsMountPath
  if not (clusterExists && secretsExists)
    then
      pure
        ( Left
            ( "demo backend requires the cluster ConfigMap at "
                <> ClusterConfig.defaultClusterConfigMountPath
                <> " and the secrets Secret at "
                <> SecretsConfig.defaultClusterSecretsMountPath
                <> "; the demo Deployment mounts both via the supported chart templates"
            )
        )
    else do
      clusterConfig <- ClusterConfig.decodeClusterConfigFile ClusterConfig.defaultClusterConfigMountPath
      secretsConfig <- SecretsConfig.decodeSecretsConfigFile SecretsConfig.defaultClusterSecretsMountPath
      minioCreds <- SecretsConfig.readMinioCredentials (SecretsConfig.secretsMinio secretsConfig)
      let minio = ClusterConfig.clusterMinio clusterConfig
          (scheme, hostPort) = splitMinioEndpoint (ClusterConfig.minioEndpoint minio)
      pure
        ( Right
            PresignedUrlConfig
              { presignedScheme = scheme,
                presignedEndpoint = hostPort,
                presignedRegion = ClusterConfig.minioRegion minio,
                presignedAccessKeyId = SecretsConfig.minioAccessKey minioCreds,
                presignedSecretAccessKey = SecretsConfig.minioSecretKey minioCreds,
                presignedExpirySeconds = fromIntegral (ClusterConfig.minioPresignExpirySeconds minio)
              }
        )

-- | Phase 7 Sprint 7.17: the @ClusterConfig.minio.endpoint@ field
-- carries a full @http://host:port@ URL, but the SigV4 canonical
-- request signs only the @host:port@ as the @host@ header. Strip any
-- scheme prefix and record it separately so the minted URL points at
-- the correct transport (plain HTTP for in-cluster MinIO, HTTPS for
-- TLS-fronted MinIO).
splitMinioEndpoint :: Text -> (Text, Text)
splitMinioEndpoint raw =
  case Text.stripPrefix "https://" raw of
    Just hostPort -> ("https", hostPort)
    Nothing ->
      case Text.stripPrefix "http://" raw of
        Just hostPort -> ("http", hostPort)
        Nothing -> ("http", raw)

renderJwtError :: JwtError -> String
renderJwtError = show

renderDispositionForMime :: ArtifactMimeType -> ArtifactRenderDisposition
renderDispositionForMime _ = RenderInline

data CacheMutation = EvictCache | RebuildCache

newtype CacheMutationRequest = CacheMutationRequest
  { requestedModelId :: Maybe Text.Text
  }

instance FromJSON CacheMutationRequest where
  parseJSON = withObject "CacheMutationRequest" $ \value ->
    CacheMutationRequest <$> value .:? "modelId"

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

-- Phase 7 Sprint 7.7 retires the @./.data/object-store/@ tree, so the
-- cache-status payload no longer points at a synthetic local
-- source-artifact manifest. The active substrate's MinIO
-- @infernix-models@ bucket is the only durable source of truth; the URI
-- below names that bucket prefix instead.
sourceArtifactManifestUri :: CacheManifest -> Text.Text
sourceArtifactManifestUri manifest =
  "minio://infernix-models/" <> cacheModelId manifest <> "/"

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

-- type HostPreference = String
fromStringHost :: String -> HostPreference
fromStringHost = fromString
