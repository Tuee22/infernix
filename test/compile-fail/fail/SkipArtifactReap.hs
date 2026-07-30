{-# LANGUAGE DataKinds #-}

module Main (main) where

import Infernix.Engines.Artifact.Capability
  ( ArtifactPhase (..),
    ArtifactRun,
    readyArtifactRun,
  )

-- | A caller must not be able to present a ready run where the runner-owned
-- reaped phase is required. Only 'reapArtifactRun' produces the reaped phase,
-- and it is not reachable without a validated artifact.
skipArtifactReap ::
  ArtifactRun s 'ArtifactReady ->
  ArtifactRun s 'ArtifactReaped
skipArtifactReap run =
  run

main :: IO ()
main =
  readyArtifactRun `seq` pure ()
