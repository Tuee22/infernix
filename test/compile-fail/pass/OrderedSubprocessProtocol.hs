{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LinearTypes #-}

module Main (main) where

import Data.Aeson (Value)
import Infernix.Cluster.Subprocess.Activity (ActivityPublication)
import Infernix.Cluster.Subprocess.Protocol
  ( AnchorControl,
    PinCustodyEvidence,
    SupervisorCustodyEvidence,
    SupervisorReadyEvidence,
    awaitSupervisorReady,
    finishTarget,
    publishLease,
    startTarget,
    withCommandSession,
  )

orderedProtocol ::
  AnchorControl ->
  Value ->
  SupervisorCustodyEvidence ->
  PinCustodyEvidence ->
  SupervisorReadyEvidence ->
  ActivityPublication ->
  IO ()
orderedProtocol
  anchorControl
  configuration
  supervisorCustodyEvidence
  pinCustodyEvidence
  readyEvidence
  publication =
    withCommandSession
      maxBound
      anchorControl
      configuration
      ( \anchorReady ->
          awaitSupervisorReady
            (pure supervisorCustodyEvidence)
            (pure pinCustodyEvidence)
            (pure readyEvidence)
            anchorReady
            ( \supervisorReady ->
                publishLease
                  (pure publication)
                  supervisorReady
                  ( \leaseDurable ->
                      startTarget
                        leaseDurable
                        (finishTarget (pure ()))
                  )
            )
      )

main :: IO ()
main =
  orderedProtocol `seq` pure ()
