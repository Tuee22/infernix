{-# LANGUAGE DataKinds #-}

module Main (main) where

import Data.Coerce (coerce)
import DesiredApi

relabelEnforcer :: Enforcer 'HostRam -> Enforcer 'PodRam
relabelEnforcer = coerce

main :: IO ()
main = relabelEnforcer `seq` pure ()
