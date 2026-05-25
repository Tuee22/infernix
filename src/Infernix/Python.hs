{-# LANGUAGE OverloadedStrings #-}

module Infernix.Python
  ( ensurePoetryExecutable,
    ensurePoetryProjectReady,
    pythonAdaptersPresent,
    pythonProjectDirectory,
  )
where

import Control.Exception (throwIO)
import Control.Monad (unless)
import Data.Text qualified as Text
import Infernix.Config (ControlPlaneContext (HostNative), Paths (..), controlPlaneContext)
import Infernix.Error (InfernixError (..))
import Infernix.HostConfig qualified as HostConfig
import Infernix.Internal.Util (allM, findFirstM, firstJustM)
import Infernix.Types (RuntimeMode)
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    findExecutable,
    getHomeDirectory,
    listDirectory,
  )
import System.Environment (lookupEnv, setEnv)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath (takeDirectory, (</>))
import System.Info (os)
import System.Process (CreateProcess (cwd), proc, readCreateProcessWithExitCode)

pythonProjectDirectory :: Paths -> RuntimeMode -> FilePath
pythonProjectDirectory paths _runtimeMode =
  repoRoot paths </> "python"

pythonAdaptersPresent :: FilePath -> IO Bool
pythonAdaptersPresent projectDirectory = do
  let adaptersRoot = projectDirectory </> "adapters"
  adaptersDirectoryPresent <- doesDirectoryExist adaptersRoot
  if not adaptersDirectoryPresent
    then pure False
    else not . null <$> listVisibleEntries adaptersRoot

-- | Phase 7 Sprint 7.17 — @INFERNIX_POETRY_EXECUTABLE@ env override
-- retired. The supported Poetry path comes from
-- @HostConfig.toolPaths.poetry@ (mounted via the host manifest at
-- @./.build/infernix-host.dhall@ on Apple and
-- @/opt/infernix/dhall/InfernixHost.dhall@ in the Linux launcher
-- image). When the manifest is absent (first-run bootstrap, pre-binary
-- adapter setup), the helper falls back to a @\$PATH@ lookup so the
-- one-time bootstrap can install Poetry on Apple. After the binary
-- materializes the manifest, supported flows use the typed path
-- exclusively.
ensurePoetryExecutable :: Paths -> IO FilePath
ensurePoetryExecutable paths = do
  let manifestPoetry = case pathsHostConfig paths of
        Just hostConfig ->
          let configured = HostConfig.hostPoetry (HostConfig.hostToolPaths hostConfig)
           in if Text.null configured then Nothing else Just (Text.unpack configured)
        Nothing -> Nothing
  candidate <-
    firstJustM
      [ maybe (pure Nothing) onlyIfExists manifestPoetry,
        findExecutable "poetry"
      ]
  case candidate of
    Just executablePath -> pure executablePath
    Nothing
      | os == "darwin" && controlPlaneContext paths == HostNative ->
          bootstrapPoetryOnAppleHost
      | otherwise -> throwIO PoetryUnavailable

ensurePoetryProjectReady :: Paths -> FilePath -> IO ()
ensurePoetryProjectReady paths projectDirectory = do
  projectPresent <- doesDirectoryExist projectDirectory
  if not projectPresent
    then throwIO (PythonProjectMissing projectDirectory)
    else do
      let projectVenv = projectDirectory </> ".venv"
      venvPresent <- doesDirectoryExist projectVenv
      unless venvPresent $
        runPoetryCommand
          paths
          projectDirectory
          ["install", "--directory", projectDirectory]
          ("failed to install poetry project " <> projectDirectory)
      ensureGeneratedPythonProto paths projectDirectory

ensureGeneratedPythonProto :: Paths -> FilePath -> IO ()
ensureGeneratedPythonProto paths projectDirectory = do
  let outputRoot = repoRoot paths </> "tools" </> "generated_proto"
      generatedFiles =
        [ outputRoot </> "infernix" </> "manifest" </> "runtime_manifest_pb2.py",
          outputRoot </> "infernix" </> "runtime" </> "inference_pb2.py"
        ]
  allPresent <- allM doesFileExist generatedFiles
  unless allPresent $ do
    createDirectoryIfMissing True outputRoot
    runPoetryCommand
      paths
      projectDirectory
      ( [ "--directory",
          projectDirectory,
          "run",
          "python",
          "-m",
          "grpc_tools.protoc",
          "-I",
          repoRoot paths </> "proto",
          "--python_out",
          outputRoot
        ]
          <> map
            (\relativePath -> repoRoot paths </> "proto" </> relativePath)
            [ "infernix/manifest/runtime_manifest.proto",
              "infernix/runtime/inference.proto"
            ]
      )
      "failed to generate Python protobuf stubs"
    mapM_
      ensureNamespaceInit
      [ outputRoot,
        outputRoot </> "infernix",
        outputRoot </> "infernix" </> "manifest",
        outputRoot </> "infernix" </> "runtime"
      ]

ensureNamespaceInit :: FilePath -> IO ()
ensureNamespaceInit directoryPath = do
  let initPath = directoryPath </> "__init__.py"
  initPresent <- doesFileExist initPath
  unless initPresent (writeFile initPath "")

-- | Phase 7 Sprint 7.17: @POETRY_VIRTUALENVS_IN_PROJECT@ env-set
-- retired. The new typed source is @python/poetry.toml@'s
-- @[virtualenvs] in-project = true@ entry; Poetry picks it up
-- automatically when invoked from the project directory.
runPoetryCommand :: Paths -> FilePath -> [String] -> String -> IO ()
runPoetryCommand paths projectDirectory args failurePrefix = do
  poetryExecutable <- ensurePoetryExecutable paths
  (exitCode, _, stderrOutput) <-
    readCreateProcessWithExitCode
      ((proc poetryExecutable args) {cwd = Just projectDirectory})
      ""
  case exitCode of
    ExitSuccess -> pure ()
    _ ->
      throwIO
        ProcessFailure
          { processName = failurePrefix,
            processStderr = stderrOutput,
            processCwd = Just projectDirectory
          }

bootstrapPoetryOnAppleHost :: IO FilePath
bootstrapPoetryOnAppleHost = do
  candidatePaths <- poetryCandidatePaths
  maybeExisting <- findFirstM doesFileExist candidatePaths
  maybe installPoetryOnAppleHost activatePoetryExecutable maybeExisting

installPoetryOnAppleHost :: IO FilePath
installPoetryOnAppleHost = do
  pythonExecutable <- requireAppleBootstrapPython
  poetryHome <- resolvedPoetryHome
  let poetryVenv = poetryHome </> "venv"
      poetryExecutable = poetryVenv </> "bin" </> "poetry"
      poetryPython = poetryVenv </> "bin" </> "python"
  createDirectoryIfMissing True poetryHome
  createPoetryBootstrapVenv pythonExecutable poetryVenv
  installPoetryIntoBootstrapVenv poetryPython
  resolveInstalledPoetry poetryExecutable

createPoetryBootstrapVenv :: FilePath -> FilePath -> IO ()
createPoetryBootstrapVenv pythonExecutable poetryVenv = do
  (exitCode, _, stderrOutput) <-
    readCreateProcessWithExitCode
      (proc pythonExecutable ["-m", "venv", "--clear", "--symlinks", poetryVenv])
      ""
  case exitCode of
    ExitSuccess -> pure ()
    _ ->
      throwIO
        ProcessFailure
          { processName = "failed to create the Apple host Poetry bootstrap venv with " <> pythonExecutable,
            processStderr = stderrOutput,
            processCwd = Nothing
          }

installPoetryIntoBootstrapVenv :: FilePath -> IO ()
installPoetryIntoBootstrapVenv poetryPython = do
  (exitCode, _, stderrOutput) <-
    readCreateProcessWithExitCode
      (proc poetryPython ["-m", "pip", "install", "--upgrade", "pip", "poetry"])
      ""
  case exitCode of
    ExitSuccess -> pure ()
    _ ->
      throwIO
        ProcessFailure
          { processName = "failed to install Poetry into the Apple host bootstrap venv",
            processStderr = stderrOutput,
            processCwd = Nothing
          }

resolveInstalledPoetry :: FilePath -> IO FilePath
resolveInstalledPoetry poetryExecutable = do
  refreshedCandidatePaths <- poetryCandidatePaths
  maybeInstalled <- findFirstM doesFileExist refreshedCandidatePaths
  case maybeInstalled of
    Just installedExecutable -> activatePoetryExecutable installedExecutable
    Nothing -> do
      installed <- doesFileExist poetryExecutable
      if installed
        then activatePoetryExecutable poetryExecutable
        else
          ioError
            ( userError
                "Poetry bootstrap completed but no poetry executable was found in the expected user-local locations."
            )

activatePoetryExecutable :: FilePath -> IO FilePath
activatePoetryExecutable executablePath = do
  prependDirectoryToPath (takeDirectory executablePath)
  pure executablePath

requireAppleBootstrapPython :: IO FilePath
requireAppleBootstrapPython = do
  maybeCompatibleOnPath <- firstCompatibleCommandOnPath ["python3.13", "python3.12", "python3"]
  case maybeCompatibleOnPath of
    Just executablePath -> pure executablePath
    Nothing -> do
      maybeCompatibleFallback <-
        firstCompatiblePath
          [ "/opt/homebrew/bin/python3.13",
            "/opt/homebrew/bin/python3.12",
            "/usr/bin/python3"
          ]
      case maybeCompatibleFallback of
        Just executablePath -> pure executablePath
        Nothing ->
          ioError
            ( userError
                "Apple host-native Poetry bootstrap requires a compatible Python 3.12+ executable. The supported Apple host prerequisite reconciliation installs python@3.12 through Homebrew when adapter flows need it."
            )

resolvedPoetryHome :: IO FilePath
resolvedPoetryHome = do
  homeDirectory <- getHomeDirectory
  maybePoetryHome <- lookupEnv "POETRY_HOME"
  pure $
    case maybePoetryHome of
      Just poetryHome -> poetryHome
      Nothing -> homeDirectory </> ".local" </> "share" </> "pypoetry"

poetryCandidatePaths :: IO [FilePath]
poetryCandidatePaths = do
  homeDirectory <- getHomeDirectory
  poetryHome <- resolvedPoetryHome
  pure
    [ poetryHome </> "bin" </> "poetry",
      poetryHome </> "venv" </> "bin" </> "poetry",
      homeDirectory </> ".local" </> "bin" </> "poetry"
    ]

prependDirectoryToPath :: FilePath -> IO ()
prependDirectoryToPath directoryPath = do
  maybeCurrentPath <- lookupEnv "PATH"
  let updatedPath =
        case maybeCurrentPath of
          Nothing -> directoryPath
          Just currentPath
            | null currentPath -> directoryPath
            | otherwise -> directoryPath <> ":" <> currentPath
  setEnv "PATH" updatedPath

pythonSupportsApplePoetryBootstrap :: FilePath -> IO Bool
pythonSupportsApplePoetryBootstrap executablePath = do
  (exitCode, _, _) <-
    readCreateProcessWithExitCode
      (proc executablePath ["-c", "import sys; raise SystemExit(0 if (3, 12) <= sys.version_info[:2] < (4, 0) else 1)"])
      ""
  pure (exitCode == ExitSuccess)

firstCompatibleCommandOnPath :: [FilePath] -> IO (Maybe FilePath)
firstCompatibleCommandOnPath [] = pure Nothing
firstCompatibleCommandOnPath (commandName : remainingNames) = do
  maybeExecutable <- findExecutable commandName
  case maybeExecutable of
    Just executablePath -> do
      compatible <- pythonSupportsApplePoetryBootstrap executablePath
      if compatible
        then pure (Just executablePath)
        else firstCompatibleCommandOnPath remainingNames
    Nothing -> firstCompatibleCommandOnPath remainingNames

firstCompatiblePath :: [FilePath] -> IO (Maybe FilePath)
firstCompatiblePath [] = pure Nothing
firstCompatiblePath (pathValue : remainingPaths) = do
  exists <- doesFileExist pathValue
  if not exists
    then firstCompatiblePath remainingPaths
    else do
      compatible <- pythonSupportsApplePoetryBootstrap pathValue
      if compatible
        then pure (Just pathValue)
        else firstCompatiblePath remainingPaths

listVisibleEntries :: FilePath -> IO [FilePath]
listVisibleEntries directoryPath = do
  entries <- listDirectory directoryPath
  pure [entry | entry <- entries, entry /= "." && entry /= ".."]

-- | Returns @Just path@ when the file at @path@ exists; otherwise
-- @Nothing@. Used to gracefully ignore stale or default-fixture tool
-- paths declared in the host manifest when they do not exist on the
-- current operator's host (e.g. unit-test fixtures that synthesize a
-- HostConfig with the Apple homedir default).
onlyIfExists :: FilePath -> IO (Maybe FilePath)
onlyIfExists candidate = do
  present <- doesFileExist candidate
  pure (if present then Just candidate else Nothing)
