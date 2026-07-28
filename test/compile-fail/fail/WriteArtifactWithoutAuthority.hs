module Main (main) where

import Infernix.Engines.Artifact
  ( reconcileEngineArtifactRoot,
  )

writeArtifactWithoutAuthority :: IO ()
writeArtifactWithoutAuthority =
  reconcileEngineArtifactRoot "/tmp/infernix-artifact"

main :: IO ()
main = pure ()
