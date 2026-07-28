module Main (main) where

import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Infernix.ExecutionPlan
  ( CompiledRuntimePlan,
    compiledPlacementRoutes,
    engineRouteTopic,
    lookupCompiledPlacement,
  )

compiledRouteTopic :: Text -> CompiledRuntimePlan -> Maybe Text
compiledRouteTopic modelIdValue compiledPlan =
  engineRouteTopic . NonEmpty.head . compiledPlacementRoutes
    <$> lookupCompiledPlacement modelIdValue compiledPlan

main :: IO ()
main = compiledRouteTopic `seq` pure ()
