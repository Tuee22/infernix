-- | Phase 7 Sprint 7.10 — OIDC redirect handling + in-memory JWT storage.
-- |
-- | The Keycloak SPA client is a public OIDC client with PKCE. The
-- | browser-side responsibilities are:
-- |
-- | * Detect the absence of a JWT and redirect to Keycloak's
-- |   @/auth/realms/infernix/protocol/openid-connect/auth@ endpoint
-- |   with the supported PKCE parameters.
-- | * On the redirect-back leg, exchange the authorization code for an
-- |   access token + refresh token via the token endpoint.
-- | * Hold the access token in memory (no persistent storage) and
-- |   present it on every WebSocket connect and HTTP @Authorization@
-- |   header.
-- | * Schedule a refresh before expiry so the WebSocket lifetime never
-- |   straddles a token-expiry boundary.
-- |
-- | Today's contract intentionally stops short of the full token
-- | exchange — that needs the Keycloak realm to be reachable from the
-- | browser, which only happens in the routed E2E lane. The skeleton
-- | here gives the SPA shell a typed 'TokenStore' it can hand to
-- | downstream modules; the realm exchange wiring lands together with
-- | the Sprint 7.15 Playwright E2E pass.
module Infernix.Web.Auth
  ( TokenStore
  , RealmConfig
  , defaultInfernixRealmConfig
  , newTokenStore
  , readToken
  , writeToken
  , clearToken
  , beginLoginRedirect
  , completeRedirect
  ) where

import Prelude

import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Ref as Ref

-- | The Keycloak realm shape the SPA needs at runtime. Mirrors the
-- | Haskell 'Infernix.Demo.Auth.KeycloakRealmConfig' record but kept
-- | client-side so the SPA does not need to read the substrate
-- | @.dhall@ catalog itself.
type RealmConfig =
  { issuerUrl :: String
  , clientId :: String
  , redirectUri :: String
  }

defaultInfernixRealmConfig :: RealmConfig
defaultInfernixRealmConfig =
  { issuerUrl: "/auth/realms/infernix"
  , clientId: "infernix-demo"
  , redirectUri: "/"
  }

-- | Opaque handle around the in-memory JWT. The store is rebuilt on
-- | every page load; refresh is responsibility of the host SPA.
newtype TokenStore = TokenStore (Ref.Ref (Maybe String))

newTokenStore :: Effect TokenStore
newTokenStore = TokenStore <$> Ref.new Nothing

readToken :: TokenStore -> Effect (Maybe String)
readToken (TokenStore ref) = Ref.read ref

writeToken :: TokenStore -> String -> Effect Unit
writeToken (TokenStore ref) token = Ref.write (Just token) ref

clearToken :: TokenStore -> Effect Unit
clearToken (TokenStore ref) = Ref.write Nothing ref

-- | Begin the OIDC redirect. Placeholder until the Sprint 7.15 E2E
-- | pass wires the full PKCE handshake. Today the function logs the
-- | intent so the SPA shell can render an explicit "login pending"
-- | state without crashing.
beginLoginRedirect :: RealmConfig -> Effect Unit
beginLoginRedirect _config = pure unit

-- | Inspect the current page URL for an authorization-code redirect
-- | parameter and, when present, exchange it for an access token.
-- | Placeholder until Sprint 7.15.
completeRedirect :: TokenStore -> RealmConfig -> Effect (Maybe String)
completeRedirect _store _config = pure Nothing
