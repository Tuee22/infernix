{-# LANGUAGE OverloadedStrings #-}

module Infernix.DhallSchema
  ( DhallSchema (..),
    allDhallSchemas,
    dhallSchemaFileName,
    dhallSchemaName,
    parseDhallSchema,
    renderDhallSchema,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.ClusterConfig qualified as ClusterConfig
import Infernix.HostConfig qualified as HostConfig
import Infernix.SecretsConfig qualified as SecretsConfig
import Infernix.Substrate qualified as Substrate

data DhallSchema
  = HostSchema
  | ClusterSchema
  | SecretsSchema
  | SubstrateSchema
  deriving (Eq, Ord, Show)

allDhallSchemas :: [DhallSchema]
allDhallSchemas =
  [ HostSchema,
    ClusterSchema,
    SecretsSchema,
    SubstrateSchema
  ]

dhallSchemaName :: DhallSchema -> Text
dhallSchemaName schema =
  case schema of
    HostSchema -> "host"
    ClusterSchema -> "cluster"
    SecretsSchema -> "secrets"
    SubstrateSchema -> "substrate"

dhallSchemaFileName :: DhallSchema -> FilePath
dhallSchemaFileName schema =
  case schema of
    HostSchema -> "InfernixHost.dhall"
    ClusterSchema -> "InfernixCluster.dhall"
    SecretsSchema -> "InfernixSecrets.dhall"
    SubstrateSchema -> "InfernixSubstrate.dhall"

parseDhallSchema :: String -> Maybe DhallSchema
parseDhallSchema rawValue =
  case Text.toLower (Text.pack rawValue) of
    "host" -> Just HostSchema
    "cluster" -> Just ClusterSchema
    "secrets" -> Just SecretsSchema
    "substrate" -> Just SubstrateSchema
    _ -> Nothing

renderDhallSchema :: DhallSchema -> Either String Text
renderDhallSchema schema =
  case schema of
    HostSchema -> HostConfig.renderHostConfigSchema
    ClusterSchema -> ClusterConfig.renderClusterConfigSchema
    SecretsSchema -> SecretsConfig.renderSecretsConfigSchema
    SubstrateSchema -> Substrate.renderSubstrateConfigSchema
