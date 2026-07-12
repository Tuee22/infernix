{-# LANGUAGE OverloadedStrings #-}

module Infernix.Bridge.Result
  ( ResultBridgeConfig (..),
    bridgeSubscriptionName,
    resultDedupKey,
    inferenceResultEventFor,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Conversation.Event (ConversationEvent (..))
import Infernix.Web.Contracts
  ( ConversationInferenceResultPayload (..),
    InferenceError,
    MessageId (..),
    ObjectRef,
  )

-- | Configuration for the result-bridge consumer the coordinator runs. The
-- bridge reads typed @InferenceResult@ messages off the substrate's
-- @inference.result.<mode>@ topic and writes the matching
-- @ConversationInferenceResultEvent@ back to the per-context conversation
-- topic with producer-side dedup keyed by @(userPromptMessageId, kind)@.
data ResultBridgeConfig = ResultBridgeConfig
  { resultBridgeSubstrate :: Text,
    resultBridgeResultTopic :: Text,
    resultBridgeConversationTopicNamespace :: Text
  }
  deriving (Eq, Show)

-- | Named Failover subscription label for the result-bridge on a given
-- substrate. Two coordinator replicas can subscribe with this name; the
-- broker promotes exactly one of them to active.
bridgeSubscriptionName :: ResultBridgeConfig -> Text
bridgeSubscriptionName config =
  Text.concat ["result-bridge-", resultBridgeSubstrate config]

-- | Producer-side dedup sequence key for writing the typed
-- @InferenceResult@ back to the conversation log. Keyed by
-- @userPromptMessageId@ + the @InferenceResult@ kind discriminator so a
-- crashed bridge that retries publication produces exactly one event.
resultDedupKey :: MessageId -> Text
resultDedupKey (MessageId messageId) =
  "inference-result:" <> messageId

-- | Construct the @ConversationEvent@ the bridge must publish on the
-- conversation topic given an @InferenceResult@ payload it consumed off
-- the result topic. Pure: no IO is required to translate from one wire
-- form to the other.
inferenceResultEventFor ::
  MessageId ->
  Text ->
  Maybe Text ->
  Maybe InferenceError ->
  [ObjectRef] ->
  ConversationEvent
inferenceResultEventFor userPromptMessageId status inlineOutput inferenceError artifacts =
  ConversationInferenceResultEvent
    ConversationInferenceResultPayload
      { inferenceResultUserPromptMessageId = userPromptMessageId,
        inferenceResultStatus = status,
        inferenceResultInlineOutput = inlineOutput,
        inferenceResultError = inferenceError,
        inferenceResultArtifacts = artifacts
      }
