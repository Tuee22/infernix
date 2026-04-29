{-# LANGUAGE OverloadedStrings #-}

module Infernix.Python
  ( ensurePoetryExecutable,
    ensurePoetryProjectReady,
    pythonAdaptersPresent,
    pythonProjectDirectory,
  )
where

import Control.Monad (unless)
import Data.ByteString.Lazy qualified as Lazy
import Infernix.Config (Paths (..), controlPlaneContext)
import Infernix.Types (RuntimeMode)
import Network.HTTP.Client (httpLbs, parseRequest, responseBody, responseStatus)
import Network.HTTP.Client.TLS (getGlobalManager)
import Network.HTTP.Types.Status (statusCode)
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    findExecutable,
    getHomeDirectory,
    getTemporaryDirectory,
    listDirectory,
    removeFile,
  )
import System.Environment (getEnvironment, lookupEnv, setEnv)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath (takeDirectory, (</>))
import System.IO (hClose, openTempFile)
import System.Info (os)
import System.Process (CreateProcess (cwd, env), proc, readCreateProcessWithExitCode)

poetryInstallerUrl :: String
poetryInstallerUrl = "https://install.python-poetry.org"

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
  case maybeExisting of
    Just executablePath -> do
      prependDirectoryToPath (directoryOf executablePath)
      pure executablePath
    Nothing -> do
      pythonExecutable <- requireAppleBootstrapPython
      installerScriptPath <- downloadPoetryInstaller
      (exitCode, _, stderrOutput) <-
        readCreateProcessWithExitCode
          (proc pythonExecutable [installerScriptPath, "--yes"])
          ""
      removeFile installerScriptPath
      case exitCode of
        ExitSuccess -> do
          refreshedCandidatePaths <- poetryCandidatePaths
          maybeInstalled <- firstExistingPath refreshedCandidatePaths
          case maybeInstalled of
            Just executablePath -> do
              prependDirectoryToPath (directoryOf executablePath)
              pure executablePath
            Nothing ->
              ioError
                ( userError
                    "Poetry bootstrap completed but no poetry executable was found in the expected user-local locations."
                )
        _ ->
          ioError
            ( userError
                ( "failed to bootstrap Poetry with the Apple host Python\n"
                    <> stderrOutput
                )
            )

requireAppleBootstrapPython :: IO FilePath
requireAppleBootstrapPython = do
  maybeSystemPython <- firstExistingPath ["/usr/bin/python3"]
  case maybeSystemPython of
    Just executablePath -> pure executablePath
    Nothing -> do
      maybePythonOnPath <- findOnPath "python3"
      case maybePythonOnPath of
        Just executablePath -> pure executablePath
        Nothing ->
          ioError
            ( userError
                "Apple host-native Poetry bootstrap requires the host's built-in python3 executable."
            )

downloadPoetryInstaller :: IO FilePath
downloadPoetryInstaller = do
  tempDirectory <- getTemporaryDirectory
  (installerPath, installerHandle) <- openTempFile tempDirectory "infernix-poetry-installer.py"
  hClose installerHandle
  request <- parseRequest poetryInstallerUrl
  manager <- getGlobalManager
  response <- httpLbs request manager
  if statusCode (responseStatus response) >= 400
    then do
      removeFile installerPath
      ioError
        ( userError
            ( "failed to download the Poetry installer from "
                <> poetryInstallerUrl
            )
        )
    else do
      Lazy.writeFile installerPath (responseBody response)
      pure installerPath

poetryCandidatePaths :: IO [FilePath]
poetryCandidatePaths = do
  homeDirectory <- getHomeDirectory
  maybePoetryHome <- lookupEnv "POETRY_HOME"
  pure $
    case maybePoetryHome of
      Just poetryHome ->
        [ poetryHome </> "bin" </> "poetry",
          homeDirectory </> ".local" </> "bin" </> "poetry"
        ]
      Nothing ->
        [ homeDirectory </> ".local" </> "bin" </> "poetry"
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
