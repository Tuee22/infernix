module Main (main) where

import Infernix.Engines.MaterializationLock
  ( withEngineMaterializationLock,
  )

captureWriterAfterUnlock :: IO (IO ())
captureWriterAfterUnlock =
  withEngineMaterializationLock "/tmp/infernix-engines" $ \authority ->
    pure (authority `seq` pure ())

main :: IO ()
main = pure ()
