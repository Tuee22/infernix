{-# LANGUAGE OverloadedStrings #-}

module Infernix.Demo.Auth
  ( KeycloakRealmConfig (..),
    defaultInfernixRealmConfig,
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
      realmClientId = "infernix-demo",
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
