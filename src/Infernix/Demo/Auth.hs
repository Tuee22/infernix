{-# LANGUAGE OverloadedStrings #-}

module Infernix.Demo.Auth
  ( KeycloakRealmConfig (..),
    defaultInfernixRealmConfig,
    loadRealmConfigFromCluster,
    realmIssuerUrl,
    realmJwksUrl,
    realmValidationConfig,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Auth.Jwt
  ( JwtAudience (..),
    JwtIssuer (..),
    JwtValidationConfig (..),
  )
import Infernix.ClusterConfig
  ( ClusterConfig (..),
    KeycloakWiring (..),
  )

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

-- | Phase 7 Sprint 7.17 — typed cluster-manifest override hook for
-- the supported Keycloak realm wiring. The Envoy Gateway proxy can
-- strip the @:port@ suffix from the request Host before forwarding
-- to Keycloak when the operator-facing edge port is non-standard;
-- in that case Keycloak's emitted @iss@ claim does not match the
-- hardcoded default and the demo backend rejects every JWT with an
-- issuer-mismatch error. Cluster-resident deployments mount the
-- typed `ClusterConfig.keycloak.*` fields and pass them here; the
-- previous @INFERNIX_KEYCLOAK_BASE_URL@ / @INFERNIX_KEYCLOAK_REALM_NAME@ /
-- @INFERNIX_KEYCLOAK_CLIENT_ID@ env-var hook is retired. Host-native
-- and unit-test flows that don't mount the cluster manifest still
-- fall back to 'defaultInfernixRealmConfig' by passing 'Nothing'.
loadRealmConfigFromCluster :: Maybe ClusterConfig -> KeycloakRealmConfig
loadRealmConfigFromCluster Nothing = defaultInfernixRealmConfig
loadRealmConfigFromCluster (Just clusterConfig) =
  let defaults = defaultInfernixRealmConfig
      keycloak = clusterKeycloak clusterConfig
      pickNonEmpty fallback value = if Text.null value then fallback else value
   in defaults
        { realmExternalBaseUrl = pickNonEmpty (realmExternalBaseUrl defaults) (keycloakBaseUrl keycloak),
          realmName = pickNonEmpty (realmName defaults) (keycloakRealmName keycloak),
          realmClientId = pickNonEmpty (realmClientId defaults) (keycloakClientId keycloak)
        }
