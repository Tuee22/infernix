module Main (main) where

import DesiredApi

forgedRawRuntimeConfig :: RawRuntimeConfig
forgedRawRuntimeConfig = RawRuntimeConfig undefined

main :: IO ()
main = forgedRawRuntimeConfig `seq` pure ()
