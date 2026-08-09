{-# LANGUAGE RankNTypes #-}

module Main (main) where

import Infernix.BuildMemory
  ( BuildMemoryPlan,
    ToolchainSpawnAuthority,
    withToolchainSpawnAuthority,
  )

-- The region tag is universally quantified, so an authority cannot outlive the
-- region whose ceiling it carries.
escapeAuthority ::
  FilePath ->
  BuildMemoryPlan ->
  (forall s. ToolchainSpawnAuthority s -> IO (ToolchainSpawnAuthority s)) ->
  IO (ToolchainSpawnAuthority ())
escapeAuthority =
  withToolchainSpawnAuthority

main :: IO ()
main = pure ()
