{-# LANGUAGE DataKinds #-}

module Main (main) where

import Data.Coerce (coerce)
import DesiredApi

relabelCeiling :: MemoryCeiling 'HostRam -> MemoryCeiling 'PodRam
relabelCeiling = coerce

main :: IO ()
main = relabelCeiling `seq` pure ()
