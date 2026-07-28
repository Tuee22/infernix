{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LinearTypes #-}

module Main (main) where

import Infernix.Cluster.Subprocess.Protocol
  ( CommandPhase (..),
    PinCustodyEvidence,
    Session,
    SessionProgram,
    SupervisorReadyEvidence,
    abandonSession,
    awaitSupervisorReady,
  )

skipSupervisorObservation ::
  PinCustodyEvidence ->
  SupervisorReadyEvidence ->
  Session s 'AnchorReady %1 ->
  SessionProgram s 'AnchorReady ()
skipSupervisorObservation pinCustody readyEvidence anchorReady =
  awaitSupervisorReady
    (pure ())
    (pure pinCustody)
    (pure readyEvidence)
    anchorReady
    (abandonSession (pure ()))

main :: IO ()
main = pure ()
