{-# LANGUAGE DataKinds #-}

module Main (main) where

import Infernix.Engines.Artifact.Capability
  ( ArtifactLaunchRequest,
    ArtifactTerminalOutcome (ArtifactTerminalCompleted),
    ValidatedEngineArtifact,
    artifactLauncher,
  )

-- | A launcher is handed only the closed launch request, so it must not be
-- able to receive, retain, or reuse the validated artifact capability.
reuseArtifactCapability ::
  (ValidatedEngineArtifact s -> IO ArtifactTerminalOutcome) ->
  ArtifactLaunchRequest ->
  IO ArtifactTerminalOutcome
reuseArtifactCapability retain =
  case artifactLauncher retain of
    _launcher -> const (pure ArtifactTerminalCompleted)

main :: IO ()
main = pure ()
