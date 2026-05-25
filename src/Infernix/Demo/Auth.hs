{-# LANGUAGE OverloadedStrings #-}

module Infernix.Demo.Auth
  ( KeycloakRealmConfig (..),
    defaultInfernixRealmConfig,
    loadRealmConfigFromEnv,
    realmIssuerUrl,
    realmJwksUrl,
    realmValidationConfig,
  )
where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Auth.Jwt
  ( JwtAudience (..),
    JwtIssuer (..),
    JwtValidationConfig (..),
  )
import System.Environment (lookupEnv)

-- | The supported Keycloak realm wiring the durable-context demo uses. Two
-- realms are pre-defined: the realm Keycloak hosts (e.g. @infernix@) and the
-- public-facing base URL that fronts it (e.g. @http://localhost:9090/auth@).
data KeycloakRealmConfig = KeycloakRealmConfig
  { realmName :: Text,
    realmExternalBaseUrl :: Text,
    realmClientId :: Text,
    realmJwtLeewaySeconds :: Int
  }
  deriving (Eq, Show)

-- | The realm the demo backend expects after Sprint 7.1 lands the Helm
-- templates. @http://localhost:9090@ is the supported edge listener port
-- chosen by `cluster up` (it walks up from @9090@ until a port is free).
-- Production deployments override `realmExternalBaseUrl` to the operator's
-- routed hostname.
defaultInfernixRealmConfig :: KeycloakRealmConfig
defaultInfernixRealmConfig =
  KeycloakRealmConfig
    { realmName = "infernix",
      realmExternalBaseUrl = "http://localhost:9090/auth",
      realmClientId = "infernix-spa",
      realmJwtLeewaySeconds = 30
    }

-- | The issuer URL Keycloak embeds in JWTs. Matches
-- @{baseUrl}/realms/{realmName}@.
realmIssuerUrl :: KeycloakRealmConfig -> Text
realmIssuerUrl config =
  Text.concat
    [ realmExternalBaseUrl config,
      "/realms/",
      realmName config
    ]

-- | The JWKS endpoint URL the demo backend fetches when verifying tokens.
realmJwksUrl :: KeycloakRealmConfig -> Text
realmJwksUrl config =
  Text.concat
    [ realmExternalBaseUrl config,
      "/realms/",
      realmName config,
      "/protocol/openid-connect/certs"
    ]

-- | Build the @JwtValidationConfig@ the shared `Auth.Jwt` validator uses.
realmValidationConfig :: KeycloakRealmConfig -> JwtValidationConfig
realmValidationConfig config =
  JwtValidationConfig
    { jwtValidationIssuer = JwtIssuer (realmIssuerUrl config),
      jwtValidationAudience = JwtAudience (realmClientId config),
      jwtValidationLeewaySeconds = realmJwtLeewaySeconds config
    }

-- | Phase 7 Sprint 7.14 — runtime override hook for the supported
-- Keycloak realm wiring. The Envoy Gateway proxy can strip the @:port@
-- suffix from the request Host before forwarding to Keycloak when the
-- operator-facing edge port is non-standard; in that case Keycloak's
-- emitted @iss@ claim does not match the hardcoded default and the
-- demo backend rejects every JWT with an issuer-mismatch error. The
-- operator-facing env vars @INFERNIX_KEYCLOAK_BASE_URL@,
-- @INFERNIX_KEYCLOAK_REALM_NAME@, and @INFERNIX_KEYCLOAK_CLIENT_ID@
-- let the chart deploy a realm config that matches whatever Keycloak
-- actually emits for the active routing topology. Defaults remain
-- 'defaultInfernixRealmConfig' so the unit-test path and host-native
-- flow stay unchanged.
loadRealmConfigFromEnv :: IO KeycloakRealmConfig
loadRealmConfigFromEnv = do
  maybeBaseUrl <- lookupEnv "INFERNIX_KEYCLOAK_BASE_URL"
  maybeRealmName <- lookupEnv "INFERNIX_KEYCLOAK_REALM_NAME"
  maybeClientId <- lookupEnv "INFERNIX_KEYCLOAK_CLIENT_ID"
  let defaults = defaultInfernixRealmConfig
  pure
    defaults
      { realmExternalBaseUrl = Text.pack (fromMaybe (Text.unpack (realmExternalBaseUrl defaults)) maybeBaseUrl),
        realmName = Text.pack (fromMaybe (Text.unpack (realmName defaults)) maybeRealmName),
        realmClientId = Text.pack (fromMaybe (Text.unpack (realmClientId defaults)) maybeClientId)
      }
