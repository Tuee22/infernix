module Main (main) where

import Infernix.DemoConfig
  ( decodeBootstrapDemoConfigFile,
    decodeDemoConfigFile,
    validateDemoConfig,
  )

main :: IO ()
main =
  decodeBootstrapDemoConfigFile `seq`
    decodeDemoConfigFile `seq`
      validateDemoConfig `seq`
        pure ()
