{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Phase 7 Sprint 7.3 — durable-context WebSocket entrypoint.
--
-- The supported demo binary mounts this module's 'wsApplication' on the
-- @/ws@ path through a WAI WebSockets upgrade. The handshake validates a
-- Keycloak-signed JWT carried in either the @Authorization: Bearer …@
-- header or the @token@ query parameter (browsers cannot set the
-- @Authorization@ header on WebSocket connects, so the query-string
-- fallback is the only path browsers actually use).
--
-- Per the daemon-topology contract (`documents/architecture/daemon_topology.md`),
-- the demo Service has @sessionAffinity: None@ so any frontend replica
-- can host any session. Each WebSocket connection therefore holds only
-- the transport handle plus the per-context Pulsar Reader cursors;
-- nothing in this module reaches into per-user identity state on the
-- pod's local filesystem.
--
-- Browser-originated state-changing frames now dispatch through an
-- injected Pulsar publisher. The remaining Sprint 7.14 work is the
-- Reader / Failover subscription path that streams snapshots and
-- patches back to the client after coordinator failover.
module Infernix.Demo.WebSocket
  ( WebSocketOptions (..),
    WebSocketDispatchError (..),
    DemoWebSocketApp,
    wsApplication,
    defaultWebSocketOptions,
    -- exported for unit testing
    extractTokenFromQuery,
    classifyClientMessage,
    ClientMessageOutcome (..),
  )
where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (MVar, modifyMVar_, newMVar)
import Control.Exception (SomeException, displayException, try)
import Control.Monad (forever, unless, void)
import Data.Aeson (eitherDecodeStrict', encode)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as Lazy
import Data.IORef (IORef, atomicModifyIORef', newIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time.Clock (getCurrentTime)
import Infernix.Auth.Jwt
  ( Jwks,
    JwtClaims (..),
    verifyAndParseJwt,
  )
import Infernix.Demo.Auth
  ( KeycloakRealmConfig,
    defaultInfernixRealmConfig,
    realmValidationConfig,
  )
import Infernix.Web.Contracts
  ( ContextId,
    UserId (..),
    WsClientMessage (..),
    WsServerMessage (..),
  )
import Network.HTTP.Types (Query, parseQuery, status401)
import Network.Wai
  ( Application,
    responseLBS,
  )
import Network.Wai.Handler.WebSockets (websocketsOr)
import Network.WebSockets qualified as WS

-- | Configuration the WebSocket app needs at request time. The JWKS
-- loader is supplied as an 'IO' callback so the demo binary can choose
-- whether to fetch JWKS per-request (current implementation), cache it
-- with a TTL (Sprint 7.14), or load it from a static fixture for unit
-- tests.
data WebSocketOptions = WebSocketOptions
  { wsRealmConfig :: KeycloakRealmConfig,
    wsLoadJwks :: IO (Either String Jwks),
    wsDispatchClientMessage :: UserId -> WsClientMessage -> IO (Either WebSocketDispatchError ()),
    wsStartUserStreams :: UserId -> (WsServerMessage -> IO ()) -> IO (),
    wsStartContextStream :: UserId -> ContextId -> (WsServerMessage -> IO ()) -> IO ()
  }

data WebSocketDispatchError = WebSocketDispatchError
  { webSocketDispatchErrorCode :: Text,
    webSocketDispatchErrorMessage :: Text
  }
  deriving (Eq, Show)

-- | A WAI 'Application' that handles WebSocket upgrades at the WS layer
-- and falls back to a fallback HTTP handler for non-upgrade requests on
-- the same route.
type DemoWebSocketApp = Application

-- | Default 'WebSocketOptions' wiring against the supported Keycloak
-- realm. Real deployments override 'wsLoadJwks' with the cluster-aware
-- fetcher in @Infernix.Demo.Api@.
defaultWebSocketOptions :: IO (Either String Jwks) -> WebSocketOptions
defaultWebSocketOptions jwksLoader =
  WebSocketOptions
    { wsRealmConfig = defaultInfernixRealmConfig,
      wsLoadJwks = jwksLoader,
      wsDispatchClientMessage =
        \_ _ ->
          pure
            ( Left
                WebSocketDispatchError
                  { webSocketDispatchErrorCode = "ws_pulsar_dispatch_failed",
                    webSocketDispatchErrorMessage =
                      "Pulsar dispatch is not configured for this WebSocket app; pass wsDispatchClientMessage in WebSocketOptions"
                  }
            ),
      wsStartUserStreams =
        \_ _ -> pure (),
      wsStartContextStream =
        \_ _ send ->
          send
            ( ServerError
                { serverErrorErrorCode = "ws_context_stream_unavailable",
                  serverErrorMessage =
                    "Pulsar context streaming is not configured for this WebSocket app; pass wsStartContextStream in WebSocketOptions"
                }
            )
    }

-- | Build the WAI application that handles WS upgrades on the @/ws@
-- route. Non-WS requests are answered with 401 because the route is
-- WebSocket-only by contract.
wsApplication :: WebSocketOptions -> DemoWebSocketApp
wsApplication options =
  websocketsOr
    WS.defaultConnectionOptions
    (handleWsUpgrade options)
    fallbackHttpHandler

-- type Application = Request -> (Response -> IO ResponseReceived) -> IO ResponseReceived
fallbackHttpHandler :: Application
fallbackHttpHandler _request respond =
  respond
    ( responseLBS
        status401
        [("Content-Type", "text/plain; charset=utf-8")]
        "the /ws route requires a WebSocket upgrade with a valid JWT"
    )

-- | Handle the WebSocket upgrade. The pending connection's @Request@
-- carries the query string we use to look up the bearer token; once
-- accepted we hand off to 'runSession'.
handleWsUpgrade :: WebSocketOptions -> WS.PendingConnection -> IO ()
handleWsUpgrade options pending = do
  let pendingRequest = WS.pendingRequest pending
      requestPathBytes = WS.requestPath pendingRequest
      tokenFromQuery = extractTokenFromQuery (parseQueryFromRequestPath requestPathBytes)
      tokenFromHeader = bearerTokenFromHeaders (WS.requestHeaders pendingRequest)
  case tokenFromHeader <|> tokenFromQuery of
    Nothing ->
      WS.rejectRequestWith
        pending
        WS.defaultRejectRequest
          { WS.rejectCode = 401,
            WS.rejectMessage = "missing JWT (set Authorization: Bearer or ?token=)"
          }
    Just token -> do
      jwksResult <- wsLoadJwks options
      case jwksResult of
        Left jwksError ->
          WS.rejectRequestWith
            pending
            WS.defaultRejectRequest
              { WS.rejectCode = 503,
                WS.rejectMessage = TextEncoding.encodeUtf8 (Text.pack ("JWKS fetch failed: " <> jwksError))
              }
        Right jwks -> do
          now <- getCurrentTime
          case verifyAndParseJwt (realmValidationConfig (wsRealmConfig options)) now jwks token of
            Left jwtError ->
              WS.rejectRequestWith
                pending
                WS.defaultRejectRequest
                  { WS.rejectCode = 401,
                    WS.rejectMessage = TextEncoding.encodeUtf8 (Text.pack ("invalid JWT: " <> show jwtError))
                  }
            Right claims -> do
              connection <- WS.acceptRequest pending
              runSession options connection (UserId (jwtClaimSubject claims))

-- | Drive the framed-envelope receive loop. Per-WS state is limited to
-- the WebSocket handle plus the authenticated 'UserId' captured at
-- handshake. The dispatch callback publishes state-changing frames to
-- Pulsar; Reader cursors that stream snapshots back to the client land
-- with Sprint 7.14's real-cluster chaos validation.
runSession :: WebSocketOptions -> WS.Connection -> UserId -> IO ()
runSession options connection userId = do
  sendLock <- newMVar ()
  userStreamsStarted <- newIORef False
  forever $ do
    incomingResult <- try @SomeException (WS.receiveData connection)
    case incomingResult of
      Left _ -> WS.sendClose connection ("connection closed" :: Text)
      Right frame -> handleFrame options sendLock userStreamsStarted connection userId frame

handleFrame :: WebSocketOptions -> MVar () -> IORef Bool -> WS.Connection -> UserId -> Lazy.ByteString -> IO ()
handleFrame options sendLock userStreamsStarted connection userId frame =
  case eitherDecodeStrict' (Lazy.toStrict frame) of
    Left decodeError ->
      sendServerMessage
        sendLock
        connection
        ( ServerError
            { serverErrorErrorCode = "ws_frame_decode_failed",
              serverErrorMessage = Text.pack decodeError
            }
        )
    Right clientMessage ->
      case classifyClientMessage userId clientMessage of
        AcknowledgePending ->
          dispatchClientMessage options sendLock userStreamsStarted connection userId clientMessage

dispatchClientMessage :: WebSocketOptions -> MVar () -> IORef Bool -> WS.Connection -> UserId -> WsClientMessage -> IO ()
dispatchClientMessage options sendLock userStreamsStarted connection userId clientMessage =
  case clientMessage of
    ClientHello {} -> do
      alreadyStarted <-
        atomicModifyIORef' userStreamsStarted $ \started ->
          if started then (started, True) else (True, False)
      unless alreadyStarted $
        void $
          forkIO $ do
            streamResult <-
              try @SomeException
                (wsStartUserStreams options userId (sendServerMessage sendLock connection))
            case streamResult of
              Right () -> pure ()
              Left streamError ->
                void $
                  try @SomeException $
                    sendServerMessage
                      sendLock
                      connection
                      ( ServerError
                          { serverErrorErrorCode = "ws_user_stream_failed",
                            serverErrorMessage = Text.pack (displayException streamError)
                          }
                      )
    ClientSubscribeContext contextId -> do
      void $
        forkIO $ do
          streamResult <-
            try @SomeException
              (wsStartContextStream options userId contextId (sendServerMessage sendLock connection))
          case streamResult of
            Right () -> pure ()
            Left streamError ->
              void $
                try @SomeException $
                  sendServerMessage
                    sendLock
                    connection
                    ( ServerError
                        { serverErrorErrorCode = "ws_context_stream_failed",
                          serverErrorMessage = Text.pack (displayException streamError)
                        }
                    )
    _ -> do
      dispatchResult <- wsDispatchClientMessage options userId clientMessage
      case dispatchResult of
        Right () -> pure ()
        Left dispatchError ->
          sendServerMessage
            sendLock
            connection
            ( ServerError
                { serverErrorErrorCode = webSocketDispatchErrorCode dispatchError,
                  serverErrorMessage = webSocketDispatchErrorMessage dispatchError
                }
            )

sendServerMessage :: MVar () -> WS.Connection -> WsServerMessage -> IO ()
sendServerMessage sendLock connection message =
  modifyMVar_ sendLock $ \() -> do
    WS.sendTextData connection (encode message)
    pure ()

-- | Pure classification of a decoded client message. Today every
-- supported message family acknowledges back through Pulsar; the
-- 'ClientMessageOutcome' type leaves room for future per-family
-- responses without bloating the framed-envelope dispatch.
data ClientMessageOutcome
  = AcknowledgePending
  deriving (Eq, Show)

classifyClientMessage :: UserId -> WsClientMessage -> ClientMessageOutcome
classifyClientMessage _userId clientMessage =
  case clientMessage of
    ClientHello {} -> AcknowledgePending
    ClientSubscribeContext {} -> AcknowledgePending
    ClientSubmitPrompt {} -> AcknowledgePending
    ClientCancelPrompt {} -> AcknowledgePending
    ClientRecordUpload {} -> AcknowledgePending
    ClientUpdateDraft {} -> AcknowledgePending
    ClientCreateContext {} -> AcknowledgePending
    ClientRenameContext {} -> AcknowledgePending
    ClientSoftDeleteContext {} -> AcknowledgePending

-- | Pull the bearer token out of a parsed WAI query string. Returns
-- 'Nothing' if the @token@ parameter is absent or empty.
extractTokenFromQuery :: Query -> Maybe Text
extractTokenFromQuery query =
  case lookup "token" query of
    Just (Just tokenBytes) -> nonEmptyText (TextEncoding.decodeUtf8 tokenBytes)
    _ -> Nothing

nonEmptyText :: Text -> Maybe Text
nonEmptyText value
  | Text.null value = Nothing
  | otherwise = Just value

-- | Split the raw WebSocket request path (@/ws?token=...@) on the first
-- @?@ and parse the suffix as an HTTP query string. The 'WS.requestPath'
-- field carries the URI verbatim, so the host application is responsible
-- for the @path@/@query@ split.
parseQueryFromRequestPath :: ByteString -> Query
parseQueryFromRequestPath rawPath =
  case BS.break (== questionMarkByte) rawPath of
    (_, queryWithMark) | not (BS.null queryWithMark) -> parseQuery (BS.drop 1 queryWithMark)
    _ -> []
  where
    questionMarkByte = 0x3F

bearerTokenFromHeaders :: WS.Headers -> Maybe Text
bearerTokenFromHeaders headers =
  case lookup "Authorization" headers of
    Just rawHeader ->
      let decoded = TextEncoding.decodeUtf8 rawHeader
       in stripBearerPrefix decoded
    Nothing -> Nothing

stripBearerPrefix :: Text -> Maybe Text
stripBearerPrefix headerValue =
  case Text.stripPrefix "Bearer " headerValue of
    Just token | not (Text.null token) -> Just token
    _ -> Nothing

-- | Smart alternative for 'Maybe' values that lets us prefer the
-- @Authorization@ header over the query-string token when both are
-- present. Keeps the call site at 'handleWsUpgrade' readable instead of
-- nesting another @case@.
(<|>) :: Maybe a -> Maybe a -> Maybe a
Just value <|> _ = Just value
Nothing <|> right = right

infixl 3 <|>
