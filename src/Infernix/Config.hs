module Infernix.Config
  ( Paths (..),
    discoverPaths,
    ensureRepoLayout,
    generatedKubeconfigPath,
    generatedTestConfigPath,
  )
where

import System.Directory (createDirectoryIfMissing, doesPathExist, getCurrentDirectory)
import System.Environment (lookupEnv)
import System.FilePath (isAbsolute, takeDirectory, (</>))

data Paths = Paths
  { repoRoot :: FilePath,
    buildRoot :: FilePath,
    dataRoot :: FilePath,
    runtimeRoot :: FilePath,
    kindRoot :: FilePath,
    objectStoreRoot :: FilePath,
    resultsRoot :: FilePath,
    modelCacheRoot :: FilePath
  }
  deriving (Eq, Show)

discoverPaths :: IO Paths
discoverPaths = do
  cwd <- getCurrentDirectory
  repoRootPath <- findRepoRoot cwd
  buildRootEnv <- lookupEnv "INFERNIX_BUILD_ROOT"
  let buildRootPath = maybe (repoRootPath </> ".build") (makeRooted repoRootPath) buildRootEnv
      dataRootPath = repoRootPath </> ".data"
      runtimeRootPath = dataRootPath </> "runtime"
      kindRootPath = dataRootPath </> "kind"
      objectStoreRootPath = dataRootPath </> "object-store"
      resultsRootPath = runtimeRootPath </> "results"
      modelCacheRootPath = runtimeRootPath </> "model-cache"
  pure
    Paths
      { repoRoot = repoRootPath,
        buildRoot = buildRootPath,
        dataRoot = dataRootPath,
        runtimeRoot = runtimeRootPath,
        kindRoot = kindRootPath,
        objectStoreRoot = objectStoreRootPath,
        resultsRoot = resultsRootPath,
        modelCacheRoot = modelCacheRootPath
      }
  where
    makeRooted cwd value
      | isAbsolute value = value
      | otherwise = cwd </> value

findRepoRoot :: FilePath -> IO FilePath
findRepoRoot start = go start
  where
    go current = do
      hasPlan <- doesPathExist (current </> "DEVELOPMENT_PLAN" </> "README.md")
      hasGit <- doesPathExist (current </> ".git")
      if hasPlan || hasGit
        then pure current
        else
          let parent = takeDirectory current
           in if parent == current
                then pure start
                else go parent

ensureRepoLayout :: Paths -> IO ()
ensureRepoLayout paths =
  mapM_
    (createDirectoryIfMissing True)
    [ buildRoot paths,
      dataRoot paths,
      runtimeRoot paths,
      kindRoot paths,
      objectStoreRoot paths,
      resultsRoot paths,
      modelCacheRoot paths
    ]

generatedKubeconfigPath :: Paths -> FilePath
generatedKubeconfigPath paths = buildRoot paths </> "infernix.kubeconfig"

generatedTestConfigPath :: Paths -> FilePath
generatedTestConfigPath paths = buildRoot paths </> "infernix-test-config.dhall"
