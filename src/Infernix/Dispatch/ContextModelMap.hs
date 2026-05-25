-- | Phase 7 Sprint 7.12 — typed map from 'Contracts.ContextId' to the
-- per-context model id the SPA's @ClientCreateContext@ message picked.
--
-- The supported flow:
--
-- 1. The SPA's new-context dialog reads the active substrate's
--    generated @.dhall@ catalog, surfaces it as the model picker, and
--    fires a typed @ClientCreateContext { clientCreateContextId,
--    clientCreateContextModelId, clientCreateContextTitle }@.
-- 2. The demo's WebSocket handler unwraps that and publishes a typed
--    @ContextMetadataEvent { ContextCreated { contextCreatedContextId,
--    contextCreatedModelId, contextCreatedTitle } }@ to
--    @persistent://infernix/demo/demo.user.<userId>.contexts@ (compacted).
-- 3. The coordinator daemon spawns a per-user compacted-reader worker
--    when it observes a new user (its dispatcher loop already enumerates
--    @demo.user.*.contexts@-shaped topics). That worker decodes each
--    'ContextCreated' event and calls 'recordContextModel' so the
--    dispatcher publish path can look up the right model id at the
--    moment of dispatch.
-- 4. The dispatcher's 'publishDispatchedInferenceRequest' helper calls
--    'lookupModelId' to populate the @request_model_id@ proto field. If
--    the map has no entry, the dispatcher publishes an empty model id;
--    the engine validates and surfaces a typed error result rather than
--    silently succeeding with a generic-shape result.
--
-- The map lives in process memory only — it is rebuilt from the
-- compacted topic on coordinator restart. No durable derivation lives
-- here.
module Infernix.Dispatch.ContextModelMap
  ( ContextModelMap,
    newContextModelMap,
    lookupModelId,
    recordContextModel,
    recordContextMetadataEvent,
    contextModelMapSize,
  )
where

import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Infernix.Web.Contracts
  ( ContextId (..),
    ContextMetadataEvent
      ( ContextCreated,
        ContextRenamed,
        ContextSoftDeleted,
        contextCreatedContextId,
        contextCreatedModelId
      ),
  )

-- | Process-local map keyed by 'ContextId'.
newtype ContextModelMap = ContextModelMap (IORef (Map Text Text))

newContextModelMap :: IO ContextModelMap
newContextModelMap = ContextModelMap <$> newIORef Map.empty

-- | Look up the model id the SPA pinned to the context at create time.
-- Returns 'Nothing' when the dispatcher fires before the
-- @ContextCreated@ event has been consumed (race window during cold
-- coordinator startup). The supported flow surfaces a typed engine
-- error rather than auto-selecting a default model.
lookupModelId :: ContextModelMap -> ContextId -> IO (Maybe Text)
lookupModelId (ContextModelMap ref) (ContextId contextIdText) = do
  m <- readIORef ref
  pure (Map.lookup contextIdText m)

-- | Write a @(contextId, modelId)@ pair into the map. Idempotent: a
-- repeat insert of the same key/value is a no-op. The supported
-- 'ContextCreated' event from the SPA pins the model id for the
-- context's lifetime; later 'ContextRenamed' and 'ContextSoftDeleted'
-- events do not alter the binding.
recordContextModel :: ContextModelMap -> ContextId -> Text -> IO ()
recordContextModel (ContextModelMap ref) (ContextId contextIdText) modelId =
  atomicModifyIORef' ref $ \m -> (Map.insert contextIdText modelId m, ())

-- | Apply one decoded 'ContextMetadataEvent' to the map. 'ContextCreated'
-- pins the model id; 'ContextRenamed' and 'ContextSoftDeleted' are
-- no-ops for the map (the supported contract pins model id for life;
-- rename and soft-delete are pure metadata changes).
recordContextMetadataEvent :: ContextModelMap -> ContextMetadataEvent -> IO ()
recordContextMetadataEvent contextModelMap event = case event of
  ContextCreated {contextCreatedContextId = cid, contextCreatedModelId = mid} ->
    recordContextModel contextModelMap cid mid
  ContextRenamed {} -> pure ()
  ContextSoftDeleted {} -> pure ()

-- | Number of contexts currently mapped. Exposed for diagnostics in the
-- coordinator startup log and for the unit suite's invariant checks.
contextModelMapSize :: ContextModelMap -> IO Int
contextModelMapSize (ContextModelMap ref) = Map.size <$> readIORef ref
