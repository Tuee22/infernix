module Main (main) where

import Infernix.Runtime.Pulsar
  ( serviceConsumerSubscriptionTypeForTopic,
    startupTopicsForDemoConfig,
  )

main :: IO ()
main =
  serviceConsumerSubscriptionTypeForTopic `seq`
    startupTopicsForDemoConfig `seq`
      pure ()
