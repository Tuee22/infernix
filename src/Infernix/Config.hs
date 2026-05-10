module Infernix.Config
  ( Paths (..),
    controlPlaneContext,
    discoverPaths,
    ensureSupportedRuntimeModeForExecutionContext,
    ensureRepoLayout,
    generatedDemoConfigPath,
    generatedKubeconfigPath,
    helmEnvironment,
    publicationStatePath,
    publishedConfigMapCatalogPath,
    publishedConfigMapManifestPath,
    resolveRuntimeMode,
    watchedDemoConfigPath,
  )
where

import Data.Aeson (Value (Object, String), eitherDecodeStrict')
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteStringChar8
import Data.Text qualified as Text
import Infernix.Types (RuntimeMode (..), parseRuntimeMode, runtimeModeId)
import System.Directory (createDirectoryIfMissing, doesFileExist, doesPathExist, getCurrentDirectory)
import System.Environment (lookupEnv)
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

ensureSupportedRuntimeModeForExecutionContext :: Paths -> RuntimeMode -> IO ()
ensureSupportedRuntimeModeForExecutionContext paths runtimeMode =
  case (controlPlaneContext paths, runtimeMode) of
    ("host-native", AppleSilicon) -> pure ()
    ("host-native", _) ->
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
    ("outer-container", AppleSilicon) ->
      ioError
        ( userError
            ( unlines
                [ "Unsupported outer-container runtime mode: apple-silicon",
                  "The supported outer-container workflow stages only `linux-cpu` or `linux-gpu` under `./.build/outer-container/build/`.",
                  "Use the Apple host-native workflow for `apple-silicon`: `./bootstrap/apple-silicon.sh ...`."
                ]
            )
        )
    ("outer-container", _) -> pure ()
    _ -> pure ()

generatedKubeconfigPath :: Paths -> FilePath
generatedKubeconfigPath paths
  | controlPlaneContext paths == "outer-container" = runtimeRoot paths </> "infernix.kubeconfig"
  | otherwise = buildRoot paths </> "infernix.kubeconfig"

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

watchedDemoConfigPath :: FilePath
watchedDemoConfigPath =
  "/opt/build/infernix-substrate.dhall"

resolveRuntimeModeFromGeneratedFile :: FilePath -> IO RuntimeMode
resolveRuntimeModeFromGeneratedFile substratePath = do
  rawValue <- ByteString.readFile substratePath
  case eitherDecodeStrict' (stripGeneratedBanner rawValue) of
    Right (Object objectValue) ->
      case KeyMap.lookup (Key.fromString "runtimeMode") objectValue of
        Just (String rawRuntimeMode) ->
          case parseRuntimeMode rawRuntimeMode of
            Just runtimeMode -> pure runtimeMode
            Nothing ->
              ioError
                (userError ("Unsupported runtime mode in " <> substratePath <> ": " <> Text.unpack rawRuntimeMode))
        _ ->
          ioError
            (userError ("Generated substrate file is missing runtimeMode: " <> substratePath))
    Left message ->
      ioError
        (userError ("Invalid generated substrate file " <> substratePath <> ": " <> message))
    Right _ ->
      ioError
        (userError ("Generated substrate file is not a JSON object: " <> substratePath))

stripGeneratedBanner :: ByteString.ByteString -> ByteString.ByteString
stripGeneratedBanner rawValue =
  case dropBlankPrefix (ByteStringChar8.lines rawValue) of
    firstLine : remainingLines
      | ByteStringChar8.isPrefixOf (ByteStringChar8.pack "{-") (ByteStringChar8.strip firstLine) ->
          ByteStringChar8.unlines remainingLines
    trimmedLines -> ByteStringChar8.unlines trimmedLines
  where
    dropBlankPrefix = dropWhile (ByteString.null . ByteStringChar8.strip)

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
