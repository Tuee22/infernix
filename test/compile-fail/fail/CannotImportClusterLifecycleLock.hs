module Main (main) where

import Infernix.Cluster.LifecycleLock (withLifecycleFileLock)

main :: IO ()
main = withLifecycleFileLock "unreachable.lock" (pure ())
