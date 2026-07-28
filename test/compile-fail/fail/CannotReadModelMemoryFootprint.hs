module Main (main) where

import DesiredApi

forgedFootprint :: ModelMemoryFootprint
forgedFootprint = read "ModelMemoryFootprint 0"

main :: IO ()
main = forgedFootprint `seq` pure ()
