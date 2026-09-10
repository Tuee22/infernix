{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE LinearTypes #-}

module Main (main) where

import Data.IORef (IORef, writeIORef)
import Infernix.Cluster (LifecycleProgram, finishLifecycle, lifecycleOperatorDown, runClusterLifecycle)

data Retained = forall s. Retained (LifecycleProgram s ())

capture :: IORef (Maybe Retained) -> IO ()
capture reference = runClusterLifecycle $ \session ->
  writeIORef reference (Just (Retained (lifecycleOperatorDown session Nothing (finishLifecycle ()))))

main :: IO ()
main = capture `seq` pure ()
