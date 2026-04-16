module Infernix.Service
  ( runService,
  )
where

import Infernix.Config
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.Process (callProcess)
import Text.Read (readMaybe)

runService :: Maybe Int -> IO ()
runService maybePort = do
  paths <- discoverPaths
  ensureRepoLayout paths
  envPort <- lookupEnv "INFERNIX_PORT"
  edgePort <- readEdgePort paths
  let port = maybe (maybe (maybe 8080 id edgePort) read envPort) id maybePort
  callProcess
    "python3"
    [ repoRoot paths </> "tools" </> "service_server.py",
      "--repo-root",
      repoRoot paths,
      "--port",
      show port
    ]

readEdgePort :: Paths -> IO (Maybe Int)
readEdgePort paths = do
  let portFile = runtimeRoot paths <> "/edge-port.json"
  portFileExists <- doesFileExist portFile
  if portFileExists
    then do
      contents <- readFile portFile
      pure (readMaybe contents)
    else pure Nothing
