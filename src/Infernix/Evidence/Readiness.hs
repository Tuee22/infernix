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
    PollOutcome (..),
    foldReadiness,
    awaitReadiness,
    awaitReadinessObservable,
    budgetDeadline,
  )
where

import Control.Concurrent (threadDelay)
import Data.Text (Text)
import Data.Text qualified as Text

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

-- | The outcome of one poll of an /observable/ probe. A probe that reads a
-- remote system does not always get to observe it: a transport fault (a reset
-- idle connection, a HEAD timeout, a not-yet-ready @5xx@) is neither "ready"
-- nor "a concrete not-ready count" — it is a failure /to measure at all/.
-- Collapsing that third fact into a fabricated 'Progress' count is the
-- representable-invalid-state the warm-model-cache stall was built from: a
-- present-but-momentarily-unreachable sentinel was counted as "absent",
-- deflating the readiness census and stalling an already-warm cache to the
-- give-up deadline. 'PollOutcome' makes "I could not observe" a first-class
-- term the kernel routes to /retry-within-budget/, so it can never masquerade
-- as ground truth.
data PollOutcome e
  = -- | the probe observed the system: ready (@Right@) or a real not-ready
    -- count (@Left progress@).
    Measured !(Either Progress e)
  | -- | the probe could not observe the system this poll (carries a reason for
    -- diagnostics only — never a fact about the observed state).
    Unobservable !Text

-- | Poll @step@ until it yields evidence (@Right@) or the 'Deadline' is
-- reached. @step@ reports @Left progress@ when not yet ready. Progress that
-- advances resets the stall timer; a stall past 'deadlineStallSeconds'
-- resolves as 'Expired'; reaching 'deadlineCeilingSeconds' while still
-- advancing resolves as 'NotReady'. The only constructor of a positive
-- 'Ready' is here, from a real @Right@ the step returned. This is the
-- non-observable-fault special case of 'awaitReadinessObservable': every
-- poll is a 'Measured' outcome.
awaitReadiness :: Deadline -> IO (Either Progress e) -> IO (Readiness e)
awaitReadiness deadline step =
  awaitReadinessObservable deadline (Measured <$> step)

-- | Poll an /observable/ @step@ until it yields evidence or the 'Deadline' is
-- reached. Identical to 'awaitReadiness' on 'Measured' outcomes (so it is a
-- behaviour-preserving generalization: 'awaitReadiness' is exactly this fed
-- @Measured <$> step@, and every existing count-based caller is unchanged). An
-- 'Unobservable' poll is /not/ a measurement: it accrues stall like a
-- non-advancing poll and cannot advance the running maximum, so a transient
-- fault can never mint a 'Ready' nor deflate the observed count — it only ever
-- buys another poll within the same bounded budget. If the budget expires while
-- every recent poll was unobservable, the last real 'Progress' (or a zero
-- baseline) rides the 'Expired' / 'NotReady' outcome.
awaitReadinessObservable :: Deadline -> IO (PollOutcome e) -> IO (Readiness e)
awaitReadinessObservable deadline step = go 0 0 minBound baselineProgress
  where
    pollSeconds = max 1 (deadlinePollMicros deadline `div` 1000000)
    baselineProgress = Progress 0 0 (Text.pack "no readiness measurement observed yet")
    go elapsed stall lastObserved lastProgress = do
      outcome <- step
      case outcome of
        Measured (Right evidence) -> pure (Ready evidence)
        Measured (Left progress)
          | progressObserved progress > lastObserved ->
              if elapsed >= deadlineCeilingSeconds deadline
                then pure (NotReady progress)
                else
                  delayThen
                    (go (elapsed + pollSeconds) 0 (progressObserved progress) progress)
          | stall + pollSeconds >= deadlineStallSeconds deadline ->
              pure (Expired progress)
          | elapsed >= deadlineCeilingSeconds deadline ->
              pure (NotReady progress)
          | otherwise ->
              delayThen
                (go (elapsed + pollSeconds) (stall + pollSeconds) lastObserved progress)
        Unobservable _reason
          | stall + pollSeconds >= deadlineStallSeconds deadline ->
              pure (Expired lastProgress)
          | elapsed >= deadlineCeilingSeconds deadline ->
              pure (NotReady lastProgress)
          | otherwise ->
              delayThen
                (go (elapsed + pollSeconds) (stall + pollSeconds) lastObserved lastProgress)
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
