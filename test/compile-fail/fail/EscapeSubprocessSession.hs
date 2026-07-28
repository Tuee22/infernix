{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LinearTypes #-}

module Main (main) where

import Infernix.Cluster.Subprocess.Protocol
  ( AnchorControl,
    CommandPhase (..),
    Session,
    abandonSession,
    encloseAnchorControl,
    withCommandSession,
  )
import System.IO (stdin)

anchorControl :: AnchorControl
anchorControl =
  encloseAnchorControl stdin

escapeSession ::
  IO (Session () 'AnchorReady)
escapeSession =
  withCommandSession maxBound anchorControl () $ \session ->
    abandonSession (pure session) session

main :: IO ()
main = pure ()
