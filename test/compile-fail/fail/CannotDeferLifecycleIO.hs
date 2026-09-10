{-# LANGUAGE LinearTypes #-}

module Main (main) where

import Control.Exception (evaluate)
import Control.Monad (void)
import Infernix.Cluster (finishLifecycle, lifecycleOperatorDown, runClusterLifecycle)

defer :: IO (IO ())
defer = runClusterLifecycle $ \session ->
  pure (void (evaluate (lifecycleOperatorDown session Nothing (finishLifecycle ())))) :: IO (IO ())

main :: IO ()
main = defer `seq` pure ()
