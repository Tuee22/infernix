{-# LANGUAGE OverloadedStrings #-}

module Infernix.Runtime.KVCache
  ( KVCacheDecision (..),
    EngineKVCache,
    KVCacheObservation (..),
    KVCacheRequest (..),
    kvCacheDecisionLabel,
    newEngineKVCache,
    observeKVCachePrefix,
    rebuildPrefixHashFromLog,
    verifyKVCachePrefix,
  )
where

import Data.IORef (IORef, atomicModifyIORef', newIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
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

newtype EngineKVCache = EngineKVCache (IORef (Map KVCacheKey PrefixHash))

data KVCacheKey = KVCacheKey
  { kvCacheKeyContextId :: Text,
    kvCacheKeyModelId :: Text
  }
  deriving (Eq, Ord, Show)

data KVCacheRequest = KVCacheRequest
  { kvCacheRequestContextId :: Text,
    kvCacheRequestModelId :: Text,
    kvCacheRequestPrefixHash :: PrefixHash
  }
  deriving (Eq, Show)

data KVCacheObservation = KVCacheObservation
  { kvCacheObservationRequest :: KVCacheRequest,
    kvCacheObservationDecision :: KVCacheDecision
  }
  deriving (Eq, Show)

newEngineKVCache :: IO EngineKVCache
newEngineKVCache = EngineKVCache <$> newIORef Map.empty

observeKVCachePrefix :: EngineKVCache -> KVCacheRequest -> IO KVCacheObservation
observeKVCachePrefix (EngineKVCache cacheRef) request =
  atomicModifyIORef' cacheRef $ \cache ->
    let key =
          KVCacheKey
            { kvCacheKeyContextId = kvCacheRequestContextId request,
              kvCacheKeyModelId = kvCacheRequestModelId request
            }
        cached = Map.lookup key cache
        decision = verifyKVCachePrefix (kvCacheRequestPrefixHash request) cached
        updatedCache = Map.insert key (kvCacheRequestPrefixHash request) cache
     in ( updatedCache,
          KVCacheObservation
            { kvCacheObservationRequest = request,
              kvCacheObservationDecision = decision
            }
        )

kvCacheDecisionLabel :: KVCacheDecision -> Text
kvCacheDecisionLabel decision =
  case decision of
    ReuseKVCache _ -> "reuse"
    RebuildKVCache {} -> "rebuild"

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
