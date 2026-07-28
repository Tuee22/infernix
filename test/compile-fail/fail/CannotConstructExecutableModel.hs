module Main (main) where

import DesiredApi

forgedExecutableModel :: ExecutableModel
forgedExecutableModel = ExecutableModel

main :: IO ()
main = forgedExecutableModel `seq` pure ()
