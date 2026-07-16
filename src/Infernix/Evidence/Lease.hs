{-# LANGUAGE RankNTypes #-}

-- | Phase 1 Sprint 1.16 — the revocable-evidence kernel of the
-- managed-state-transition doctrine
-- ('documents/architecture/managed_state_transitions.md'). A revocable
-- condition (a drained writer, a valid credential, a reachable cluster) is
-- witnessed by a 'Lease' held for a scoped region. The region tag @s@ is
-- rank-2 quantified over the continuation given to 'withLease', so the
-- evidence cannot escape the scope in which the condition is actively held —
-- the direct answer to "the property was true when the transition ran, but
-- may not be true now". Spend-once capabilities layer surgical linear
-- consumption on top of this at their call sites.
module Infernix.Evidence.Lease
  ( Lease,
    Acquire (..),
    withLease,
    leasePayload,
  )
where

import Control.Exception (bracket)

-- | Evidence that a revocable condition is actively held. The constructor
-- is hidden: only 'withLease' builds one, and the phantom region @s@ confines
-- it to the establishing scope.
newtype Lease s p = Lease p

-- | How to establish the condition — performing the transition and proving
-- it holds — and how to release it on scope exit.
data Acquire p = Acquire
  { acquireEstablish :: IO p,
    acquireRelease :: p -> IO ()
  }

-- | Run @body@ with a 'Lease' witnessing that the condition is held. The
-- rank-2 quantifier over @s@ keeps the 'Lease' out of @body@'s result type,
-- so it cannot be returned or stored past the region; 'acquireRelease'
-- always runs on exit, including on exception.
withLease :: Acquire p -> (forall s. Lease s p -> IO r) -> IO r
withLease acquire body =
  bracket (acquireEstablish acquire) (acquireRelease acquire) (body . Lease)

-- | Read the held payload within the region. The payload (for example a
-- drained resource's identifier) is safe to read; the capability to act on
-- the held condition is the 'Lease' value itself, which the region confines.
leasePayload :: Lease s p -> p
leasePayload (Lease p) = p
