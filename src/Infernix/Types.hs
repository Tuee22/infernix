module Infernix.Types
  ( ClusterState (..),
    ErrorResponse (..),
    InferenceRequest (..),
    InferenceResult (..),
    PersistentClaim (..),
    RequestField (..),
    ResultPayload (..),
    RouteInfo (..),
    ModelDescriptor (..),
  )
where

import Data.Text (Text)
import Data.Time (UTCTime)

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
    claim :: Text
  }
  deriving (Eq, Read, Show)

data ClusterState = ClusterState
  { clusterPresent :: Bool,
    edgePort :: Int,
    routes :: [RouteInfo],
    storageClass :: Text,
    claims :: [PersistentClaim],
    kubeconfigPath :: FilePath,
    testConfigPath :: FilePath,
    updatedAt :: UTCTime
  }
  deriving (Eq, Read, Show)

data RequestField = RequestField
  { name :: Text,
    label :: Text,
    fieldType :: Text
  }
  deriving (Eq, Read, Show)

data ModelDescriptor = ModelDescriptor
  { modelId :: Text,
    displayName :: Text,
    family :: Text,
    description :: Text,
    requestShape :: [RequestField]
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
