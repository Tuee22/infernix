module Infernix.Topic.Metadata
  ( CompactedKey,
    KeyedEvent (..),
    CompactedView,
    emptyCompactedView,
    upsertCompactedView,
    foldCompactedEvents,
    compactedViewEntries,
    lookupCompactedView,
    compactedViewSize,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)

-- | Compacted topics are keyed by an opaque string. The Pulsar broker keeps
-- only the latest value for each key, so the reader pattern is a fold that
-- mutates a 'Map' rather than accumulating a list.
type CompactedKey = Text

-- | Generic projection over a compacted topic: every event carries a key and
-- a value. Producers publish @KeyedEvent k v@ messages to the compacted topic,
-- and the broker discards every older value sharing the same @k@.
data KeyedEvent value = KeyedEvent
  { keyedEventKey :: CompactedKey,
    keyedEventValue :: value
  }
  deriving (Eq, Show)

-- | The reader-side projection of a compacted topic. @value@ is the typed
-- payload the producers publish; consumers see only the latest one per key.
newtype CompactedView value = CompactedView
  { compactedViewMap :: Map CompactedKey value
  }
  deriving (Eq, Show)

emptyCompactedView :: CompactedView value
emptyCompactedView = CompactedView Map.empty

-- | Upsert a keyed event into the view. Producing two events with the same
-- key replaces the earlier value, matching the broker's compaction semantics.
upsertCompactedView :: KeyedEvent value -> CompactedView value -> CompactedView value
upsertCompactedView event (CompactedView m) =
  CompactedView (Map.insert (keyedEventKey event) (keyedEventValue event) m)

-- | Fold a sequence of compacted events into a view. Useful both for
-- replaying a topic during reader bootstrap and for property tests that
-- assert the @N events with M distinct keys → M latest values@ invariant.
foldCompactedEvents :: [KeyedEvent value] -> CompactedView value
foldCompactedEvents = foldr upsertCompactedView emptyCompactedView . reverse

-- | All @(key, value)@ entries in the view, in ascending key order.
compactedViewEntries :: CompactedView value -> [(CompactedKey, value)]
compactedViewEntries (CompactedView m) = Map.toAscList m

lookupCompactedView :: CompactedKey -> CompactedView value -> Maybe value
lookupCompactedView key (CompactedView m) = Map.lookup key m

compactedViewSize :: CompactedView value -> Int
compactedViewSize (CompactedView m) = Map.size m
