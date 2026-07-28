{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LinearTypes #-}

module Main (main) where

import Infernix.Cluster.Subprocess.Protocol
  ( CommandPhase (..),
    Session,
    SessionProgram,
    finishTarget,
    publishLease,
    startTarget,
  )

skipDurablePublication ::
  Session s 'SupervisorReady %1 ->
  SessionProgram s 'SupervisorReady ()
skipDurablePublication supervisorReady =
  publishLease
    (pure ())
    supervisorReady
    ( \leaseDurable ->
        startTarget
          leaseDurable
          (finishTarget (pure ()))
    )

main :: IO ()
main = pure ()
