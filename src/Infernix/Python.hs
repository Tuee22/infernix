{-# LANGUAGE OverloadedStrings #-}

module Infernix.Python
  ( ensurePoetryExecutable,
    ensurePoetryProjectInstalledWithGroups,
    ensurePoetryProjectReadyWithGroups,
    ensurePoetryProjectReady,
    pythonAdaptersPresent,
    pythonProjectDirectory,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (bracket_, throwIO)
import Control.Monad (unless)
import Data.Text qualified as Text
import Infernix.Config (ControlPlaneContext (HostNative), Paths (..), controlPlaneContext)
import Infernix.Error (InfernixError (..))
import Infernix.HostConfig qualified as HostConfig
import Infernix.Internal.Util (allM, findFirstM, firstJustM)
import Infernix.Types (RuntimeMode)
import System.Directory
  ( createDirectory,
    createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    findExecutable,
    listDirectory,
    removeDirectory,
  )
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.IO.Error (catchIOError, isAlreadyExistsError, isDoesNotExistError)
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
-- image). When the manifest is absent (unit-test fixture without a
-- supplied 'HostConfig'), the helper falls back to a @\$PATH@ lookup so
-- those fixtures still resolve a Poetry executable. The Apple
-- host-native one-time bootstrap path
-- ('bootstrapPoetryOnAppleHost') requires the staged manifest because
-- the install location is derived from @HostFilesystem.homeDirectory@.
-- Phase 7 Sprint 7.17 Apple cohort closure (2026-05-29) retired the
-- remaining @POETRY_HOME@ / @PATH@ env reads alongside the
-- 'Infernix.Lint.HaskellStyle.envFunctionExemptedFiles' row for this
-- module.
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
          bootstrapPoetryOnAppleHost paths
      | otherwise -> throwIO PoetryUnavailable

ensurePoetryProjectReady :: Paths -> FilePath -> IO ()
ensurePoetryProjectReady paths projectDirectory =
  ensurePoetryProjectReadyWithGroups paths projectDirectory []

ensurePoetryProjectReadyWithGroups :: Paths -> FilePath -> [String] -> IO ()
ensurePoetryProjectReadyWithGroups paths projectDirectory optionalGroups = do
  ensurePoetryProjectInstalledWithGroups paths projectDirectory optionalGroups
  ensureGeneratedPythonProto paths projectDirectory

ensurePoetryProjectInstalledWithGroups :: Paths -> FilePath -> [String] -> IO ()
ensurePoetryProjectInstalledWithGroups paths projectDirectory optionalGroups = do
  projectPresent <- doesDirectoryExist projectDirectory
  if not projectPresent
    then throwIO (PythonProjectMissing projectDirectory)
    else do
      withPoetryProjectInstallLock projectDirectory $
        runPoetryCommand
          paths
          projectDirectory
          (["install", "--directory", projectDirectory] <> optionalGroupArgs optionalGroups)
          ("failed to install poetry project " <> projectDirectory)

withPoetryProjectInstallLock :: FilePath -> IO a -> IO a
withPoetryProjectInstallLock projectDirectory =
  bracket_ acquireLock releaseLock
  where
    lockDirectory = projectDirectory </> ".infernix-poetry-install.lock"
    acquireLock = go (600 :: Int)
      where
        go remainingAttempts
          | remainingAttempts <= 0 =
              ioError (userError ("timed out waiting for Poetry project install lock: " <> lockDirectory))
          | otherwise =
              catchIOError
                (createDirectory lockDirectory)
                ( \err ->
                    if isAlreadyExistsError err
                      then do
                        threadDelay 500000
                        go (remainingAttempts - 1)
                      else ioError err
                )
    releaseLock =
      catchIOError
        (removeDirectory lockDirectory)
        ( \err ->
            unless (isDoesNotExistError err) (ioError err)
        )

optionalGroupArgs :: [String] -> [String]
optionalGroupArgs optionalGroups =
  case filter (not . null) optionalGroups of
    [] -> []
    groups -> ["--with", Text.unpack (Text.intercalate "," (map Text.pack groups))]

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

-- | Phase 7 Sprint 7.17 Apple cohort closure (2026-05-29): the Apple
-- Poetry bootstrap path now reads its install location, candidate
-- paths, and required Python executable from the typed
-- 'HostConfig.HostConfig' record carried on 'Paths', so the previous
-- @POETRY_HOME@ / @PATH@ env reads are gone. The bootstrap requires a
-- staged host manifest; the binary materializes that manifest as part
-- of its lifecycle before any adapter flow needs Poetry, so a missing
-- manifest at this point indicates a real bug rather than a
-- legitimate first-run.
bootstrapPoetryOnAppleHost :: Paths -> IO FilePath
bootstrapPoetryOnAppleHost paths =
  case pathsHostConfig paths of
    Nothing -> throwIO PoetryUnavailable
    Just hostConfig -> do
      let candidatePaths = poetryCandidatePaths hostConfig
      maybeExisting <- findFirstM doesFileExist candidatePaths
      maybe (installPoetryOnAppleHost hostConfig) pure maybeExisting

installPoetryOnAppleHost :: HostConfig.HostConfig -> IO FilePath
installPoetryOnAppleHost hostConfig = do
  pythonExecutable <- requireAppleBootstrapPython hostConfig
  let poetryHome = poetryHomeFromConfig hostConfig
      poetryVenv = poetryHome </> "venv"
      poetryExecutable = poetryVenv </> "bin" </> "poetry"
      poetryPython = poetryVenv </> "bin" </> "python"
  createDirectoryIfMissing True poetryHome
  createPoetryBootstrapVenv pythonExecutable poetryVenv
  installPoetryIntoBootstrapVenv poetryPython
  resolveInstalledPoetry hostConfig poetryExecutable

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

resolveInstalledPoetry :: HostConfig.HostConfig -> FilePath -> IO FilePath
resolveInstalledPoetry hostConfig poetryExecutable = do
  let refreshedCandidatePaths = poetryCandidatePaths hostConfig
  maybeInstalled <- findFirstM doesFileExist refreshedCandidatePaths
  case maybeInstalled of
    Just installedExecutable -> pure installedExecutable
    Nothing -> do
      installed <- doesFileExist poetryExecutable
      if installed
        then pure poetryExecutable
        else
          ioError
            ( userError
                "Poetry bootstrap completed but no poetry executable was found in the expected user-local locations."
            )

requireAppleBootstrapPython :: HostConfig.HostConfig -> IO FilePath
requireAppleBootstrapPython hostConfig = do
  let manifestPython = Text.unpack (HostConfig.hostPython3 (HostConfig.hostToolPaths hostConfig))
  manifestCompatible <-
    if null manifestPython
      then pure Nothing
      else firstCompatiblePath [manifestPython]
  case manifestCompatible of
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
                "Apple host-native Poetry bootstrap requires a compatible Python 3.12+ executable. The supported Apple host prerequisite reconciliation installs python@3.12 through Homebrew when adapter flows need it, and the staged host manifest's toolPaths.python3 must point at a compatible interpreter."
            )

poetryHomeFromConfig :: HostConfig.HostConfig -> FilePath
poetryHomeFromConfig hostConfig =
  Text.unpack (HostConfig.hostHomeDirectory (HostConfig.hostFilesystem hostConfig))
    </> ".local"
    </> "share"
    </> "pypoetry"

poetryCandidatePaths :: HostConfig.HostConfig -> [FilePath]
poetryCandidatePaths hostConfig =
  let homeDirectory = Text.unpack (HostConfig.hostHomeDirectory (HostConfig.hostFilesystem hostConfig))
      poetryHome = poetryHomeFromConfig hostConfig
   in [ poetryHome </> "bin" </> "poetry",
        poetryHome </> "venv" </> "bin" </> "poetry",
        homeDirectory </> ".local" </> "bin" </> "poetry"
      ]

pythonSupportsApplePoetryBootstrap :: FilePath -> IO Bool
pythonSupportsApplePoetryBootstrap executablePath = do
  (exitCode, _, _) <-
    readCreateProcessWithExitCode
      (proc executablePath ["-c", "import sys; raise SystemExit(0 if (3, 12) <= sys.version_info[:2] < (4, 0) else 1)"])
      ""
  pure (exitCode == ExitSuccess)

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
