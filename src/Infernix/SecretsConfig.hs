{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

-- | Phase 7 Sprint 7.17 — typed Haskell record for the
-- @dhall/InfernixSecrets.dhall@ manifest. The manifest names the
-- *paths* at which credential material lives, never the credential
-- values themselves; the daemon reads each named JSON file via
-- @readFile@ after decoding this record at startup.
--
-- See `documents/architecture/configuration_doctrine.md` for the
-- overall configuration substrate and the chicken-and-egg
-- resolution that lets the bootstrap shell find the secrets dir
-- without env-var inheritance.
module Infernix.SecretsConfig
  ( SecretsConfig (..),
    MinioCredentialsRef (..),
    KeycloakAdminCredentialsRef (..),
    KeycloakDbCredentialsRef (..),
    MinioCredentials (..),
    decodeSecretsConfigFile,
    renderSecretsConfigSchema,
    readMinioCredentials,
    defaultClusterSecretsMountPath,
    defaultHostSecretsManifestPath,
  )
where

import Control.Exception (SomeException, displayException, try)
import Data.Aeson (FromJSON (..), eitherDecodeStrict', withObject, (.:))
import Data.ByteString qualified as ByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import GHC.Generics (Generic)
import Infernix.DhallSchema.Reflection (renderDecoderExpected)

-- | Path to the MinIO credentials JSON file. The file's payload is
-- decoded into 'MinioCredentials' below; see 'readMinioCredentials'.
newtype MinioCredentialsRef = MinioCredentialsRef
  { minioCredentialsPath :: Text
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall MinioCredentialsRef where
  autoWith _ = Dhall.genericAutoWith minioRefFieldOptions

minioRefFieldOptions :: Dhall.InterpretOptions
minioRefFieldOptions =
  Dhall.defaultInterpretOptions
    { Dhall.fieldModifier = \case
        "minioCredentialsPath" -> "credentialsPath"
        other -> other
    }

-- | Path to the Keycloak admin credentials JSON file (used by the
-- bootstrap realm-init helpers, not by the request-handling daemon).
newtype KeycloakAdminCredentialsRef = KeycloakAdminCredentialsRef
  { keycloakAdminCredentialsPath :: Text
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall KeycloakAdminCredentialsRef where
  autoWith _ = Dhall.genericAutoWith keycloakAdminRefFieldOptions

keycloakAdminRefFieldOptions :: Dhall.InterpretOptions
keycloakAdminRefFieldOptions =
  Dhall.defaultInterpretOptions
    { Dhall.fieldModifier = \case
        "keycloakAdminCredentialsPath" -> "credentialsPath"
        other -> other
    }

-- | Path to the Keycloak database credentials JSON file (consumed by
-- the operator-managed Patroni cluster definition + the matching
-- Keycloak `KC_DB_*` env block on Keycloak's own pod template; the
-- `KC_DB_*` upstream env contract is the one documented third-party
-- exception per `documents/architecture/configuration_doctrine.md`).
newtype KeycloakDbCredentialsRef = KeycloakDbCredentialsRef
  { keycloakDbCredentialsPath :: Text
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall KeycloakDbCredentialsRef where
  autoWith _ = Dhall.genericAutoWith keycloakDbRefFieldOptions

keycloakDbRefFieldOptions :: Dhall.InterpretOptions
keycloakDbRefFieldOptions =
  Dhall.defaultInterpretOptions
    { Dhall.fieldModifier = \case
        "keycloakDbCredentialsPath" -> "credentialsPath"
        other -> other
    }

-- | Full secrets manifest. Every field is a file path; the credential
-- values live in the named files, not in this record.
data SecretsConfig = SecretsConfig
  { secretsMinio :: MinioCredentialsRef,
    secretsKeycloakAdmin :: KeycloakAdminCredentialsRef,
    secretsKeycloakDb :: KeycloakDbCredentialsRef
  }
  deriving (Eq, Show, Generic)

instance Dhall.FromDhall SecretsConfig where
  autoWith _ = Dhall.genericAutoWith secretsFieldOptions

secretsFieldOptions :: Dhall.InterpretOptions
secretsFieldOptions =
  Dhall.defaultInterpretOptions
    { Dhall.fieldModifier = \case
        "secretsMinio" -> "minio"
        "secretsKeycloakAdmin" -> "keycloakAdmin"
        "secretsKeycloakDb" -> "keycloakDb"
        other -> other
    }

-- | The cluster-side mount path the chart writes the secrets manifest
-- to. The companion `Secret/infernix-cluster-secrets` writes each
-- credential JSON beside this manifest under `/etc/infernix/secrets/`.
defaultClusterSecretsMountPath :: FilePath
defaultClusterSecretsMountPath = "/etc/infernix/secrets/InfernixSecrets.dhall"

-- | The host-side path the host workflow (`infernix internal
-- materialize-substrate`) writes the secrets manifest to. Operators
-- edit the placeholder credential files under this directory; the
-- directory is gitignored.
defaultHostSecretsManifestPath :: FilePath
defaultHostSecretsManifestPath = "./.data/runtime/secrets/InfernixSecrets.dhall"

-- | Decode a materialized @InfernixSecrets.dhall@ file. Errors carry
-- the supported failure context so daemon-startup flows surface them
-- early.
decodeSecretsConfigFile :: FilePath -> IO SecretsConfig
decodeSecretsConfigFile filePath = do
  decoded <- try (Dhall.inputFile Dhall.auto filePath :: IO SecretsConfig)
  case decoded of
    Left err ->
      ioError
        ( userError
            ( "invalid secrets manifest Dhall at "
                <> filePath
                <> ":\n"
                <> displayException (err :: SomeException)
            )
        )
    Right value -> pure value

renderSecretsConfigSchema :: Either String Text
renderSecretsConfigSchema =
  renderDecoderExpected (Dhall.auto @SecretsConfig)

-- | Decoded MinIO credentials payload. The JSON shape is
-- @{ "accessKey": "...", "secretKey": "..." }@.
data MinioCredentials = MinioCredentials
  { minioAccessKey :: Text,
    minioSecretKey :: Text
  }
  deriving (Eq, Show, Generic)

instance FromJSON MinioCredentials where
  parseJSON = withObject "MinioCredentials" $ \value ->
    MinioCredentials
      <$> value .: "accessKey"
      <*> value .: "secretKey"

-- | Read the MinIO credentials from the JSON file named by
-- @SecretsConfig.minio.credentialsPath@.
readMinioCredentials :: MinioCredentialsRef -> IO MinioCredentials
readMinioCredentials ref = do
  let path = Text.unpack (minioCredentialsPath ref)
  bytes <- ByteString.readFile path
  case eitherDecodeStrict' bytes of
    Left err -> ioError (userError ("invalid MinIO credentials JSON at " <> path <> ": " <> err))
    Right value -> pure value
