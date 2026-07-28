module Main (main) where

import Data.List.NonEmpty (NonEmpty)
import Infernix.ExecutionPlan
  ( EngineRoute,
    executableModelRoutes,
  )
import Infernix.Types (ModelDescriptor)

routesFromRawModel :: ModelDescriptor -> NonEmpty EngineRoute
routesFromRawModel = executableModelRoutes

main :: IO ()
main = routesFromRawModel `seq` pure ()
