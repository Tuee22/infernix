{-# LANGUAGE OverloadedStrings #-}

module Infernix.Dispatch.SingleFlight
  ( InferenceRequestEnvelope (..),
    DispatchDecision (..),
    buildDispatchDecision,
    dispatchableEnvelopeFor,
    producerDedupSequenceId,
    dispatcherSubscriptionName,
  )
where

import Data.Foldable (find)
import Data.Maybe (fromMaybe)
import Data.Sequence qualified as Seq
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Conversation.Hash (PrefixHash (..))
import Infernix.Conversation.Reducer
  ( ReducerState,
    nextDispatchablePrompt,
    reducerContextId,
    reducerMessages,
    reducerPrefixHash,
  )
import Infernix.Web.Contracts
  ( ClientIdempotencyKey,
    ContextId (..),
    ConversationEvent (..),
    ConversationMessage (..),
    MessageId (..),
    UserId,
    UserPromptPayload (..),
  )

-- | The typed envelope produced by the single-flight dispatcher and
-- published on @inference.request.<substrate>@. Each field is load-bearing:
--
-- * @inferenceUserId@ + @inferenceContextId@ — addressing for the engine's
--   result writeback and per-user MinIO scoping.
-- * @inferenceUserPromptMessageId@ — the conversation-log @MessageId@ used as
--   both the causal reference and the producer-dedup sequence ID for the
--   inference-request topic. Producer dedup keyed by this value guarantees
--   exactly-once dispatch across crashed dispatcher replicas.
-- * @inferenceClientIdempotencyKey@ — carried through so retries surface back
--   to the original client request.
-- * @inferenceConversationLogOffset@ — the message's broker offset on the
--   conversation topic. The engine uses this with @prefixHash@ to confirm KV
--   cache consistency.
-- * @inferencePrefixHash@ — Merkle-style hash of the projection at dispatch
--   time. Engine compares against its KV cache key; on mismatch it rebuilds.
-- * @inferencePromptText@ — the actual prompt payload the engine consumes.
data InferenceRequestEnvelope = InferenceRequestEnvelope
  { inferenceUserId :: UserId,
    inferenceContextId :: ContextId,
    inferenceUserPromptMessageId :: MessageId,
    inferenceClientIdempotencyKey :: ClientIdempotencyKey,
    inferenceConversationLogOffset :: Int,
    inferencePrefixHash :: Text,
    inferencePromptText :: Text,
    inferenceCausalRef :: Text
  }
  deriving (Eq, Show)

-- | The dispatcher's pure-fold decision after observing a reducer state.
-- @NoOp@ means no in-flight prompt is dispatchable (queue empty or the head
-- already has a result). @DispatchPrompt@ carries the typed envelope the
-- dispatcher should publish to @inference.request.<substrate>@.
data DispatchDecision
  = DispatchNoOp
  | DispatchPrompt InferenceRequestEnvelope
  deriving (Eq, Show)

-- | The single-flight dispatch rule, parameterised in the runtime view of
-- the conversation log. Equivalent to: \"dispatch a 'UserPrompt' iff every
-- prior 'UserPrompt' has a matching 'InferenceResult' or 'Cancel'\".
--
-- Two-prompts-in-a-row queue cleanly: the second prompt is held until the
-- first resolves, then the next reducer step re-applies the rule.
buildDispatchDecision :: UserId -> ReducerState -> DispatchDecision
buildDispatchDecision userId state =
  case nextDispatchablePrompt state of
    Nothing -> DispatchNoOp
    Just promptMessageId -> buildEnvelopeFor userId state promptMessageId

buildEnvelopeFor :: UserId -> ReducerState -> MessageId -> DispatchDecision
buildEnvelopeFor userId state promptMessageId =
  let messages = reducerMessages state
      messageList = foldr (:) [] messages
      isPromptForId msg =
        conversationMessageId msg == promptMessageId
          && isPromptEvent (conversationMessageEvent msg)
   in finalizeEnvelope userId state messages promptMessageId (find isPromptForId messageList)

finalizeEnvelope ::
  UserId ->
  ReducerState ->
  Seq.Seq ConversationMessage ->
  MessageId ->
  Maybe ConversationMessage ->
  DispatchDecision
finalizeEnvelope _ _ _ _ Nothing = DispatchNoOp
finalizeEnvelope userId state messages promptMessageId (Just promptMsg) =
  envelopeFromPromptMessage userId state messages promptMessageId promptMsg

envelopeFromPromptMessage ::
  UserId ->
  ReducerState ->
  Seq.Seq ConversationMessage ->
  MessageId ->
  ConversationMessage ->
  DispatchDecision
envelopeFromPromptMessage userId state messages promptMessageId promptMsg =
  case conversationMessageEvent promptMsg of
    ConversationUserPromptEvent payload ->
      DispatchPrompt
        InferenceRequestEnvelope
          { inferenceUserId = userId,
            inferenceContextId = reducerContextId state,
            inferenceUserPromptMessageId = promptMessageId,
            inferenceClientIdempotencyKey = promptClientIdempotencyKey payload,
            inferenceConversationLogOffset = conversationOffsetOf messages promptMessageId,
            inferencePrefixHash = unPrefixHash (reducerPrefixHash state),
            inferencePromptText = promptText payload,
            inferenceCausalRef = unMessageId promptMessageId
          }
    _ -> DispatchNoOp

isPromptEvent :: ConversationEvent -> Bool
isPromptEvent (ConversationUserPromptEvent _) = True
isPromptEvent _ = False

conversationOffsetOf :: Seq.Seq ConversationMessage -> MessageId -> Int
conversationOffsetOf messages target =
  let entries = zip [0 :: Int ..] (foldr (:) [] messages)
   in fromMaybe (-1) $
        lookup
          target
          [(conversationMessageId message, idx) | (idx, message) <- entries]

-- | Convenience: extract the envelope from a 'DispatchDecision', returning
-- 'Nothing' for 'DispatchNoOp'.
dispatchableEnvelopeFor :: DispatchDecision -> Maybe InferenceRequestEnvelope
dispatchableEnvelopeFor DispatchNoOp = Nothing
dispatchableEnvelopeFor (DispatchPrompt envelope) = Just envelope

-- | The producer-side dedup sequence ID for an envelope. Keyed by
-- @userPromptMessageId@ on the @inference.request.<mode>@ topic so a crashed
-- coordinator that retries publication does not produce a duplicate dispatch.
producerDedupSequenceId :: InferenceRequestEnvelope -> Text
producerDedupSequenceId envelope = unMessageId (inferenceUserPromptMessageId envelope)

-- | Named Failover subscription label for a per-context dispatcher. Two
-- coordinator replicas can subscribe with the same name; the broker promotes
-- exactly one of them to active for a given context.
dispatcherSubscriptionName :: ContextId -> Text
dispatcherSubscriptionName (ContextId contextId) =
  Text.concat ["dispatcher-", contextId]
