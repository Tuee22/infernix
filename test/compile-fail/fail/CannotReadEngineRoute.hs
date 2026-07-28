module Main (main) where

import DesiredApi

forgedRoute :: EngineRoute
forgedRoute =
  read
    "EngineRoute { routePoolId = \"pool\", routeMemberId = \"member\", routeTopic = \"topic\", routeSubscriptionType = ConsumerShared, routeMaxInflightPerMember = 1 }"

main :: IO ()
main = forgedRoute `seq` pure ()
