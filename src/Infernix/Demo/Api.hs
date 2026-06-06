{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Infernix.Demo.Api
  ( DemoApiOptions (..),
    DemoBridgeMode (..),
    renderDispositionForMime,
    runDemoApiServer,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, fromException, try)
import Control.Monad (forM, unless, when)
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
import Data.Maybe (listToMaybe)
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
import Infernix.Demo.Bootstrap (requiredDemoBuckets)
import Infernix.Demo.WebSocket qualified as DemoWebSocket
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Models (engineBindingForSelectedEngine)
import Infernix.Objects.Layout
  ( DemoObjectsBucket (..),
    UserPrefix (..),
    defaultDemoObjectsBucket,
    pathBelongsToUser,
    uploadObjectKey,
    userPrefix,
  )
import Infernix.Objects.Presigned
  ( HttpMethod (..),
    PresignedBucketRequest (..),
    PresignedRequest (..),
    PresignedUrl (..),
    PresignedUrlConfig (..),
    isoExpiryFor,
    presignedBucketUrl,
    presignedBucketUrlWithQuery,
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
    ArtifactMimeType (..),
    ArtifactRenderDisposition (..),
    ArtifactUploadGrant (..),
    ArtifactUploadRequest (..),
    ObjectRef (..),
    UserId (..),
  )
import Network.HTTP.Client
  ( RequestBody (RequestBodyLBS),
    defaultManagerSettings,
    httpLbs,
    method,
    newManager,
    parseRequest,
    requestBody,
    responseBody,
    responseStatus,
    responseTimeout,
    responseTimeoutMicro,
  )
import Network.HTTP.Types
  ( Status,
    hAuthorization,
    hContentType,
    methodDelete,
    methodGet,
    methodPost,
    methodPut,
    status200,
    status202,
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
import System.IO (hPutStrLn, stderr)

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
  demoConfig <- decodeDemoConfigFile (demoConfigPath options)
  jwksCache <- newJwksCache
  -- Phase 7 Sprint 7.17: realm wiring now comes from the typed
  -- @ClusterConfig.keycloak.*@ fields when the chart ConfigMap is
  -- mounted; host-native + unit-test flows that don't mount the
  -- manifest fall back to 'defaultInfernixRealmConfig'.
  maybeClusterConfig <- tryLoadClusterConfig
  when (demoUiEnabled demoConfig) (repairDemoBucketsAtStartup maybeClusterConfig)
  let realmConfig = loadRealmConfigFromCluster maybeClusterConfig
      settings =
        setHost (fromStringHost (demoBindHost options)) $
          setPort (demoPort options) defaultSettings
  runSettings settings (application options jwksCache realmConfig maybeClusterConfig)

-- | Sprint 7.9 runtime repair path. Chart-time MinIO provisioning is the
-- supported normal path, but the demo backend also reconciles its buckets
-- at startup when it is running in a cluster with mounted config/secrets.
-- Host-native test runs without the cluster mounts skip this edge repair.
repairDemoBucketsAtStartup :: Maybe ClusterConfig.ClusterConfig -> IO ()
repairDemoBucketsAtStartup Nothing =
  hPutStrLn stderr "demo bucket reconcile skipped: cluster ConfigMap is not mounted"
repairDemoBucketsAtStartup (Just clusterConfig) = do
  repairConfig <- loadBucketRepairConfig clusterConfig
  ensureDemoBucketsWithRetry repairConfig requiredDemoBuckets

loadBucketRepairConfig :: ClusterConfig.ClusterConfig -> IO PresignedUrlConfig
loadBucketRepairConfig clusterConfig = do
  secretsExists <- doesFileExist SecretsConfig.defaultClusterSecretsMountPath
  unless secretsExists $
    ioError
      ( userError
          ( "demo bucket reconcile requires the secrets Secret at "
              <> SecretsConfig.defaultClusterSecretsMountPath
          )
      )
  secretsConfig <- SecretsConfig.decodeSecretsConfigFile SecretsConfig.defaultClusterSecretsMountPath
  minioCreds <- SecretsConfig.readMinioCredentials (SecretsConfig.secretsMinio secretsConfig)
  let minio = ClusterConfig.clusterMinio clusterConfig
      (scheme, hostPort) = splitMinioEndpoint (ClusterConfig.minioEndpoint minio)
  pure
    PresignedUrlConfig
      { presignedScheme = scheme,
        presignedEndpoint = hostPort,
        presignedPathPrefix = "",
        presignedRegion = ClusterConfig.minioRegion minio,
        presignedAccessKeyId = SecretsConfig.minioAccessKey minioCreds,
        presignedSecretAccessKey = SecretsConfig.minioSecretKey minioCreds,
        presignedExpirySeconds = 60
      }

ensureDemoBucketsWithRetry :: PresignedUrlConfig -> [Text] -> IO ()
ensureDemoBucketsWithRetry config bucketNames = go (12 :: Int)
  where
    go attemptsRemaining = do
      result <- try @SomeException (mapM_ (ensureDemoBucket config) bucketNames)
      case result of
        Right () ->
          hPutStrLn stderr "demo bucket reconcile complete"
        Left err
          | attemptsRemaining <= 1 ->
              ioError
                ( userError
                    ( "demo bucket reconcile failed after retries: "
                        <> show err
                    )
                )
          | otherwise -> do
              hPutStrLn
                stderr
                ( "demo bucket reconcile attempt failed; retrying: "
                    <> show err
                )
              threadDelay 5000000
              go (attemptsRemaining - 1)

ensureDemoBucket :: PresignedUrlConfig -> Text -> IO ()
ensureDemoBucket config bucketName = do
  now <- getCurrentTime
  let signed =
        presignedBucketUrl
          config
          PresignedBucketRequest
            { presignedBucketRequestMethod = HttpPut,
              presignedBucketRequestBucket = bucketName,
              presignedBucketRequestNow = now
            }
  manager <- newManager defaultManagerSettings
  requestValue <- parseRequest (Text.unpack (unPresignedUrl signed))
  response <-
    httpLbs
      ( requestValue
          { method = methodPut,
            requestBody = RequestBodyLBS "",
            responseTimeout = responseTimeoutMicro 5000000
          }
      )
      manager
  let code = statusCode (responseStatus response)
  unless (code == 200 || code == 409) $
    ioError
      ( userError
          ( "MinIO bucket reconcile for "
              <> Text.unpack bucketName
              <> " returned HTTP "
              <> show code
          )
      )

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
    ["api", "account"]
      | requestMethod request == methodDelete && demoEnabled ->
          handleAccountDeletion options jwksCache realmConfig maybeClusterConfig request respond
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
            ),
      DemoWebSocket.wsStartUserStreams =
        RuntimePulsar.streamDemoUserMetadata
          (demoPaths options)
          (demoRuntimeMode options)
          maybeClusterConfig,
      DemoWebSocket.wsStartContextStream =
        RuntimePulsar.streamDemoContextConversation
          (demoPaths options)
          (demoRuntimeMode options)
          maybeClusterConfig
    }

mapDispatchError :: IO () -> IO (Either DemoWebSocket.WebSocketDispatchError ())
mapDispatchError action = do
  result <- try @SomeException action
  case result of
    Right () -> pure (Right ())
    Left err ->
      case fromException err of
        Just validationError ->
          pure
            ( Left
                DemoWebSocket.WebSocketDispatchError
                  { DemoWebSocket.webSocketDispatchErrorCode = RuntimePulsar.demoClientMessageErrorCode validationError,
                    DemoWebSocket.webSocketDispatchErrorMessage = RuntimePulsar.demoClientMessageErrorMessage validationError
                  }
            )
        Nothing ->
          pure
            ( Left
                DemoWebSocket.WebSocketDispatchError
                  { DemoWebSocket.webSocketDispatchErrorCode = "ws_pulsar_dispatch_failed",
                    DemoWebSocket.webSocketDispatchErrorMessage = Text.pack (show err)
                  }
            )

-- | Phase 7 Sprint 7.9: /api/objects upload-grant + download-grant
-- handlers. Both endpoints consume a Keycloak-signed JWT in the
-- @Authorization: Bearer ...@ header, derive the @UserId@ from the
-- token's @sub@ claim, scope the requested artifact to
-- @users/<userId>/contexts/<contextId>/{uploads,generated}/@, and mint a
-- presigned PUT or GET URL the browser uses to talk to MinIO directly.
-- The demo backend never proxies the binary bytes.
data AuthFailure = AuthFailure Status String

authenticateBearerUser ::
  JwksCache ->
  KeycloakRealmConfig ->
  Request ->
  IO (Either AuthFailure UserId)
authenticateBearerUser jwksCache realmConfig request =
  case extractBearerToken request of
    Nothing -> pure (Left (AuthFailure status401 "missing bearer token"))
    Just token -> do
      jwksResult <- loadJwksCached jwksCache realmConfig
      case jwksResult of
        Left jwksError ->
          pure (Left (AuthFailure status503 ("JWKS fetch failed: " <> jwksError)))
        Right jwks -> do
          now <- getCurrentTime
          pure $
            case verifyAndParseJwt (realmValidationConfig realmConfig) now jwks token of
              Left jwtError ->
                Left (AuthFailure status401 ("invalid JWT: " <> renderJwtError jwtError))
              Right claims ->
                Right (UserId (Jwt.jwtClaimSubject claims))

respondAuthFailure :: AuthFailure -> (Response -> IO responseReceived) -> IO responseReceived
respondAuthFailure (AuthFailure responseStatus message) respond =
  respond (textResponse responseStatus message)

data ObjectsAction = ObjectsUpload | ObjectsDownload

handleObjectsGrant ::
  JwksCache ->
  KeycloakRealmConfig ->
  Request ->
  ObjectsAction ->
  (Response -> IO responseReceived) ->
  IO responseReceived
handleObjectsGrant jwksCache realmConfig request action respond = do
  authResult <- authenticateBearerUser jwksCache realmConfig request
  case authResult of
    Left authFailure -> respondAuthFailure authFailure respond
    Right userId -> do
      now <- getCurrentTime
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
              let contextId = artifactUploadRequestContextId uploadRequest
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

handleAccountDeletion ::
  DemoApiOptions ->
  JwksCache ->
  KeycloakRealmConfig ->
  Maybe ClusterConfig.ClusterConfig ->
  Request ->
  (Response -> IO responseReceived) ->
  IO responseReceived
handleAccountDeletion options jwksCache realmConfig maybeClusterConfig request respond = do
  authResult <- authenticateBearerUser jwksCache realmConfig request
  case authResult of
    Left authFailure -> respondAuthFailure authFailure respond
    Right userId -> do
      presignedResult <- loadInternalMinioPresignedConfig
      case presignedResult of
        Left configError ->
          respond (textResponse status503 ("account cleanup config missing: " <> configError))
        Right presigned -> do
          cleanupResult <- try @SomeException $ do
            minioDeleted <- deleteMinioUserObjects presigned userId
            pulsarDeleted <-
              RuntimePulsar.deleteDemoUserTopicsWithAttemptBudget
                (demoPaths options)
                (demoRuntimeMode options)
                maybeClusterConfig
                userId
                accountPulsarCleanupAttemptBudget
            pure (minioDeleted, pulsarDeleted)
          case cleanupResult of
            Left err ->
              respond (textResponse status500 ("account cleanup failed: " <> show err))
            Right (minioDeleted, pulsarDeleted) -> do
              let remainingTopics = RuntimePulsar.demoUserTopicDeletionRemaining pulsarDeleted
                  cleanupComplete = null remainingTopics
                  responseStatus = if cleanupComplete then status200 else status202
              hPutStrLn
                stderr
                ( "account cleanup for "
                    <> Text.unpack (unUserId userId)
                    <> ": minioObjectsDeleted="
                    <> show minioDeleted
                    <> " pulsarTopicsDeleted="
                    <> show (RuntimePulsar.demoUserTopicDeletionDeleted pulsarDeleted)
                    <> " cleanupComplete="
                    <> show cleanupComplete
                    <> " remainingTopics="
                    <> show (length remainingTopics)
                )
              respond
                ( jsonResponse
                    responseStatus
                    ( object
                        [ "userId" .= userId,
                          "cleanupComplete" .= cleanupComplete,
                          "minioObjectsDeleted" .= minioDeleted,
                          "pulsarTopicsDeleted" .= RuntimePulsar.demoUserTopicDeletionDeleted pulsarDeleted,
                          "pulsarTopicsRemaining" .= remainingTopics
                        ]
                    )
                )

accountPulsarCleanupAttemptBudget :: Int
accountPulsarCleanupAttemptBudget = 32

deleteMinioUserObjects :: PresignedUrlConfig -> UserId -> IO Int
deleteMinioUserObjects config userId = do
  objectKeys <- listMinioUserObjectKeys config userId
  deleted <- forM objectKeys (deleteMinioObject config)
  pure (length (filter id deleted))

listMinioUserObjectKeys :: PresignedUrlConfig -> UserId -> IO [Text]
listMinioUserObjectKeys config userId = do
  manager <- newManager defaultManagerSettings
  go manager Nothing []
  where
    DemoObjectsBucket bucket = defaultDemoObjectsBucket
    UserPrefix prefix = userPrefix userId

    go manager maybeContinuation acc = do
      now <- getCurrentTime
      let signed =
            presignedBucketUrlWithQuery
              config
              PresignedBucketRequest
                { presignedBucketRequestMethod = HttpGet,
                  presignedBucketRequestBucket = bucket,
                  presignedBucketRequestNow = now
                }
              ( listObjectsQuery prefix
                  <> maybe [] (\token -> [("continuation-token", token)]) maybeContinuation
              )
      requestValue <- parseRequest (Text.unpack (unPresignedUrl signed))
      response <-
        httpLbs
          (requestValue {responseTimeout = responseTimeoutMicro 5000000})
          manager
      case statusCode (responseStatus response) of
        200 -> do
          let bodyText = TextEncoding.decodeUtf8 (LazyByteString.toStrict (responseBody response))
              keys = extractXmlTagValues "Key" bodyText
              isTruncated = listToMaybe (extractXmlTagValues "IsTruncated" bodyText) == Just "true"
              nextContinuation = listToMaybe (extractXmlTagValues "NextContinuationToken" bodyText)
          case nextContinuation of
            Just _ | isTruncated -> go manager nextContinuation (acc <> keys)
            _ -> pure (acc <> keys)
        404 -> pure acc
        code ->
          ioError
            ( userError
                ( "MinIO ListObjectsV2 for account prefix returned HTTP "
                    <> show code
                    <> ":\n"
                    <> lazyBodyToString (responseBody response)
                )
            )

listObjectsQuery :: Text -> [(Text, Text)]
listObjectsQuery prefix =
  [ ("list-type", "2"),
    ("prefix", prefix)
  ]

deleteMinioObject :: PresignedUrlConfig -> Text -> IO Bool
deleteMinioObject config objectKeyValue = do
  now <- getCurrentTime
  let DemoObjectsBucket bucket = defaultDemoObjectsBucket
      objectReference =
        ObjectRef
          { objectBucket = bucket,
            objectKey = objectKeyValue
          }
      signed =
        presignedUrlForRequest
          config
          PresignedRequest
            { presignedRequestMethod = HttpDelete,
              presignedRequestObject = objectReference,
              presignedRequestNow = now
            }
  manager <- newManager defaultManagerSettings
  requestValue <- parseRequest (Text.unpack (unPresignedUrl signed))
  response <-
    httpLbs
      ( requestValue
          { method = methodDelete,
            responseTimeout = responseTimeoutMicro 5000000
          }
      )
      manager
  let code = statusCode (responseStatus response)
  if code `elem` [200, 202, 204]
    then pure True
    else
      if code == 404
        then pure False
        else
          ioError
            ( userError
                ( "MinIO DELETE for account object returned HTTP "
                    <> show code
                    <> ":\n"
                    <> lazyBodyToString (responseBody response)
                )
            )

extractXmlTagValues :: Text -> Text -> [Text]
extractXmlTagValues tagName = go
  where
    openTag = "<" <> tagName <> ">"
    closeTag = "</" <> tagName <> ">"
    go remaining =
      let (_, afterOpenWithTag) = Text.breakOn openTag remaining
       in if Text.null afterOpenWithTag
            then []
            else
              let afterOpen = Text.drop (Text.length openTag) afterOpenWithTag
                  (rawValue, afterCloseWithTag) = Text.breakOn closeTag afterOpen
               in if Text.null afterCloseWithTag
                    then []
                    else
                      decodeXmlEntities rawValue
                        : go (Text.drop (Text.length closeTag) afterCloseWithTag)

decodeXmlEntities :: Text -> Text
decodeXmlEntities =
  Text.replace "&amp;" "&"
    . Text.replace "&apos;" "'"
    . Text.replace "&quot;" "\""
    . Text.replace "&gt;" ">"
    . Text.replace "&lt;" "<"

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
    httpLbs (requestValue {responseTimeout = responseTimeoutMicro 5000000}) manager
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
loadPresignedConfig =
  loadPresignedConfigWithEndpoint
    ClusterConfig.minioPresignPublicEndpoint
    splitMinioPublicEndpoint

loadInternalMinioPresignedConfig :: IO (Either String PresignedUrlConfig)
loadInternalMinioPresignedConfig =
  loadPresignedConfigWithEndpoint
    ClusterConfig.minioEndpoint
    ( \raw ->
        let (scheme, hostPort) = splitMinioEndpoint raw
         in (scheme, hostPort, "")
    )

loadPresignedConfigWithEndpoint ::
  (ClusterConfig.MinioWiring -> Text) ->
  (Text -> (Text, Text, Text)) ->
  IO (Either String PresignedUrlConfig)
loadPresignedConfigWithEndpoint endpointSelector splitEndpoint = do
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
          (scheme, hostPort, pathPrefix) = splitEndpoint (endpointSelector minio)
      pure
        ( Right
            PresignedUrlConfig
              { presignedScheme = scheme,
                presignedEndpoint = hostPort,
                presignedPathPrefix = pathPrefix,
                presignedRegion = ClusterConfig.minioRegion minio,
                presignedAccessKeyId = SecretsConfig.minioAccessKey minioCreds,
                presignedSecretAccessKey = SecretsConfig.minioSecretKey minioCreds,
                presignedExpirySeconds = fromIntegral (ClusterConfig.minioPresignExpirySeconds minio)
              }
        )

-- | Phase 7 Sprint 7.17: MinIO endpoint fields carry full
-- @http://host:port@ URLs, but the SigV4 canonical request signs only
-- the @host:port@ as the @host@ header. Strip any scheme prefix and
-- record it separately so the minted URL points at the right transport.
splitMinioEndpoint :: Text -> (Text, Text)
splitMinioEndpoint raw =
  case Text.stripPrefix "https://" raw of
    Just hostPort -> ("https", hostPort)
    Nothing ->
      case Text.stripPrefix "http://" raw of
        Just hostPort -> ("http", hostPort)
        Nothing -> ("http", raw)

splitMinioPublicEndpoint :: Text -> (Text, Text, Text)
splitMinioPublicEndpoint raw =
  let (scheme, withoutScheme) = splitMinioEndpoint raw
      (hostPort, pathPrefix) = Text.breakOn "/" withoutScheme
   in (scheme, hostPort, pathPrefix)

renderJwtError :: JwtError -> String
renderJwtError = show

renderDispositionForMime :: ArtifactMimeType -> ArtifactRenderDisposition
renderDispositionForMime (ArtifactMimeType mimeType)
  | mimeType == "audio/midi" = DownloadOnly
  | mimeType == "audio/x-midi" = DownloadOnly
  | "image/" `Text.isPrefixOf` mimeType = RenderInline
  | "audio/" `Text.isPrefixOf` mimeType = RenderInline
  | "video/" `Text.isPrefixOf` mimeType = RenderInline
  | mimeType == "application/pdf" = BrowserNativePdf
  | mimeType == "application/json" = BoundedTextPreview
  | "text/" `Text.isPrefixOf` mimeType = BoundedTextPreview
  | otherwise = DownloadOnly

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

lazyBodyToString :: LazyByteString.ByteString -> String
lazyBodyToString = ByteStringChar8.unpack . LazyByteString.toStrict

jsonResponse :: (ToJSON a) => Status -> a -> Response
jsonResponse responseStatus payload =
  responseLBS responseStatus [(hContentType, "application/json; charset=utf-8")] (encode payload)

textResponse :: Status -> String -> Response
textResponse responseStatus body =
  responseLBS responseStatus [(hContentType, "text/plain; charset=utf-8")] (LazyByteString.fromStrict (ByteStringChar8.pack body))

-- type HostPreference = String
fromStringHost :: String -> HostPreference
fromStringHost = fromString
