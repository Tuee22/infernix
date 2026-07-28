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
    Deadline
      ( Deadline,
        deadlinePollMicros,
        deadlineStallSeconds,
        deadlineCeilingSeconds
      ),
    Progress (..),
    PollOutcome (..),
    foldReadiness,
    awaitReadiness,
    awaitReadinessObservable,
    budgetDeadline,
    pollLimitedDeadline,
  )
where

import Control.Concurrent (threadDelay)
import Control.Monad (when)
import Data.Text (Text)
import Data.Text qualified as Text
import GHC.Clock (getMonotonicTimeNSec)
import System.Timeout (timeout)

-- | A bounded wait budget. Every field is required, so a wait with no
-- ceiling and a poll with no interval are both unrepresentable.
data Deadline
  = Deadline
      { -- | delay between polls, in microseconds.
        deadlinePollMicros :: !Int,
        -- | give up as 'Expired' after this many seconds with no new progress.
        deadlineStallSeconds :: !Int,
        -- | absolute ceiling in seconds; reaching it while still advancing
        -- resolves as 'NotReady' (progressing but out of time) rather than
        -- 'Expired'.
        deadlineCeilingSeconds :: !Int
      }
  | PollBudgetDeadline
      { deadlinePollMicros :: !Int,
        deadlineStallSeconds :: !Int,
        deadlineCeilingSeconds :: !Int,
        deadlineMaximumPolls :: !Int,
        deadlineStallClockMicros :: !Integer,
        deadlineWallClockMicros :: !Integer
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
awaitReadinessObservable deadline step = do
  startedAt <- monotonicMicros
  go
    startedAt
    startedAt
    0
    minBound
    False
    baselineProgress
  where
    baselineProgress = Progress 0 0 (Text.pack "no readiness measurement observed yet")
    pollDelayMicros = max 0 (deadlinePollMicros deadline)
    totalWallClockMicros =
      case deadline of
        Deadline {} ->
          secondsToMicros (deadlineCeilingSeconds deadline)
        PollBudgetDeadline {} ->
          deadlineWallClockMicros deadline
    stallWallClockMicros =
      case deadline of
        Deadline {} ->
          secondsToMicros (deadlineStallSeconds deadline)
        PollBudgetDeadline {} ->
          deadlineStallClockMicros deadline
    maximumPolls =
      case deadline of
        Deadline {} -> Nothing
        PollBudgetDeadline {} -> Just (deadlineMaximumPolls deadline)

    go startedAt lastProgressAt polls lastObserved lastPollAdvanced lastProgress = do
      beforePoll <- monotonicMicros
      let ceilingAt = startedAt + totalWallClockMicros
          stallAt = lastProgressAt + stallWallClockMicros
          cutoffAt = min ceilingAt stallAt
      if polls > 0 && beforePoll >= cutoffAt
        then pure (deadlineOutcome ceilingAt stallAt lastPollAdvanced lastProgress)
        else do
          maybeOutcome <-
            timeout
              (boundedTimeoutMicros (max 1 (cutoffAt - beforePoll)))
              step
          observedAt <- monotonicMicros
          case maybeOutcome of
            Nothing ->
              pure (deadlineOutcome ceilingAt stallAt lastPollAdvanced lastProgress)
            Just _outcome
              | observedAt >= cutoffAt ->
                  pure (deadlineOutcome ceilingAt stallAt lastPollAdvanced lastProgress)
            Just outcome ->
              resolveOutcome
                startedAt
                lastProgressAt
                (polls + 1)
                lastObserved
                lastProgress
                observedAt
                outcome

    resolveOutcome startedAt lastProgressAt polls lastObserved lastProgress observedAt outcome =
      case outcome of
        Measured (Right evidence) ->
          pure (Ready evidence)
        Measured (Left progress)
          | progressObserved progress > lastObserved ->
              finishOrDelay
                startedAt
                observedAt
                polls
                (progressObserved progress)
                True
                progress
                observedAt
                (NotReady progress)
          | otherwise ->
              finishOrDelay
                startedAt
                lastProgressAt
                polls
                lastObserved
                False
                progress
                observedAt
                (Expired progress)
        Unobservable _reason ->
          finishOrDelay
            startedAt
            lastProgressAt
            polls
            lastObserved
            False
            lastProgress
            observedAt
            (Expired lastProgress)

    finishOrDelay startedAt lastProgressAt polls lastObserved lastPollAdvanced lastProgress observedAt pollLimitOutcome = do
      let ceilingAt = startedAt + totalWallClockMicros
          stallAt = lastProgressAt + stallWallClockMicros
          pollLimitReached = maybe False (polls >=) maximumPolls
      if pollLimitReached
        then pure pollLimitOutcome
        else
          if observedAt >= stallAt || observedAt >= ceilingAt
            then pure (deadlineOutcome ceilingAt stallAt lastPollAdvanced lastProgress)
            else do
              let remainingBudget =
                    min
                      (stallAt - observedAt)
                      (ceilingAt - observedAt)
                  delayBudget =
                    min
                      (toInteger pollDelayMicros)
                      remainingBudget
              if remainingBudget <= 0
                then pure (deadlineOutcome ceilingAt stallAt lastPollAdvanced lastProgress)
                else do
                  when (delayBudget > 0) $
                    threadDelay (boundedTimeoutMicros delayBudget)
                  go
                    startedAt
                    lastProgressAt
                    polls
                    lastObserved
                    lastPollAdvanced
                    lastProgress

    -- A fast first progress sample can share the start timestamp at microsecond
    -- resolution. Preserve its classification when stall and ceiling tie.
    deadlineOutcome ceilingAt stallAt lastPollAdvanced progress
      | stallAt < ceilingAt = Expired progress
      | stallAt == ceilingAt && not lastPollAdvanced = Expired progress
      | otherwise = NotReady progress

secondsToMicros :: Int -> Integer
secondsToMicros seconds =
  toInteger (max 0 seconds) * 1000000

boundedTimeoutMicros :: Integer -> Int
boundedTimeoutMicros micros =
  fromInteger (min (toInteger (maxBound :: Int)) (max 1 micros))

monotonicMicros :: IO Integer
monotonicMicros =
  (`div` 1000) . toInteger <$> getMonotonicTimeNSec

-- | Encode a legacy @attempts x delayMicros@ retry budget as a 'Deadline'. The
-- poll interval and exact /maximum/ poll count are preserved as a cap, not a
-- quota, while the wait also gains a real wall-clock ceiling of
-- @attempts * delayMicros@. The extra interval bounds the final probe itself; a
-- hung probe therefore cannot escape the budget. A slow probe can consume the
-- wall budget before that maximum is reached. Callers whose probes
-- intentionally consume a separate timeout must use an explicit 'Deadline'
-- that includes that probe budget.
budgetDeadline :: Int -> Int -> Deadline
budgetDeadline attempts delayMicros =
  let boundedAttempts = max 1 attempts
      boundedDelayMicros = max 1 delayMicros
      wallClockMicros =
        toInteger boundedAttempts * toInteger boundedDelayMicros
      budgetSeconds =
        fromInteger
          ( min
              (toInteger (maxBound :: Int))
              ((wallClockMicros + 999999) `div` 1000000)
          )
   in PollBudgetDeadline
        { deadlinePollMicros = delayMicros,
          deadlineStallSeconds = budgetSeconds,
          deadlineCeilingSeconds = budgetSeconds,
          deadlineMaximumPolls = boundedAttempts,
          deadlineStallClockMicros = wallClockMicros,
          deadlineWallClockMicros = wallClockMicros
        }

-- | Build a deadline for a probe that intentionally consumes part of the wait
-- budget itself. The explicit stall and ceiling remain true monotonic wall-clock
-- bounds, while @maximumPolls@ independently preserves the caller's attempt
-- cap. This is the required shape for long-poll HTTP or subprocess probes: the
-- ceiling must include their declared per-probe timeout as well as inter-poll
-- delays.
pollLimitedDeadline :: Int -> Int -> Int -> Int -> Deadline
pollLimitedDeadline pollMicros stallSeconds ceilingSeconds maximumPolls =
  let boundedPollMicros = max 0 pollMicros
      boundedStallSeconds = max 0 stallSeconds
      boundedCeilingSeconds = max 0 ceilingSeconds
   in PollBudgetDeadline
        { deadlinePollMicros = boundedPollMicros,
          deadlineStallSeconds = boundedStallSeconds,
          deadlineCeilingSeconds = boundedCeilingSeconds,
          deadlineMaximumPolls = max 1 maximumPolls,
          deadlineStallClockMicros = secondsToMicros boundedStallSeconds,
          deadlineWallClockMicros = secondsToMicros boundedCeilingSeconds
        }
