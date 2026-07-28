module Main (main) where

import Infernix.Cluster.Subprocess.Activity (ActivityPublication)

constructPublication :: ActivityPublication
constructPublication =
  ActivityPublication
    "/tmp"
    "/tmp/activity.lease.json"
    mempty
    Nothing
    Nothing

main :: IO ()
main = pure ()
