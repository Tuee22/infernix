{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RoleAnnotations #-}

module Infernix.Python
  ( ensurePoetryExecutable,
    ensurePoetryProjectReadyWithGroups,
    ensurePoetryProjectReady,
    ensurePreparedPythonEngineEnvironments,
    PreparedPythonEnvironmentReadAuthority,
    withPreparedPythonEngineEnvironmentReadAuthority,
    withPreparedPythonEngineEnvironmentReadAuthorityForTest,
    preparedPythonEnvironmentReadInterpreter,
    preparedPythonEngineInterpreterPathForTest,
    preparedPythonEnvironmentPlanForTest,
    preparedPythonFrameworkMarkerForTest,
    preparedPythonEngineEnvironmentReadyForTest,
    interruptPreparedPythonEnvironmentAfterInvalidationForTest,
    pythonAdaptersPresent,
    pythonProjectDirectory,
  )
where

import Control.Exception (IOException, displayException, throwIO, try)
import Control.Monad (unless, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as ByteString8
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.List (intercalate, nubBy)
import Data.List qualified as List
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.Config (ControlPlaneContext (HostNative), Paths (..), controlPlaneContext)
import Infernix.EngineBindings (canonicalEngineBindingsForMode)
import Infernix.Engines.Provisioning qualified as Provisioning
import Infernix.Error (InfernixError (..))
import Infernix.HostConfig qualified as HostConfig
import Infernix.HostTools qualified as HostTools
import Infernix.Internal.Util (findFirstM)
import Infernix.Python.MutationLock.Internal qualified as MutationLock
import Infernix.Types
  ( EngineAdapterType (PythonStdio),
    EngineBinding (..),
    RuntimeMode (..),
    runtimeModeId,
  )
import System.Directory
  ( doesDirectoryExist,
    doesFileExist,
    executable,
    getPermissions,
    listDirectory,
    pathIsSymbolicLink,
  )
import System.FilePath ((</>))
import System.IO (IOMode (ReadMode), hFileSize, withBinaryFile)
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
        else bootstrapConfiguredDefault configuredPath (pathsHostConfig paths)
    Nothing -> do
      candidate <-
        findFirstM doesFileExist (HostTools.hostToolFallbackCandidates HostTools.HostPoetry)
      case candidate of
        Just executablePath -> pure executablePath
        Nothing
          | os == "darwin" && controlPlaneContext paths == HostNative ->
              bootstrapPoetryOnAppleHost paths
          | otherwise -> throwIO PoetryUnavailable
  where
    -- A configured Poetry path may be bootstrapped only when it is exactly the
    -- fixed Apple-host default; any other missing configured path is fatal.
    bootstrapConfiguredDefault configuredPath hostConfigValue =
      case hostConfigValue of
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
        groups <- parseRequestedGroups projectDirectory requestedGroups
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
                        environmentOutcome <-
                          ensurePreparedProjectEnvironment
                            projectWriter
                            grant
                            poetry
                            projectDirectory
                        installOutcome <-
                          case provisioningFailure environmentOutcome of
                            Just _ -> pure environmentOutcome
                            Nothing ->
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

-- | One framework environment prepared before inference starts. The adapter
-- binding comes from the canonical model catalog and the group is selected by
-- the host/runtime pair; neither adapter ids nor paths are caller supplied.
data PreparedPythonEnvironment = PreparedPythonEnvironment
  { preparedEnvironmentBinding :: !EngineBinding,
    preparedEnvironmentName :: !String,
    preparedEnvironmentGroups :: ![String]
  }

-- | Materialize every per-engine framework environment required by this
-- host/runtime pair. Each project is installed and its readiness marker is
-- published under the same project mutation lock. Runtime consumers never
-- call this producer: they only verify the prepared interpreter and marker.
ensurePreparedPythonEngineEnvironments :: Paths -> RuntimeMode -> IO ()
ensurePreparedPythonEngineEnvironments paths runtimeMode = do
  plans <-
    either
      (ioError . userError . ("invalid prepared Python environment plan: " <>))
      pure
      (preparedPythonEnvironmentPlans os runtimeMode)
  case plans of
    [] -> pure ()
    _ -> do
      _ <- ensurePoetryExecutable paths
      environment <- Subprocess.clusterSubprocessEnv paths
      mapM_
        ( provisionPreparedPythonEnvironment
            ContinueAfterPreparedEnvironmentInvalidation
            paths
            environment
            runtimeMode
        )
        plans

data PreparedPythonMutationHook
  = ContinueAfterPreparedEnvironmentInvalidation
  | InterruptAfterPreparedEnvironmentInvalidation

provisionPreparedPythonEnvironment ::
  PreparedPythonMutationHook ->
  Paths ->
  Subprocess.SubprocessEnv ->
  RuntimeMode ->
  PreparedPythonEnvironment ->
  IO ()
provisionPreparedPythonEnvironment
  mutationHook
  paths
  environment
  runtimeMode
  plan = do
    let projectDirectory = preparedPythonEnvironmentProjectDirectory paths plan
    projectPresent <- doesDirectoryExist projectDirectory
    unless projectPresent $
      throwIO (PythonProjectMissing projectDirectory)
    groups <-
      parseRequestedGroups
        projectDirectory
        (preparedEnvironmentGroups plan)
    result <-
      Provisioning.withPythonProvisioningSession
        (repoRoot paths)
        projectDirectory
        environment
        ( \projectWriter _bindingsWriter grant -> do
            projectReady <-
              Provisioning.provisioningPoetryProjectReady projectWriter
            if not projectReady
              then pure (Left "locked per-engine Python project root is incomplete")
              else do
                readyBefore <-
                  preparedEnvironmentReadyInSession
                    projectWriter
                    paths
                    runtimeMode
                    plan
                case readyBefore of
                  Left failure -> pure (Left failure)
                  Right True -> pure (Right ())
                  Right False -> do
                    let markerPath =
                          preparedPythonEnvironmentMarkerPath paths runtimeMode plan
                    markerBeforeMutation <-
                      Provisioning.provisioningProjectReadFile
                        projectWriter
                        markerPath
                        maximumFrameworkMarkerBytes
                    case markerBeforeMutation of
                      Left failure -> pure (Left failure)
                      Right maybeMarker -> do
                        -- Existing readiness evidence must be invalidated
                        -- durably before Poetry can mutate the environment.
                        -- A stably absent marker (including a fresh project
                        -- with no .venv yet) is already fail-closed evidence,
                        -- so do not require Poetry's future parent directory
                        -- to exist merely to publish a tombstone.
                        case maybeMarker of
                          Nothing -> pure ()
                          Just _ ->
                            Provisioning.provisioningProjectWriteFile
                              projectWriter
                              markerPath
                              preparedPythonEnvironmentMutationMarker
                        case mutationHook of
                          InterruptAfterPreparedEnvironmentInvalidation ->
                            pure (Left preparedPythonEnvironmentInjectedInterruption)
                          ContinueAfterPreparedEnvironmentInvalidation -> do
                            poetryResult <- Provisioning.resolvePoetry grant
                            case poetryResult of
                              Left failure -> pure (Left failure)
                              Right poetry -> do
                                environmentOutcome <-
                                  ensurePreparedProjectEnvironment
                                    projectWriter
                                    grant
                                    poetry
                                    projectDirectory
                                installOutcome <-
                                  case provisioningFailure environmentOutcome of
                                    Just _ -> pure environmentOutcome
                                    Nothing ->
                                      Provisioning.installPoetryProjectWithGroups
                                        projectWriter
                                        grant
                                        poetryInstallDeadline
                                        poetry
                                        groups
                                case provisioningFailure installOutcome of
                                  Just failure -> pure (Left failure)
                                  Nothing -> do
                                    -- Poetry may create poetry.lock. Compute the
                                    -- project digest only after the bounded install,
                                    -- while this same project lock is still held.
                                    markerEvidence <-
                                      preparedEnvironmentMarkerEvidenceInSession
                                        projectWriter
                                        paths
                                        runtimeMode
                                        plan
                                    case markerEvidence of
                                      Left failure -> pure (Left failure)
                                      Right Nothing ->
                                        pure
                                          ( Left
                                              "bounded Poetry install did not publish an executable per-engine interpreter"
                                          )
                                      Right (Just markerContents) -> do
                                        Provisioning.provisioningProjectWriteFile
                                          projectWriter
                                          markerPath
                                          markerContents
                                        readyAfter <-
                                          preparedEnvironmentReadyInSession
                                            projectWriter
                                            paths
                                            runtimeMode
                                            plan
                                        case readyAfter of
                                          Right True -> pure (Right ())
                                          Right False ->
                                            pure
                                              (Left "prepared framework marker did not read back exactly")
                                          Left failure -> pure (Left failure)
        )
    case result of
      Right () -> pure ()
      Left failure ->
        throwIO
          ProcessFailure
            { processName = "bounded per-engine Python provisioning failed",
              processStderr = failure,
              processCwd = Just projectDirectory
            }

-- | Deterministic crash seam for the durable invalidation protocol. It enters
-- the real project-writer region, publishes the same tombstone as production,
-- and stops before Poetry resolution or mutation. The resulting exception is
-- intentional; callers then prove runtime readiness rejects the residue.
interruptPreparedPythonEnvironmentAfterInvalidationForTest ::
  String ->
  Paths ->
  RuntimeMode ->
  EngineBinding ->
  IO ()
interruptPreparedPythonEnvironmentAfterInvalidationForTest
  platform
  paths
  runtimeMode
  engineBinding = do
    maybePlan <-
      either
        (ioError . userError)
        pure
        (preparedPythonEnvironmentForBinding platform runtimeMode engineBinding)
    plan <-
      maybe
        (ioError (userError "test binding has no prepared Python environment"))
        pure
        maybePlan
    environment <- Subprocess.clusterSubprocessEnv paths
    provisionPreparedPythonEnvironment
      InterruptAfterPreparedEnvironmentInvalidation
      paths
      environment
      runtimeMode
      plan

-- | Opaque evidence that the exact prepared interpreter and marker were
-- validated while a shared lease over the project mutation lock is still
-- held. The nominal region prevents the evidence from escaping the callback;
-- retaining it through subprocess completion prevents Poetry from mutating
-- the environment while Python is still importing from it.
data PreparedPythonEnvironmentReadAuthority s
  = PreparedPythonEnvironmentReadAuthority
      !(MutationLock.PoetryProjectReadAuthority s)
      !RuntimeMode
      !EngineBinding
      !FilePath

type role PreparedPythonEnvironmentReadAuthority nominal

withPreparedPythonEngineEnvironmentReadAuthority ::
  Paths ->
  RuntimeMode ->
  EngineBinding ->
  (forall s. PreparedPythonEnvironmentReadAuthority s -> IO result) ->
  IO result
withPreparedPythonEngineEnvironmentReadAuthority =
  withPreparedPythonEngineEnvironmentReadAuthorityForPlatform os

-- | Platform-selectable form used only by filesystem fixtures. It enters the
-- same shared kernel-lock region and mints the same authority as production.
withPreparedPythonEngineEnvironmentReadAuthorityForTest ::
  String ->
  Paths ->
  RuntimeMode ->
  EngineBinding ->
  (forall s. PreparedPythonEnvironmentReadAuthority s -> IO result) ->
  IO result
withPreparedPythonEngineEnvironmentReadAuthorityForTest =
  withPreparedPythonEngineEnvironmentReadAuthorityForPlatform

withPreparedPythonEngineEnvironmentReadAuthorityForPlatform ::
  String ->
  Paths ->
  RuntimeMode ->
  EngineBinding ->
  (forall s. PreparedPythonEnvironmentReadAuthority s -> IO result) ->
  IO result
withPreparedPythonEngineEnvironmentReadAuthorityForPlatform
  platform
  paths
  runtimeMode
  engineBinding
  action = do
    projectDirectory <-
      either
        (ioError . userError)
        pure
        (preparedPythonEngineProjectDirectory paths engineBinding)
    MutationLock.withPoetryProjectReadLockInternal projectDirectory $ \lockAuthority -> do
      ready <-
        preparedPythonEngineEnvironmentReadyForPlatform
          platform
          paths
          runtimeMode
          engineBinding
      interpreter <- either (ioError . userError) pure ready
      action
        ( PreparedPythonEnvironmentReadAuthority
            lockAuthority
            runtimeMode
            engineBinding
            interpreter
        )

-- | Consume the authority only for the runtime/binding pair that minted it.
-- CappedEngine uses this path directly; it must not re-derive or recheck a
-- mutable pathname after the locked readiness observation.
preparedPythonEnvironmentReadInterpreter ::
  PreparedPythonEnvironmentReadAuthority s ->
  RuntimeMode ->
  EngineBinding ->
  Either String FilePath
preparedPythonEnvironmentReadInterpreter
  (PreparedPythonEnvironmentReadAuthority _ authorizedRuntime authorizedBinding interpreter)
  requestedRuntime
  requestedBinding
    | authorizedRuntime == requestedRuntime
        && authorizedBinding == requestedBinding =
        Right interpreter
    | otherwise =
        Left "prepared Python read authority does not match the requested runtime and engine binding"

preparedPythonEngineEnvironmentReadyForTest ::
  String ->
  Paths ->
  RuntimeMode ->
  EngineBinding ->
  IO (Either String FilePath)
preparedPythonEngineEnvironmentReadyForTest =
  preparedPythonEngineEnvironmentReadyForPlatform

preparedPythonEngineEnvironmentReadyForPlatform ::
  String ->
  Paths ->
  RuntimeMode ->
  EngineBinding ->
  IO (Either String FilePath)
preparedPythonEngineEnvironmentReadyForPlatform
  platform
  paths
  runtimeMode
  engineBinding = do
    observed <-
      try @IOException $ do
        pythonPath <-
          either
            (ioError . userError)
            pure
            (preparedPythonEngineInterpreterPath paths engineBinding)
        pythonPresent <- doesFileExist pythonPath
        pythonExecutable <-
          if pythonPresent
            then executable <$> getPermissions pythonPath
            else pure False
        unless pythonExecutable $
          ioError
            ( userError
                ( "prepared per-engine Python interpreter is missing or not executable for "
                    <> Text.unpack (engineBindingAdapterId engineBinding)
                    <> ": "
                    <> pythonPath
                )
            )
        maybePlan <-
          either
            (ioError . userError)
            pure
            (preparedPythonEnvironmentForBinding platform runtimeMode engineBinding)
        case maybePlan of
          Nothing -> pure pythonPath
          Just plan -> do
            let projectDirectory = preparedPythonEnvironmentProjectDirectory paths plan
                markerPath = preparedPythonEnvironmentMarkerPath paths runtimeMode plan
            firstDigest <- readPreparedProjectDigest projectDirectory
            let expectedMarker =
                  preparedPythonEnvironmentMarkerContents runtimeMode plan firstDigest
            markerContents <-
              readBoundedPlainFile markerPath maximumFrameworkMarkerBytes
            unless (markerContents == Just (ByteString8.pack expectedMarker)) $
              ioError
                ( userError
                    ( "prepared per-engine Python marker is missing or stale for "
                        <> Text.unpack (engineBindingAdapterId engineBinding)
                        <> ": "
                        <> markerPath
                    )
                )
            finalDigest <- readPreparedProjectDigest projectDirectory
            unless (finalDigest == firstDigest) $
              ioError
                (userError "prepared per-engine Python project changed during readiness observation")
            pure pythonPath
    case observed of
      Left failure -> pure (Left (displayException failure))
      Right pythonPath -> pure (Right pythonPath)

preparedPythonEnvironmentPlans ::
  String ->
  RuntimeMode ->
  Either String [PreparedPythonEnvironment]
preparedPythonEnvironmentPlans platform runtimeMode =
  case preparedPythonInstallGroup platform runtimeMode of
    Nothing -> Right []
    Just group ->
      traverse
        (\binding -> preparedPythonEnvironment binding [group])
        uniquePythonBindings
  where
    uniquePythonBindings =
      nubBy
        (\left right -> engineBindingAdapterId left == engineBindingAdapterId right)
        [ binding
        | binding <- canonicalEngineBindingsForMode runtimeMode,
          engineBindingPythonNative binding,
          engineBindingAdapterType binding == PythonStdio
        ]

preparedPythonEnvironmentForBinding ::
  String ->
  RuntimeMode ->
  EngineBinding ->
  Either String (Maybe PreparedPythonEnvironment)
preparedPythonEnvironmentForBinding platform runtimeMode engineBinding = do
  plans <- preparedPythonEnvironmentPlans platform runtimeMode
  pure
    ( List.find
        ( (== engineBindingAdapterId engineBinding)
            . engineBindingAdapterId
            . preparedEnvironmentBinding
        )
        plans
    )

preparedPythonEnvironment ::
  EngineBinding ->
  [String] ->
  Either String PreparedPythonEnvironment
preparedPythonEnvironment binding groups = do
  engineName <- preparedPythonEngineName binding
  pure
    PreparedPythonEnvironment
      { preparedEnvironmentBinding = binding,
        preparedEnvironmentName = engineName,
        preparedEnvironmentGroups = groups
      }

preparedPythonInstallGroup :: String -> RuntimeMode -> Maybe String
preparedPythonInstallGroup platform runtimeMode =
  case (platform, runtimeMode) of
    ("darwin", AppleSilicon) -> Just "apple-silicon"
    ("linux", LinuxCpu) -> Just "linux-cpu"
    _ -> Nothing

preparedPythonEnvironmentPlanForTest ::
  String ->
  RuntimeMode ->
  Either String [(Text.Text, [String])]
preparedPythonEnvironmentPlanForTest platform runtimeMode =
  map
    ( \plan ->
        ( engineBindingAdapterId (preparedEnvironmentBinding plan),
          preparedEnvironmentGroups plan
        )
    )
    <$> preparedPythonEnvironmentPlans platform runtimeMode

preparedPythonEngineName :: EngineBinding -> Either String String
preparedPythonEngineName engineBinding =
  case Text.stripSuffix "-python" (engineBindingAdapterId engineBinding) of
    Just engineName
      | not (Text.null engineName)
          && Text.all validEngineNameCharacter engineName ->
          Right (Text.unpack engineName)
    _ ->
      Left
        ( "Python adapter id does not have a safe exact -python suffix: "
            <> Text.unpack (engineBindingAdapterId engineBinding)
        )
  where
    validEngineNameCharacter character =
      isAsciiLower character
        || isAsciiUpper character
        || isDigit character
        || character == '-'

preparedPythonEngineProjectDirectory ::
  Paths ->
  EngineBinding ->
  Either String FilePath
preparedPythonEngineProjectDirectory paths engineBinding = do
  engineName <- preparedPythonEngineName engineBinding
  pure (repoRoot paths </> "python" </> "engines" </> engineName)

preparedPythonEngineInterpreterPath ::
  Paths ->
  EngineBinding ->
  Either String FilePath
preparedPythonEngineInterpreterPath paths engineBinding = do
  projectDirectory <- preparedPythonEngineProjectDirectory paths engineBinding
  pure (projectDirectory </> ".venv" </> "bin" </> "python")

preparedPythonEngineInterpreterPathForTest ::
  Paths ->
  EngineBinding ->
  Either String FilePath
preparedPythonEngineInterpreterPathForTest =
  preparedPythonEngineInterpreterPath

preparedPythonEnvironmentProjectDirectory ::
  Paths ->
  PreparedPythonEnvironment ->
  FilePath
preparedPythonEnvironmentProjectDirectory paths plan =
  repoRoot paths
    </> "python"
    </> "engines"
    </> preparedEnvironmentName plan

preparedPythonEnvironmentMarkerPath ::
  Paths ->
  RuntimeMode ->
  PreparedPythonEnvironment ->
  FilePath
preparedPythonEnvironmentMarkerPath paths runtimeMode plan =
  preparedPythonEnvironmentProjectDirectory paths plan
    </> ".venv"
    </> preparedPythonEnvironmentMarkerFileName runtimeMode plan

preparedPythonEnvironmentMarkerFileName ::
  RuntimeMode ->
  PreparedPythonEnvironment ->
  FilePath
preparedPythonEnvironmentMarkerFileName runtimeMode plan =
  ".infernix-framework-groups-"
    <> Text.unpack (runtimeModeId runtimeMode)
    <> "-"
    <> intercalate "-" (preparedEnvironmentGroups plan)

preparedPythonEnvironmentMarkerContents ::
  RuntimeMode ->
  PreparedPythonEnvironment ->
  String ->
  String
preparedPythonEnvironmentMarkerContents runtimeMode plan projectDigest =
  unlines
    [ "runtimeMode=" <> Text.unpack (runtimeModeId runtimeMode),
      "adapterId="
        <> Text.unpack
          (engineBindingAdapterId (preparedEnvironmentBinding plan)),
      "groups=" <> intercalate "," (preparedEnvironmentGroups plan),
      "projectDigest=" <> projectDigest
    ]

preparedPythonFrameworkMarkerForTest ::
  String ->
  RuntimeMode ->
  EngineBinding ->
  ByteString.ByteString ->
  Maybe ByteString.ByteString ->
  Either String (Maybe (FilePath, String))
preparedPythonFrameworkMarkerForTest
  platform
  runtimeMode
  engineBinding
  pyprojectBytes
  maybeLockBytes = do
    maybePlan <-
      preparedPythonEnvironmentForBinding platform runtimeMode engineBinding
    pure
      ( ( \plan ->
            ( preparedPythonEnvironmentMarkerFileName runtimeMode plan,
              preparedPythonEnvironmentMarkerContents
                runtimeMode
                plan
                (preparedPythonProjectDigest pyprojectBytes maybeLockBytes)
            )
        )
          <$> maybePlan
      )

preparedEnvironmentReadyInSession ::
  Provisioning.ProjectWriter p s q ->
  Paths ->
  RuntimeMode ->
  PreparedPythonEnvironment ->
  Provisioning.ProvisioningSession s (Either String Bool)
preparedEnvironmentReadyInSession writer paths runtimeMode plan = do
  firstEvidence <-
    preparedEnvironmentMarkerEvidenceInSession
      writer
      paths
      runtimeMode
      plan
  markerResult <-
    Provisioning.provisioningProjectReadFile
      writer
      (preparedPythonEnvironmentMarkerPath paths runtimeMode plan)
      maximumFrameworkMarkerBytes
  finalEvidence <-
    preparedEnvironmentMarkerEvidenceInSession
      writer
      paths
      runtimeMode
      plan
  pure $ do
    initial <- firstEvidence
    observedMarker <- markerResult
    final <- finalEvidence
    case (initial == final, initial) of
      (False, _) ->
        Left "per-engine Python project changed during locked readiness observation"
      (True, Nothing) -> Right False
      (True, Just expectedMarker) ->
        Right (observedMarker == Just (ByteString8.pack expectedMarker))

preparedEnvironmentMarkerEvidenceInSession ::
  Provisioning.ProjectWriter p s q ->
  Paths ->
  RuntimeMode ->
  PreparedPythonEnvironment ->
  Provisioning.ProvisioningSession s (Either String (Maybe String))
preparedEnvironmentMarkerEvidenceInSession writer paths runtimeMode plan = do
  digestResult <-
    preparedProjectDigestInSession
      writer
      (preparedPythonEnvironmentProjectDirectory paths plan)
  executableResult <-
    Provisioning.provisioningProjectExecutableReady
      writer
      ( preparedPythonEnvironmentProjectDirectory paths plan
          </> ".venv"
          </> "bin"
          </> "python"
      )
  pure $ do
    digest <- digestResult
    executableReady <- executableResult
    pure
      ( if executableReady
          then
            Just
              (preparedPythonEnvironmentMarkerContents runtimeMode plan digest)
          else Nothing
      )

preparedProjectDigestInSession ::
  Provisioning.ProjectWriter p s q ->
  FilePath ->
  Provisioning.ProvisioningSession s (Either String String)
preparedProjectDigestInSession writer projectDirectory = do
  pyprojectResult <-
    Provisioning.provisioningProjectReadFile
      writer
      (projectDirectory </> "pyproject.toml")
      maximumPyprojectBytes
  lockResult <-
    Provisioning.provisioningProjectReadFile
      writer
      (projectDirectory </> "poetry.lock")
      maximumPoetryLockBytes
  pure $ do
    maybePyproject <- pyprojectResult
    pyprojectBytes <-
      maybe
        (Left "per-engine pyproject.toml is missing")
        Right
        maybePyproject
    preparedPythonProjectDigest pyprojectBytes <$> lockResult

readPreparedProjectDigest :: FilePath -> IO String
readPreparedProjectDigest projectDirectory = do
  maybePyproject <-
    readBoundedPlainFile
      (projectDirectory </> "pyproject.toml")
      maximumPyprojectBytes
  pyprojectBytes <-
    maybe
      (ioError (userError "prepared per-engine pyproject.toml is missing"))
      pure
      maybePyproject
  maybeLockBytes <-
    readBoundedPlainFile
      (projectDirectory </> "poetry.lock")
      maximumPoetryLockBytes
  pure (preparedPythonProjectDigest pyprojectBytes maybeLockBytes)

preparedPythonProjectDigest ::
  ByteString.ByteString ->
  Maybe ByteString.ByteString ->
  String
preparedPythonProjectDigest pyprojectBytes maybeLockBytes =
  Text.unpack
    ( TextEncoding.decodeUtf8
        ( Base16.encode
            ( SHA256.hash
                ( ByteString.concat
                    [ pyprojectBytes,
                      ByteString8.pack "\n",
                      fromMaybe ByteString.empty maybeLockBytes
                    ]
                )
            )
        )
    )

readBoundedPlainFile ::
  FilePath ->
  Integer ->
  IO (Maybe ByteString.ByteString)
readBoundedPlainFile path maximumBytes = do
  present <- doesFileExist path
  if not present
    then pure Nothing
    else do
      symbolicLink <- pathIsSymbolicLink path
      when symbolicLink $
        ioError (userError ("prepared Python evidence is a symbolic link: " <> path))
      withBinaryFile path ReadMode $ \handle -> do
        observedBytes <- hFileSize handle
        unless (observedBytes >= 0 && observedBytes <= maximumBytes) $
          ioError (userError ("prepared Python evidence exceeds its fixed bound: " <> path))
        contents <- ByteString.hGet handle (fromIntegral observedBytes)
        finalBytes <- hFileSize handle
        unless
          ( ByteString.length contents == fromIntegral observedBytes
              && finalBytes == observedBytes
          )
          (ioError (userError ("prepared Python evidence changed during read: " <> path)))
        pure (Just contents)

parseRequestedGroups ::
  FilePath ->
  [String] ->
  IO [Provisioning.PoetryInstallGroup]
parseRequestedGroups projectDirectory =
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
    . filter (not . null)

maximumPyprojectBytes :: Integer
maximumPyprojectBytes = 4 * 1024 * 1024

maximumPoetryLockBytes :: Integer
maximumPoetryLockBytes = 64 * 1024 * 1024

maximumFrameworkMarkerBytes :: Integer
maximumFrameworkMarkerBytes = 4096

-- | Durable tombstone published before a framework-environment mutation.
-- This intentionally cannot parse as the four-line readiness record.
preparedPythonEnvironmentMutationMarker :: String
preparedPythonEnvironmentMutationMarker =
  "infernix-framework-environment-incomplete\n"

preparedPythonEnvironmentInjectedInterruption :: String
preparedPythonEnvironmentInjectedInterruption =
  "injected interruption after prepared-environment marker invalidation"

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

poetryProjectVenvDeadline :: Provisioning.ProvisioningDeadline
poetryProjectVenvDeadline =
  requiredDeadline
    "Poetry project environment creation deadline"
    (5 * 60 * 1000 * 1000)

-- | Give the project its own stable environment before Poetry picks one for it.
--
-- Every Poetry install runs from an exact per-command snapshot. If the project
-- has no environment, Poetry or virtualenv can therefore record that snapshot
-- as the base interpreter even when the sealed Python home is a real Darwin
-- framework rather than a virtual environment. The snapshot is retired when
-- the command finishes, leaving the project interpreter as a dangling link.
--
-- The closed creation command deliberately uses the configured host Python
-- without sealing its home and requests copied project executables. The venv's
-- base home is therefore the stable manifest-owned framework even though its
-- informational creation-command metadata records the bounded executable
-- snapshot. An existing exact project interpreter still short-circuits the
-- operation; this does not clear a ready environment on an idempotent rerun.
ensurePreparedProjectEnvironment ::
  Provisioning.ProjectWriter p s q ->
  Provisioning.ProvisioningGrant s ->
  Provisioning.ResolvedPoetry s ->
  FilePath ->
  Provisioning.ProvisioningSession s Provisioning.ProvisioningOutcome
ensurePreparedProjectEnvironment writer grant _poetry projectDirectory = do
  interpreterReady <-
    Provisioning.provisioningProjectExecutableReady
      writer
      (projectDirectory </> ".venv" </> "bin" </> "python")
  case interpreterReady of
    Left failure -> pure (Provisioning.ProvisioningRejected failure)
    Right True -> pure skipped
    Right False ->
      Provisioning.createPoetryProjectVenv
        writer
        grant
        poetryProjectVenvDeadline
  where
    skipped = Provisioning.ProvisioningSucceeded ""

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
