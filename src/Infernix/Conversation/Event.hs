module Infernix.Conversation.Event
  ( ConversationEvent (..),
    ConversationMessage (..),
    UserPromptPayload (..),
    ConversationInferenceResultPayload (..),
    ConversationCancelPayload (..),
    ConversationUserUploadPayload (..),
    eventClientIdempotencyKey,
    eventUserPromptMessageId,
    isUserPrompt,
    isInferenceResult,
    isCancel,
  )
where

import Infernix.Web.Contracts
  ( ClientIdempotencyKey,
    ConversationCancelPayload (..),
    ConversationEvent (..),
    ConversationInferenceResultPayload (..),
    ConversationMessage (..),
    ConversationUserUploadPayload (..),
    MessageId,
    UserPromptPayload (..),
  )
import Infernix.Web.Contracts qualified as Contracts

-- | The idempotency key carried by a @UserPrompt@ event, if any. Other event
-- variants have no idempotency-key field; this returns @Nothing@ for them.
eventClientIdempotencyKey :: ConversationEvent -> Maybe ClientIdempotencyKey
eventClientIdempotencyKey (ConversationUserPromptEvent payload) =
  Just (Contracts.promptClientIdempotencyKey payload)
eventClientIdempotencyKey _ = Nothing

-- | The user-prompt @MessageId@ that an @InferenceResult@ or @Cancel@ event
-- refers to. @UserPrompt@ events are themselves identified by their own
-- @MessageId@ at the @ConversationMessage@ layer; this helper inspects the
-- causal pointer carried in result/cancel payloads.
eventUserPromptMessageId :: ConversationEvent -> Maybe MessageId
eventUserPromptMessageId (ConversationInferenceResultEvent payload) =
  Just (Contracts.inferenceResultUserPromptMessageId payload)
eventUserPromptMessageId (ConversationCancelEvent payload) =
  Just (Contracts.cancelUserPromptMessageId payload)
eventUserPromptMessageId _ = Nothing

isUserPrompt :: ConversationEvent -> Bool
isUserPrompt (ConversationUserPromptEvent _) = True
isUserPrompt _ = False

isInferenceResult :: ConversationEvent -> Bool
isInferenceResult (ConversationInferenceResultEvent _) = True
isInferenceResult _ = False

isCancel :: ConversationEvent -> Bool
isCancel (ConversationCancelEvent _) = True
isCancel _ = False
