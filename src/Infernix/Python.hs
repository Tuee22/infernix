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

import Control.Exception (throwIO)
import Data.Text qualified as Text
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.Config (ControlPlaneContext (HostNative), Paths (..), controlPlaneContext)
import Infernix.Engines.Provisioning qualified as Provisioning
import Infernix.Error (InfernixError (..))
import Infernix.HostConfig qualified as HostConfig
import Infernix.HostTools qualified as HostTools
import Infernix.Internal.Util (findFirstM)
import Infernix.Types (RuntimeMode)
import System.Directory
  ( doesDirectoryExist,
    doesFileExist,
    listDirectory,
  )
import System.FilePath ((</>))
import System.Info (os)

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
-- @./infernix-host.dhall@ on Apple and
-- @/opt/infernix/dhall/InfernixHost.dhall@ in the Linux launcher
-- image). When the manifest is absent (unit-test fixture without a
-- supplied 'HostConfig'), the helper checks only fixed absolute
-- fallback candidates from 'HostTools.hostToolFallbackCandidates'. The Apple
-- host-native one-time bootstrap path
-- ('bootstrapPoetryOnAppleHost') requires the initialized manifest because
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
  case manifestPoetry of
    Just configuredPath -> do
      configuredPresent <- doesFileExist configuredPath
      if configuredPresent
        then pure configuredPath
        else case pathsHostConfig paths of
          Just hostConfig
            | os == "darwin"
                && controlPlaneContext paths == HostNative
                && configuredPath
                  == poetryHomeFromConfig hostConfig
                    </> "venv"
                    </> "bin"
                    </> "poetry" ->
                bootstrapPoetryOnAppleHost paths
          _ -> throwIO PoetryUnavailable
    Nothing -> do
      candidate <-
        findFirstM doesFileExist (HostTools.hostToolFallbackCandidates HostTools.HostPoetry)
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
ensurePoetryProjectReadyWithGroups paths projectDirectory optionalGroups =
  runPythonProjectProvisioning
    paths
    projectDirectory
    optionalGroups
    True

ensurePoetryProjectInstalledWithGroups :: Paths -> FilePath -> [String] -> IO ()
ensurePoetryProjectInstalledWithGroups paths projectDirectory optionalGroups =
  runPythonProjectProvisioning
    paths
    projectDirectory
    optionalGroups
    False

runPythonProjectProvisioning ::
  Paths ->
  FilePath ->
  [String] ->
  Bool ->
  IO ()
runPythonProjectProvisioning
  paths
  projectDirectory
  requestedGroups
  generateProto = do
    projectPresent <- doesDirectoryExist projectDirectory
    if not projectPresent
      then throwIO (PythonProjectMissing projectDirectory)
      else do
        _ <- ensurePoetryExecutable paths
        groups <-
          mapM
            ( \group ->
                maybe
                  ( throwIO
                      ProcessFailure
                        { processName = "reject unsupported Poetry install group",
                          processStderr = group,
                          processCwd = Just projectDirectory
                        }
                  )
                  pure
                  (Provisioning.parsePoetryInstallGroup group)
            )
            (filter (not . null) requestedGroups)
        environment <- Subprocess.clusterSubprocessEnv paths
        result <-
          Provisioning.withPythonProvisioningSession
            (repoRoot paths)
            projectDirectory
            environment
            ( \projectWriter bindingsWriter grant -> do
                projectReady <-
                  Provisioning.provisioningPoetryProjectReady projectWriter
                if not projectReady
                  then pure (Left "locked Python project root is incomplete")
                  else do
                    poetryResult <- Provisioning.resolvePoetry grant
                    case poetryResult of
                      Left failure -> pure (Left failure)
                      Right poetry -> do
                        installOutcome <-
                          Provisioning.installPoetryProjectWithGroups
                            projectWriter
                            grant
                            poetryInstallDeadline
                            poetry
                            groups
                        case provisioningFailure installOutcome of
                          Just failure -> pure (Left failure)
                          Nothing
                            | not generateProto -> pure (Right ())
                            | otherwise -> do
                                projectPythonResult <-
                                  Provisioning.resolveProjectPython projectWriter
                                case projectPythonResult of
                                  Left failure -> pure (Left failure)
                                  Right projectPython -> do
                                    required <-
                                      Provisioning.provisioningGeneratedBindingsRequired
                                        bindingsWriter
                                    if not required
                                      then pure (Right ())
                                      else do
                                        Provisioning.provisioningCreateGeneratedBindingNamespaces
                                          bindingsWriter
                                        generationOutcome <-
                                          Provisioning.generatePythonProtoBindings
                                            projectWriter
                                            bindingsWriter
                                            grant
                                            protoGenerationDeadline
                                            projectPython
                                        pure
                                          ( maybe
                                              (Right ())
                                              Left
                                              (provisioningFailure generationOutcome)
                                          )
            )
        case result of
          Right () -> pure ()
          Left failure ->
            throwIO
              ProcessFailure
                { processName = "bounded Python project provisioning failed",
                  processStderr = failure,
                  processCwd = Just projectDirectory
                }

provisioningFailure :: Provisioning.ProvisioningOutcome -> Maybe String
provisioningFailure outcome =
  case outcome of
    Provisioning.ProvisioningSucceeded _ -> Nothing
    Provisioning.ProvisioningRejected failure ->
      Just ("rejected: " <> failure)
    Provisioning.ProvisioningFailedFatal failure ->
      Just ("target failure: " <> failure)
    Provisioning.ProvisioningFailedKernel failure ->
      Just ("kernel failure: " <> failure)
    Provisioning.ProvisioningTimedOut deadline ->
      Just
        ( "timed out after "
            <> show (Provisioning.provisioningDeadlineMicros deadline)
            <> " microseconds"
        )

poetryInstallDeadline :: Provisioning.ProvisioningDeadline
poetryInstallDeadline =
  requiredDeadline "Poetry install deadline" (30 * 60 * 1000 * 1000)

protoGenerationDeadline :: Provisioning.ProvisioningDeadline
protoGenerationDeadline =
  requiredDeadline "protobuf generation deadline" (5 * 60 * 1000 * 1000)

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
    Just hostConfig ->
      installPoetryOnAppleHost paths hostConfig

installPoetryOnAppleHost :: Paths -> HostConfig.HostConfig -> IO FilePath
installPoetryOnAppleHost paths hostConfig = do
  let poetryHome = poetryHomeFromConfig hostConfig
      poetryExecutable = poetryHome </> "venv" </> "bin" </> "poetry"
      homeDirectory =
        Text.unpack
          (HostConfig.hostHomeDirectory (HostConfig.hostFilesystem hostConfig))
  environment <- Subprocess.clusterSubprocessEnv paths
  result <-
    Provisioning.withPoetryBootstrapProvisioningSession
      homeDirectory
      environment
      ( \writer grant -> do
          pythonResult <-
            Provisioning.resolvePython
              grant
              Provisioning.ctranslate2PythonAdapter
          case pythonResult of
            Left failure -> pure (Left failure)
            Right python -> do
              probeOutcome <-
                Provisioning.probePoetryBootstrapPython
                  writer
                  grant
                  poetryBootstrapProbeDeadline
                  python
              case provisioningFailure probeOutcome of
                Just failure -> pure (Left failure)
                Nothing -> do
                  venvOutcome <-
                    Provisioning.createPoetryBootstrapVenv
                      writer
                      grant
                      poetryBootstrapVenvDeadline
                      python
                  case provisioningFailure venvOutcome of
                    Just failure -> pure (Left failure)
                    Nothing -> do
                      bootstrapPython <-
                        Provisioning.materializePoetryBootstrapPython
                          writer
                          python
                      installOutcome <-
                        Provisioning.installPinnedPoetryBootstrap
                          writer
                          grant
                          poetryBootstrapInstallDeadline
                          bootstrapPython
                      case provisioningFailure installOutcome of
                        Just failure -> pure (Left failure)
                        Nothing -> do
                          installed <-
                            Provisioning.provisioningPoetryBootstrapExecutable
                              writer
                          pure
                            ( maybe
                                (Left "pinned Poetry executable was not published exactly")
                                Right
                                installed
                            )
      )
  case result of
    Left failure ->
      throwIO
        ProcessFailure
          { processName = "bounded Apple Poetry bootstrap failed",
            processStderr = failure,
            processCwd = Just poetryHome
          }
    Right installedExecutable
      | installedExecutable == poetryExecutable ->
          pure installedExecutable
      | otherwise ->
          throwIO
            ProcessFailure
              { processName = "bounded Apple Poetry bootstrap returned another path",
                processStderr = installedExecutable,
                processCwd = Just poetryHome
              }

poetryBootstrapProbeDeadline :: Provisioning.ProvisioningDeadline
poetryBootstrapProbeDeadline =
  requiredDeadline "Poetry bootstrap Python probe deadline" (30 * 1000 * 1000)

poetryBootstrapVenvDeadline :: Provisioning.ProvisioningDeadline
poetryBootstrapVenvDeadline =
  requiredDeadline "Poetry bootstrap venv deadline" (5 * 60 * 1000 * 1000)

poetryBootstrapInstallDeadline :: Provisioning.ProvisioningDeadline
poetryBootstrapInstallDeadline =
  requiredDeadline "Poetry bootstrap install deadline" (15 * 60 * 1000 * 1000)

requiredDeadline :: String -> Int -> Provisioning.ProvisioningDeadline
requiredDeadline label microseconds =
  either
    (error . ((label <> ": ") <>))
    id
    (Provisioning.mkProvisioningDeadline microseconds)

poetryHomeFromConfig :: HostConfig.HostConfig -> FilePath
poetryHomeFromConfig hostConfig =
  Text.unpack (HostConfig.hostHomeDirectory (HostConfig.hostFilesystem hostConfig))
    </> ".local"
    </> "share"
    </> "pypoetry"

listVisibleEntries :: FilePath -> IO [FilePath]
listVisibleEntries directoryPath = do
  entries <- listDirectory directoryPath
  pure [entry | entry <- entries, entry /= "." && entry /= ".."]
