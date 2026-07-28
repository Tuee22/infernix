module Infernix.Cluster.MutationRecovery
  ( InterruptedMutationRecoveryEffects (..),
    runInterruptedMutationRecovery,
  )
where

import Control.Monad (unless)

-- | Effect boundary for recovering a persisted cluster mutation before the
-- ordinary bring-up reconciles the chart's desired state.
data InterruptedMutationRecoveryEffects state = InterruptedMutationRecoveryEffects
  { observeMutationRecoveryState :: IO (Maybe state),
    mutationRecoveryRequired :: state -> Bool,
    mutationRecoveryClusterExists :: state -> IO Bool,
    prepareLiveMutationRecovery :: state -> IO (),
    uncordonMutationNodes :: state -> IO Bool,
    announceLiveMutationRecovered :: state -> IO (),
    settleAbsentMutation :: state -> IO ()
  }

-- | Prepare any interrupted mutation, then continue through the ordinary
-- desired-state reconciliation. A failed uncordon prevents that continuation.
runInterruptedMutationRecovery ::
  InterruptedMutationRecoveryEffects state ->
  IO a ->
  IO a
runInterruptedMutationRecovery effects reconcileDesiredState = do
  maybeState <- observeMutationRecoveryState effects
  case maybeState of
    Just state
      | mutationRecoveryRequired effects state -> do
          clusterExists <- mutationRecoveryClusterExists effects state
          if clusterExists
            then do
              prepareLiveMutationRecovery effects state
              uncordoned <- uncordonMutationNodes effects state
              unless uncordoned $
                ioError
                  ( userError
                      "cluster up could not prove that every node was uncordoned; preserving the mutation marker and refusing to publish steady-state"
                  )
              announceLiveMutationRecovered effects state
            else settleAbsentMutation effects state
    _ -> pure ()
  reconcileDesiredState
