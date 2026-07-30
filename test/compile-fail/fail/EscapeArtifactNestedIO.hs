{-# LANGUAGE DataKinds #-}

module Main (main) where

import Infernix.Engines.Artifact.Capability
  ( ArtifactLaunchRequest,
    ArtifactLauncher,
    artifactLauncher,
  )

-- | The launcher result is a fixed, closed classification. It must not be able
-- to carry a nested 'IO' action back out of the shared-lock region.
escapeArtifactNestedIO :: ArtifactLauncher
escapeArtifactNestedIO =
  artifactLauncher nestedAction

nestedAction :: ArtifactLaunchRequest -> IO (IO ())
nestedAction _request = pure (pure ())

main :: IO ()
main = pure ()
