module Infernix.Config
  ( Paths (..),
    controlPlaneContext,
    discoverPaths,
    ensureRepoLayout,
    generatedDemoConfigPath,
    generatedKubeconfigPath,
    helmEnvironment,
    publicationStatePath,
    publishedConfigMapCatalogPath,
    publishedConfigMapManifestPath,
    resolveCabalBuildDir,
    resolveRuntimeMode,
    watchedDemoConfigPath,
  )
where

import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Infernix.Types (RuntimeMode (..), parseRuntimeMode, runtimeModeId)
import System.Directory (createDirectoryIfMissing, doesPathExist, getCurrentDirectory)
import System.Environment (lookupEnv)
import System.FilePath (isAbsolute, normalise, takeDirectory, (</>))
import System.Info (os)

data Paths = Paths
  { repoRoot :: FilePath,
    buildRoot :: FilePath,
    dataRoot :: FilePath,
    runtimeRoot :: FilePath,
    kindRoot :: FilePath,
    helmConfigRoot :: FilePath,
    helmCacheRoot :: FilePath,
    helmDataRoot :: FilePath,
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
  dataRootEnv <- lookupEnv "INFERNIX_DATA_ROOT"
  let buildRootPath = maybe (repoRootPath </> ".build") (makeRooted repoRootPath) buildRootEnv
      dataRootPath = maybe (repoRootPath </> ".data") (makeRooted repoRootPath) dataRootEnv
      runtimeRootPath = dataRootPath </> "runtime"
      kindRootPath = dataRootPath </> "kind"
      helmConfigRootPath = dataRootPath </> "helm" </> "config"
      helmCacheRootPath = dataRootPath </> "helm" </> "cache"
      helmDataRootPath = dataRootPath </> "helm" </> "data"
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
        helmConfigRoot = helmConfigRootPath,
        helmCacheRoot = helmCacheRootPath,
        helmDataRoot = helmDataRootPath,
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
      helmConfigRoot paths,
      helmCacheRoot paths,
      helmDataRoot paths,
      objectStoreRoot paths,
      resultsRoot paths,
      modelCacheRoot paths
    ]

controlPlaneContext :: Paths -> String
controlPlaneContext paths
  | normalise (buildRoot paths) == normalise (repoRoot paths </> ".build") = "host-native"
  | otherwise = "outer-container"

generatedKubeconfigPath :: Paths -> FilePath
generatedKubeconfigPath paths
  | controlPlaneContext paths == "outer-container" = runtimeRoot paths </> "infernix.kubeconfig"
  | otherwise = buildRoot paths </> "infernix.kubeconfig"

generatedDemoConfigPath :: Paths -> RuntimeMode -> FilePath
generatedDemoConfigPath paths runtimeMode =
  buildRoot paths </> ("infernix-demo-" <> modeSuffix <> ".dhall")
  where
    modeSuffix = Text.unpack (runtimeModeId runtimeMode)

publishedConfigMapCatalogPath :: Paths -> RuntimeMode -> FilePath
publishedConfigMapCatalogPath paths runtimeMode =
  runtimeRoot paths
    </> "configmaps"
    </> "infernix-demo-config"
    </> ("infernix-demo-" <> modeSuffix <> ".dhall")
  where
    modeSuffix = Text.unpack (runtimeModeId runtimeMode)

publishedConfigMapManifestPath :: Paths -> FilePath
publishedConfigMapManifestPath paths =
  runtimeRoot paths </> "configmaps" </> "infernix-demo-config" </> "configmap.yaml"

publicationStatePath :: Paths -> FilePath
publicationStatePath paths = runtimeRoot paths </> "publication.json"

helmEnvironment :: Paths -> [(String, String)]
helmEnvironment paths =
  [ ("HELM_CONFIG_HOME", helmConfigRoot paths),
    ("HELM_CACHE_HOME", helmCacheRoot paths),
    ("HELM_DATA_HOME", helmDataRoot paths)
  ]

resolveCabalBuildDir :: IO FilePath
resolveCabalBuildDir = do
  maybeValue <- lookupEnv "INFERNIX_CABAL_BUILDDIR"
  pure (fromMaybe ".build/cabal" maybeValue)

resolveRuntimeMode :: Maybe RuntimeMode -> IO RuntimeMode
resolveRuntimeMode (Just runtimeMode) = pure runtimeMode
resolveRuntimeMode Nothing = do
  maybeEnvValue <- lookupEnv "INFERNIX_RUNTIME_MODE"
  case maybeEnvValue of
    Just value ->
      case parseRuntimeMode (Text.pack value) of
        Just runtimeMode -> pure runtimeMode
        Nothing ->
          ioError
            (userError ("Unsupported runtime mode: " <> value))
    Nothing -> pure defaultRuntimeMode

watchedDemoConfigPath :: RuntimeMode -> FilePath
watchedDemoConfigPath runtimeMode =
  "/opt/build/infernix-demo-" <> modeSuffix <> ".dhall"
  where
    modeSuffix = Text.unpack (runtimeModeId runtimeMode)

defaultRuntimeMode :: RuntimeMode
defaultRuntimeMode
  | os == "darwin" = AppleSilicon
  | otherwise = LinuxCpu
