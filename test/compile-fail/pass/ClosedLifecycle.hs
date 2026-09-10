module Main (main) where

import Data.IORef (IORef, writeIORef)
import Infernix.Cluster (finishLifecycle, lifecycleOperatorDown, observeLifecycle, runClusterLifecycle)
import Infernix.Types (ClusterState)

ordered :: IO (Maybe ClusterState)
ordered = runClusterLifecycle $ \session ->
  observeLifecycle
    session
    ( \state ready ->
        lifecycleOperatorDown ready Nothing (finishLifecycle state)
    )

referenceControl :: IORef (Maybe ClusterState) -> IO ()
referenceControl reference = do
  observed <- runClusterLifecycle (`observeLifecycle` finishLifecycle)
  writeIORef reference observed

deferredControl :: IO (IO ())
deferredControl = runClusterLifecycle (finishLifecycle (pure ()))

main :: IO ()
main = ordered `seq` referenceControl `seq` deferredControl `seq` pure ()
