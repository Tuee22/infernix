module Infernix.Conversation.Idempotency
  ( IdempotencyKey (..),
    IdempotencySet,
    emptyIdempotencySet,
    rememberIdempotencyKey,
    alreadySeen,
    extractKey,
  )
where

import Data.Set (Set)
import Data.Set qualified as Set
import Infernix.Conversation.Event (eventClientIdempotencyKey)
import Infernix.Web.Contracts
  ( ClientIdempotencyKey,
    ContextId,
    ConversationEvent,
  )

-- | The composite key used for duplicate suppression on the conversation
-- topic. A second @UserPrompt@ that carries the same key in the same context
-- is dropped before reducer fold; this is the idempotent retry guarantee a
-- well-behaved client can rely on.
data IdempotencyKey = IdempotencyKey
  { idempotencyContextId :: ContextId,
    idempotencyClientKey :: ClientIdempotencyKey
  }
  deriving (Eq, Ord, Show)

newtype IdempotencySet = IdempotencySet {unIdempotencySet :: Set IdempotencyKey}
  deriving (Eq, Show)

emptyIdempotencySet :: IdempotencySet
emptyIdempotencySet = IdempotencySet Set.empty

-- | Record an idempotency key as seen. Returns the new set and whether the
-- key was previously absent (i.e. whether the caller should accept the event).
rememberIdempotencyKey :: IdempotencyKey -> IdempotencySet -> (Bool, IdempotencySet)
rememberIdempotencyKey key (IdempotencySet seen)
  | Set.member key seen = (False, IdempotencySet seen)
  | otherwise = (True, IdempotencySet (Set.insert key seen))

alreadySeen :: IdempotencyKey -> IdempotencySet -> Bool
alreadySeen key (IdempotencySet seen) = Set.member key seen

-- | Project an @IdempotencyKey@ out of a @(contextId, event)@ pair when the
-- event is a @UserPrompt@. Other events have no idempotency key.
extractKey :: ContextId -> ConversationEvent -> Maybe IdempotencyKey
extractKey contextId event =
  IdempotencyKey contextId <$> eventClientIdempotencyKey event
