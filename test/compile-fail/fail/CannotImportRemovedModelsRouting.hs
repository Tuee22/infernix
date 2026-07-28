module Main (main) where

import Infernix.Models (enginePoolTopicForMode)

main :: IO ()
main = enginePoolTopicForMode `seq` pure ()
