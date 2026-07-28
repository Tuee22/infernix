module Main (main) where

import Infernix.Engines.Artifact.Capability (ValidatedEngineArtifact)

escapeValidatedArtifact ::
  ValidatedEngineArtifact s ->
  ValidatedEngineArtifact s
escapeValidatedArtifact = id

main :: IO ()
main = escapeValidatedArtifact `seq` pure ()
