{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LinearTypes #-}

module Main (main) where

import Infernix.Cluster.Subprocess.Protocol
  ( CommandPhase (..),
    Session,
    SessionProgram,
    finishTarget,
    startTarget,
  )

reuseStartAuthority ::
  Session s 'LeaseDurable %1 ->
  ( SessionProgram s 'LeaseDurable (),
    SessionProgram s 'LeaseDurable ()
  )
reuseStartAuthority session =
  ( startTarget
      session
      (finishTarget (pure ())),
    startTarget
      session
      (finishTarget (pure ()))
  )

main :: IO ()
main = pure ()
