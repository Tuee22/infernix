{-# LANGUAGE RankNTypes #-}

-- | Phase 1 Sprint 1.16 — the readiness kernel of the managed-state-transition
-- doctrine ('documents/architecture/managed_state_transitions.md'). A readiness
-- wait returns typed evidence instead of @IO ()@ or @IO Bool@: 'awaitReadiness'
-- is the only producer of a positive 'Ready', so a 'Ready' value witnesses that
-- a real poll observed the ready condition. The deadline is a required value, so
-- no wait is unbounded. This generalizes the existing @HarborBootstrapOutcome@
-- shape into a reusable primitive.
module Infernix.Evidence.Readiness
  ( Readiness,
    Deadline (..),
    Progress (..),
    foldReadiness,
    awaitReadiness,
    budgetDeadline,
  )
where

import Control.Concurrent (threadDelay)
import Data.Text (Text)

-- | A bounded wait budget. Every field is required, so a wait with no
-- ceiling and a poll with no interval are both unrepresentable.
data Deadline = Deadline
  { -- | delay between polls, in microseconds.
    deadlinePollMicros :: !Int,
    -- | give up as 'Expired' after this many seconds with no new progress.
    deadlineStallSeconds :: !Int,
    -- | absolute ceiling in seconds; reaching it while still advancing
    -- resolves as 'NotReady' (progressing but out of time) rather than
    -- 'Expired'.
    deadlineCeilingSeconds :: !Int
  }
  deriving (Eq, Show)

-- | Observed-versus-expected progress carried by a non-ready outcome.
data Progress = Progress
  { progressObserved :: !Int,
    progressExpected :: !Int,
    progressDetail :: !Text
  }
  deriving (Eq, Show)

-- | The typed outcome of a readiness wait. The constructors are hidden:
-- only 'awaitReadiness' builds a 'Ready', and callers eliminate the value
-- only through 'foldReadiness', so a fabricated 'Ready' is unrepresentable.
data Readiness e
  = Ready !e
  | NotReady !Progress
  | Expired !Progress

-- | Total eliminator: every outcome must be handled.
foldReadiness ::
  (e -> r) ->
  (Progress -> r) ->
  (Progress -> r) ->
  Readiness e ->
  r
foldReadiness onReady _ _ (Ready evidence) = onReady evidence
foldReadiness _ onNotReady _ (NotReady progress) = onNotReady progress
foldReadiness _ _ onExpired (Expired progress) = onExpired progress

-- | Poll @step@ until it yields evidence (@Right@) or the 'Deadline' is
-- reached. @step@ reports @Left progress@ when not yet ready. Progress that
-- advances resets the stall timer; a stall past 'deadlineStallSeconds'
-- resolves as 'Expired'; reaching 'deadlineCeilingSeconds' while still
-- advancing resolves as 'NotReady'. The only constructor of a positive
-- 'Ready' is here, from a real @Right@ the step returned.
awaitReadiness :: Deadline -> IO (Either Progress e) -> IO (Readiness e)
awaitReadiness deadline step = go 0 0 minBound
  where
    pollSeconds = max 1 (deadlinePollMicros deadline `div` 1000000)
    go elapsed stall lastObserved = do
      outcome <- step
      case outcome of
        Right evidence -> pure (Ready evidence)
        Left progress
          | progressObserved progress > lastObserved ->
              if elapsed >= deadlineCeilingSeconds deadline
                then pure (NotReady progress)
                else
                  delayThen
                    (go (elapsed + pollSeconds) 0 (progressObserved progress))
          | stall + pollSeconds >= deadlineStallSeconds deadline ->
              pure (Expired progress)
          | elapsed >= deadlineCeilingSeconds deadline ->
              pure (NotReady progress)
          | otherwise ->
              delayThen
                (go (elapsed + pollSeconds) (stall + pollSeconds) lastObserved)
    delayThen continue = threadDelay (deadlinePollMicros deadline) >> continue

-- | Encode a legacy @attempts x delayMicros@ retry budget as a 'Deadline'. The
-- poll interval is preserved exactly; the stall and ceiling are both
-- @(attempts - 1) x pollSeconds@ so a probe that never signals progress (always
-- @Left ('Progress' 0 1 _)@) runs exactly @max 1 attempts@ polls at the real
-- @delayMicros@ cadence — matching the legacy bare-recursion count for both
-- second and sub-second intervals (the kernel floors per-poll accounting to
-- >=1 s). The @max 0@ (rather than @max 1@) budget makes the @attempts <= 1@
-- edge exact: a single-attempt budget resolves to a 0 s ceiling, so the kernel
-- runs one poll and stops, instead of rounding up to two. This is the shared
-- bridge every hand-rolled @go n@ readiness loop migrates onto (Sprint 6.41).
budgetDeadline :: Int -> Int -> Deadline
budgetDeadline attempts delayMicros =
  let pollSeconds = max 1 (delayMicros `div` 1000000)
      budgetSeconds = max 0 ((attempts - 1) * pollSeconds)
   in Deadline
        { deadlinePollMicros = delayMicros,
          deadlineStallSeconds = budgetSeconds,
          deadlineCeilingSeconds = budgetSeconds
        }
