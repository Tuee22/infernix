{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE LinearTypes #-}

module Main (main) where

import Infernix.Cluster (LifecycleProgram, finishLifecycle, lifecycleOperatorDown, runClusterLifecycle)

data Retained = forall s. Retained (LifecycleProgram s ())

capture :: IO Retained
capture = runClusterLifecycle $ \session ->
  finishLifecycle (Retained (lifecycleOperatorDown session Nothing (finishLifecycle ()))) session

main :: IO ()
main = capture `seq` pure ()
