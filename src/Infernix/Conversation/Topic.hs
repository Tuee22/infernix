{-# LANGUAGE OverloadedStrings #-}

module Infernix.Conversation.Topic
  ( TopicNamespace (..),
    defaultDemoTopicNamespace,
    systemTopicNamespace,
    conversationTopicName,
    conversationTopicPrefix,
    contextsMetadataTopicName,
    draftsMetadataTopicName,
    topicBelongsToUser,
    inferenceRequestTopicName,
    inferenceResultTopicName,
    inferenceBatchTopicName,
    modelBootstrapRequestTopicName,
    modelBootstrapReadyTopicName,
    qualifiedTopic,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Web.Contracts (ContextId (..), UserId (..))

-- | The Pulsar tenant/namespace prefix the durable-context surface lives
-- under. Every demo-gated topic family is published into the demo namespace;
-- platform-wide concerns (model-weight bootstrap) live under the system
-- namespace.
data TopicNamespace = TopicNamespace
  { topicNamespaceTenant :: Text,
    topicNamespaceName :: Text
  }
  deriving (Eq, Show)

-- | Supported demo namespace. @infernix/demo@ replaces the legacy
-- @public/default@ usage and is reconciled by @cluster up@ before any topic
-- creation.
defaultDemoTopicNamespace :: TopicNamespace
defaultDemoTopicNamespace = TopicNamespace "infernix" "demo"

-- | System namespace carrying the model-bootstrap request topic family.
-- Demo-gating does not apply: production-only deployments use this namespace
-- for the engine's lazy model-weight workflow.
systemTopicNamespace :: TopicNamespace
systemTopicNamespace = TopicNamespace "infernix" "system"

-- | Render a topic name as a fully-qualified persistent topic URL.
qualifiedTopic :: TopicNamespace -> Text -> Text
qualifiedTopic ns topic =
  Text.concat
    [ "persistent://",
      topicNamespaceTenant ns,
      "/",
      topicNamespaceName ns,
      "/",
      topic
    ]

-- | Per-context conversation log topic
-- @persistent://infernix/demo/demo.conversation.<userId>.<contextId>@.
-- Single-partition; broker-assigned @MessageId@ is the canonical sequence.
conversationTopicName :: TopicNamespace -> UserId -> ContextId -> Text
conversationTopicName ns (UserId userId) (ContextId contextId) =
  qualifiedTopic
    ns
    ("demo.conversation." <> userId <> "." <> contextId)

conversationTopicPrefix :: TopicNamespace -> UserId -> Text
conversationTopicPrefix ns (UserId userId) =
  qualifiedTopic ns ("demo.conversation." <> userId <> ".")

-- | Per-user compacted contexts-metadata topic
-- @persistent://infernix/demo/demo.user.<userId>.contexts@. The compacted
-- reader yields the latest value per @ContextId@ key.
contextsMetadataTopicName :: TopicNamespace -> UserId -> Text
contextsMetadataTopicName ns (UserId userId) =
  qualifiedTopic ns ("demo.user." <> userId <> ".contexts")

-- | Per-user compacted drafts topic
-- @persistent://infernix/demo/demo.user.<userId>.drafts@. Compacted by
-- @ContextId@ key so deleting a draft is an explicit upsert-to-empty.
draftsMetadataTopicName :: TopicNamespace -> UserId -> Text
draftsMetadataTopicName ns (UserId userId) =
  qualifiedTopic ns ("demo.user." <> userId <> ".drafts")

topicBelongsToUser :: TopicNamespace -> UserId -> Text -> Bool
topicBelongsToUser ns uid topic =
  topic == contextsMetadataTopicName ns uid
    || topic == draftsMetadataTopicName ns uid
    || conversationTopicPrefix ns uid `Text.isPrefixOf` topic

-- | Substrate-scoped inference request topic. Shared with the existing
-- production dispatch path; the durable-context envelope adds
-- @(userId, contextId, causalRef, conversationLogOffset, prefixHash)@.
inferenceRequestTopicName :: TopicNamespace -> Text -> Text
inferenceRequestTopicName ns substrateId =
  qualifiedTopic ns ("inference.request." <> substrateId)

-- | Substrate-scoped inference result topic. The coordinator role consumes
-- this and writes the typed @InferenceResult@ back to the conversation log.
inferenceResultTopicName :: TopicNamespace -> Text -> Text
inferenceResultTopicName ns substrateId =
  qualifiedTopic ns ("inference.result." <> substrateId)

-- | Apple host-batch handoff topic
-- @persistent://infernix/demo/inference.batch.<substrate>@. Sprint 7.7
-- generalises this to every substrate; the helper is namespace-aware now so
-- callers don't need to know the future cluster role split.
inferenceBatchTopicName :: TopicNamespace -> Text -> Text
inferenceBatchTopicName ns substrateId =
  qualifiedTopic ns ("inference.batch." <> substrateId)

-- | Model-weight bootstrap request topic. Producer dedup keyed by @modelId@;
-- Failover subscription guarantees exactly-one upstream download.
modelBootstrapRequestTopicName :: TopicNamespace -> Text
modelBootstrapRequestTopicName ns =
  qualifiedTopic ns "model.bootstrap.request"

-- | Model-weight bootstrap ready topic
-- @persistent://infernix/system/model.bootstrap.ready.<modelId>@. Engines
-- subscribe with a bounded timeout and load from MinIO once the sentinel
-- arrives.
modelBootstrapReadyTopicName :: TopicNamespace -> Text -> Text
modelBootstrapReadyTopicName ns modelId =
  qualifiedTopic ns ("model.bootstrap.ready." <> modelId)
