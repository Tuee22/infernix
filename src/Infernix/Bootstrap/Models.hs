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

import Data.Text (Text)
import Data.Text qualified as Text

-- | A request the engine pod publishes when its adapter sees an uncached
-- model. The supported topic is @infernix/system/model.bootstrap.request@;
-- producer-side dedup is keyed by @modelId@ so two engines requesting the
-- same uncached model produce exactly one upstream download.
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

-- | Producer-side dedup sequence ID for a bootstrap request. Keyed by
-- modelId so a crashed engine pod that re-publishes the same request does
-- not cause a duplicate upstream download.
bootstrapRequestDedupKey :: ModelBootstrapRequest -> Text
bootstrapRequestDedupKey = bootstrapRequestModelId

-- | Producer-side dedup sequence ID for a ready event. Same semantics as
-- the request key: one upstream download yields one ready event regardless
-- of how many times the coordinator restarts mid-bootstrap.
readyEventDedupKey :: ModelBootstrapReadyEvent -> Text
readyEventDedupKey = readyEventModelId

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
