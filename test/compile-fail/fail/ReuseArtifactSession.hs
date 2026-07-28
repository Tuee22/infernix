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

reuseArtifactSession ::
  Session s 'ArtifactReady %1 ->
  ( Program s 'ArtifactReaped ArtifactTerminalOutcome,
    Program s 'ArtifactReaped ArtifactTerminalOutcome
  )
reuseArtifactSession session =
  ( reapArtifact (const (pure ArtifactTerminalCompleted)) session,
    reapArtifact (const (pure ArtifactTerminalCompleted)) session
  )

main :: IO ()
main = pure ()
