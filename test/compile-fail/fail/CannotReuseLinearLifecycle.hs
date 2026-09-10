{-# LANGUAGE LinearTypes #-}

module Main (main) where

import Infernix.Cluster (LifecycleProgram, LifecycleSession, finishLifecycle)

reuse :: LifecycleSession s %1 -> (LifecycleProgram s (), LifecycleProgram s ())
reuse session = (finishLifecycle () session, finishLifecycle () session)

main :: IO ()
main = reuse `seq` pure ()
