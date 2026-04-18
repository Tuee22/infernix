{-# LANGUAGE OverloadedStrings #-}

module Infernix.Types
  ( ApiUpstream (..),
    CacheManifest (..),
    ClusterState (..),
    DemoConfig (..),
    ErrorResponse (..),
    InferenceRequest (..),
    InferenceResult (..),
    ModelDescriptor (..),
    PersistentClaim (..),
    PublicationUpstream (..),
    RequestField (..),
    ResultPayload (..),
    RouteInfo (..),
    RuntimeMode (..),
    allRuntimeModes,
    parseRuntimeMode,
    runtimeModeId,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)

data RuntimeMode
  = AppleSilicon
  | LinuxCpu
  | LinuxCuda
  deriving (Eq, Ord, Read, Show)

allRuntimeModes :: [RuntimeMode]
allRuntimeModes = [AppleSilicon, LinuxCpu, LinuxCuda]

runtimeModeId :: RuntimeMode -> Text
runtimeModeId runtimeMode = case runtimeMode of
  AppleSilicon -> "apple-silicon"
  LinuxCpu -> "linux-cpu"
  LinuxCuda -> "linux-cuda"

parseRuntimeMode :: Text -> Maybe RuntimeMode
parseRuntimeMode rawValue = case Text.toLower rawValue of
  "apple-silicon" -> Just AppleSilicon
  "linux-cpu" -> Just LinuxCpu
  "linux-cuda" -> Just LinuxCuda
  _ -> Nothing

data RouteInfo = RouteInfo
  { path :: Text,
    purpose :: Text
  }
  deriving (Eq, Read, Show)

data PersistentClaim = PersistentClaim
  { namespace :: Text,
    release :: Text,
    workload :: Text,
    ordinal :: Int,
    claim :: Text,
    pvcName :: Text,
    requestedStorage :: Text
  }
  deriving (Eq, Read, Show)

data ClusterState = ClusterState
  { clusterPresent :: Bool,
    edgePort :: Int,
    routes :: [RouteInfo],
    storageClass :: Text,
    claims :: [PersistentClaim],
    clusterRuntimeMode :: RuntimeMode,
    kubeconfigPath :: FilePath,
    generatedDemoConfigPath :: FilePath,
    publishedDemoConfigPath :: FilePath,
    publishedConfigMapManifestPath :: FilePath,
    mountedDemoConfigPath :: FilePath,
    updatedAt :: UTCTime
  }
  deriving (Eq, Read, Show)

data ApiUpstream = ApiUpstream
  { apiUpstreamMode :: Text,
    apiUpstreamHost :: Text,
    apiUpstreamPort :: Int
  }
  deriving (Eq, Read, Show)

data PublicationUpstream = PublicationUpstream
  { publicationUpstreamId :: Text,
    publicationUpstreamRoutePrefix :: Text,
    publicationUpstreamTargetSurface :: Text,
    publicationUpstreamHealthStatus :: Text,
    publicationUpstreamDurableBackendState :: Text
  }
  deriving (Eq, Read, Show)

data CacheManifest = CacheManifest
  { cacheRuntimeMode :: RuntimeMode,
    cacheModelId :: Text,
    cacheSelectedEngine :: Text,
    cacheDurableSourceUri :: Text,
    cacheCacheKey :: Text
  }
  deriving (Eq, Read, Show)

data DemoConfig = DemoConfig
  { configRuntimeMode :: RuntimeMode,
    configEdgePort :: Int,
    configMapName :: Text,
    generatedPath :: FilePath,
    mountedPath :: FilePath,
    models :: [ModelDescriptor]
  }
  deriving (Eq, Read, Show)

data RequestField = RequestField
  { name :: Text,
    label :: Text,
    fieldType :: Text
  }
  deriving (Eq, Read, Show)

data ModelDescriptor = ModelDescriptor
  { matrixRowId :: Text,
    modelId :: Text,
    displayName :: Text,
    family :: Text,
    description :: Text,
    artifactType :: Text,
    referenceModel :: Text,
    downloadUrl :: Text,
    selectedEngine :: Text,
    requestShape :: [RequestField],
    runtimeMode :: RuntimeMode,
    runtimeLane :: Text,
    requiresGpu :: Bool,
    notes :: Text
  }
  deriving (Eq, Read, Show)

data InferenceRequest = InferenceRequest
  { requestModelId :: Text,
    inputText :: Text
  }
  deriving (Eq, Read, Show)

data ResultPayload = ResultPayload
  { inlineOutput :: Maybe Text,
    objectRef :: Maybe Text
  }
  deriving (Eq, Read, Show)

data InferenceResult = InferenceResult
  { requestId :: Text,
    resultModelId :: Text,
    resultMatrixRowId :: Text,
    resultRuntimeMode :: RuntimeMode,
    resultSelectedEngine :: Text,
    status :: Text,
    payload :: ResultPayload,
    createdAt :: UTCTime
  }
  deriving (Eq, Read, Show)

data ErrorResponse = ErrorResponse
  { errorCode :: Text,
    message :: Text
  }
  deriving (Eq, Read, Show)
