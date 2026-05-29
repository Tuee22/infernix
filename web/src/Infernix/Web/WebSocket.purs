-- | Phase 7 Sprint 7.10 — durable-context WebSocket client.
-- |
-- | Connects to @ws[s]://<edgeOrigin>/ws?token=<JWT>@, decodes framed
-- | 'WsServerMessage' envelopes via Simple.JSON, and exposes a typed
-- | 'sendClientMessage' that mirrors the supported Aeson tagged-object
-- | wire format. Per the daemon-topology contract the demo Service has
-- | @sessionAffinity: None@ so a reconnect can land on any replica
-- | without losing per-context state; this client treats every
-- | disconnect as recoverable and surfaces the status through
-- | 'connectionStatus' so the SPA shell can render the right UI.
module Infernix.Web.WebSocket
  ( WsClientConfig
  , WsConnection
  , ConnectionStatus(..)
  , defaultWsClientConfig
  , wsEndpointUrl
  , connect
  , sendClientMessage
  , connectionStatus
  , close
  ) where

import Prelude

import Data.Either (Either(..))
import Data.Foldable (traverse_)
import Data.Maybe (Maybe(..))
import Data.Newtype (un)
import Data.String (Pattern(..), stripPrefix)
import Effect (Effect)
import Effect.Console as Console
import Effect.Ref as Ref
import Generated.Contracts (WsClientMessage, WsServerMessage)
import Simple.JSON as JSON
import Web.Event.Event (EventType(..))
import Web.Event.Event as Event
import Web.Event.EventTarget as EventTarget
import Web.Socket.Event.EventTypes as WsEvents
import Web.Socket.Event.MessageEvent as MessageEvent
import Web.Socket.WebSocket as WS

-- | Minimal config the client needs to mount a session. @edgeOrigin@ is
-- | usually @window.location.origin@ (e.g. @http://localhost:9090@) and
-- | @token@ is the in-memory access token from 'Infernix.Web.Auth'.
type WsClientConfig =
  { edgeOrigin :: String
  , token :: String
  , initialMessages :: Array WsClientMessage
  }

defaultWsClientConfig :: String -> String -> WsClientConfig
defaultWsClientConfig origin token =
  { edgeOrigin: origin
  , token: token
  , initialMessages: []
  }

-- | Connection lifecycle states the SPA shell renders.
data ConnectionStatus
  = NotConnected
  | Connecting
  | Connected
  | Disconnected String

derive instance eqConnectionStatus :: Eq ConnectionStatus

instance showConnectionStatus :: Show ConnectionStatus where
  show NotConnected = "NotConnected"
  show Connecting = "Connecting"
  show Connected = "Connected"
  show (Disconnected reason) = "Disconnected: " <> reason

-- | Live WebSocket handle. Holds the underlying socket plus a status
-- | ref the SPA shell can poll.
newtype WsConnection = WsConnection
  { socket :: WS.WebSocket
  , status :: Ref.Ref ConnectionStatus
  }

-- | Compute the supported @/ws?token=...@ endpoint URL by rewriting the
-- | @http(s)@ scheme to @ws(s)@.
wsEndpointUrl :: WsClientConfig -> String
wsEndpointUrl config =
  case stripPrefix (Pattern "https://") config.edgeOrigin of
    Just rest -> "wss://" <> rest <> "/ws?token=" <> config.token
    Nothing ->
      case stripPrefix (Pattern "http://") config.edgeOrigin of
        Just rest -> "ws://" <> rest <> "/ws?token=" <> config.token
        Nothing -> config.edgeOrigin <> "/ws?token=" <> config.token

-- | Open a WebSocket and wire up open / message / close handlers. The
-- | message handler decodes each frame as a 'WsServerMessage' and invokes
-- | the supplied callback. Decode failures log to the JS console but do
-- | not close the socket; the supported flow is to let the SPA shell
-- | continue rendering the last good state and surface a typed
-- | 'ServerError' when one arrives.
connect
  :: WsClientConfig
  -> (WsServerMessage -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect WsConnection
connect config onServerMessage onClose = do
  statusRef <- Ref.new Connecting
  socket <- WS.create (wsEndpointUrl config) []
  let target = WS.toEventTarget socket
  openListener <- EventTarget.eventListener \_ ->
    Ref.write Connected statusRef
      *> traverse_ (WS.sendString socket <<< JSON.writeJSON) config.initialMessages
  closeListener <- EventTarget.eventListener \evt -> do
    let reason = un EventType (Event.type_ evt)
    Ref.write (Disconnected reason) statusRef
    onClose reason
  messageListener <- EventTarget.eventListener \evt ->
    case MessageEvent.fromEvent evt of
      Nothing -> Console.warn "WS message event missing payload"
      Just messageEvent -> do
        let raw = MessageEvent.data_ messageEvent
        case decodeServerMessage raw of
          Left err -> Console.warn ("WS decode error: " <> err)
          Right msg -> onServerMessage msg
  EventTarget.addEventListener WsEvents.onOpen openListener false target
  EventTarget.addEventListener WsEvents.onClose closeListener false target
  EventTarget.addEventListener WsEvents.onMessage messageListener false target
  pure (WsConnection { socket: socket, status: statusRef })

-- | Encode and send one 'WsClientMessage' as a JSON string. The
-- | supported wire format matches the Haskell-side tagged-object
-- | encoding produced by 'Aeson.genericToJSON taggedSumOptions'.
sendClientMessage :: WsConnection -> WsClientMessage -> Effect Unit
sendClientMessage (WsConnection record) message =
  WS.sendString record.socket (JSON.writeJSON message)

connectionStatus :: WsConnection -> Effect ConnectionStatus
connectionStatus (WsConnection record) = Ref.read record.status

close :: WsConnection -> Effect Unit
close (WsConnection record) = WS.close record.socket

-- Decode a raw message payload (foreign value coming off the socket) as
-- a 'WsServerMessage'. Browser WebSockets normally surface strings, but
-- we go through 'unsafeCoerce' here so the decoder accepts any
-- string-shaped payload Simple.JSON can parse.
decodeServerMessage :: forall a. a -> Either String WsServerMessage
decodeServerMessage rawValue =
  case (JSON.readJSON (unsafeAsString rawValue) :: _ WsServerMessage) of
    Left err -> Left (show err)
    Right msg -> Right msg

foreign import unsafeAsString :: forall a. a -> String
