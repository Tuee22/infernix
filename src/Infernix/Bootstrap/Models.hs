{-# LANGUAGE OverloadedStrings #-}

module Infernix.Bootstrap.Models
  ( ModelBootstrapRequest (..),
    ModelBootstrapReadyEvent (..),
    ModelFile (..),
    bootstrapSubscriptionName,
    bootstrapRequestDedupKey,
    readyEventDedupKey,
    bootstrapReadyTopicFor,
    readySentinelFilename,
    modelFileObjectKey,
    isReadySentinel,
  )
where

import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    object,
    withObject,
    (.:),
    (.=),
  )
import Data.Text (Text)
import Data.Text qualified as Text

instance ToJSON ModelBootstrapRequest where
  toJSON request =
    object
      [ "modelId" .= bootstrapRequestModelId request,
        "downloadUrl" .= bootstrapRequestDownloadUrl request,
        "requestedAt" .= bootstrapRequestRequestedAtIso8601 request
      ]

instance FromJSON ModelBootstrapRequest where
  parseJSON = withObject "ModelBootstrapRequest" $ \value ->
    ModelBootstrapRequest
      <$> value .: "modelId"
      <*> value .: "downloadUrl"
      <*> value .: "requestedAt"

instance ToJSON ModelBootstrapReadyEvent where
  toJSON event =
    object
      [ "modelId" .= readyEventModelId event,
        "readyAt" .= readyEventReadyAtIso8601 event
      ]

instance FromJSON ModelBootstrapReadyEvent where
  parseJSON = withObject "ModelBootstrapReadyEvent" $ \value ->
    ModelBootstrapReadyEvent
      <$> value .: "modelId"
      <*> value .: "readyAt"

-- | A request the engine pod publishes when its adapter sees an uncached
-- model. The supported topic is @infernix/system/model.bootstrap.request@.
-- Producer-side dedup is scoped to a single request attempt so exact
-- replays collapse without permanently poisoning later retries for the
-- same model.
data ModelBootstrapRequest = ModelBootstrapRequest
  { bootstrapRequestModelId :: Text,
    bootstrapRequestDownloadUrl :: Text,
    bootstrapRequestRequestedAtIso8601 :: Text
  }
  deriving (Eq, Show)

-- | The completion event published once every file is uploaded to MinIO
-- and the @.ready@ sentinel has been written.
data ModelBootstrapReadyEvent = ModelBootstrapReadyEvent
  { readyEventModelId :: Text,
    readyEventReadyAtIso8601 :: Text
  }
  deriving (Eq, Show)

-- | A single file within a model bundle. The bootstrap workflow uploads
-- every file under @infernix-models/<modelId>/<filename>@ and writes the
-- ready sentinel last.
data ModelFile = ModelFile
  { modelFileFilename :: Text,
    modelFileSourceUrl :: Text
  }
  deriving (Eq, Show)

-- | Named Failover subscription label for the coordinator's bootstrap
-- consumer. The subscription is shared across coordinator replicas; the
-- broker promotes exactly one of them to active for a given bootstrap.
bootstrapSubscriptionName :: Text
bootstrapSubscriptionName = "bootstrap-models"

-- | Producer-side dedup sequence ID for a bootstrap request. It includes the
-- request timestamp so a crashed engine that republishes the exact same
-- request collapses, while a later recovery attempt can still enqueue work
-- if the previous attempt never produced a ready event.
bootstrapRequestDedupKey :: ModelBootstrapRequest -> Text
bootstrapRequestDedupKey request =
  bootstrapRequestModelId request <> "@" <> bootstrapRequestRequestedAtIso8601 request

-- | Producer-side dedup sequence ID for a ready event. Include the event
-- timestamp so a later cluster lifecycle can publish a fresh ready signal
-- even when broker-side dedup state from an earlier run is still retained.
readyEventDedupKey :: ModelBootstrapReadyEvent -> Text
readyEventDedupKey event =
  readyEventModelId event <> "@" <> readyEventReadyAtIso8601 event

-- | Per-model ready-event topic name. Engines @Reader@-subscribe to this
-- topic with a bounded timeout; the broker preserves the latest message
-- because the topic is single-partition + compacted.
bootstrapReadyTopicFor :: Text -> Text -> Text
bootstrapReadyTopicFor systemNamespace modelId =
  systemNamespace <> "/model.bootstrap.ready." <> modelId

-- | Filename of the ready sentinel inside the @<modelId>/@ prefix. The
-- coordinator writes this last; engines wait for its appearance before
-- loading.
readySentinelFilename :: Text
readySentinelFilename = ".ready"

-- | Compute the MinIO object key for a given file in a model bundle.
modelFileObjectKey :: Text -> Text -> Text
modelFileObjectKey modelId filename = modelId <> "/" <> filename

-- | True iff the supplied object key is the ready sentinel for any model.
isReadySentinel :: Text -> Bool
isReadySentinel = Text.isSuffixOf ("/" <> readySentinelFilename)
