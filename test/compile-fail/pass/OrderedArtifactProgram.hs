{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LinearTypes #-}

module Main (main) where

import Infernix.Engines.Artifact.Capability
  ( ArtifactPhase (..),
    ArtifactTerminalOutcome (ArtifactTerminalCompleted),
    Program,
    Session,
    reapArtifact,
  )

orderedArtifactProgram ::
  Session s 'ArtifactReady %1 ->
  Program s 'ArtifactReaped ArtifactTerminalOutcome
orderedArtifactProgram =
  reapArtifact (const (pure ArtifactTerminalCompleted))

main :: IO ()
main =
  orderedArtifactProgram `seq` pure ()
