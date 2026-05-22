module Infernix.Topic.Drafts
  ( DraftKey,
    draftKeyFromContextId,
    applyDraftEvent,
    foldDraftEvents,
    draftMapFromState,
    draftMapToState,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Infernix.Web.Contracts
  ( ContextId (..),
    DraftEntry (..),
    DraftEvent (..),
    DraftMapState (..),
  )

-- | Drafts are keyed by @ContextId@ at the compacted-topic layer. The broker
-- compacts away superseded text for a context; a @DraftCleared@ event is the
-- demo's explicit upsert-to-empty.
type DraftKey = Text

draftKeyFromContextId :: ContextId -> DraftKey
draftKeyFromContextId = unContextId

-- | Apply a single 'DraftEvent' to a draft map. @DraftCleared@ removes the
-- entry rather than recording an empty string; the latest event for a key
-- wins, matching compaction semantics.
applyDraftEvent :: Map DraftKey Text -> DraftEvent -> Map DraftKey Text
applyDraftEvent m (DraftUpdated contextId text) =
  Map.insert (draftKeyFromContextId contextId) text m
applyDraftEvent m (DraftCleared contextId) =
  Map.delete (draftKeyFromContextId contextId) m

foldDraftEvents :: [DraftEvent] -> Map DraftKey Text
foldDraftEvents = foldl applyDraftEvent Map.empty

-- | Build the typed @DraftMapState@ wire surface from a compacted-event fold.
-- Entries are returned in ascending @ContextId@ order so wire snapshots are
-- canonical.
draftMapFromState :: Map DraftKey Text -> DraftMapState
draftMapFromState m =
  DraftMapState
    { draftMapStateDrafts =
        [ DraftEntry (ContextId key) text
        | (key, text) <- Map.toAscList m
        ]
    }

draftMapToState :: DraftMapState -> Map DraftKey Text
draftMapToState DraftMapState {draftMapStateDrafts = entries} =
  Map.fromList
    [ (draftKeyFromContextId (draftEntryContextId entry), draftEntryText entry)
    | entry <- entries
    ]
