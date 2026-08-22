{-# LANGUAGE DataKinds #-}

module Main (main) where

import DesiredApi

forgedRequirement :: ModelMemoryRequirement 'HostRam
forgedRequirement = read "ModelMemoryRequirement 0"

main :: IO ()
main = forgedRequirement `seq` pure ()
