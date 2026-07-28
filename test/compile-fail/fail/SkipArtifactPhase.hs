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

skipArtifactPhase ::
  Session s 'ArtifactReady %1 ->
  Program s 'ArtifactReady ArtifactTerminalOutcome
skipArtifactPhase =
  reapArtifact (const (pure ArtifactTerminalCompleted))

main :: IO ()
main = pure ()
