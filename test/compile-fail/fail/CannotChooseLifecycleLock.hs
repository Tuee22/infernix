module Main (main) where

import Infernix.Cluster (beginHarnessConfigTransaction, cleanupHarnessRuntimeState, completeHarnessConfigTransaction, reconcileInterruptedHarnessStateAt, requireBoundedCommandActivitiesQuiescent, runClusterLifecycleAt, withRuntimeConfigWriteAccessAt)

main :: IO ()
main = pure ()
