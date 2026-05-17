{-# LANGUAGE OverloadedStrings #-}

module Infernix.Python
  ( ensurePoetryExecutable,
    ensurePoetryProjectReady,
    pythonAdaptersPresent,
    pythonProjectDirectory,
  )
where

import Control.Monad (unless)
import Infernix.Config (Paths (..), controlPlaneContext)
import Infernix.Types (RuntimeMode)
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    findExecutable,
    getHomeDirectory,
    listDirectory,
  )
import System.Environment (getEnvironment, lookupEnv, setEnv)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath (takeDirectory, (</>))
import System.Info (os)
import System.Process (CreateProcess (cwd, env), proc, readCreateProcessWithExitCode)

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

ensurePoetryExecutable :: Paths -> IO FilePath
ensurePoetryExecutable paths = do
  maybeOverride <- lookupEnv "INFERNIX_POETRY_EXECUTABLE"
  case maybeOverride of
    Just executablePath -> pure executablePath
    Nothing -> do
      maybePathExecutable <- findOnPath "poetry"
      case maybePathExecutable of
        Just executablePath -> pure executablePath
        Nothing ->
          if os == "darwin" && controlPlaneContext paths == "host-native"
            then bootstrapPoetryOnAppleHost
            else
              ioError
                ( userError
                    "poetry is not available on PATH. The supported non-Apple paths provide Poetry inside the shared Linux substrate images."
                )

ensurePoetryProjectReady :: Paths -> FilePath -> IO ()
ensurePoetryProjectReady paths projectDirectory = do
  projectPresent <- doesDirectoryExist projectDirectory
  if not projectPresent
    then ioError (userError ("python substrate project is missing: " <> projectDirectory))
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
        [ outputRoot </> "infernix" </> "api" </> "inference_service_pb2.py",
          outputRoot </> "infernix" </> "manifest" </> "runtime_manifest_pb2.py",
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
            [ "infernix/api/inference_service.proto",
              "infernix/manifest/runtime_manifest.proto",
              "infernix/runtime/inference.proto"
            ]
      )
      "failed to generate Python protobuf stubs"
    mapM_
      ensureNamespaceInit
      [ outputRoot,
        outputRoot </> "infernix",
        outputRoot </> "infernix" </> "api",
        outputRoot </> "infernix" </> "manifest",
        outputRoot </> "infernix" </> "runtime"
      ]

ensureNamespaceInit :: FilePath -> IO ()
ensureNamespaceInit directoryPath = do
  let initPath = directoryPath </> "__init__.py"
  initPresent <- doesFileExist initPath
  unless initPresent (writeFile initPath "")

runPoetryCommand :: Paths -> FilePath -> [String] -> String -> IO ()
runPoetryCommand paths projectDirectory args failurePrefix = do
  poetryExecutable <- ensurePoetryExecutable paths
  baseEnvironment <- getEnvironment
  (exitCode, _, stderrOutput) <-
    readCreateProcessWithExitCode
      ( (proc poetryExecutable args)
          { cwd = Just projectDirectory,
            env =
              Just
                ( ("POETRY_VIRTUALENVS_IN_PROJECT", "true")
                    : filter ((/= "POETRY_VIRTUALENVS_IN_PROJECT") . fst) baseEnvironment
                )
          }
      )
      ""
  case exitCode of
    ExitSuccess -> pure ()
    _ ->
      ioError
        ( userError
            ( failurePrefix
                <> "\nproject: "
                <> projectDirectory
                <> "\n"
                <> stderrOutput
            )
        )

bootstrapPoetryOnAppleHost :: IO FilePath
bootstrapPoetryOnAppleHost = do
  candidatePaths <- poetryCandidatePaths
  maybeExisting <- firstExistingPath candidatePaths
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
      ioError
        ( userError
            ( "failed to create the Apple host Poetry bootstrap venv with "
                <> pythonExecutable
                <> "\n"
                <> stderrOutput
            )
        )

installPoetryIntoBootstrapVenv :: FilePath -> IO ()
installPoetryIntoBootstrapVenv poetryPython = do
  (exitCode, _, stderrOutput) <-
    readCreateProcessWithExitCode
      (proc poetryPython ["-m", "pip", "install", "--upgrade", "pip", "poetry"])
      ""
  case exitCode of
    ExitSuccess -> pure ()
    _ ->
      ioError
        ( userError
            ( "failed to install Poetry into the Apple host bootstrap venv\n"
                <> stderrOutput
            )
        )

resolveInstalledPoetry :: FilePath -> IO FilePath
resolveInstalledPoetry poetryExecutable = do
  refreshedCandidatePaths <- poetryCandidatePaths
  maybeInstalled <- firstExistingPath refreshedCandidatePaths
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
  prependDirectoryToPath (directoryOf executablePath)
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

findOnPath :: FilePath -> IO (Maybe FilePath)
findOnPath = findExecutable

directoryOf :: FilePath -> FilePath
directoryOf = takeDirectory

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
  maybeExecutable <- findOnPath commandName
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

firstExistingPath :: [FilePath] -> IO (Maybe FilePath)
firstExistingPath [] = pure Nothing
firstExistingPath (pathValue : remainingPaths) = do
  exists <- doesFileExist pathValue
  if exists
    then pure (Just pathValue)
    else firstExistingPath remainingPaths

allM :: (a -> IO Bool) -> [a] -> IO Bool
allM predicate = go
  where
    go [] = pure True
    go (value : rest) = do
      matches <- predicate value
      if matches
        then go rest
        else pure False

listVisibleEntries :: FilePath -> IO [FilePath]
listVisibleEntries directoryPath = do
  entries <- listDirectory directoryPath
  pure [entry | entry <- entries, entry /= "." && entry /= ".."]
