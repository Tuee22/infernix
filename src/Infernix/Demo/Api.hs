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
import Data.List (nub)
import Data.Maybe (fromMaybe, listToMaybe)
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
    sanitizeFilename,
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
import Infernix.Objects.Sts qualified as Sts
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
    ContextId (..),
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
import Network.HTTP.Client qualified as HttpClient
import Network.HTTP.Types
  ( Status,
    hAuthorization,
    hContentType,
    hCookie,
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
    status502,
    status503,
  )
import Network.HTTP.Types.Status (statusCode)
import Network.Wai
  ( Application,
    Request,
    Response,
    pathInfo,
    queryString,
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
        presignedExpirySeconds = 60,
        presignedSessionToken = Nothing
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
          withAdminRequest jwksCache realmConfig request respond (serveCacheStatus options respond)
    ["api", "cache", "evict"]
      | requestMethod request == methodPost && demoEnabled ->
          withAdminRequest jwksCache realmConfig request respond (handleCacheMutation options request EvictCache respond)
    ["api", "cache", "rebuild"]
      | requestMethod request == methodPost && demoEnabled ->
          withAdminRequest jwksCache realmConfig request respond (handleCacheMutation options request RebuildCache respond)
    ["api", "admin", "overview"]
      | requestMethod request == methodGet && demoEnabled ->
          handleAdminOverview options jwksCache realmConfig request respond
    ["api", "account"]
      | requestMethod request == methodDelete && demoEnabled ->
          handleAccountDeletion options jwksCache realmConfig maybeClusterConfig request respond
    ["api", "objects", "upload"]
      | requestMethod request == methodPost && demoEnabled ->
          handleObjectsUpload jwksCache realmConfig request respond
    ["api", "objects", "download"]
      | requestMethod request == methodPost && demoEnabled ->
          handleObjectsDownloadGrant jwksCache realmConfig request respond
    ["api", "objects", "download"]
      | requestMethod request == methodGet && demoEnabled ->
          handleObjectsDownloadBytes jwksCache realmConfig request respond
    ["api", "objects", "list"]
      | requestMethod request == methodGet && demoEnabled ->
          handleObjectsList jwksCache realmConfig request respond
    ["api", "objects"]
      | requestMethod request == methodDelete && demoEnabled ->
          handleObjectsDelete jwksCache realmConfig request respond
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

-- | Phase 7 Sprint 7.25: /api/objects is a webapp object-proxy. The browser
-- never holds a MinIO credential, never receives a presigned MinIO URL, and
-- never reaches MinIO through the gateway. Every endpoint authenticates the
-- caller (Keycloak JWT -> @UserId@ from @sub@), derives the object key
-- server-side from that @sub@ (never from a client-supplied full key), and
-- authorizes it with 'pathBelongsToUser' before reading or writing MinIO over
-- the cluster-internal endpoint ('loadInternalMinioPresignedConfig'). This
-- realizes documents/architecture/object_access_doctrine.md and
-- documents/architecture/tenant_isolation_doctrine.md.
data AuthFailure = AuthFailure Status String

authenticateBearerUser ::
  JwksCache ->
  KeycloakRealmConfig ->
  Request ->
  IO (Either AuthFailure UserId)
authenticateBearerUser jwksCache realmConfig request =
  case extractBearerToken request of
    Nothing -> pure (Left (AuthFailure status401 "missing bearer token"))
    Just token -> validateBearerToken jwksCache realmConfig token

-- | Like 'authenticateBearerUser' but also accepts the JWT from the
-- @infernix_operator_token@ cookie when no @Authorization@ header is present.
-- Browser-issued media @src@ fetches (@\<img\>@, @\<audio\>@, @\<video\>@,
-- @\<iframe\>@) cannot set request headers, so the streaming download endpoint
-- accepts the same cookie the operator console already writes.
authenticateRequestUser ::
  JwksCache ->
  KeycloakRealmConfig ->
  Request ->
  IO (Either AuthFailure UserId)
authenticateRequestUser jwksCache realmConfig request =
  case requestToken of
    Nothing -> pure (Left (AuthFailure status401 "missing bearer token"))
    Just token -> validateBearerToken jwksCache realmConfig token
  where
    requestToken =
      case extractBearerToken request of
        Just token -> Just token
        Nothing -> cookieBearerToken request

validateBearerToken ::
  JwksCache ->
  KeycloakRealmConfig ->
  Text ->
  IO (Either AuthFailure UserId)
validateBearerToken jwksCache realmConfig token = do
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

-- | The Infernix cluster-wide admin realm role. Matches the chart default
-- @keycloak.realm.adminRealmRole@; Keycloak emits it in @realm_access.roles@.
infernixAdminRealmRole :: Text
infernixAdminRealmRole = "infernix-admin"

-- | Authenticate the caller AND require the admin realm role. Gates the
-- cluster-wide model-cache mutations so ordinary or self-registered users
-- (whose tokens carry no admin role) cannot mutate shared cluster state.
-- Accepts the Authorization header or the operator cookie, like
-- 'authenticateRequestUser'. Returns 401 without a token, 403 for a valid
-- non-admin token.
authenticateAdminRequest ::
  JwksCache ->
  KeycloakRealmConfig ->
  Request ->
  IO (Either AuthFailure UserId)
authenticateAdminRequest jwksCache realmConfig request =
  case adminRequestToken of
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
              Right claims
                | Jwt.jwtClaimsHasRealmRole infernixAdminRealmRole claims ->
                    Right (UserId (Jwt.jwtClaimSubject claims))
                | otherwise ->
                    Left (AuthFailure status403 "admin realm role required")
  where
    adminRequestToken =
      case extractBearerToken request of
        Just token -> Just token
        Nothing -> cookieBearerToken request

-- | Run @action@ only if the caller carries the admin realm role; otherwise
-- respond with the auth failure (401/403/503). Gates @\/api\/cache\/{evict,rebuild}@.
withAdminRequest ::
  JwksCache ->
  KeycloakRealmConfig ->
  Request ->
  (Response -> IO responseReceived) ->
  IO responseReceived ->
  IO responseReceived
withAdminRequest jwksCache realmConfig request respond action = do
  authResult <- authenticateAdminRequest jwksCache realmConfig request
  case authResult of
    Left authFailure -> respondAuthFailure authFailure respond
    Right _ -> action

-- | @GET \/api\/admin\/overview@ — Phase 9 Sprint 9.5. The admin-only
-- cluster-wide monitoring surface. Admin-gated ('withAdminRequest'), it
-- aggregates only real, cluster-wide platform state the webapp already
-- observes: the active substrate + dispatch mode, the generated catalog /
-- engine-pool sizes, the coordinator-visible model-cache manifest count, and
-- the number of distinct @users\/<sub>\/@ prefixes present in the demo-objects
-- bucket (the all-user object footprint). Every field is derived, never
-- fabricated; the user count is reported as @null@ with an explicit error
-- string if MinIO cannot be listed. Non-admins never reach this endpoint.
handleAdminOverview ::
  DemoApiOptions ->
  JwksCache ->
  KeycloakRealmConfig ->
  Request ->
  (Response -> IO responseReceived) ->
  IO responseReceived
handleAdminOverview options jwksCache realmConfig request respond =
  withAdminRequest jwksCache realmConfig request respond $ do
    demoConfig <- decodeDemoConfigFile (demoConfigPath options)
    let activeRuntimeMode = configRuntimeMode demoConfig
    manifests <- listCacheManifests (demoPaths options) activeRuntimeMode
    userCountResult <- countUsersWithObjects
    let usersWithObjectsMaybe = either (const Nothing) Just userCountResult
        usersWithObjectsErrorMaybe = either Just (const Nothing) userCountResult
    respond
      ( jsonResponse
          status200
          ( object
              [ "runtimeMode" .= runtimeModeId activeRuntimeMode,
                "substrate" .= runtimeModeId activeRuntimeMode,
                "dispatchMode" .= bridgeModeLabel (demoBridgeMode options),
                "demoUiEnabled" .= demoUiEnabled demoConfig,
                "catalogModelCount" .= length (models demoConfig),
                "engineBindingCount" .= length (engines demoConfig),
                "engineNames" .= nub (map engineBindingName (engines demoConfig)),
                "enginePoolCount" .= length (enginePools demoConfig),
                "engineMemberCount" .= length (engineMembers demoConfig),
                "modelCacheEntryCount" .= length manifests,
                "usersWithObjects" .= (usersWithObjectsMaybe :: Maybe Int),
                "usersWithObjectsError" .= (usersWithObjectsErrorMaybe :: Maybe String)
              ]
          )
      )

-- | The dispatch-mode label the admin overview reports for the active demo
-- bridge posture.
bridgeModeLabel :: DemoBridgeMode -> Text
bridgeModeLabel DirectDemoInference = "direct"
bridgeModeLabel PulsarDaemonBridge = "pulsar"

-- | Count the distinct @users\/<sub>\/@ prefixes present in the demo-objects
-- bucket. This is the real all-user footprint the admin overview surfaces
-- (users who have stored at least one object). Returns @Left@ with a diagnostic
-- when the object-storage config is missing or MinIO cannot be listed, so the
-- overview reports the count honestly instead of fabricating one.
countUsersWithObjects :: IO (Either String Int)
countUsersWithObjects = do
  presignedResult <- loadInternalMinioPresignedConfig
  case presignedResult of
    Left configError -> pure (Left configError)
    Right presigned -> do
      attempt <- try @SomeException (listMinioUserObjectPrefixes presigned)
      case attempt of
        Left err -> pure (Left (show err))
        Right prefixes -> pure (Right (length prefixes))

-- | List the distinct top-level @users\/<sub>\/@ common prefixes in the
-- demo-objects bucket via a delimited MinIO ListObjectsV2. Each prefix is one
-- user with stored objects.
listMinioUserObjectPrefixes :: PresignedUrlConfig -> IO [Text]
listMinioUserObjectPrefixes config = do
  manager <- newManager defaultManagerSettings
  now <- getCurrentTime
  let DemoObjectsBucket bucket = defaultDemoObjectsBucket
      signed =
        presignedBucketUrlWithQuery
          config
          PresignedBucketRequest
            { presignedBucketRequestMethod = HttpGet,
              presignedBucketRequestBucket = bucket,
              presignedBucketRequestNow = now
            }
          [ ("list-type", "2"),
            ("prefix", "users/"),
            ("delimiter", "/")
          ]
  requestValue <- parseRequest (Text.unpack (unPresignedUrl signed))
  response <-
    httpLbs
      (requestValue {responseTimeout = responseTimeoutMicro 5000000})
      manager
  case statusCode (responseStatus response) of
    200 ->
      let bodyText = TextEncoding.decodeUtf8 (LazyByteString.toStrict (responseBody response))
       in pure (nub (extractXmlTagValues "Prefix" bodyText))
    404 -> pure []
    code ->
      ioError
        ( userError
            ("MinIO ListObjectsV2 for user prefixes returned HTTP " <> show code)
        )

-- | The operator-console cookie the SPA writes after login
-- (chart values @operatorConsole.jwtGating.cookieName@; the Keycloak edge
-- SecurityPolicy reads the same cookie for operator routes).
operatorTokenCookieName :: Text
operatorTokenCookieName = "infernix_operator_token"

cookieBearerToken :: Request -> Maybe Text
cookieBearerToken request = do
  cookieHeader <- TextEncoding.decodeUtf8 <$> lookup hCookie (requestHeaders request)
  let pairs =
        [ (Text.strip name, Text.drop 1 rest)
        | rawPair <- Text.splitOn ";" cookieHeader,
          let (name, rest) = Text.breakOn "=" rawPair
        ]
  value <- lookup operatorTokenCookieName pairs
  if Text.null value then Nothing else Just value

respondAuthFailure :: AuthFailure -> (Response -> IO responseReceived) -> IO responseReceived
respondAuthFailure (AuthFailure responseStatus message) respond =
  respond (textResponse responseStatus message)

-- | @POST \/api\/objects\/upload@ — the webapp stores the request body bytes
-- in MinIO server-side over the internal endpoint. Metadata
-- (@contextId@, @displayName@) arrives as query parameters; the object key is
-- derived entirely server-side from the verified @sub@ plus the sanitized
-- display name, so the caller can never write outside its own prefix.
handleObjectsUpload ::
  JwksCache ->
  KeycloakRealmConfig ->
  Request ->
  (Response -> IO responseReceived) ->
  IO responseReceived
handleObjectsUpload jwksCache realmConfig request respond = do
  authResult <- authenticateBearerUser jwksCache realmConfig request
  case authResult of
    Left authFailure -> respondAuthFailure authFailure respond
    Right userId -> do
      let query = queryString request
      case (,) <$> lookupQueryText "contextId" query <*> lookupQueryText "displayName" query of
        Nothing ->
          respond (textResponse status400 "upload requires contextId and displayName query parameters")
        Just (contextIdValue, displayNameValue) -> do
          let contextId = ContextId contextIdValue
              objectReference = uploadObjectKey userId contextId (sanitizeFilename displayNameValue)
          if not (pathBelongsToUser userId (objectKey objectReference))
            then respond (textResponse status403 "object key is outside the caller's scope")
            else do
              presignedResult <- loadUserScopedMinioPresignedConfig userId
              case presignedResult of
                Left configError ->
                  respond (textResponse status503 ("object storage config missing: " <> configError))
                Right presigned -> do
                  bodyBytes <- strictRequestBody request
                  now <- getCurrentTime
                  putResult <- putMinioObjectBytes presigned objectReference bodyBytes
                  case putResult of
                    Left err ->
                      respond (textResponse status502 ("object upload failed: " <> err))
                    Right () ->
                      respond
                        ( jsonResponse
                            status200
                            ArtifactUploadGrant
                              { artifactUploadGrantObjectRef = objectReference,
                                artifactUploadGrantExpiresAtIso8601 = isoExpiryFor presigned now
                              }
                        )

-- | @POST \/api\/objects\/download@ — returns the typed download metadata
-- (canonical server-derived 'ObjectRef', MIME, render disposition) so the
-- browser knows the object key and how to render it. The bytes are fetched
-- separately from @GET \/api\/objects\/download@; no presigned MinIO URL is
-- ever handed to the browser.
handleObjectsDownloadGrant ::
  JwksCache ->
  KeycloakRealmConfig ->
  Request ->
  (Response -> IO responseReceived) ->
  IO responseReceived
handleObjectsDownloadGrant jwksCache realmConfig request respond = do
  authResult <- authenticateBearerUser jwksCache realmConfig request
  case authResult of
    Left authFailure -> respondAuthFailure authFailure respond
    Right userId -> do
      bodyBytes <- strictRequestBody request
      case eitherDecode bodyBytes of
        Left decodeError ->
          respond (textResponse status400 ("invalid request body: " <> decodeError))
        Right downloadRequest -> do
          presignedResult <- loadInternalMinioPresignedConfig
          case presignedResult of
            Left configError ->
              respond (textResponse status503 ("object storage config missing: " <> configError))
            Right presigned -> do
              now <- getCurrentTime
              let contextId = artifactUploadRequestContextId downloadRequest
                  mimeType = artifactUploadRequestMimeType downloadRequest
                  objectReference =
                    uploadObjectKey userId contextId (sanitizeFilename (artifactUploadRequestDisplayName downloadRequest))
              if not (pathBelongsToUser userId (objectKey objectReference))
                then respond (textResponse status403 "object key is outside the caller's scope")
                else
                  respond
                    ( jsonResponse
                        status200
                        ArtifactDownloadGrant
                          { artifactDownloadGrantObjectRef = objectReference,
                            artifactDownloadGrantMimeType = mimeType,
                            artifactDownloadGrantRenderDisposition = renderDispositionForMime mimeType,
                            artifactDownloadGrantExpiresAtIso8601 = isoExpiryFor presigned now
                          }
                    )

-- | @GET \/api\/objects\/download?key=...&mimeType=...@ — streams the object
-- bytes back through the webapp. Authenticates via the @Authorization@ header
-- or the operator cookie (for browser-issued media @src@ fetches), forces the
-- demo-objects bucket, and rejects any key outside the caller's @users\/<sub>\/@
-- prefix with HTTP 403 before touching MinIO.
handleObjectsDownloadBytes ::
  JwksCache ->
  KeycloakRealmConfig ->
  Request ->
  (Response -> IO responseReceived) ->
  IO responseReceived
handleObjectsDownloadBytes jwksCache realmConfig request respond = do
  authResult <- authenticateRequestUser jwksCache realmConfig request
  case authResult of
    Left authFailure -> respondAuthFailure authFailure respond
    Right userId -> do
      let query = queryString request
      case lookupQueryText "key" query of
        Nothing ->
          respond (textResponse status400 "download requires a key query parameter")
        Just keyValue ->
          if not (pathBelongsToUser userId keyValue)
            then respond (textResponse status403 "object key is outside the caller's scope")
            else do
              presignedResult <- loadUserScopedMinioPresignedConfig userId
              case presignedResult of
                Left configError ->
                  respond (textResponse status503 ("object storage config missing: " <> configError))
                Right presigned -> do
                  let DemoObjectsBucket bucket = defaultDemoObjectsBucket
                      objectReference = ObjectRef {objectBucket = bucket, objectKey = keyValue}
                      mimeType = fromMaybe "application/octet-stream" (lookupQueryText "mimeType" query)
                      disposition = renderDispositionForMime (ArtifactMimeType mimeType)
                  getResult <- getMinioObjectBytes presigned objectReference
                  case getResult of
                    Left err ->
                      respond (textResponse status502 ("object download failed: " <> err))
                    Right (404, _) ->
                      respond (textResponse status404 "object not found")
                    Right (200, body) ->
                      respond (objectBytesResponse mimeType disposition (downloadFilename keyValue) body)
                    Right (code, _) ->
                      respond (textResponse status502 ("object download failed: MinIO HTTP " <> show code))

-- | @GET \/api\/objects\/list@ — Phase 7 Sprint 7.26. Lists the caller's own
-- objects scoped server-side to the @users\/<sub>\/@ prefix (derived from the
-- verified token) and returns them as a JSON array of typed 'ObjectRef'. The
-- browser never names a prefix; the scope is the caller's own by construction.
handleObjectsList ::
  JwksCache ->
  KeycloakRealmConfig ->
  Request ->
  (Response -> IO responseReceived) ->
  IO responseReceived
handleObjectsList jwksCache realmConfig request respond = do
  authResult <- authenticateBearerUser jwksCache realmConfig request
  case authResult of
    Left authFailure -> respondAuthFailure authFailure respond
    Right userId -> do
      presignedResult <- loadUserScopedMinioPresignedConfig userId
      case presignedResult of
        Left configError ->
          respond (textResponse status503 ("object storage config missing: " <> configError))
        Right presigned -> do
          listResult <- try @SomeException (listMinioUserObjectKeys presigned userId)
          case listResult of
            Left err ->
              respond (textResponse status502 ("object listing failed: " <> show err))
            Right keys -> do
              let DemoObjectsBucket bucket = defaultDemoObjectsBucket
                  refs = [ObjectRef {objectBucket = bucket, objectKey = key} | key <- keys]
              respond (jsonResponse status200 refs)

-- | @DELETE \/api\/objects?key=…@ — Phase 7 Sprint 7.26. Removes a single
-- caller-owned object. The key is authorized through the same
-- 'pathBelongsToUser' choke point on the verified @sub@ before any MinIO
-- operation, so a cross-user key is rejected with HTTP 403.
handleObjectsDelete ::
  JwksCache ->
  KeycloakRealmConfig ->
  Request ->
  (Response -> IO responseReceived) ->
  IO responseReceived
handleObjectsDelete jwksCache realmConfig request respond = do
  authResult <- authenticateBearerUser jwksCache realmConfig request
  case authResult of
    Left authFailure -> respondAuthFailure authFailure respond
    Right userId -> do
      let query = queryString request
      case lookupQueryText "key" query of
        Nothing ->
          respond (textResponse status400 "delete requires a key query parameter")
        Just keyValue ->
          if not (pathBelongsToUser userId keyValue)
            then respond (textResponse status403 "object key is outside the caller's scope")
            else do
              presignedResult <- loadUserScopedMinioPresignedConfig userId
              case presignedResult of
                Left configError ->
                  respond (textResponse status503 ("object storage config missing: " <> configError))
                Right presigned -> do
                  deleteResult <- try @SomeException (deleteMinioObject presigned keyValue)
                  case deleteResult of
                    Left err ->
                      respond (textResponse status502 ("object deletion failed: " <> show err))
                    Right True ->
                      respond (jsonResponse status200 (object ["objectKey" .= keyValue, "deleted" .= True]))
                    Right False ->
                      respond (textResponse status404 "object not found")

-- | Server-side PUT of the upload bytes against the internal MinIO endpoint.
putMinioObjectBytes :: PresignedUrlConfig -> ObjectRef -> LazyByteString.ByteString -> IO (Either String ())
putMinioObjectBytes config objectReference body = do
  now <- getCurrentTime
  let signed =
        presignedUrlForRequest
          config
          PresignedRequest
            { presignedRequestMethod = HttpPut,
              presignedRequestObject = objectReference,
              presignedRequestNow = now
            }
  attempt <- try @SomeException $ do
    manager <- newManager defaultManagerSettings
    base <- parseRequest (Text.unpack (unPresignedUrl signed))
    httpLbs
      ( base
          { method = methodPut,
            requestBody = RequestBodyLBS body,
            responseTimeout = responseTimeoutMicro 60000000
          }
      )
      manager
  case attempt of
    Left err -> pure (Left (show err))
    Right response ->
      let code = statusCode (responseStatus response)
       in if code >= 200 && code < 300
            then pure (Right ())
            else pure (Left ("MinIO PUT returned HTTP " <> show code <> ": " <> lazyBodyToString (responseBody response)))

-- | Server-side GET of an object's bytes against the internal MinIO endpoint.
-- Returns @Right (status, body)@ on a completed HTTP exchange (so 404 is
-- distinguishable from 200) and @Left@ on a transport failure.
getMinioObjectBytes :: PresignedUrlConfig -> ObjectRef -> IO (Either String (Int, LazyByteString.ByteString))
getMinioObjectBytes config objectReference = do
  now <- getCurrentTime
  let signed =
        presignedUrlForRequest
          config
          PresignedRequest
            { presignedRequestMethod = HttpGet,
              presignedRequestObject = objectReference,
              presignedRequestNow = now
            }
  attempt <- try @SomeException $ do
    manager <- newManager defaultManagerSettings
    base <- parseRequest (Text.unpack (unPresignedUrl signed))
    httpLbs (base {responseTimeout = responseTimeoutMicro 60000000}) manager
  case attempt of
    Left err -> pure (Left (show err))
    Right response -> pure (Right (statusCode (responseStatus response), responseBody response))

-- | Build a byte-streaming response with the correct @Content-Type@ and
-- @Content-Disposition@. Download-only artifacts force @attachment@; everything
-- else renders @inline@ so the browser can preview it.
objectBytesResponse :: Text -> ArtifactRenderDisposition -> Text -> LazyByteString.ByteString -> Response
objectBytesResponse mimeType disposition filename =
  responseLBS
    status200
    [ (hContentType, TextEncoding.encodeUtf8 mimeType),
      ("Content-Disposition", TextEncoding.encodeUtf8 (dispositionPrefix <> "; filename=\"" <> filename <> "\""))
    ]
  where
    dispositionPrefix = case disposition of
      DownloadOnly -> "attachment"
      _ -> "inline"

downloadFilename :: Text -> Text
downloadFilename key = sanitizeFilename (last ("file" : Text.splitOn "/" key))

lookupQueryText :: ByteString.ByteString -> [(ByteString.ByteString, Maybe ByteString.ByteString)] -> Maybe Text
lookupQueryText name query = do
  maybeValue <- lookup name query
  rawValue <- maybeValue
  let decoded = TextEncoding.decodeUtf8 rawValue
  if Text.null decoded then Nothing else Just decoded

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
accountPulsarCleanupAttemptBudget = 240

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
-- surfaces a typed diagnostic when either is absent. Phase 7 Sprint 7.25
-- retired the public-endpoint variant: the webapp object-proxy and account
-- cleanup both sign against the cluster-internal endpoint, and there is no
-- browser-facing presigned URL.
loadInternalMinioPresignedConfig :: IO (Either String PresignedUrlConfig)
loadInternalMinioPresignedConfig =
  loadPresignedConfigWithEndpoint
    ClusterConfig.minioEndpoint
    ( \raw ->
        let (scheme, hostPort) = splitMinioEndpoint raw
         in (scheme, hostPort, "")
    )

-- | Phase 9 Sprint 9.7: the credential source for a per-user object-proxy
-- operation. When the mounted cluster config sets @minio.stsPerUser = True@,
-- this exchanges the shared root credential for a short-lived MinIO STS
-- credential scoped by an inline session policy to the caller's
-- @users\/<sub>\/@ prefix — a second, IAM-layer isolation boundary independent
-- of the server-side 'pathBelongsToUser' check. The flag defaults to 'True'
-- (STS-scoped credential by default). When it is 'False' — the opt-out — this
-- returns the shared root-credential config unchanged, preserving the validated
-- Phase 7 object path; Wave Q validated the default-on scoped path and its live
-- cross-user IAM denial.
loadUserScopedMinioPresignedConfig :: UserId -> IO (Either String PresignedUrlConfig)
loadUserScopedMinioPresignedConfig userId = do
  rootResult <- loadInternalMinioPresignedConfig
  case rootResult of
    Left err -> pure (Left err)
    Right rootConfig -> do
      maybeClusterConfig <- tryLoadClusterConfig
      let stsEnabled =
            maybe
              False
              (ClusterConfig.minioStsPerUser . ClusterConfig.clusterMinio)
              maybeClusterConfig
      if not stsEnabled
        then pure (Right rootConfig)
        else mintScopedPresignedConfig rootConfig userId

-- | The lifetime of a per-user scoped MinIO credential. Comfortably longer
-- than a single object operation, short enough that a leaked scoped credential
-- expires quickly.
perUserStsDurationSeconds :: Int
perUserStsDurationSeconds = 3600

-- | Exchange the root credential for a per-user scoped MinIO STS credential via
-- @AssumeRole@ with the 'Sts.userScopedPolicyDocument' session policy. Returns
-- a presigned config carrying the scoped access key + session token so every
-- minted URL is IAM-limited to the caller's prefix.
mintScopedPresignedConfig :: PresignedUrlConfig -> UserId -> IO (Either String PresignedUrlConfig)
mintScopedPresignedConfig rootConfig userId = do
  now <- getCurrentTime
  let DemoObjectsBucket bucket = defaultDemoObjectsBucket
      stsConfig =
        Sts.StsConfig
          { Sts.stsScheme = presignedScheme rootConfig,
            Sts.stsEndpoint = presignedEndpoint rootConfig,
            Sts.stsRegion = presignedRegion rootConfig,
            Sts.stsAccessKeyId = presignedAccessKeyId rootConfig,
            Sts.stsSecretAccessKey = presignedSecretAccessKey rootConfig,
            Sts.stsDurationSeconds = perUserStsDurationSeconds,
            Sts.stsBucket = bucket
          }
      signed = Sts.signedStsAssumeRoleRequest stsConfig userId now
  attempt <- try @SomeException $ do
    manager <- newManager defaultManagerSettings
    base <- parseRequest (Text.unpack (Sts.signedStsUrl signed))
    httpLbs
      ( base
          { method = methodPost,
            requestBody = RequestBodyLBS (LazyByteString.fromStrict (TextEncoding.encodeUtf8 (Sts.signedStsBody signed))),
            HttpClient.requestHeaders =
              [ (hContentType, TextEncoding.encodeUtf8 (Sts.signedStsContentType signed)),
                (hAuthorization, TextEncoding.encodeUtf8 (Sts.signedStsAuthorization signed)),
                ("X-Amz-Date", TextEncoding.encodeUtf8 (Sts.signedStsAmzDate signed))
              ],
            responseTimeout = responseTimeoutMicro 10000000
          }
      )
      manager
  case attempt of
    Left err -> pure (Left ("MinIO STS AssumeRole request failed: " <> show err))
    Right response ->
      pure
        ( scopedConfigFromResponse
            rootConfig
            (statusCode (responseStatus response))
            (TextEncoding.decodeUtf8 (LazyByteString.toStrict (responseBody response)))
        )

-- | Interpret the MinIO STS @AssumeRole@ HTTP result into a scoped presigned
-- config or a typed error.
scopedConfigFromResponse :: PresignedUrlConfig -> Int -> Text -> Either String PresignedUrlConfig
scopedConfigFromResponse rootConfig code bodyText
  | code /= 200 =
      Left ("MinIO STS AssumeRole returned HTTP " <> show code <> ": " <> Text.unpack (Text.take 300 bodyText))
  | otherwise = scopedConfigFromCredentials rootConfig bodyText

-- | Fold the parsed scoped credential into a presigned config carrying the
-- scoped access key + STS session token.
scopedConfigFromCredentials :: PresignedUrlConfig -> Text -> Either String PresignedUrlConfig
scopedConfigFromCredentials rootConfig bodyText =
  case Sts.parseAssumeRoleCredentials bodyText of
    Left parseError -> Left ("MinIO STS AssumeRole parse failed: " <> parseError)
    Right creds ->
      Right
        rootConfig
          { presignedAccessKeyId = Sts.scopedAccessKeyId creds,
            presignedSecretAccessKey = Sts.scopedSecretAccessKey creds,
            presignedSessionToken = Just (Sts.scopedSessionToken creds)
          }

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
                presignedExpirySeconds = fromIntegral (ClusterConfig.minioPresignExpirySeconds minio),
                presignedSessionToken = Nothing
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

renderJwtError :: JwtError -> String
renderJwtError = show

renderDispositionForMime :: ArtifactMimeType -> ArtifactRenderDisposition
renderDispositionForMime (ArtifactMimeType mimeType)
  | mimeType == "audio/midi" = RenderMidi
  | mimeType == "audio/x-midi" = RenderMidi
  | "image/" `Text.isPrefixOf` mimeType = RenderInline
  | "audio/" `Text.isPrefixOf` mimeType = RenderInline
  | "video/" `Text.isPrefixOf` mimeType = RenderInline
  | mimeType == "application/pdf" = BrowserNativePdf
  | mimeType == "application/json" = BoundedTextPreview
  | "text/" `Text.isPrefixOf` mimeType = BoundedTextPreview
  | mimeType == "application/vnd.recordare.musicxml+xml" = RenderMusicXml
  | mimeType == "application/vnd.recordare.musicxml" = RenderMusicXml
  | mimeType == "application/zip" = RenderZipStems
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
