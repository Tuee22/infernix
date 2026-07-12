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
-- | * Clear local token state and redirect through Keycloak logout so
-- |   the upstream SSO session does not survive Sign out.
-- |
-- | The routed SPA owns the PKCE redirect, authorization-code exchange,
-- | and in-memory access-token handoff used by WebSocket and artifact
-- | HTTP calls. Tokens are intentionally kept out of persistent storage;
-- | only the short-lived PKCE verifier/state pair is held in
-- | sessionStorage across the Keycloak redirect.
module Infernix.Web.Auth
  ( TokenStore
  , RealmConfig
  , defaultInfernixRealmConfig
  , newTokenStore
  , readToken
  , writeToken
  , clearToken
  , beginLoginRedirect
  , beginRegisterRedirect
  , beginLogoutRedirect
  , beginDeleteAccountRedirect
  , completeRedirect
  , clearBrowserAuthSession
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
  , clientId: "infernix-spa"
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

beginLoginRedirect :: RealmConfig -> Effect Unit
beginLoginRedirect = beginLoginRedirectImpl

-- | Like 'beginLoginRedirect', but starts at Keycloak's OIDC
-- | registration endpoint so the user lands directly on the
-- | registration form instead of the login form.
beginRegisterRedirect :: RealmConfig -> Effect Unit
beginRegisterRedirect = beginRegisterRedirectImpl

-- | Clear local browser token state and start Keycloak's OIDC logout
-- | redirect. This lets a user sign out and then choose a different
-- | account, including the separate demo admin account.
beginLogoutRedirect :: RealmConfig -> Effect Unit
beginLogoutRedirect = beginLogoutRedirectImpl

-- | Reap demo-owned account state through the backend before starting
-- | Keycloak's account-deletion Application Initiated Action.
beginDeleteAccountRedirect :: RealmConfig -> String -> (String -> Effect Unit) -> Effect Unit
beginDeleteAccountRedirect = beginDeleteAccountRedirectImpl

-- | Inspect the current page URL for an authorization-code redirect
-- | parameter and, when present, exchange it for an access token. The
-- | exchange is browser-async, so the caller supplies a callback that
-- | mounts the token into the rest of the SPA once the fetch completes.
completeRedirect :: TokenStore -> RealmConfig -> (String -> Effect Unit) -> Effect Unit
completeRedirect store config onToken =
  completeRedirectImpl config \token -> do
    writeToken store token
    onToken token

foreign import beginLoginRedirectImpl :: RealmConfig -> Effect Unit

foreign import beginRegisterRedirectImpl :: RealmConfig -> Effect Unit

foreign import beginLogoutRedirectImpl :: RealmConfig -> Effect Unit

foreign import beginDeleteAccountRedirectImpl
  :: RealmConfig
  -> String
  -> (String -> Effect Unit)
  -> Effect Unit

foreign import completeRedirectImpl
  :: RealmConfig
  -> (String -> Effect Unit)
  -> Effect Unit

foreign import clearBrowserAuthSession :: Effect Unit
