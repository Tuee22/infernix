module Infernix.Conversation.Reducer
  ( ReducerState (..),
    initialReducerState,
    StepOutcome (..),
    stepReducer,
    snapshotReducer,
    foldEvents,
    foldEventsKeepingPatches,
    applyPatchToState,
    inflightUserPrompts,
    nextDispatchablePrompt,
  )
where

import Data.Maybe (mapMaybe)
import Data.Sequence (Seq, (|>))
import Data.Sequence qualified as Seq
import Data.Set (Set)
import Data.Set qualified as Set
import Infernix.Conversation.Event
  ( ConversationEvent (..),
    eventUserPromptMessageId,
    isUserPrompt,
  )
import Infernix.Conversation.Hash
  ( PrefixHash (..),
    emptyPrefixHash,
    extendPrefixHashWithMessage,
  )
import Infernix.Conversation.Idempotency
  ( IdempotencyKey,
    IdempotencySet,
    emptyIdempotencySet,
    extractKey,
    rememberIdempotencyKey,
  )
import Infernix.Web.Contracts
  ( ContextId,
    ConversationMessage (..),
    ConversationState (..),
    ConversationStatePatch (..),
    MessageId,
  )

-- | Reducer-internal state. Carries the projected @ConversationState@ plus
-- the idempotency set so duplicate user prompts are dropped at fold time.
data ReducerState = ReducerState
  { reducerContextId :: ContextId,
    reducerMessages :: Seq ConversationMessage,
    reducerPrefixHash :: PrefixHash,
    reducerIdempotency :: IdempotencySet,
    reducerResolvedPromptIds :: Set MessageId
  }
  deriving (Eq, Show)

initialReducerState :: ContextId -> ReducerState
initialReducerState contextId =
  ReducerState
    { reducerContextId = contextId,
      reducerMessages = Seq.empty,
      reducerPrefixHash = emptyPrefixHash,
      reducerIdempotency = emptyIdempotencySet,
      reducerResolvedPromptIds = Set.empty
    }

-- | Possible outcomes for a single reducer step. A reducer that drops a
-- duplicate emits @StepDropped@ with no patch and an unchanged state, so the
-- caller can decide whether to ack-and-drop or surface the duplicate.
data StepOutcome
  = StepAdvanced ReducerState ConversationStatePatch
  | StepDropped ReducerState
  deriving (Eq, Show)

-- | Single-event reducer step. The (@ConversationMessage@) wraps the event
-- with its broker @MessageId@; that pair becomes the canonical sequence point
-- in both the snapshot and the patch.
stepReducer :: ReducerState -> ConversationMessage -> StepOutcome
stepReducer state message =
  classifyStep
    state
    message
    (extractKey (reducerContextId state) (conversationMessageEvent message))

classifyStep ::
  ReducerState ->
  ConversationMessage ->
  Maybe IdempotencyKey ->
  StepOutcome
classifyStep state _ (Just key)
  | (False, _) <- rememberIdempotencyKey key (reducerIdempotency state) =
      StepDropped state
classifyStep state message maybeKey =
  let event = conversationMessageEvent message
      newIdempotency = rememberMaybeKey maybeKey (reducerIdempotency state)
      newPrefixHash = extendPrefixHashWithMessage (reducerPrefixHash state) message
      newMessages = reducerMessages state |> message
      newResolved = resolvedAfter event (reducerResolvedPromptIds state)
      advanced =
        state
          { reducerMessages = newMessages,
            reducerPrefixHash = newPrefixHash,
            reducerIdempotency = newIdempotency,
            reducerResolvedPromptIds = newResolved
          }
      patch =
        ConversationStateAppendMessage
          { appendMessage = message,
            appendNewPrefixHash = unPrefixHash newPrefixHash
          }
   in StepAdvanced advanced patch

rememberMaybeKey :: Maybe IdempotencyKey -> IdempotencySet -> IdempotencySet
rememberMaybeKey Nothing set = set
rememberMaybeKey (Just key) set = snd (rememberIdempotencyKey key set)

resolvedAfter :: ConversationEvent -> Set MessageId -> Set MessageId
resolvedAfter event resolved = case eventUserPromptMessageId event of
  Just promptMessageId
    | isResolving event -> Set.insert promptMessageId resolved
  _ -> resolved

isResolving :: ConversationEvent -> Bool
isResolving (ConversationInferenceResultEvent _) = True
isResolving (ConversationCancelEvent _) = True
isResolving _ = False

-- | Snapshot reducer. Convenience wrapper that returns just the projection.
snapshotReducer :: ContextId -> [ConversationMessage] -> ConversationState
snapshotReducer contextId messages =
  let (finalState, _) = foldEventsKeepingPatches contextId messages
   in projectionFor finalState

-- | Identical projection to @snapshotReducer@. Kept as a separate name so the
-- intent at call sites is obvious.
foldEvents :: ContextId -> [ConversationMessage] -> ReducerState
foldEvents contextId messages =
  fst (foldEventsKeepingPatches contextId messages)

foldEventsKeepingPatches ::
  ContextId ->
  [ConversationMessage] ->
  (ReducerState, [ConversationStatePatch])
foldEventsKeepingPatches contextId =
  foldl step (initialReducerState contextId, [])
  where
    step (state, patches) message =
      case stepReducer state message of
        StepAdvanced advanced patch -> (advanced, patches <> [patch])
        StepDropped _ -> (state, patches)

-- | Apply a single patch to a state, returning the new state. Used by the
-- patch-stream-vs-snapshot equivalence property test.
applyPatchToState :: ConversationState -> ConversationStatePatch -> ConversationState
applyPatchToState state patch = case patch of
  ConversationStateAppendMessage message newHash ->
    state
      { conversationStateMessages = conversationStateMessages state <> [message],
        conversationStatePrefixHash = newHash
      }
  ConversationStateReplaceSnapshot snapshot -> snapshot

projectionFor :: ReducerState -> ConversationState
projectionFor state =
  ConversationState
    { conversationStateContextId = reducerContextId state,
      conversationStateMessages = toListSeq (reducerMessages state),
      conversationStatePrefixHash = unPrefixHash (reducerPrefixHash state)
    }
  where
    toListSeq = foldr (:) []

-- | The @MessageId@s of user prompts that have neither a matching
-- @InferenceResult@ nor a matching @Cancel@. The list is in conversation order;
-- the dispatcher's single-flight rule uses the first element.
inflightUserPrompts :: ReducerState -> [MessageId]
inflightUserPrompts state =
  let promptIds =
        mapMaybe
          (\message -> if isUserPrompt (conversationMessageEvent message) then Just (conversationMessageId message) else Nothing)
          (toList (reducerMessages state))
   in filter (`Set.notMember` reducerResolvedPromptIds state) promptIds
  where
    toList = foldr (:) []

-- | The next user-prompt @MessageId@ that the dispatcher should dispatch.
-- @Nothing@ when the queue is empty.
nextDispatchablePrompt :: ReducerState -> Maybe MessageId
nextDispatchablePrompt state =
  case inflightUserPrompts state of
    [] -> Nothing
    (next : _) -> Just next
