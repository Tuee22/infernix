module Main (main) where

import Infernix.Cluster.Subprocess.Protocol (AnchorControl)
import System.IO (Handle)

constructAnchorControl :: Handle -> AnchorControl
constructAnchorControl =
  AnchorControl

main :: IO ()
main = pure ()
