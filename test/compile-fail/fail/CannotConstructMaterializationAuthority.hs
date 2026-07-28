module Main (main) where

import Infernix.Engines.MaterializationLock
  ( MaterializationAuthority,
  )

constructMaterializationAuthority ::
  MaterializationAuthority ()
constructMaterializationAuthority =
  MaterializationAuthority

main :: IO ()
main = pure ()
