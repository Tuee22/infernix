{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LinearTypes #-}

module Main (main) where

import Infernix.Cluster.Subprocess.Protocol
  ( CommandPhase (..),
    PinCustodyEvidence,
    Session,
    SessionProgram,
    SupervisorCustodyEvidence,
    abandonSession,
    awaitSupervisorReady,
  )

skipFinalReadyObservation ::
  SupervisorCustodyEvidence ->
  PinCustodyEvidence ->
  Session s 'AnchorReady %1 ->
  SessionProgram s 'AnchorReady ()
skipFinalReadyObservation supervisorCustody pinCustody anchorReady =
  awaitSupervisorReady
    (pure supervisorCustody)
    (pure pinCustody)
    (pure ())
    anchorReady
    (abandonSession (pure ()))

main :: IO ()
main = pure ()
