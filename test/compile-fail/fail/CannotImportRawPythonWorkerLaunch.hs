module Main (main) where

import Infernix.Runtime.CappedEngine (runExecutablePythonWorker)

main :: IO ()
main = runExecutablePythonWorker `seq` pure ()
