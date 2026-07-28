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

skipDurableLease ::
  Session s 'AnchorReady %1 ->
  SessionProgram s 'LeaseDurable ()
skipDurableLease anchorReady =
  startTarget
    anchorReady
    (finishTarget (pure ()))

main :: IO ()
main = pure ()
