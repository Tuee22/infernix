module Main (main) where

import Infernix.Bootstrap.Models (ModelBootstrapRequest)
import Infernix.Config (Paths)
import Infernix.Runtime.Pulsar (publishModelBootstrapRequest)

rawBootstrapPublish ::
  Paths ->
  ModelBootstrapRequest ->
  IO ()
rawBootstrapPublish = publishModelBootstrapRequest

main :: IO ()
main = rawBootstrapPublish `seq` pure ()
