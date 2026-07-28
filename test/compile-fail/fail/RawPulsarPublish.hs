module Main (main) where

import Data.Text (Text)
import Infernix.Config (Paths)
import Infernix.Runtime.Pulsar (publishInferenceRequest)
import Infernix.Types
  ( InferenceRequest,
    RuntimeMode,
  )

rawPublish ::
  Paths ->
  RuntimeMode ->
  Text ->
  InferenceRequest ->
  IO Text
rawPublish = publishInferenceRequest

main :: IO ()
main = rawPublish `seq` pure ()
