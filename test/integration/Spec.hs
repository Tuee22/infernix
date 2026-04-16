module Main (main) where

import Infernix.Cluster
import Infernix.Config
import System.Directory
import System.IO.Error (catchIOError, isDoesNotExistError)

main :: IO ()
main = withTestRoot ".tmp/integration" $ do
  clusterUp
  paths <- discoverPaths
  kubeconfigExists <- doesFileExist (generatedKubeconfigPath paths)
  dhallExists <- doesFileExist (generatedTestConfigPath paths)
  stateExists <- fmap maybeFalse (loadClusterState paths)
  assert kubeconfigExists "cluster up creates a repo-local kubeconfig"
  assert dhallExists "cluster up creates the generated test config"
  assert stateExists "cluster up persists cluster state"
  clusterDown
  putStrLn "integration tests passed"
  where
    maybeFalse maybeState = maybe False (not . null . show) maybeState

withTestRoot :: FilePath -> IO a -> IO a
withTestRoot root action = do
  catchIOError (removePathForcibly root) ignoreMissing
  createDirectoryIfMissing True root
  withCurrentDirectory root action
  where
    ignoreMissing err
      | isDoesNotExistError err = pure ()
      | otherwise = ioError err

assert :: Bool -> String -> IO ()
assert True _ = pure ()
assert False message = fail message
