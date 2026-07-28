module Main (main) where

import Infernix.Substrate.Internal (decodeRawRuntimeConfigFile)

main :: IO ()
main = decodeRawRuntimeConfigFile `seq` pure ()
