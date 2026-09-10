{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RoleAnnotations #-}

module Infernix.Evidence.Lease.Internal
  ( Lease,
    Acquire (..),
    withLease,
    leasePayload,
  )
where

import Control.Exception (bracket)

-- | Evidence that a revocable condition is actively held. The constructor
-- is hidden outside this package kernel. The nominal region prevents direct
-- region substitution; the owning domain must contain any protected effects.
newtype Lease s p = Lease p

type role Lease nominal nominal

-- | How to establish the condition — performing the transition and proving
-- it holds — and how to release it on scope exit.
data Acquire p = Acquire
  { acquireEstablish :: IO p,
    acquireRelease :: p -> IO ()
  }

-- | Package-private runtime bracket. Rank-2 ordinary IO does not prevent a
-- deferred effect or existential from escaping. Only trusted domain operations
-- consume this callback; public effects use the closed lifecycle program.
withLease :: Acquire p -> (forall s. Lease s p -> IO r) -> IO r
withLease acquire body =
  bracket (acquireEstablish acquire) (acquireRelease acquire) (body . Lease)

-- | Internal payload access is not lifetime evidence. The owning operation
-- retains responsibility for resource liveness and must not export the payload
-- as revocable authority.
leasePayload :: Lease s p -> p
leasePayload (Lease p) = p
