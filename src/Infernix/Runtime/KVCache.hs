{-# LANGUAGE OverloadedStrings #-}

-- | Phase 7 Sprint 7.31 — what an engine is allowed to claim it already holds.
--
-- The retired form kept a map from @(context, model)@ to a prefix hash, and
-- wrote the requested hash into that map on every observation. Two things were
-- wrong with it, and they compound. The key was too coarse: a different
-- artifact, a different tokenizer or template, a different execution shape, or
-- a different tenant all shared one entry, so a "hit" could describe state that
-- did not correspond to the request. And the write happened at observation time,
-- before any engine state existed — the bookkeeping recorded an intention, so
-- the next request for the same prefix read a hit whether or not the first
-- request ever built anything.
--
-- The identity here names every input that changes what the state /is/, and
-- validity is published only by 'publishKVCacheState', which a caller reaches
-- only after the engine reported constructed state. A failed construction, a
-- restart, or a prefix divergence leaves nothing to reuse, which is the honest
-- answer rather than an optimistic one.
module Infernix.Runtime.KVCache
  ( EngineKVCache,
    KVCacheDecision (..),
    KVCacheDisposition (..),
    KVCacheIdentity (..),
    KVCacheObservation (..),
    KVCacheRequest (..),
    KVCacheRequestSeed (..),
    completeKVCacheRequest,
    invalidateKVCacheState,
    kvCacheDecisionLabel,
    kvCacheDispositionLabel,
    kvCacheRequestIdentity,
    newEngineKVCache,
    observeKVCachePrefix,
    publishKVCacheState,
    rebuildPrefixHashFromLog,
    verifyKVCachePrefix,
  )
where

import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Infernix.Conversation.Hash (PrefixHash (..))
import Infernix.Conversation.Reducer qualified as Reducer
import Infernix.Web.Contracts (ContextId, ConversationMessage)

-- | Engine-side decision for whether a request can reuse existing state. The
-- request's verified prefix hash is the source of truth: a missing or
-- mismatched entry forces a rebuild from the durable conversation log before
-- inference can run.
data KVCacheDecision
  = ReuseKVCache PrefixHash
  | RebuildKVCache
      { requestedPrefixHash :: PrefixHash,
        cachedPrefixHash :: Maybe PrefixHash
      }
  deriving (Eq, Show)

-- | What the engine is actually told to do. A backend that cannot reuse state
-- is told to replay, and says so, rather than being handed a reuse it has no
-- way to honour.
data KVCacheDisposition
  = ReuseConstructedState
  | ReplayVerifiedPrefix
  deriving (Eq, Show)

kvCacheDispositionLabel :: KVCacheDisposition -> Text
kvCacheDispositionLabel disposition =
  case disposition of
    ReuseConstructedState -> "reuse"
    ReplayVerifiedPrefix -> "replay"

-- | Every input that changes what the constructed state is. Two requests share
-- an entry only when all of these agree.
data KVCacheIdentity = KVCacheIdentity
  { kvIdentityTenant :: Text,
    kvIdentityContext :: Text,
    kvIdentityModel :: Text,
    -- | The artifact the weights came from, so a rebuilt or replaced model does
    -- not inherit the previous one's state.
    kvIdentityArtifact :: Text,
    -- | The tokenizer or prompt template in force. The same text tokenizes
    -- differently under a different one, so the state is not the same state.
    kvIdentityTemplate :: Text,
    -- | The admitted execution shape, rendered. A different context length or
    -- batch shape produces differently shaped state.
    kvIdentityExecutionShape :: Text
  }
  deriving (Eq, Ord, Show)

newtype EngineKVCache = EngineKVCache (IORef (Map KVCacheIdentity PrefixHash))

data KVCacheRequest = KVCacheRequest
  { kvCacheRequestContextId :: Text,
    kvCacheRequestModelId :: Text,
    kvCacheRequestTenantId :: Text,
    kvCacheRequestArtifact :: Text,
    kvCacheRequestTemplate :: Text,
    kvCacheRequestExecutionShape :: Text,
    kvCacheRequestPrefixHash :: PrefixHash
  }
  deriving (Eq, Show)

data KVCacheObservation = KVCacheObservation
  { kvCacheObservationRequest :: KVCacheRequest,
    kvCacheObservationDecision :: KVCacheDecision
  }
  deriving (Eq, Show)

-- | What the request envelope alone establishes: who is asking, about which
-- context and model, at which verified prefix. The remaining identity fields
-- are properties of the admitted execution and are supplied where that is in
-- hand, rather than guessed at the transport boundary.
data KVCacheRequestSeed = KVCacheRequestSeed
  { kvSeedTenantId :: Text,
    kvSeedContextId :: Text,
    kvSeedModelId :: Text,
    kvSeedPrefixHash :: PrefixHash,
    kvSeedConversationLogOffset :: Int
  }
  deriving (Eq, Show)

completeKVCacheRequest :: KVCacheRequestSeed -> Text -> Text -> Text -> KVCacheRequest
completeKVCacheRequest seed artifact template executionShape =
  KVCacheRequest
    { kvCacheRequestContextId = kvSeedContextId seed,
      kvCacheRequestModelId = kvSeedModelId seed,
      kvCacheRequestTenantId = kvSeedTenantId seed,
      kvCacheRequestArtifact = artifact,
      kvCacheRequestTemplate = template,
      kvCacheRequestExecutionShape = executionShape,
      kvCacheRequestPrefixHash = kvSeedPrefixHash seed
    }

kvCacheRequestIdentity :: KVCacheRequest -> KVCacheIdentity
kvCacheRequestIdentity request =
  KVCacheIdentity
    { kvIdentityTenant = kvCacheRequestTenantId request,
      kvIdentityContext = kvCacheRequestContextId request,
      kvIdentityModel = kvCacheRequestModelId request,
      kvIdentityArtifact = kvCacheRequestArtifact request,
      kvIdentityTemplate = kvCacheRequestTemplate request,
      kvIdentityExecutionShape = kvCacheRequestExecutionShape request
    }

newEngineKVCache :: IO EngineKVCache
newEngineKVCache = EngineKVCache <$> newIORef Map.empty

-- | Read what this engine holds for the request's identity. This is a read:
-- observing a request never makes its state exist.
observeKVCachePrefix :: EngineKVCache -> KVCacheRequest -> IO KVCacheObservation
observeKVCachePrefix (EngineKVCache cacheRef) request = do
  cache <- readIORef cacheRef
  let cached = Map.lookup (kvCacheRequestIdentity request) cache
  pure
    KVCacheObservation
      { kvCacheObservationRequest = request,
        kvCacheObservationDecision =
          verifyKVCachePrefix (kvCacheRequestPrefixHash request) cached
      }

-- | Record that this engine now holds constructed state for exactly this
-- identity and prefix. The only caller is the path that observed the engine
-- build it.
publishKVCacheState :: EngineKVCache -> KVCacheIdentity -> PrefixHash -> IO ()
publishKVCacheState (EngineKVCache cacheRef) identity prefixHash =
  atomicModifyIORef' cacheRef (\cache -> (Map.insert identity prefixHash cache, ()))

-- | Drop whatever was recorded for an identity. Construction failure, engine
-- restart, and prefix divergence all reach this rather than leaving a claim
-- standing.
invalidateKVCacheState :: EngineKVCache -> KVCacheIdentity -> IO ()
invalidateKVCacheState (EngineKVCache cacheRef) identity =
  atomicModifyIORef' cacheRef (\cache -> (Map.delete identity cache, ()))

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
