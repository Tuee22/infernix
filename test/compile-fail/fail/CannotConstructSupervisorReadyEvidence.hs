module Main (main) where

import Infernix.Cluster.Subprocess.Protocol (SupervisorReadyEvidence)

constructReadyEvidence :: SupervisorReadyEvidence
constructReadyEvidence =
  SupervisorReadyEvidence

main :: IO ()
main = pure ()
