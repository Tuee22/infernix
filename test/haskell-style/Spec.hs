module Main (main) where

import Infernix.Lint.HaskellStyle (runHaskellStyleLint)

main :: IO ()
main = runHaskellStyleLint
