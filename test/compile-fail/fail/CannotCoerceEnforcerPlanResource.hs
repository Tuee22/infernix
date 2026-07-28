{-# LANGUAGE DataKinds #-}

module Main (main) where

import Data.Coerce (coerce)
import DesiredApi

relabelEnforcerPlan :: EnforcerPlan 'HostRam -> EnforcerPlan 'PodRam
relabelEnforcerPlan = coerce

main :: IO ()
main = relabelEnforcerPlan `seq` pure ()
