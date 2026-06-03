module Infernix.Runtime.KVCache
  ( KVCacheDecision (..),
    rebuildPrefixHashFromLog,
    verifyKVCachePrefix,
  )
where

import Infernix.Conversation.Hash (PrefixHash (..))
import Infernix.Conversation.Reducer qualified as Reducer
import Infernix.Web.Contracts (ContextId, ConversationMessage)

-- | Engine-side decision for whether a request can reuse an existing
-- context KV cache. The request's prefix hash is the source of truth:
-- a missing or mismatched cache forces a rebuild from the Pulsar
-- conversation log before inference can run.
data KVCacheDecision
  = ReuseKVCache PrefixHash
  | RebuildKVCache
      { requestedPrefixHash :: PrefixHash,
        cachedPrefixHash :: Maybe PrefixHash
      }
  deriving (Eq, Show)

verifyKVCachePrefix :: PrefixHash -> Maybe PrefixHash -> KVCacheDecision
verifyKVCachePrefix requested cached =
  case cached of
    Just cachedValue
      | cachedValue == requested -> ReuseKVCache requested
    _ ->
      RebuildKVCache
        { requestedPrefixHash = requested,
          cachedPrefixHash = cached
        }

rebuildPrefixHashFromLog :: ContextId -> [ConversationMessage] -> PrefixHash
rebuildPrefixHashFromLog contextId messages =
  Reducer.reducerPrefixHash (Reducer.foldEvents contextId messages)
