{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LinearTypes #-}

module Main (main) where

import Infernix.Engines.Artifact.Capability
  ( ArtifactPhase (..),
    ArtifactTerminalOutcome,
    Program,
    Session,
    reapArtifact,
  )

escapeArtifactNestedIO ::
  Session s 'ArtifactReady %1 ->
  Program s 'ArtifactReaped (IO ())
escapeArtifactNestedIO =
  reapArtifact (const (pure (pure ())))

main :: IO ()
main = pure ()
