{-# LANGUAGE ScopedTypeVariables #-}

module Infernix.Config
  ( ControlPlaneContext (..),
    Paths (..),
    controlPlaneContext,
    controlPlaneContextId,
    parseControlPlaneContext,
    discoverPaths,
    discoverPathsWithHostManifest,
    ensureSupportedRuntimeModeForExecutionContext,
    ensureRepoLayout,
    generatedDemoConfigPath,
    generatedKubeconfigPath,
    helmEnvironment,
    publicationStatePath,
    publishedConfigMapCatalogPath,
    publishedConfigMapManifestPath,
    resolveRuntimeMode,
    targetRuntimeModeForExecutionContext,
    watchedDemoConfigPath,
  )
where

import Data.Text qualified as Text
import Infernix.HostConfig qualified as HostConfig
import Infernix.Substrate (resolveRuntimeModeFromSubstrateFile)
import Infernix.Types (RuntimeMode (..), runtimeModeId)
import System.Directory (createDirectoryIfMissing, doesFileExist, doesPathExist, getCurrentDirectory)
import System.FilePath (isAbsolute, normalise, takeDirectory, (</>))
import System.IO.Error (mkIOError, userErrorType)

data Paths = Paths
  { repoRoot :: FilePath,
    buildRoot :: FilePath,
    dataRoot :: FilePath,
    runtimeRoot :: FilePath,
    kindRoot :: FilePath,
    helmConfigRoot :: FilePath,
    helmCacheRoot :: FilePath,
    helmDataRoot :: FilePath,
    resultsRoot :: FilePath,
    modelCacheRoot :: FilePath,
    -- | Phase 2 Sprint 2.13: the staged host manifest, when present.
    -- Cluster lifecycle helpers route their external invocations
    -- through this so absolute tool paths come from
    -- @HostConfig.toolPaths.*@ instead of @\$PATH@. 'Nothing' means
    -- the manifest is absent (first-run bootstrap, unit tests
    -- without an explicit fixture) and the callers fall back to the
    -- bare-name tool resolution they used before this field landed.
    pathsHostConfig :: Maybe HostConfig.HostConfig
  }
  deriving (Eq, Show)

-- | Phase 1 Sprint 1.11 — discover the active 'Paths' by combining the
-- repo-root walk with any staged host manifest. When the manifest is
-- present (post-bootstrap), its @filesystem@ record overrides the
-- convention defaults so operators can edit the typed Dhall record
-- instead of setting process-inherited build/data-root overrides.
-- When the manifest is absent (first-run bootstrap, before the
-- binary has materialized it), the convention defaults still apply so
-- the binary remains workable enough to materialize the manifest from
-- itself.
discoverPaths :: IO Paths
discoverPaths = do
  cwd <- getCurrentDirectory
  repoRootPath <- findRepoRoot cwd
  maybeHostConfig <- tryLoadHostManifest repoRootPath
  pure (pathsFromRepoRoot repoRootPath maybeHostConfig)

-- | Variant exposed for callers that want explicit control over which
-- host manifest is consulted (e.g. test fixtures that supply a typed
-- record directly rather than reading from disk).
discoverPathsWithHostManifest :: Maybe HostConfig.HostConfig -> IO Paths
discoverPathsWithHostManifest maybeHostConfig = do
  cwd <- getCurrentDirectory
  repoRootPath <- findRepoRoot cwd
  pure (pathsFromRepoRoot repoRootPath maybeHostConfig)

pathsFromRepoRoot :: FilePath -> Maybe HostConfig.HostConfig -> Paths
pathsFromRepoRoot fallbackRepoRoot maybeHostConfig =
  let manifestFs = HostConfig.hostFilesystem <$> maybeHostConfig
      repoRootPath =
        maybe
          fallbackRepoRoot
          (resolveAgainst fallbackRepoRoot . Text.unpack . HostConfig.hostRepoRoot)
          manifestFs
      buildRootPath =
        maybe
          (repoRootPath </> ".build")
          (resolveAgainst repoRootPath . Text.unpack . HostConfig.hostBuildRoot)
          manifestFs
      dataRootPath =
        maybe
          (repoRootPath </> ".data")
          (resolveAgainst repoRootPath . Text.unpack . HostConfig.hostDataRoot)
          manifestFs
      runtimeRootPath =
        maybe
          (dataRootPath </> "runtime")
          (resolveAgainst repoRootPath . Text.unpack . HostConfig.hostRuntimeRoot)
          manifestFs
      kindRootPath =
        maybe
          (dataRootPath </> "kind")
          (resolveAgainst repoRootPath . Text.unpack . HostConfig.hostKindRoot)
          manifestFs
      helmConfigRootPath = dataRootPath </> "helm" </> "config"
      helmCacheRootPath = dataRootPath </> "helm" </> "cache"
      helmDataRootPath = dataRootPath </> "helm" </> "data"
      resultsRootPath = runtimeRootPath </> "results"
      modelCacheRootPath = runtimeRootPath </> "model-cache"
   in Paths
        { repoRoot = repoRootPath,
          buildRoot = buildRootPath,
          dataRoot = dataRootPath,
          runtimeRoot = runtimeRootPath,
          kindRoot = kindRootPath,
          helmConfigRoot = helmConfigRootPath,
          helmCacheRoot = helmCacheRootPath,
          helmDataRoot = helmDataRootPath,
          resultsRoot = resultsRootPath,
          modelCacheRoot = modelCacheRootPath,
          pathsHostConfig = maybeHostConfig
        }

resolveAgainst :: FilePath -> FilePath -> FilePath
resolveAgainst anchor candidate
  | isAbsolute candidate = candidate
  | otherwise = anchor </> candidate

-- | Try the supported staging locations for the host manifest in
-- preference order: Apple host-native build root, Linux outer-container
-- bind-mount build root (legacy compose layout retained until Sprint
-- 1.11's compose shrink lands), and the Linux launcher image's baked
-- default. Returns @Nothing@ if no candidate exists; the caller falls
-- back to convention defaults so first-run bootstrap remains workable.
-- If a candidate exists but is invalid, fail immediately: silently
-- falling through to convention defaults can misclassify the execution
-- context and route Linux launcher work through host-native guardrails.
tryLoadHostManifest :: FilePath -> IO (Maybe HostConfig.HostConfig)
tryLoadHostManifest repoRootPath = loop candidatePaths
  where
    candidatePaths =
      [ repoRootPath </> ".build" </> "infernix-host.dhall",
        repoRootPath </> ".build" </> "outer-container" </> "build" </> "infernix-host.dhall",
        "/opt/infernix/dhall/InfernixHost.dhall"
      ]
    loop [] = pure Nothing
    loop (candidate : rest) = do
      exists <- doesFileExist candidate
      if exists
        then Just <$> HostConfig.decodeHostConfigFile candidate
        else loop rest

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
      resultsRoot paths,
      modelCacheRoot paths
    ]

data ControlPlaneContext
  = HostNative
  | OuterContainer
  deriving (Eq, Ord, Read, Show)

controlPlaneContextId :: ControlPlaneContext -> String
controlPlaneContextId HostNative = "host-native"
controlPlaneContextId OuterContainer = "outer-container"

parseControlPlaneContext :: String -> Maybe ControlPlaneContext
parseControlPlaneContext "host-native" = Just HostNative
parseControlPlaneContext "outer-container" = Just OuterContainer
parseControlPlaneContext _ = Nothing

controlPlaneContext :: Paths -> ControlPlaneContext
controlPlaneContext paths
  | normalise (buildRoot paths) == normalise (repoRoot paths </> ".build") = HostNative
  | otherwise = OuterContainer

ensureSupportedRuntimeModeForExecutionContext :: Paths -> RuntimeMode -> IO ()
ensureSupportedRuntimeModeForExecutionContext paths runtimeMode =
  case (controlPlaneContext paths, runtimeMode) of
    (HostNative, AppleSilicon) -> pure ()
    (HostNative, _) ->
      ioError
        ( userError
            ( unlines
                [ "Unsupported host-native runtime mode: " <> Text.unpack (runtimeModeId runtimeMode),
                  "The supported host-native control-plane workflow stages only `apple-silicon` under `./.build/`.",
                  "Use the Linux outer-container workflow for `linux-cpu` and `linux-gpu`:"
                    <> " `./bootstrap/linux-cpu.sh ...` or `./bootstrap/linux-gpu.sh ...`."
                ]
            )
        )
    (OuterContainer, AppleSilicon) ->
      ioError
        ( userError
            ( unlines
                [ "Unsupported outer-container runtime mode: apple-silicon",
                  "The supported outer-container workflow stages only `linux-cpu` or `linux-gpu` under `./.build/outer-container/build/`.",
                  "Use the Apple host-native workflow for `apple-silicon`: `./bootstrap/apple-silicon.sh ...`."
                ]
            )
        )
    (OuterContainer, _) -> pure ()

generatedKubeconfigPath :: Paths -> FilePath
generatedKubeconfigPath paths = case controlPlaneContext paths of
  OuterContainer -> runtimeRoot paths </> "infernix.kubeconfig"
  HostNative -> buildRoot paths </> "infernix.kubeconfig"

generatedDemoConfigPath :: Paths -> FilePath
generatedDemoConfigPath = generatedSubstratePath

generatedSubstratePath :: Paths -> FilePath
generatedSubstratePath paths =
  buildRoot paths </> "infernix-substrate.dhall"

publishedConfigMapCatalogPath :: Paths -> FilePath
publishedConfigMapCatalogPath paths =
  runtimeRoot paths
    </> "configmaps"
    </> "infernix-demo-config"
    </> "infernix-substrate.dhall"

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

resolveRuntimeMode :: Maybe RuntimeMode -> IO RuntimeMode
resolveRuntimeMode (Just runtimeMode) = pure runtimeMode
resolveRuntimeMode Nothing = do
  paths <- discoverPaths
  let substratePath = generatedDemoConfigPath paths
  substrateExists <- doesFileExist substratePath
  if substrateExists
    then resolveRuntimeModeFromGeneratedFile substratePath
    else ioError (missingGeneratedSubstrateFileError substratePath)

-- | Phase 1 Sprint 1.11 — return the substrate the current launcher
-- targets without consulting any environment variable. The supported
-- contract is:
--
-- * Host-native (Apple) → 'AppleSilicon'. Apple lifecycle commands
--   materialize @./.build/infernix-substrate.dhall@ from the bootstrap
--   script before reaching this code path, so callers that need the
--   substrate identity for subsequent work read the staged file
--   directly via 'resolveRuntimeMode'.
-- * Outer-container (Linux) → read the substrate from the staged
--   @infernix-substrate.dhall@ baked into the launcher image (the image
--   build runs @infernix internal materialize-substrate@ as part of the
--   Dockerfile). When the file is absent (first-run bootstrap before
--   the binary has staged anything), the caller surfaces a typed
--   diagnostic.
targetRuntimeModeForExecutionContext :: Paths -> IO RuntimeMode
targetRuntimeModeForExecutionContext paths =
  case controlPlaneContext paths of
    HostNative -> pure AppleSilicon
    OuterContainer -> do
      let substratePath = generatedDemoConfigPath paths
      substrateExists <- doesFileExist substratePath
      if substrateExists
        then resolveRuntimeModeFromGeneratedFile substratePath
        else ioError (missingGeneratedSubstrateFileError substratePath)

watchedDemoConfigPath :: FilePath
watchedDemoConfigPath =
  "/opt/build/infernix-substrate.dhall"

resolveRuntimeModeFromGeneratedFile :: FilePath -> IO RuntimeMode
resolveRuntimeModeFromGeneratedFile = resolveRuntimeModeFromSubstrateFile

missingGeneratedSubstrateFileError :: FilePath -> IOError
missingGeneratedSubstrateFileError substratePath =
  mkIOError
    userErrorType
    ( unlines
        [ "Missing generated substrate file: " <> substratePath,
          "Build or restage the active substrate before running supported infernix commands.",
          "Examples:",
          "  cabal install --installdir=./.build --install-method=copy --overwrite-policy=always exe:infernix exe:infernix-demo",
          "  infernix internal materialize-substrate apple-silicon",
          "  docker compose run --rm infernix infernix internal materialize-substrate <runtime-mode> --demo-ui true"
        ]
    )
    Nothing
    Nothing
