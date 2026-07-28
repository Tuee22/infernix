{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LinearTypes #-}

module Main (main) where

import Infernix.Cluster.Subprocess.Protocol
  ( CommandPhase (..),
    Session,
    SessionProgram,
    SupervisorCustodyEvidence,
    SupervisorReadyEvidence,
    abandonSession,
    awaitSupervisorReady,
  )

skipPinCustodyObservation ::
  SupervisorCustodyEvidence ->
  SupervisorReadyEvidence ->
  Session s 'AnchorReady %1 ->
  SessionProgram s 'AnchorReady ()
skipPinCustodyObservation supervisorCustody readyEvidence anchorReady =
  awaitSupervisorReady
    (pure supervisorCustody)
    (pure ())
    (pure readyEvidence)
    anchorReady
    (abandonSession (pure ()))

main :: IO ()
main = pure ()
