module Main (main) where

import Infernix.Engines.MaterializationLock
  ( MaterializationAuthority,
    withEngineMaterializationLock,
  )

escapeMaterializationAuthority ::
  IO (MaterializationAuthority ())
escapeMaterializationAuthority =
  withEngineMaterializationLock "/tmp" pure

main :: IO ()
main = pure ()
