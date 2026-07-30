{-# LANGUAGE DataKinds #-}

module Main (main) where

import Infernix.Engines.Artifact.Capability
  ( ArtifactLaunchRequest,
    ArtifactLauncher,
    ArtifactTerminalOutcome (ArtifactTerminalCompleted),
    artifactLaunchEntrypoint,
    artifactLaunchInstallRoot,
    artifactLauncher,
  )

-- | The supported shape: an unprivileged launcher over the closed, first-order
-- launch request. It never names a validated artifact, an artifact run, or a
-- next-phase continuation.
orderedArtifactLauncher :: ArtifactLauncher
orderedArtifactLauncher =
  artifactLauncher describeAndComplete

describeAndComplete :: ArtifactLaunchRequest -> IO ArtifactTerminalOutcome
describeAndComplete request =
  artifactLaunchInstallRoot request `seq`
    artifactLaunchEntrypoint request `seq`
      pure ArtifactTerminalCompleted

main :: IO ()
main =
  orderedArtifactLauncher `seq` pure ()
