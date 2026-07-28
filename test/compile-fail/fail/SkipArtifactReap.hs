{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LinearTypes #-}

module Main (main) where

import Infernix.Engines.Artifact.Capability
  ( ArtifactPhase (..),
    ArtifactTerminalOutcome,
    Program,
    Session,
  )

skipArtifactReap ::
  Session s 'ArtifactReady %1 ->
  Program s 'ArtifactReaped ArtifactTerminalOutcome
skipArtifactReap session =
  session

main :: IO ()
main = pure ()
