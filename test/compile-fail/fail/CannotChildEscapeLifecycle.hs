{-# LANGUAGE LinearTypes #-}

module Main (main) where

import Control.Concurrent (ThreadId, forkIO)
import Control.Exception (evaluate)
import Control.Monad (void)
import Infernix.Cluster (finishLifecycle, lifecycleOperatorDown, runClusterLifecycle)

escape :: IO ThreadId
escape = runClusterLifecycle $ \session ->
  forkIO (void (evaluate (lifecycleOperatorDown session Nothing (finishLifecycle ()))))

main :: IO ()
main = escape `seq` pure ()
