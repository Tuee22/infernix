module Infernix.Demo.Bootstrap
  ( DemoBucketBootstrapPlan (..),
    planDemoBucketBootstrap,
    requiredDemoBuckets,
  )
where

import Data.Text (Text)
import Infernix.Objects.Layout qualified as Layout

-- | The buckets the demo backend requires before serving requests. Used by
-- the idempotent first-run bootstrap path that creates any missing bucket
-- via the MinIO admin API.
requiredDemoBuckets :: [Text]
requiredDemoBuckets =
  [ Layout.unModelsBucket Layout.defaultModelsBucket,
    Layout.unDemoObjectsBucket Layout.defaultDemoObjectsBucket
  ]

-- | A pure diff between the buckets MinIO already has and the ones the demo
-- needs. The reconcile loop calls @MinIO.makeBucket@ for each entry in
-- @planMissingBuckets@; the call is itself idempotent (MinIO returns
-- BucketAlreadyOwnedByYou on retry).
data DemoBucketBootstrapPlan = DemoBucketBootstrapPlan
  { planExistingBuckets :: [Text],
    planMissingBuckets :: [Text]
  }
  deriving (Eq, Show)

-- | Compute the bootstrap plan from a snapshot of the buckets MinIO already
-- exposes.
planDemoBucketBootstrap :: [Text] -> DemoBucketBootstrapPlan
planDemoBucketBootstrap existing =
  DemoBucketBootstrapPlan
    { planExistingBuckets = existing,
      planMissingBuckets = filter (`notElem` existing) requiredDemoBuckets
    }
