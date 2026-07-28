module Main (main) where

import Data.Text (Text)
import DesiredApi

refinedLookup :: Text -> RuntimePlan -> Maybe ExecutableModel
refinedLookup = lookupExecutableModel

main :: IO ()
main = refinedLookup `seq` pure ()
