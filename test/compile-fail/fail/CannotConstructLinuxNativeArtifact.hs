module Main (main) where

import Infernix.Engines.LinuxNative
  ( LinuxNativeEngineArtifact,
  )

constructLinuxNativeArtifact :: LinuxNativeEngineArtifact
constructLinuxNativeArtifact =
  LinuxNativeEngineArtifact
    "adapter"
    "engine"
    "kind"
    "source"
    "version"
    "runtime"
    "bin/runner"
    "bin/runner --smoke"

main :: IO ()
main = pure ()
