{-# LANGUAGE DataKinds #-}

module Main (main) where

import Infernix.Engines.Artifact.Capability
  ( ArtifactPhase (..),
    ArtifactRun,
    ArtifactTerminalOutcome,
    artifactRunOutcome,
  )

-- | The terminal result must be readable only from the reaped phase. Reading
-- it out of a ready run would skip the runner-owned revalidation and launch.
skipArtifactPhase ::
  ArtifactRun s 'ArtifactReady ->
  ArtifactTerminalOutcome
skipArtifactPhase =
  artifactRunOutcome

main :: IO ()
main = pure ()
