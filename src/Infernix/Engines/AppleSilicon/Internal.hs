{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RoleAnnotations #-}

module Infernix.Engines.AppleSilicon.Internal
  ( ensureAppleSiliconRuntimeReady,
    MetalEngineArtifact,
    metalEngineAdapterId,
    metalEngineName,
    metalEngineArtifactKind,
    metalEngineSourceRef,
    metalEngineVersion,
    metalEngineRuntimeVersion,
    materializeMetalEngines,
    materializeAudiverisProductionPausedForTest,
    AppleMaterializerFixtureBoundary (..),
    appleMaterializerFixtureBoundaries,
    appleMaterializerBoundaryFailureForTest,
    appleMaterializerBoundaryCancellationForTest,
    appleMaterializerFixtureCandidateRoot,
    appleMaterializerLockContentionForTest,
    retireLegacyAppleMetalRuntimeBridgeForTest,
    MachOFixturePlan (..),
    inspectMachOFixtureForTest,
    machOInstallNameTargetForTest,
    shebangBindsHostInstallationForTest,
    supportedMachOMagicForTest,
    resolveMachOPathsFixtureForTest,
    AudiverisMountRecoveryFixture (..),
    recoverAudiverisMountRecordFixtureForTest,
    audiverisMountRecoveryFixtureRootForTest,
    audiverisMountRecoveryRequiredForTest,
    metalEngineBuildPlan,
    metalEngineArtifactAdapterIds,
    metalEngineInstallRoot,
    manifestForHydratedMetalEngineArtifact,
    parseAppleRuntimeVersionForTest,
    parseResolvedPythonProvenance,
  )
where

import Control.Concurrent.MVar (MVar)
import Control.Monad (unless, when)
import Data.Aeson qualified as Aeson
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (toLower)
import Data.List (nubBy)
import Data.List qualified as List
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.Config (Paths (..))
import Infernix.Engines.Artifact
  ( EngineArtifactManifest (..),
    ResolvedArtifactProvenance (..),
    appleArtifactRuntimeExpectation,
    currentArtifactRecipeFingerprint,
    engineArtifactTempRoot,
    parseNativeArtifactIdentity,
  )
import Infernix.Engines.Artifact.Recipe qualified as Recipe
import Infernix.Engines.Artifact.Target
  ( nativeArtifactTarget,
    nativeArtifactTargetFingerprint,
  )
import Infernix.Engines.Provisioning qualified as Provisioning
import Infernix.Models (engineBindingsForMode)
import Infernix.Python
  ( pythonProjectDirectory,
  )
import Infernix.Types (EngineBinding (..), RuntimeMode (AppleSilicon))
import System.FilePath
  ( isAbsolute,
    makeRelative,
    normalise,
    splitDirectories,
    (</>),
  )
import System.Info (os)

data AppleProvisioningDeadlines = AppleProvisioningDeadlines
  { deadlinePoetryInstall :: !Provisioning.ProvisioningDeadline,
    deadlineProtoGeneration :: !Provisioning.ProvisioningDeadline,
    deadlinePythonProbe :: !Provisioning.ProvisioningDeadline,
    deadlineVenvCreate :: !Provisioning.ProvisioningDeadline,
    deadlinePipUpgrade :: !Provisioning.ProvisioningDeadline,
    deadlineRequirementsInstall :: !Provisioning.ProvisioningDeadline,
    deadlineAudiverisDownload :: !Provisioning.ProvisioningDeadline,
    deadlineAudiverisMount :: !Provisioning.ProvisioningDeadline,
    deadlineArtifactSmoke :: !Provisioning.ProvisioningDeadline,
    deadlineProvenanceQuery :: !Provisioning.ProvisioningDeadline
  }

data AppleMaterializationHook
  = NoAppleMaterializationHook
  | PauseAfterAudiverisMount !(MVar ()) !(MVar ())

data AppleMaterializationPhase
  = AppleMaterializationStarted
  | AppleCandidatePrepared
  | ApplePayloadWritten
  | AppleMaterializationCompleted

data AppleMaterializationSession s (phase :: AppleMaterializationPhase) where
  AppleMaterializationStartedSession ::
    AppleMaterializationSession s 'AppleMaterializationStarted
  AppleCandidatePreparedSession ::
    AppleMaterializationSession s 'AppleCandidatePrepared
  ApplePayloadWrittenSession ::
    AppleMaterializationSession s 'ApplePayloadWritten
  AppleMaterializationCompletedSession ::
    AppleMaterializationSession s 'AppleMaterializationCompleted

type role AppleMaterializationSession nominal nominal

beginAppleMaterialization ::
  Provisioning.ProvisioningSession
    s
    (AppleMaterializationSession s 'AppleMaterializationStarted)
beginAppleMaterialization =
  pure AppleMaterializationStartedSession

finishAppleMaterialization ::
  AppleMaterializationSession s 'AppleMaterializationCompleted ->
  Provisioning.ProvisioningSession s ()
finishAppleMaterialization AppleMaterializationCompletedSession =
  pure ()

runAudiverisMountHook ::
  AppleMaterializationHook ->
  Provisioning.ProvisioningSession s ()
runAudiverisMountHook hook =
  case hook of
    NoAppleMaterializationHook -> pure ()
    PauseAfterAudiverisMount entered resume ->
      Provisioning.pauseProvisioningSessionForTest entered resume

appleProvisioningDeadlines :: IO AppleProvisioningDeadlines
appleProvisioningDeadlines =
  AppleProvisioningDeadlines
    <$> requireDeadline "Poetry project install" 1800000000
    <*> requireDeadline "Python proto generation" 300000000
    <*> requireDeadline "Python version probe" 30000000
    <*> requireDeadline "Python venv creation" 120000000
    <*> requireDeadline "pip upgrade" 600000000
    <*> requireDeadline "Python requirements installation" 1800000000
    <*> requireDeadline "Audiveris download" 1200000000
    <*> requireDeadline "Audiveris mount/detach" 120000000
    <*> requireDeadline "artifact runtime smoke" 600000000
    <*> requireDeadline "artifact provenance query" 120000000

requireDeadline :: String -> Int -> IO Provisioning.ProvisioningDeadline
requireDeadline label microseconds =
  either
    (ioError . userError . ((label <> ": ") <>))
    pure
    (Provisioning.mkProvisioningDeadline microseconds)

data AppleSetupRequest = AppleSetupRequest
  { setupRequestId :: !Provisioning.ApplePoetrySetupId,
    setupRequestInstallRoot :: !FilePath
  }

ensureAppleSiliconRuntimeReady :: Paths -> IO ()
ensureAppleSiliconRuntimeReady paths = do
  let projectDirectory = pythonProjectDirectory paths AppleSilicon
      uniqueBindings =
        nubBy
          (\left right -> engineBindingAdapterId left == engineBindingAdapterId right)
          (engineBindingsForMode AppleSilicon)
      pythonBindings = filter engineBindingPythonNative uniqueBindings
      engineInstallRoot binding =
        dataRoot paths </> "engines" </> Text.unpack (engineBindingAdapterId binding)
  setupRequests <- mapM (bindingSetupRequest engineInstallRoot) pythonBindings
  environment <- Subprocess.clusterSubprocessEnv paths
  deadlines <- appleProvisioningDeadlines
  Provisioning.withAppleProvisioningSession
    paths
    projectDirectory
    environment
    $ \projectWriter generatedBindingsWriter _cacheWriter engineWriter grant -> do
      poetry <-
        requireProvisioningResolution "resolve configured Poetry"
          =<< Provisioning.resolvePoetry grant
      ensureBoundedPoetryProjectReady
        projectWriter
        generatedBindingsWriter
        grant
        deadlines
        poetry
        projectDirectory
      mapM_
        (runAppleSetupRequest engineWriter)
        setupRequests

ensureBoundedPoetryProjectReady ::
  Provisioning.ProjectWriter p s q ->
  Provisioning.GeneratedBindingsWriter g s q ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  Provisioning.ResolvedPoetry s ->
  FilePath ->
  Provisioning.ProvisioningSession s ()
ensureBoundedPoetryProjectReady
  writer
  generatedBindingsWriter
  grant
  deadlines
  poetry
  projectDirectory = do
    projectPresent <-
      Provisioning.provisioningPoetryProjectReady writer
    unless projectPresent $
      Provisioning.failProvisioningSession
        ("Python project is missing: " <> projectDirectory)
    installOutcome <-
      Provisioning.installPoetryProject
        writer
        grant
        (deadlinePoetryInstall deadlines)
        poetry
    _ <-
      requireProvisioningSuccess
        "install Apple Poetry project"
        installOutcome
    protoGenerationRequired <-
      Provisioning.provisioningGeneratedBindingsRequired
        generatedBindingsWriter
    when protoGenerationRequired $ do
      projectPython <-
        requireProvisioningResolution
          "resolve installed project Python"
          =<< Provisioning.resolveProjectPython writer
      generationOutcome <-
        Provisioning.generatePythonProtoBindings
          writer
          generatedBindingsWriter
          grant
          (deadlineProtoGeneration deadlines)
          projectPython
      _ <-
        requireProvisioningSuccess
          "generate Python protobuf bindings"
          generationOutcome
      Provisioning.provisioningCreateGeneratedBindingNamespaces
        generatedBindingsWriter

bindingSetupRequest ::
  (EngineBinding -> FilePath) ->
  EngineBinding ->
  IO AppleSetupRequest
bindingSetupRequest engineInstallRoot binding
  | engineBindingAdapterId binding
      `elem` metalEngineArtifactAdapterIds =
      ioError
        ( userError
            ( "Apple Python bootstrap binding overlaps an exact native artifact id: "
                <> Text.unpack (engineBindingAdapterId binding)
            )
        )
  | otherwise =
      case Provisioning.parseApplePoetrySetupEntrypoint
        (Text.unpack (engineBindingSetupEntrypoint binding)) of
        Nothing ->
          ioError
            ( userError
                ( "unsupported Apple Poetry setup entrypoint: "
                    <> Text.unpack (engineBindingSetupEntrypoint binding)
                )
            )
        Just setupId ->
          pure
            AppleSetupRequest
              { setupRequestId = setupId,
                setupRequestInstallRoot = engineInstallRoot binding
              }

runAppleSetupRequest ::
  Provisioning.EngineWriter w s q ->
  AppleSetupRequest ->
  Provisioning.ProvisioningSession s ()
runAppleSetupRequest writer request = do
  let installRoot = setupRequestInstallRoot request
  Provisioning.provisioningCreateDirectory writer installRoot
  bootstrapReady <-
    Provisioning.provisioningAppleSetupReady
      writer
      (setupRequestId request)
      installRoot
  unless bootstrapReady $
    Provisioning.provisioningPublishAppleSetupManifest
      writer
      (setupRequestId request)
      installRoot

-- | One allowlisted Apple host engine artifact. The adapter identity is opaque
-- outside the provisioning kernel, so a raw executable or argument vector
-- cannot be smuggled into materialization.
data MetalEngineArtifact = MetalEngineArtifact
  { metalEngineProvisioningAdapter :: !Provisioning.AppleAdapterId,
    metalEngineName :: !Text,
    metalEngineArtifactKind :: !Text,
    metalEngineSourceRef :: !Text,
    metalEngineVersion :: !Text,
    metalEngineRuntimeVersion :: !Text
  }
  deriving (Eq, Show)

metalEngineAdapterId :: MetalEngineArtifact -> Text
metalEngineAdapterId =
  Text.pack
    . Provisioning.renderAppleAdapterId
    . metalEngineProvisioningAdapter

metalEngineBuildPlan :: [MetalEngineArtifact]
metalEngineBuildPlan =
  [ MetalEngineArtifact Provisioning.llamaCppCliAdapter "llama.cpp Metal" "native-binary" "github:ggml-org/llama.cpp" "resolved-by-runtime-smoke" "Metal.framework/runtime",
    MetalEngineArtifact Provisioning.whisperCppCliAdapter "whisper.cpp Metal" "native-binary" "github:ggml-org/whisper.cpp" "resolved-by-runtime-smoke" "Metal.framework/runtime",
    MetalEngineArtifact Provisioning.coreMlAdapter "Core ML native runner" "venv" "python:coremltools/basic-pitch/apple-ml-stable-diffusion" "resolved-from-pinned-environment" "CoreML.framework via coremltools",
    MetalEngineArtifact Provisioning.ctranslate2Adapter "CTranslate2 native runner" "venv" "python:ctranslate2/faster-whisper" "resolved-from-pinned-environment" "macos-arm64-cpu",
    MetalEngineArtifact Provisioning.mlxAdapter "MLX native runner" "venv" "python:mlx/mlx-lm" "resolved-from-pinned-environment" "Metal.framework/runtime",
    MetalEngineArtifact Provisioning.onnxRuntimeAdapter "ONNX Runtime native runner" "venv" "python:onnxruntime" "resolved-from-pinned-environment" "macos-arm64-cpu",
    MetalEngineArtifact Provisioning.jvmAdapter "Audiveris JVM runner" "jvm-tool" (Text.pack Provisioning.audiverisPinnedDmgUrl) (Text.pack Provisioning.audiverisPinnedVersion) "resolved-Audiveris-bundle-and-JVM"
  ]

metalEngineArtifactAdapterIds :: [Text]
metalEngineArtifactAdapterIds = map metalEngineAdapterId metalEngineBuildPlan

parseAppleRuntimeVersionForTest ::
  MetalEngineArtifact ->
  ByteString.ByteString ->
  Either String Text
parseAppleRuntimeVersionForTest artifact smokeOutput =
  Provisioning.appleRuntimeVersionText
    <$> Provisioning.parseAppleRuntimeVersionForTest
      (metalEngineProvisioningAdapter artifact)
      smokeOutput

metalEngineInstallRoot :: Paths -> Text -> FilePath
metalEngineInstallRoot paths adapterId =
  dataRoot paths </> "engines" </> Text.unpack adapterId

materializeMetalEngines :: Paths -> IO ()
materializeMetalEngines paths = do
  unless (os == "darwin") $
    ioError (userError metalEngineLaneNotAppleMessage)
  let projectDirectory = pythonProjectDirectory paths AppleSilicon
  environment <- Subprocess.clusterSubprocessEnv paths
  deadlines <- appleProvisioningDeadlines
  Provisioning.withAppleProvisioningSession
    paths
    projectDirectory
    environment
    $ \_projectWriter _generatedBindingsWriter cacheWriter writer grant -> do
      retireLegacyAppleMetalRuntimeBridge writer paths
      mapM_
        ( materializeMetalEngineArtifact
            cacheWriter
            writer
            paths
            grant
            deadlines
        )
        metalEngineBuildPlan

-- | Darwin-only evidence hook for the production Audiveris attach boundary.
-- The selected artifact, command language, deadlines, environment, and lock
-- ordering remain fixed by this module; callers can only coordinate
-- cancellation after the typed mount operation has succeeded.
materializeAudiverisProductionPausedForTest ::
  Paths ->
  MVar () ->
  MVar () ->
  IO ()
materializeAudiverisProductionPausedForTest paths entered resume = do
  let projectDirectory = pythonProjectDirectory paths AppleSilicon
  artifact <-
    maybe
      (ioError (userError "closed Apple materialization plan omitted Audiveris"))
      pure
      ( List.find
          ((== Provisioning.jvmAdapter) . metalEngineProvisioningAdapter)
          metalEngineBuildPlan
      )
  environment <- Subprocess.clusterSubprocessEnv paths
  deadlines <- appleProvisioningDeadlines
  Provisioning.withAppleProvisioningSession
    paths
    projectDirectory
    environment
    $ \_projectWriter _generatedBindingsWriter cacheWriter writer grant -> do
      retireLegacyAppleMetalRuntimeBridge writer paths
      materializeMetalEngineArtifactWith
        cacheWriter
        writer
        (PauseAfterAudiverisMount entered resume)
        paths
        grant
        deadlines
        artifact

data AppleMaterializerFixtureBoundary
  = FixtureCandidatePrepared
  | FixturePayloadWritten
  | FixtureHydrationComplete
  | FixtureSmokeComplete
  | FixtureManifestPublished
  | FixtureActivationComplete
  deriving (Bounded, Enum, Eq, Show)

appleMaterializerFixtureBoundaries :: [AppleMaterializerFixtureBoundary]
appleMaterializerFixtureBoundaries = [minBound .. maxBound]

appleMaterializerBoundaryFailureForTest ::
  Paths ->
  AppleMaterializerFixtureBoundary ->
  IO ()
appleMaterializerBoundaryFailureForTest paths target =
  runAppleMaterializerBoundaryFixtureForTest
    paths
    (FailAtFixtureBoundary target)

appleMaterializerBoundaryCancellationForTest ::
  Paths ->
  AppleMaterializerFixtureBoundary ->
  MVar () ->
  MVar () ->
  IO ()
appleMaterializerBoundaryCancellationForTest paths target entered resume =
  runAppleMaterializerBoundaryFixtureForTest
    paths
    (PauseAtFixtureBoundary target entered resume)

appleMaterializerFixtureCandidateRoot :: Paths -> FilePath
appleMaterializerFixtureCandidateRoot paths =
  dataRoot paths
    </> "engines"
    </> ".apple-materializer-boundary-fixture.tmp"

data AppleMaterializerFixtureAction
  = FailAtFixtureBoundary !AppleMaterializerFixtureBoundary
  | PauseAtFixtureBoundary
      !AppleMaterializerFixtureBoundary
      !(MVar ())
      !(MVar ())

runAppleMaterializerBoundaryFixtureForTest ::
  Paths ->
  AppleMaterializerFixtureAction ->
  IO ()
runAppleMaterializerBoundaryFixtureForTest paths fixtureAction = do
  let projectDirectory = pythonProjectDirectory paths AppleSilicon
      candidateRoot = appleMaterializerFixtureCandidateRoot paths
  environment <- Subprocess.clusterSubprocessEnv paths
  Provisioning.withAppleProvisioningSession
    paths
    projectDirectory
    environment
    $ \_projectWriter _generatedBindingsWriter _cacheWriter writer _grant ->
      Provisioning.bracketProvisioning
        beginAppleMaterialization
        (cleanupAppleMaterializerFixture writer candidateRoot)
        ( \started -> do
            prepared <-
              prepareAppleMaterializerFixture
                writer
                candidateRoot
                fixtureAction
                started
            payloadWritten <-
              writeAppleMaterializerFixturePayload
                writer
                candidateRoot
                fixtureAction
                prepared
            completed <-
              completeAppleMaterializerFixture
                writer
                candidateRoot
                fixtureAction
                payloadWritten
            finishAppleMaterialization completed
        )

prepareAppleMaterializerFixture ::
  Provisioning.EngineWriter w s q ->
  FilePath ->
  AppleMaterializerFixtureAction ->
  AppleMaterializationSession s 'AppleMaterializationStarted ->
  Provisioning.ProvisioningSession
    s
    (AppleMaterializationSession s 'AppleCandidatePrepared)
prepareAppleMaterializerFixture
  writer
  candidateRoot
  fixtureAction
  AppleMaterializationStartedSession = do
    Provisioning.provisioningRemovePath
      writer
      candidateRoot
    Provisioning.provisioningCreateDirectory
      writer
      candidateRoot
    runAppleMaterializerFixtureAction
      fixtureAction
      FixtureCandidatePrepared
    pure AppleCandidatePreparedSession

writeAppleMaterializerFixturePayload ::
  Provisioning.EngineWriter w s q ->
  FilePath ->
  AppleMaterializerFixtureAction ->
  AppleMaterializationSession s 'AppleCandidatePrepared ->
  Provisioning.ProvisioningSession
    s
    (AppleMaterializationSession s 'ApplePayloadWritten)
writeAppleMaterializerFixturePayload
  writer
  candidateRoot
  fixtureAction
  AppleCandidatePreparedSession = do
    writeAppleMaterializerFixtureStage writer candidateRoot "payload"
    runAppleMaterializerFixtureAction
      fixtureAction
      FixturePayloadWritten
    pure ApplePayloadWrittenSession

completeAppleMaterializerFixture ::
  Provisioning.EngineWriter w s q ->
  FilePath ->
  AppleMaterializerFixtureAction ->
  AppleMaterializationSession s 'ApplePayloadWritten ->
  Provisioning.ProvisioningSession
    s
    (AppleMaterializationSession s 'AppleMaterializationCompleted)
completeAppleMaterializerFixture
  writer
  candidateRoot
  fixtureAction
  ApplePayloadWrittenSession = do
    writeAppleMaterializerFixtureStage writer candidateRoot "hydrated"
    runAppleMaterializerFixtureAction
      fixtureAction
      FixtureHydrationComplete
    writeAppleMaterializerFixtureStage writer candidateRoot "smoked"
    runAppleMaterializerFixtureAction
      fixtureAction
      FixtureSmokeComplete
    writeAppleMaterializerFixtureStage writer candidateRoot "manifest"
    runAppleMaterializerFixtureAction
      fixtureAction
      FixtureManifestPublished
    writeAppleMaterializerFixtureStage writer candidateRoot "activated"
    runAppleMaterializerFixtureAction
      fixtureAction
      FixtureActivationComplete
    pure AppleMaterializationCompletedSession

cleanupAppleMaterializerFixture ::
  Provisioning.EngineWriter w s q ->
  FilePath ->
  AppleMaterializationSession s 'AppleMaterializationStarted ->
  Provisioning.ProvisioningSession s ()
cleanupAppleMaterializerFixture
  writer
  candidateRoot
  AppleMaterializationStartedSession =
    Provisioning.provisioningRemovePath writer candidateRoot

writeAppleMaterializerFixtureStage ::
  Provisioning.EngineWriter w s q ->
  FilePath ->
  FilePath ->
  Provisioning.ProvisioningSession s ()
writeAppleMaterializerFixtureStage writer candidateRoot stage =
  Provisioning.provisioningWriteFile
    writer
    (candidateRoot </> (stage <> ".fixture"))
    (stage <> "\n")

runAppleMaterializerFixtureAction ::
  AppleMaterializerFixtureAction ->
  AppleMaterializerFixtureBoundary ->
  Provisioning.ProvisioningSession s ()
runAppleMaterializerFixtureAction fixtureAction boundary =
  case fixtureAction of
    FailAtFixtureBoundary target ->
      when (boundary == target) $
        Provisioning.failProvisioningSession
          ("fixture failure after " <> show target)
    PauseAtFixtureBoundary target entered resume ->
      when (boundary == target) $
        Provisioning.pauseProvisioningSessionForTest entered resume

appleMaterializerLockContentionForTest :: Paths -> IO (Bool, Bool, Bool, Bool)
appleMaterializerLockContentionForTest paths = do
  let projectDirectory = pythonProjectDirectory paths AppleSilicon
  environment <- Subprocess.clusterSubprocessEnv paths
  Provisioning.appleProvisioningLockContentionForTest
    paths
    projectDirectory
    environment

retireLegacyAppleMetalRuntimeBridgeForTest :: Paths -> IO ()
retireLegacyAppleMetalRuntimeBridgeForTest paths = do
  let projectDirectory = pythonProjectDirectory paths AppleSilicon
  environment <- Subprocess.clusterSubprocessEnv paths
  Provisioning.withAppleProvisioningSession
    paths
    projectDirectory
    environment
    $ \_projectWriter _generatedBindingsWriter _cacheWriter writer _grant ->
      retireLegacyAppleMetalRuntimeBridge writer paths

retireLegacyAppleMetalRuntimeBridge ::
  Provisioning.EngineWriter w s q ->
  Paths ->
  Provisioning.ProvisioningSession s ()
retireLegacyAppleMetalRuntimeBridge writer paths = do
  let enginesRoot = dataRoot paths </> "engines"
      legacyRoot = enginesRoot </> "apple-metal-runtime-bridge"
  legacyInfo <-
    Provisioning.provisioningLegacyAppleRuntimeBridgeInfo writer
  case legacyInfo of
    Nothing -> pure ()
    Just observedLegacyInfo -> do
      unless
        ( Provisioning.provisioningPathKind observedLegacyInfo
            == Provisioning.ProvisioningDirectory
        )
        ( Provisioning.failProvisioningSession
            ( "legacy Apple native bridge root is not an owned directory: "
                <> legacyRoot
            )
        )
      Provisioning.provisioningRemovePath writer legacyRoot

materializeMetalEngineArtifact ::
  Provisioning.DownloadCacheWriter d s q ->
  Provisioning.EngineWriter w s q ->
  Paths ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  MetalEngineArtifact ->
  Provisioning.ProvisioningSession s ()
materializeMetalEngineArtifact cacheWriter writer =
  materializeMetalEngineArtifactWith
    cacheWriter
    writer
    NoAppleMaterializationHook

materializeMetalEngineArtifactWith ::
  Provisioning.DownloadCacheWriter d s q ->
  Provisioning.EngineWriter w s q ->
  AppleMaterializationHook ->
  Paths ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  MetalEngineArtifact ->
  Provisioning.ProvisioningSession s ()
materializeMetalEngineArtifactWith
  cacheWriter
  writer
  hook
  paths
  grant
  deadlines
  artifact = do
    let installRoot =
          metalEngineInstallRoot paths (metalEngineAdapterId artifact)
        tempRoot = engineArtifactTempRoot installRoot
    Provisioning.bracketProvisioning
      beginAppleMaterialization
      ( cleanupMetalEngineCandidate
          writer
          grant
          deadlines
          tempRoot
          artifact
      )
      ( \started -> do
          prepared <-
            prepareMetalEngineCandidate
              writer
              grant
              deadlines
              installRoot
              tempRoot
              artifact
              started
          payloadWritten <-
            writeMetalEngineCandidatePayload
              writer
              paths
              tempRoot
              artifact
              prepared
          completed <-
            completeMetalEngineCandidate
              cacheWriter
              writer
              hook
              grant
              deadlines
              installRoot
              tempRoot
              artifact
              payloadWritten
          finishAppleMaterialization completed
      )

prepareMetalEngineCandidate ::
  Provisioning.EngineWriter w s q ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  FilePath ->
  FilePath ->
  MetalEngineArtifact ->
  AppleMaterializationSession s 'AppleMaterializationStarted ->
  Provisioning.ProvisioningSession
    s
    (AppleMaterializationSession s 'AppleCandidatePrepared)
prepareMetalEngineCandidate
  writer
  grant
  deadlines
  installRoot
  tempRoot
  artifact
  AppleMaterializationStartedSession = do
    if metalEngineProvisioningAdapter artifact == Provisioning.jvmAdapter
      then do
        mountAbsent <-
          recoverAudiverisMount
            writer
            grant
            deadlines
            tempRoot
        Provisioning.provisioningReconcileArtifactRoot
          writer
          installRoot
        removeRecoveredAudiverisCandidate writer mountAbsent
      else do
        Provisioning.provisioningReconcileArtifactRoot
          writer
          installRoot
        Provisioning.provisioningRemovePath writer tempRoot
    Provisioning.provisioningCreateDirectory writer tempRoot
    pure AppleCandidatePreparedSession

writeMetalEngineCandidatePayload ::
  Provisioning.EngineWriter w s q ->
  Paths ->
  FilePath ->
  MetalEngineArtifact ->
  AppleMaterializationSession s 'AppleCandidatePrepared ->
  Provisioning.ProvisioningSession
    s
    (AppleMaterializationSession s 'ApplePayloadWritten)
writeMetalEngineCandidatePayload
  writer
  paths
  tempRoot
  artifact
  AppleCandidatePreparedSession = do
    writeMetalEngineArtifactPayload
      writer
      paths
      tempRoot
      artifact
    pure ApplePayloadWrittenSession

completeMetalEngineCandidate ::
  Provisioning.DownloadCacheWriter d s q ->
  Provisioning.EngineWriter w s q ->
  AppleMaterializationHook ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  FilePath ->
  FilePath ->
  MetalEngineArtifact ->
  AppleMaterializationSession s 'ApplePayloadWritten ->
  Provisioning.ProvisioningSession
    s
    (AppleMaterializationSession s 'AppleMaterializationCompleted)
completeMetalEngineCandidate
  cacheWriter
  writer
  hook
  grant
  deadlines
  installRoot
  tempRoot
  artifact
  ApplePayloadWrittenSession = do
    hydration <-
      hydrateMetalEngineArtifact
        cacheWriter
        writer
        hook
        grant
        deadlines
        tempRoot
        artifact
    -- Only a Python-backed candidate owns a venv whose launchers and
    -- configuration must be rewritten to the final root before smoke. A
    -- native-binary or Audiveris JVM candidate has no `venv` directory at all,
    -- so relocating one unconditionally fails closed on an artifact that is
    -- correctly hydrated. The hydration witness, not a tolerant filesystem
    -- probe, decides: an absent venv under a Python candidate is still fatal.
    case hydration of
      PythonHydration {} ->
        relocateCandidateVenvInSession writer installRoot tempRoot
      HostBinaryHydration {} -> pure ()
      AudiverisHydration {} -> pure ()
    metadataSeed <-
      collectHydratedMetadataSeed
        writer
        grant
        deadlines
        installRoot
        artifact
        hydration
    let manifestBuilder =
          Provisioning.mkAppleManifestBuilder $
            \runtimeVersion smokeDigest ->
              let metadata =
                    finalizeHydratedMetadata
                      artifact
                      runtimeVersion
                      metadataSeed
               in manifestForHydratedMetalEngineArtifact
                    installRoot
                    artifact
                    (hydratedEngineVersion metadata)
                    (hydratedPythonVersion metadata)
                    (hydratedRuntimeVersion metadata)
                    (hydratedProvenance metadata)
                    smokeDigest
    Provisioning.completeAppleCandidate
      writer
      grant
      (deadlineArtifactSmoke deadlines)
      (metalEngineProvisioningAdapter artifact)
      installRoot
      tempRoot
      manifestBuilder
    pure AppleMaterializationCompletedSession

cleanupMetalEngineCandidate ::
  Provisioning.EngineWriter w s q ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  FilePath ->
  MetalEngineArtifact ->
  AppleMaterializationSession s 'AppleMaterializationStarted ->
  Provisioning.ProvisioningSession s ()
cleanupMetalEngineCandidate
  writer
  grant
  deadlines
  tempRoot
  artifact
  AppleMaterializationStartedSession = do
    cleanupEvidence <-
      if metalEngineProvisioningAdapter artifact == Provisioning.jvmAdapter
        then
          AudiverisCandidateCleanupEvidence
            <$> recoverAudiverisMount
              writer
              grant
              deadlines
              tempRoot
        else pure (OrdinaryCandidateCleanupEvidence tempRoot)
    case cleanupEvidence of
      OrdinaryCandidateCleanupEvidence candidateRoot ->
        Provisioning.provisioningRemovePath writer candidateRoot
      AudiverisCandidateCleanupEvidence mountAbsent ->
        removeRecoveredAudiverisCandidate writer mountAbsent

data AppleCandidateCleanupEvidence s
  = OrdinaryCandidateCleanupEvidence !FilePath
  | AudiverisCandidateCleanupEvidence !(AudiverisMountAbsent s)

type role AppleCandidateCleanupEvidence nominal

writeMetalEngineArtifactPayload ::
  Provisioning.EngineWriter w s q ->
  Paths ->
  FilePath ->
  MetalEngineArtifact ->
  Provisioning.ProvisioningSession s ()
writeMetalEngineArtifactPayload writer paths tempRoot artifact = do
  when
    ( isJust
        ( Provisioning.pythonAdapterForApple
            (metalEngineProvisioningAdapter artifact)
        )
    )
    (writeAppleNativeRunnerLibrary writer paths tempRoot)
  Provisioning.provisioningCreateDirectory writer (tempRoot </> "tmp")
  Provisioning.provisioningCreateDirectory
    writer
    (tempRoot </> "native" </> "lib")
  Provisioning.provisioningCreateDirectory
    writer
    (tempRoot </> "native" </> "libexec")
  Provisioning.provisioningCreateDirectory
    writer
    (tempRoot </> "native" </> "frameworks")
  Provisioning.provisioningWriteFile
    writer
    (tempRoot </> "README.txt")
    ( "Infernix Apple engine artifact root for "
        <> Text.unpack (metalEngineAdapterId artifact)
        <> ". The hydrated payload digest, exact resolved provenance, and closed direct-target "
        <> "contract are recorded in engine-artifact.json.\n"
    )

writeAppleNativeRunnerLibrary ::
  Provisioning.EngineWriter w s q ->
  Paths ->
  FilePath ->
  Provisioning.ProvisioningSession s ()
writeAppleNativeRunnerLibrary =
  Provisioning.provisioningInstallAppleNativeRunnerLibrary

data ArtifactHydration s
  = HostBinaryHydration !(Provisioning.InstalledMachORuntimeClosure s)
  | PythonHydration
      !(Provisioning.CandidatePythonTarget s)
      !(Provisioning.InstalledMachORuntimeClosure s)
  | AudiverisHydration
      !Text
      !Text
      !(Provisioning.InstalledMachORuntimeClosure s)

hydrateMetalEngineArtifact ::
  Provisioning.DownloadCacheWriter d s q ->
  Provisioning.EngineWriter w s q ->
  AppleMaterializationHook ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  FilePath ->
  MetalEngineArtifact ->
  Provisioning.ProvisioningSession s (ArtifactHydration s)
hydrateMetalEngineArtifact
  cacheWriter
  writer
  hook
  grant
  deadlines
  tempRoot
  artifact =
    case Provisioning.pythonAdapterForApple
      (metalEngineProvisioningAdapter artifact) of
      Just pythonAdapter -> do
        resolvedPython <-
          resolveAppleNativePython
            writer
            grant
            deadlines
            tempRoot
            pythonAdapter
        createOutcome <-
          Provisioning.createPythonVenv
            writer
            grant
            (deadlineVenvCreate deadlines)
            resolvedPython
            tempRoot
        _ <- requireProvisioningSuccess "create Apple engine venv" createOutcome
        pythonTarget <-
          Provisioning.materializeCandidatePythonTarget
            writer
            resolvedPython
            tempRoot
        pipOutcome <-
          Provisioning.upgradePinnedPip
            writer
            grant
            (deadlinePipUpgrade deadlines)
            pythonTarget
        _ <- requireProvisioningSuccess "install pinned Apple engine pip" pipOutcome
        requirementsOutcome <-
          Provisioning.installPinnedRequirements
            writer
            grant
            (deadlineRequirementsInstall deadlines)
            pythonTarget
        _ <-
          requireProvisioningSuccess
            "install pinned Apple engine requirements"
            requirementsOutcome
        runtimeClosure <-
          Provisioning.materializeResolvedPythonRuntimeClosure
            writer
            resolvedPython
            pythonTarget
            tempRoot
        pure (PythonHydration pythonTarget runtimeClosure)
      Nothing
        | metalEngineProvisioningAdapter artifact == Provisioning.jvmAdapter -> do
            (dmgDigest, javaVersion) <-
              hydrateAudiverisJvmTool
                cacheWriter
                writer
                hook
                grant
                deadlines
                tempRoot
            runtimeClosure <-
              Provisioning.materializeAudiverisRuntimeClosure writer tempRoot
            pure
              (AudiverisHydration dmgDigest javaVersion runtimeClosure)
        | otherwise ->
            hydrateConfiguredHostBinary
              writer
              grant
              tempRoot
              artifact

hydrateConfiguredHostBinary ::
  Provisioning.EngineWriter w s q ->
  Provisioning.ProvisioningGrant s ->
  FilePath ->
  MetalEngineArtifact ->
  Provisioning.ProvisioningSession s (ArtifactHydration s)
hydrateConfiguredHostBinary writer grant tempRoot artifact = do
  resolvedCli <-
    requireProvisioningResolution
      "resolve configured Apple native CLI"
      =<< Provisioning.resolveHostNativeCli
        grant
        (metalEngineProvisioningAdapter artifact)
  runtimeClosure <-
    Provisioning.materializeResolvedHostNativeCli
      writer
      resolvedCli
      tempRoot
  pure (HostBinaryHydration runtimeClosure)

data MachOFixturePlan = MachOFixturePlan
  { machOFixturePlannedCopies :: ![(FilePath, FilePath)],
    machOFixtureImageCount :: !Int,
    machOFixtureByteCount :: !Integer,
    machOFixtureContextCount :: !Int,
    machOFixtureEdgeCount :: !Integer,
    machOFixturePluginRootCount :: !Int
  }
  deriving (Eq, Show)

inspectMachOFixtureForTest ::
  ByteString.ByteString ->
  Either String ([FilePath], [FilePath])
inspectMachOFixtureForTest =
  Provisioning.inspectMachOFixtureForTest

machOInstallNameTargetForTest ::
  [FilePath] ->
  FilePath ->
  FilePath ->
  IO (Either String FilePath)
machOInstallNameTargetForTest =
  Provisioning.machOInstallNameTargetForTest

shebangBindsHostInstallationForTest :: ByteString.ByteString -> Bool
shebangBindsHostInstallationForTest =
  Provisioning.shebangBindsHostInstallationForTest

supportedMachOMagicForTest :: ByteString.ByteString -> Bool
supportedMachOMagicForTest =
  Provisioning.supportedMachOMagicForTest

resolveMachOPathsFixtureForTest ::
  FilePath ->
  FilePath ->
  [(FilePath, ByteString.ByteString)] ->
  Either String MachOFixturePlan
resolveMachOPathsFixtureForTest candidateRoot executablePath images =
  toMachOFixturePlan
    <$> Provisioning.resolveMachOPathsFixtureForTest
      candidateRoot
      executablePath
      images
  where
    toMachOFixturePlan plan =
      MachOFixturePlan
        { machOFixturePlannedCopies =
            Provisioning.machOFixturePlannedCopies plan,
          machOFixtureImageCount =
            Provisioning.machOFixtureImageCount plan,
          machOFixtureByteCount =
            Provisioning.machOFixtureByteCount plan,
          machOFixtureContextCount =
            Provisioning.machOFixtureContextCount plan,
          machOFixtureEdgeCount =
            Provisioning.machOFixtureEdgeCount plan,
          machOFixturePluginRootCount =
            Provisioning.machOFixturePluginRootCount plan
        }

resolveAppleNativePython ::
  Provisioning.EngineWriter w s q ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  FilePath ->
  Provisioning.ApplePythonAdapterId ->
  Provisioning.ProvisioningSession s (Provisioning.ResolvedPython s)
resolveAppleNativePython
  writer
  grant
  deadlines
  workingDirectory
  pythonAdapter = do
    resolvedPython <-
      requireProvisioningResolution
        ( "resolve exact Python for Apple adapter "
            <> Provisioning.renderApplePythonAdapterId pythonAdapter
        )
        =<< Provisioning.resolvePython grant pythonAdapter
    outcome <-
      Provisioning.probePythonVersion
        writer
        grant
        (deadlinePythonProbe deadlines)
        resolvedPython
        workingDirectory
    _ <-
      requireProvisioningSuccess
        ( "probe exact Python for Apple adapter "
            <> Provisioning.renderApplePythonAdapterId pythonAdapter
        )
        outcome
    pure resolvedPython

hydrateAudiverisJvmTool ::
  Provisioning.DownloadCacheWriter d s q ->
  Provisioning.EngineWriter w s q ->
  AppleMaterializationHook ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  FilePath ->
  Provisioning.ProvisioningSession s (Text, Text)
hydrateAudiverisJvmTool cacheWriter writer hook grant deadlines tempRoot = do
  cachedReceipt <-
    Provisioning.validateAudiverisDmgReceipt cacheWriter
  receipt <-
    case cachedReceipt of
      Just validReceipt -> pure validReceipt
      Nothing ->
        Provisioning.bracketProvisioning
          (Provisioning.prepareAudiverisDmgDownload cacheWriter)
          (\_ -> Provisioning.prepareAudiverisDmgDownload cacheWriter)
          ( \_ -> do
              downloadOutcome <-
                Provisioning.downloadAudiverisDmg
                  cacheWriter
                  grant
                  (deadlineAudiverisDownload deadlines)
              _ <-
                requireProvisioningSuccess
                  "download pinned Audiveris DMG"
                  downloadOutcome
              Provisioning.promoteAudiverisDmgDownload cacheWriter
          )
  staged <-
    Provisioning.stageAudiverisDmgForCandidate
      cacheWriter
      writer
      receipt
      tempRoot
  withAudiverisMountedPayload
    writer
    grant
    deadlines
    tempRoot
    staged
    hook
  bundledJavaVersion <-
    Provisioning.provisioningReadAudiverisBundledJavaVersion writer tempRoot
  pure (Recipe.audiverisDmgDigest, bundledJavaVersion)

data AudiverisMountPhase
  = AudiverisMountPreparedPhase
  | AudiverisMountAttachedPhase !Integer !Integer
  deriving (Eq, Show)

data AudiverisMountActivity = AudiverisMountActivity
  { audiverisActivityOwnerPid :: !Integer,
    audiverisActivityOwnerBirth :: !Text,
    audiverisActivityParentRoot :: !FilePath,
    audiverisActivityMountRoot :: !FilePath,
    audiverisActivityDmgPath :: !FilePath,
    audiverisActivityDmgDigest :: !Text,
    audiverisActivityParentDevice :: !Integer,
    audiverisActivityParentFile :: !Integer,
    audiverisActivityPlaceholderDevice :: !Integer,
    audiverisActivityPlaceholderFile :: !Integer,
    audiverisActivityPhase :: !AudiverisMountPhase
  }
  deriving (Eq, Show)

instance Aeson.ToJSON AudiverisMountActivity where
  toJSON activity =
    Aeson.object
      ( [ "version" Aeson..= (1 :: Int),
          "ownerPid" Aeson..= audiverisActivityOwnerPid activity,
          "ownerBirth" Aeson..= audiverisActivityOwnerBirth activity,
          "parentRoot" Aeson..= audiverisActivityParentRoot activity,
          "mountRoot" Aeson..= audiverisActivityMountRoot activity,
          "dmgPath" Aeson..= audiverisActivityDmgPath activity,
          "dmgDigest" Aeson..= audiverisActivityDmgDigest activity,
          "parentDevice" Aeson..= audiverisActivityParentDevice activity,
          "parentFile" Aeson..= audiverisActivityParentFile activity,
          "placeholderDevice"
            Aeson..= audiverisActivityPlaceholderDevice activity,
          "placeholderFile"
            Aeson..= audiverisActivityPlaceholderFile activity
        ]
          <> phaseFields (audiverisActivityPhase activity)
      )
    where
      phaseFields phase =
        case phase of
          AudiverisMountPreparedPhase ->
            ["phase" Aeson..= ("prepared" :: Text)]
          AudiverisMountAttachedPhase mountDevice mountFile ->
            [ "phase" Aeson..= ("attached" :: Text),
              "mountDevice" Aeson..= mountDevice,
              "mountFile" Aeson..= mountFile
            ]

instance Aeson.FromJSON AudiverisMountActivity where
  parseJSON =
    Aeson.withObject "AudiverisMountActivity" $ \value -> do
      version <- value Aeson..: "version"
      unless
        (version == (1 :: Int))
        (fail "unsupported Audiveris mount activity version")
      phaseName <- value Aeson..: "phase"
      phase <-
        case (phaseName :: Text) of
          "prepared" -> pure AudiverisMountPreparedPhase
          "attached" ->
            AudiverisMountAttachedPhase
              <$> value Aeson..: "mountDevice"
              <*> value Aeson..: "mountFile"
          _ -> fail "unsupported Audiveris mount activity phase"
      AudiverisMountActivity
        <$> value Aeson..: "ownerPid"
        <*> value Aeson..: "ownerBirth"
        <*> value Aeson..: "parentRoot"
        <*> value Aeson..: "mountRoot"
        <*> value Aeson..: "dmgPath"
        <*> value Aeson..: "dmgDigest"
        <*> value Aeson..: "parentDevice"
        <*> value Aeson..: "parentFile"
        <*> value Aeson..: "placeholderDevice"
        <*> value Aeson..: "placeholderFile"
        <*> pure phase

data AudiverisMountPrepared w s q where
  AudiverisMountPrepared ::
    Provisioning.DurableProvisioningRecord s ->
    AudiverisMountActivity ->
    Provisioning.StagedAudiverisDmg w s q ->
    AudiverisMountPrepared w s q

type role AudiverisMountPrepared nominal nominal nominal

data AudiverisMountEvidence s where
  AudiverisMountEvidence ::
    Provisioning.DurableProvisioningRecord s ->
    AudiverisMountActivity ->
    AudiverisMountEvidence s

type role AudiverisMountEvidence nominal

data AudiverisPayloadCopied s where
  AudiverisPayloadCopied ::
    Provisioning.DurableProvisioningRecord s ->
    AudiverisMountActivity ->
    AudiverisPayloadCopied s

type role AudiverisPayloadCopied nominal

newtype AudiverisMountAbsent s
  = AudiverisMountAbsent FilePath

type role AudiverisMountAbsent nominal

audiverisMountRoot :: FilePath -> FilePath
audiverisMountRoot parentRoot =
  parentRoot </> "tmp" </> "audiveris-dmg"

audiverisMountActivityPath :: FilePath -> FilePath
audiverisMountActivityPath parentRoot =
  parentRoot </> ".audiveris-mount-activity.json"

audiverisExpectedDmgPath :: FilePath -> FilePath
audiverisExpectedDmgPath parentRoot =
  parentRoot
    </> "tmp"
    </> Provisioning.audiverisPinnedDmgFileName

data AudiverisMountRecoveryFixture
  = RecoverPreparedMountRecord
  | RecoverAttachedAlreadyDetachedRecord
  | RejectChangedMountPlaceholder
  deriving (Bounded, Enum, Eq, Show)

audiverisMountRecoveryFixtureRootForTest ::
  Paths ->
  AudiverisMountRecoveryFixture ->
  FilePath
audiverisMountRecoveryFixtureRootForTest paths fixture =
  dataRoot paths
    </> "engines"
    </> (".audiveris-mount-recovery-" <> fixtureSlug fixture <> ".tmp")
  where
    fixtureSlug selected =
      case selected of
        RecoverPreparedMountRecord -> "prepared"
        RecoverAttachedAlreadyDetachedRecord -> "attached-detached"
        RejectChangedMountPlaceholder -> "changed-placeholder"

recoverAudiverisMountRecordFixtureForTest ::
  Paths ->
  AudiverisMountRecoveryFixture ->
  IO ()
recoverAudiverisMountRecordFixtureForTest paths fixture = do
  let projectDirectory = pythonProjectDirectory paths AppleSilicon
      parentRoot =
        audiverisMountRecoveryFixtureRootForTest paths fixture
      mountRoot = audiverisMountRoot parentRoot
      activityPath = audiverisMountActivityPath parentRoot
  environment <- Subprocess.clusterSubprocessEnv paths
  deadlines <- appleProvisioningDeadlines
  Provisioning.withAppleProvisioningSession
    paths
    projectDirectory
    environment
    $ \_projectWriter _generatedBindingsWriter _cacheWriter writer grant -> do
      fixtureInfo <-
        Provisioning.provisioningAudiverisCandidateInfo writer parentRoot
      when (isJust fixtureInfo) $
        Provisioning.failProvisioningSession
          ("Audiveris recovery fixture already exists: " <> parentRoot)
      Provisioning.provisioningCreateDirectory writer mountRoot
      parentInfo <- requireAudiverisCandidateInfo writer parentRoot
      mountInfo <- requireAudiverisMountInfo writer parentRoot
      owner <- Provisioning.provisioningCurrentProcessIdentity
      let parentDevice =
            fromIntegral
              (Provisioning.provisioningPathDeviceId parentInfo)
          placeholderFile =
            fromIntegral
              (Provisioning.provisioningPathFileId mountInfo)
          phase =
            case fixture of
              RecoverPreparedMountRecord ->
                AudiverisMountPreparedPhase
              RecoverAttachedAlreadyDetachedRecord ->
                AudiverisMountAttachedPhase
                  (parentDevice + 1)
                  (placeholderFile + 1)
              RejectChangedMountPlaceholder ->
                AudiverisMountAttachedPhase
                  (parentDevice + 1)
                  (placeholderFile + 1)
          activity =
            AudiverisMountActivity
              { audiverisActivityOwnerPid =
                  Provisioning.provisioningProcessIdentityPid owner,
                audiverisActivityOwnerBirth =
                  Provisioning.provisioningProcessIdentityBirth owner,
                audiverisActivityParentRoot = parentRoot,
                audiverisActivityMountRoot = mountRoot,
                audiverisActivityDmgPath =
                  audiverisExpectedDmgPath parentRoot,
                audiverisActivityDmgDigest =
                  Recipe.audiverisDmgDigest,
                audiverisActivityParentDevice = parentDevice,
                audiverisActivityParentFile =
                  fromIntegral
                    (Provisioning.provisioningPathFileId parentInfo),
                audiverisActivityPlaceholderDevice =
                  fromIntegral
                    (Provisioning.provisioningPathDeviceId mountInfo),
                audiverisActivityPlaceholderFile = placeholderFile,
                audiverisActivityPhase = phase
              }
      requireValidAudiverisMountActivity activity
      _ <-
        Provisioning.provisioningPublishDurableRecord
          writer
          activityPath
          (encodeAudiverisMountActivity activity)
      when (fixture == RejectChangedMountPlaceholder) $ do
        Provisioning.provisioningRemovePath writer mountRoot
        Provisioning.provisioningWriteFile
          writer
          mountRoot
          "changed mount placeholder\n"
      mountAbsent <-
        recoverAudiverisMount writer grant deadlines parentRoot
      removeRecoveredAudiverisCandidate writer mountAbsent

withAudiverisMountedPayload ::
  Provisioning.EngineWriter w s q ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  FilePath ->
  Provisioning.StagedAudiverisDmg w s q ->
  AppleMaterializationHook ->
  Provisioning.ProvisioningSession s ()
withAudiverisMountedPayload
  writer
  grant
  deadlines
  parentRoot
  staged
  hook =
    Provisioning.bracketProvisioning
      (pure ())
      ( \() -> do
          AudiverisMountAbsent recoveredParent <-
            recoverAudiverisMount
              writer
              grant
              deadlines
              parentRoot
          unless (recoveredParent == parentRoot) $
            Provisioning.failProvisioningSession
              "Audiveris mount recovery returned evidence for another candidate"
          removeAudiverisMountPlaceholder
            writer
            parentRoot
            (audiverisMountRoot parentRoot)
            Nothing
          Provisioning.provisioningRetireAudiverisStaging
            writer
            parentRoot
      )
      ( \() -> do
          prepared <-
            prepareAudiverisMount
              writer
              grant
              deadlines
              parentRoot
              staged
          mounted <-
            attachAudiverisPreparedMount
              writer
              grant
              deadlines
              prepared
          runAudiverisMountHook hook
          copied <-
            copyAudiverisMountedPayload
              writer
              mounted
          releaseAudiverisMountedPayload
            writer
            grant
            deadlines
            copied
      )

prepareAudiverisMount ::
  Provisioning.EngineWriter w s q ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  FilePath ->
  Provisioning.StagedAudiverisDmg w s q ->
  Provisioning.ProvisioningSession s (AudiverisMountPrepared w s q)
prepareAudiverisMount
  writer
  grant
  deadlines
  parentRoot
  staged = do
    let mountRoot = audiverisMountRoot parentRoot
        dmgPath = audiverisExpectedDmgPath parentRoot
        activityPath = audiverisMountActivityPath parentRoot
    requireExactAudiverisPaths parentRoot mountRoot dmgPath
    _ <- recoverAudiverisMount writer grant deadlines parentRoot
    removeAudiverisMountPlaceholder writer parentRoot mountRoot Nothing
    Provisioning.provisioningCreateDirectory writer mountRoot
    parentInfo <- requireAudiverisCandidateInfo writer parentRoot
    mountInfo <- requireAudiverisMountInfo writer parentRoot
    mounted <-
      requireProvisioningResolution
        "classify prepared Audiveris mount placeholder"
        (audiverisMountRecoveryRequiredForTest parentInfo mountInfo)
    when mounted $
      Provisioning.failProvisioningSession
        "new Audiveris mount placeholder unexpectedly names a distinct device"
    owner <- Provisioning.provisioningCurrentProcessIdentity
    let activity =
          AudiverisMountActivity
            { audiverisActivityOwnerPid =
                Provisioning.provisioningProcessIdentityPid owner,
              audiverisActivityOwnerBirth =
                Provisioning.provisioningProcessIdentityBirth owner,
              audiverisActivityParentRoot = parentRoot,
              audiverisActivityMountRoot = mountRoot,
              audiverisActivityDmgPath = dmgPath,
              audiverisActivityDmgDigest = Recipe.audiverisDmgDigest,
              audiverisActivityParentDevice =
                fromIntegral
                  (Provisioning.provisioningPathDeviceId parentInfo),
              audiverisActivityParentFile =
                fromIntegral
                  (Provisioning.provisioningPathFileId parentInfo),
              audiverisActivityPlaceholderDevice =
                fromIntegral
                  (Provisioning.provisioningPathDeviceId mountInfo),
              audiverisActivityPlaceholderFile =
                fromIntegral
                  (Provisioning.provisioningPathFileId mountInfo),
              audiverisActivityPhase = AudiverisMountPreparedPhase
            }
    requireValidAudiverisMountActivity activity
    record <-
      Provisioning.provisioningPublishDurableRecord
        writer
        activityPath
        (encodeAudiverisMountActivity activity)
    pure (AudiverisMountPrepared record activity staged)

attachAudiverisPreparedMount ::
  Provisioning.EngineWriter w s q ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  AudiverisMountPrepared w s q ->
  Provisioning.ProvisioningSession s (AudiverisMountEvidence s)
attachAudiverisPreparedMount
  writer
  grant
  deadlines
  (AudiverisMountPrepared record activity staged) =
    Provisioning.commitAfterInterruptibleProvisioning
      ( do
          revalidateAudiverisPreparedMount writer activity
          Provisioning.mountAudiverisDmg
            writer
            grant
            (deadlineAudiverisMount deadlines)
            staged
      )
      ( \mountOutcome -> do
          _ <-
            requireProvisioningSuccess
              "mount pinned Audiveris DMG"
              mountOutcome
          revalidateAudiverisPreparedPublication writer activity
          parentInfo <-
            requireAudiverisCandidateInfo
              writer
              (audiverisActivityParentRoot activity)
          mountInfo <-
            requireAudiverisMountInfo
              writer
              (audiverisActivityParentRoot activity)
          requireExactParentIdentity activity parentInfo
          mounted <-
            requireProvisioningResolution
              "validate attached Audiveris mount device"
              (audiverisMountRecoveryRequiredForTest parentInfo mountInfo)
          unless mounted $
            Provisioning.failProvisioningSession
              ( "Audiveris mount operation exited successfully without a distinct mounted filesystem at "
                  <> audiverisActivityMountRoot activity
              )
          let attached =
                activity
                  { audiverisActivityPhase =
                      AudiverisMountAttachedPhase
                        ( fromIntegral
                            (Provisioning.provisioningPathDeviceId mountInfo)
                        )
                        ( fromIntegral
                            (Provisioning.provisioningPathFileId mountInfo)
                        )
                  }
          attachedRecord <-
            Provisioning.provisioningReplaceDurableRecord
              writer
              record
              (encodeAudiverisMountActivity attached)
          pure (AudiverisMountEvidence attachedRecord attached)
      )

copyAudiverisMountedPayload ::
  Provisioning.EngineWriter w s q ->
  AudiverisMountEvidence s ->
  Provisioning.ProvisioningSession s (AudiverisPayloadCopied s)
copyAudiverisMountedPayload
  writer
  (AudiverisMountEvidence record activity) = do
    revalidateAudiverisMountedPayload writer activity
    _ <-
      Provisioning.provisioningCopyAudiverisMountedApp
        writer
        (audiverisActivityParentRoot activity)
    revalidateAudiverisMountedPayload writer activity
    pure (AudiverisPayloadCopied record activity)

releaseAudiverisMountedPayload ::
  Provisioning.EngineWriter w s q ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  AudiverisPayloadCopied s ->
  Provisioning.ProvisioningSession s ()
releaseAudiverisMountedPayload
  writer
  grant
  deadlines
  (AudiverisPayloadCopied record activity) = do
    revalidateAudiverisMountedPayload writer activity
    detachAudiverisExactMountAndRetire
      writer
      grant
      deadlines
      record
      activity

revalidateAudiverisPreparedMount ::
  Provisioning.EngineWriter w s q ->
  AudiverisMountActivity ->
  Provisioning.ProvisioningSession s ()
revalidateAudiverisPreparedMount writer activity = do
  revalidateAudiverisPreparedPublication writer activity
  mountInfo <-
    requireAudiverisMountInfo
      writer
      (audiverisActivityParentRoot activity)
  requireExactPlaceholderIdentity activity mountInfo

revalidateAudiverisPreparedPublication ::
  Provisioning.EngineWriter w s q ->
  AudiverisMountActivity ->
  Provisioning.ProvisioningSession s ()
revalidateAudiverisPreparedPublication writer activity = do
  requireCurrentAudiverisOwner activity
  requireExactAudiverisRecord writer activity
  parentInfo <-
    requireAudiverisCandidateInfo
      writer
      (audiverisActivityParentRoot activity)
  requireExactParentIdentity activity parentInfo

revalidateAudiverisMountedPayload ::
  Provisioning.EngineWriter w s q ->
  AudiverisMountActivity ->
  Provisioning.ProvisioningSession s ()
revalidateAudiverisMountedPayload writer activity = do
  requireCurrentAudiverisOwner activity
  requireExactAudiverisRecord writer activity
  parentInfo <-
    requireAudiverisCandidateInfo
      writer
      (audiverisActivityParentRoot activity)
  mountInfo <-
    requireAudiverisMountInfo
      writer
      (audiverisActivityParentRoot activity)
  requireExactParentIdentity activity parentInfo
  requireExactAttachedIdentity activity mountInfo

recoverAudiverisMount ::
  Provisioning.EngineWriter w s q ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  FilePath ->
  Provisioning.ProvisioningSession s (AudiverisMountAbsent s)
recoverAudiverisMount writer grant deadlines parentRoot = do
  let mountRoot = audiverisMountRoot parentRoot
      activityPath = audiverisMountActivityPath parentRoot
      dmgPath = audiverisExpectedDmgPath parentRoot
  requireExactAudiverisPaths parentRoot mountRoot dmgPath
  recovered <-
    Provisioning.provisioningRecoverDurableRecord writer activityPath
  case recovered of
    Nothing ->
      rejectUnrecordedAudiverisMount writer parentRoot mountRoot
    Just (contents, record) -> do
      activity <-
        requireProvisioningResolution
          "decode durable Audiveris mount activity"
          (decodeAudiverisMountActivity contents)
      requireValidAudiverisMountActivity activity
      unless
        ( audiverisActivityParentRoot activity == parentRoot
            && audiverisActivityMountRoot activity == mountRoot
            && audiverisActivityDmgPath activity == dmgPath
        )
        ( Provisioning.failProvisioningSession
            "durable Audiveris mount activity names an unexpected fixed path"
        )
      requireRecoverableAudiverisOwner activity
      parentInfo <- requireAudiverisCandidateInfo writer parentRoot
      mountInfo <- requireAudiverisMountInfo writer parentRoot
      requireExactParentIdentity activity parentInfo
      case audiverisActivityPhase activity of
        AudiverisMountPreparedPhase ->
          recoverPreparedAudiverisMount
            writer
            grant
            deadlines
            record
            activity
            mountInfo
        AudiverisMountAttachedPhase _ _
          | isExactPlaceholderIdentity activity mountInfo ->
              Provisioning.provisioningRetireDurableRecord writer record
          | otherwise -> do
              requireExactAttachedIdentity activity mountInfo
              detachAudiverisExactMountAndRetire
                writer
                grant
                deadlines
                record
                activity
  proveAudiverisMountDeviceAbsent writer parentRoot mountRoot
  pure (AudiverisMountAbsent parentRoot)

removeRecoveredAudiverisCandidate ::
  Provisioning.EngineWriter w s q ->
  AudiverisMountAbsent s ->
  Provisioning.ProvisioningSession s ()
removeRecoveredAudiverisCandidate writer (AudiverisMountAbsent parentRoot) =
  Provisioning.provisioningRemovePath writer parentRoot

recoverPreparedAudiverisMount ::
  Provisioning.EngineWriter w s q ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  Provisioning.DurableProvisioningRecord s ->
  AudiverisMountActivity ->
  Provisioning.ProvisioningPathInfo ->
  Provisioning.ProvisioningSession s ()
recoverPreparedAudiverisMount writer grant deadlines record activity mountInfo
  | isExactPlaceholderIdentity activity mountInfo =
      Provisioning.provisioningRetireDurableRecord writer record
  | fromIntegral (Provisioning.provisioningPathDeviceId mountInfo)
      /= audiverisActivityParentDevice activity = do
      let recoveredActivity =
            activity
              { audiverisActivityPhase =
                  AudiverisMountAttachedPhase
                    ( fromIntegral
                        (Provisioning.provisioningPathDeviceId mountInfo)
                    )
                    ( fromIntegral
                        (Provisioning.provisioningPathFileId mountInfo)
                    )
              }
      detachAudiverisExactMountAndRetire
        writer
        grant
        deadlines
        record
        recoveredActivity
  | otherwise =
      Provisioning.failProvisioningSession
        "prepared Audiveris mountpoint changed identity without naming a distinct mounted device"

detachAudiverisExactMountAndRetire ::
  Provisioning.EngineWriter w s q ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  Provisioning.DurableProvisioningRecord s ->
  AudiverisMountActivity ->
  Provisioning.ProvisioningSession s ()
detachAudiverisExactMountAndRetire writer grant deadlines record activity = do
  mountInfo <-
    requireAudiverisMountInfo
      writer
      (audiverisActivityParentRoot activity)
  requireExactAttachedIdentity activity mountInfo
  Provisioning.commitAfterInterruptibleProvisioning
    ( Provisioning.detachAudiverisDmg
        writer
        grant
        (deadlineAudiverisMount deadlines)
        (audiverisActivityParentRoot activity)
    )
    ( \detachOutcome -> do
        _ <-
          requireProvisioningSuccess
            "detach pinned Audiveris DMG"
            detachOutcome
        detachedInfo <-
          requireAudiverisMountInfo
            writer
            (audiverisActivityParentRoot activity)
        requireExactPlaceholderIdentity activity detachedInfo
        Provisioning.provisioningRetireDurableRecord writer record
    )

removeAudiverisMountPlaceholder ::
  Provisioning.EngineWriter w s q ->
  FilePath ->
  FilePath ->
  Maybe AudiverisMountActivity ->
  Provisioning.ProvisioningSession s ()
removeAudiverisMountPlaceholder writer parentRoot mountRoot expectedActivity = do
  unless (mountRoot == audiverisMountRoot parentRoot) $
    Provisioning.failProvisioningSession
      "Audiveris mount placeholder is not the fixed candidate child"
  mountInfoMaybe <-
    Provisioning.provisioningAudiverisMountInfo writer parentRoot
  case mountInfoMaybe of
    Nothing -> pure ()
    Just mountInfo -> do
      parentInfo <- requireAudiverisCandidateInfo writer parentRoot
      mounted <-
        requireProvisioningResolution
          "classify Audiveris mount placeholder before removal"
          (audiverisMountRecoveryRequiredForTest parentInfo mountInfo)
      when mounted $
        Provisioning.failProvisioningSession
          "refusing to remove an Audiveris mountpoint that still names a distinct device"
      case expectedActivity of
        Nothing -> pure ()
        Just activity -> do
          requireExactParentIdentity activity parentInfo
          requireExactPlaceholderIdentity activity mountInfo
      Provisioning.provisioningRemovePath writer mountRoot

rejectUnrecordedAudiverisMount ::
  Provisioning.EngineWriter w s q ->
  FilePath ->
  FilePath ->
  Provisioning.ProvisioningSession s ()
rejectUnrecordedAudiverisMount =
  proveAudiverisMountDeviceAbsent

proveAudiverisMountDeviceAbsent ::
  Provisioning.EngineWriter w s q ->
  FilePath ->
  FilePath ->
  Provisioning.ProvisioningSession s ()
proveAudiverisMountDeviceAbsent writer parentRoot mountRoot = do
  unless (mountRoot == audiverisMountRoot parentRoot) $
    Provisioning.failProvisioningSession
      "Audiveris mount proof is not scoped to the fixed candidate child"
  parentInfoMaybe <-
    Provisioning.provisioningAudiverisCandidateInfo writer parentRoot
  mountInfoMaybe <-
    Provisioning.provisioningAudiverisMountInfo writer parentRoot
  when (isJust mountInfoMaybe && isNothing parentInfoMaybe) $
    Provisioning.failProvisioningSession
      "the Audiveris private mount path exists without its candidate parent"
  case parentInfoMaybe of
    Nothing -> pure ()
    Just parentInfo -> do
      unless
        ( Provisioning.provisioningPathKind parentInfo
            == Provisioning.ProvisioningDirectory
        )
        $ Provisioning.failProvisioningSession
          "the Audiveris recovery parent is not an owned directory"
      case mountInfoMaybe of
        Nothing -> pure ()
        Just mountInfo -> do
          mounted <-
            requireProvisioningResolution
              "prove the Audiveris private mount device absent"
              (audiverisMountRecoveryRequiredForTest parentInfo mountInfo)
          when mounted $
            Provisioning.failProvisioningSession
              "a distinct Audiveris mount exists without durable exact activity evidence"

requireAudiverisCandidateInfo ::
  Provisioning.EngineWriter w s q ->
  FilePath ->
  Provisioning.ProvisioningSession s Provisioning.ProvisioningPathInfo
requireAudiverisCandidateInfo writer parentRoot = do
  observed <-
    Provisioning.provisioningAudiverisCandidateInfo writer parentRoot
  maybe
    ( Provisioning.failProvisioningSession
        "the fixed Audiveris candidate root is absent"
    )
    pure
    observed

requireAudiverisMountInfo ::
  Provisioning.EngineWriter w s q ->
  FilePath ->
  Provisioning.ProvisioningSession s Provisioning.ProvisioningPathInfo
requireAudiverisMountInfo writer parentRoot = do
  observed <-
    Provisioning.provisioningAudiverisMountInfo writer parentRoot
  maybe
    ( Provisioning.failProvisioningSession
        "the fixed Audiveris private mount is absent"
    )
    pure
    observed

requireExactAudiverisPaths ::
  FilePath ->
  FilePath ->
  FilePath ->
  Provisioning.ProvisioningSession s ()
requireExactAudiverisPaths parentRoot mountRoot dmgPath =
  requireProvisioningResolution
    "validate fixed Audiveris materialization paths"
    ( if
        | any
            (\path -> not (isAbsolute path) || normalise path /= path)
            [parentRoot, mountRoot, dmgPath] ->
            Left "Audiveris materialization paths must be normalized and absolute"
        | mountRoot /= audiverisMountRoot parentRoot ->
            Left "Audiveris mountpoint is not the fixed private candidate path"
        | dmgPath /= audiverisExpectedDmgPath parentRoot ->
            Left "Audiveris image is not the fixed candidate-local staged path"
        | otherwise -> Right ()
    )

requireValidAudiverisMountActivity ::
  AudiverisMountActivity ->
  Provisioning.ProvisioningSession s ()
requireValidAudiverisMountActivity activity =
  requireProvisioningResolution
    "validate durable Audiveris mount activity"
    (validateAudiverisMountActivity activity)

validateAudiverisMountActivity ::
  AudiverisMountActivity ->
  Either String ()
validateAudiverisMountActivity activity
  | audiverisActivityOwnerPid activity <= 0 =
      Left "Audiveris mount owner PID is invalid"
  | Text.null (audiverisActivityOwnerBirth activity) =
      Left "Audiveris mount owner birth identity is empty"
  | any
      (\path -> not (isAbsolute path) || normalise path /= path)
      [ audiverisActivityParentRoot activity,
        audiverisActivityMountRoot activity,
        audiverisActivityDmgPath activity
      ] =
      Left "Audiveris mount activity paths are not normalized and absolute"
  | audiverisActivityMountRoot activity
      /= audiverisMountRoot (audiverisActivityParentRoot activity) =
      Left "Audiveris mount activity names a non-fixed mountpoint"
  | audiverisActivityDmgPath activity
      /= audiverisExpectedDmgPath (audiverisActivityParentRoot activity) =
      Left "Audiveris mount activity names a non-fixed image path"
  | audiverisActivityDmgDigest activity /= Recipe.audiverisDmgDigest =
      Left "Audiveris mount activity carries the wrong pinned image digest"
  | any
      (<= 0)
      [ audiverisActivityParentFile activity,
        audiverisActivityPlaceholderFile activity
      ] =
      Left "Audiveris mount activity carries an invalid inode identity"
  | audiverisActivityPlaceholderDevice activity
      /= audiverisActivityParentDevice activity =
      Left "Audiveris mount placeholder was not on the candidate filesystem"
  | otherwise =
      case audiverisActivityPhase activity of
        AudiverisMountPreparedPhase -> Right ()
        AudiverisMountAttachedPhase mountDevice mountFile
          | mountDevice == audiverisActivityParentDevice activity ->
              Left "attached Audiveris device equals the candidate device"
          | mountFile <= 0 ->
              Left "attached Audiveris mount carries an invalid inode"
          | otherwise -> Right ()

requireExactAudiverisRecord ::
  Provisioning.EngineWriter w s q ->
  AudiverisMountActivity ->
  Provisioning.ProvisioningSession s ()
requireExactAudiverisRecord writer activity = do
  contents <-
    Provisioning.provisioningReadAudiverisActivity
      writer
      (audiverisActivityParentRoot activity)
  observed <-
    requireProvisioningResolution
      "decode current Audiveris mount activity"
      (decodeAudiverisMountActivity contents)
  unless (observed == activity) $
    Provisioning.failProvisioningSession
      "durable Audiveris mount activity changed after evidence was minted"

requireCurrentAudiverisOwner ::
  AudiverisMountActivity ->
  Provisioning.ProvisioningSession s ()
requireCurrentAudiverisOwner activity = do
  current <- Provisioning.provisioningCurrentProcessIdentity
  unless
    ( Provisioning.provisioningProcessIdentityPid current
        == audiverisActivityOwnerPid activity
        && Provisioning.provisioningProcessIdentityBirth current
          == audiverisActivityOwnerBirth activity
    )
    ( Provisioning.failProvisioningSession
        "current process does not own the exact Audiveris mount activity"
    )

requireRecoverableAudiverisOwner ::
  AudiverisMountActivity ->
  Provisioning.ProvisioningSession s ()
requireRecoverableAudiverisOwner activity = do
  exactOwnerAbsent <-
    requireProvisioningResolution
      "observe exact Audiveris mount owner"
      =<< Provisioning.provisioningExactProcessIdentityAbsent
        (audiverisActivityOwnerPid activity)
        (audiverisActivityOwnerBirth activity)
  if exactOwnerAbsent
    then pure ()
    else requireCurrentAudiverisOwner activity

requireExactParentIdentity ::
  AudiverisMountActivity ->
  Provisioning.ProvisioningPathInfo ->
  Provisioning.ProvisioningSession s ()
requireExactParentIdentity activity parentInfo =
  unless
    ( Provisioning.provisioningPathKind parentInfo
        == Provisioning.ProvisioningDirectory
        && observedPathIdentity activity parentInfo
          == parentPathIdentity activity
    )
    ( Provisioning.failProvisioningSession
        "Audiveris candidate parent identity changed"
    )

requireExactPlaceholderIdentity ::
  AudiverisMountActivity ->
  Provisioning.ProvisioningPathInfo ->
  Provisioning.ProvisioningSession s ()
requireExactPlaceholderIdentity activity mountInfo =
  unless
    (isExactPlaceholderIdentity activity mountInfo)
    ( Provisioning.failProvisioningSession
        "Audiveris mount placeholder identity was not restored"
    )

isExactPlaceholderIdentity ::
  AudiverisMountActivity ->
  Provisioning.ProvisioningPathInfo ->
  Bool
isExactPlaceholderIdentity activity mountInfo =
  Provisioning.provisioningPathKind mountInfo
    == Provisioning.ProvisioningDirectory
    && observedPathIdentity activity mountInfo
      == placeholderPathIdentity activity

requireExactAttachedIdentity ::
  AudiverisMountActivity ->
  Provisioning.ProvisioningPathInfo ->
  Provisioning.ProvisioningSession s ()
requireExactAttachedIdentity activity mountInfo =
  case audiverisActivityPhase activity of
    AudiverisMountPreparedPhase ->
      Provisioning.failProvisioningSession
        "prepared Audiveris activity cannot authorize mounted access"
    AudiverisMountAttachedPhase mountDevice mountFile ->
      unless
        ( Provisioning.provisioningPathKind mountInfo
            == Provisioning.ProvisioningDirectory
            && observedPathIdentity activity mountInfo
              == (mountDevice, mountFile)
        )
        ( Provisioning.failProvisioningSession
            "attached Audiveris mount identity changed"
        )

observedPathIdentity ::
  AudiverisMountActivity ->
  Provisioning.ProvisioningPathInfo ->
  (Integer, Integer)
observedPathIdentity _activity info =
  ( fromIntegral (Provisioning.provisioningPathDeviceId info),
    fromIntegral (Provisioning.provisioningPathFileId info)
  )

parentPathIdentity :: AudiverisMountActivity -> (Integer, Integer)
parentPathIdentity activity =
  ( audiverisActivityParentDevice activity,
    audiverisActivityParentFile activity
  )

placeholderPathIdentity :: AudiverisMountActivity -> (Integer, Integer)
placeholderPathIdentity activity =
  ( audiverisActivityPlaceholderDevice activity,
    audiverisActivityPlaceholderFile activity
  )

encodeAudiverisMountActivity ::
  AudiverisMountActivity ->
  ByteString.ByteString
encodeAudiverisMountActivity =
  LazyByteString.toStrict . Aeson.encode

decodeAudiverisMountActivity ::
  ByteString.ByteString ->
  Either String AudiverisMountActivity
decodeAudiverisMountActivity =
  Aeson.eitherDecodeStrict'

audiverisMountRecoveryRequiredForTest ::
  Provisioning.ProvisioningPathInfo ->
  Provisioning.ProvisioningPathInfo ->
  Either String Bool
audiverisMountRecoveryRequiredForTest parentInfo mountInfo
  | Provisioning.provisioningPathKind parentInfo
      /= Provisioning.ProvisioningDirectory =
      Left "Audiveris recovery parent is not an owned directory"
  | Provisioning.provisioningPathKind mountInfo
      /= Provisioning.ProvisioningDirectory =
      Left "Audiveris recovery mount is not an owned directory"
  | otherwise =
      Right
        ( Provisioning.provisioningPathDeviceId parentInfo
            /= Provisioning.provisioningPathDeviceId mountInfo
        )

data HydratedMetadata = HydratedMetadata
  { hydratedEngineVersion :: !Text,
    hydratedPythonVersion :: !(Maybe Text),
    hydratedRuntimeVersion :: !Text,
    hydratedProvenance :: ![ResolvedArtifactProvenance]
  }

data HydratedMetadataSeed
  = PythonHydratedMetadataSeed
      !Text
      !Text
      ![ResolvedArtifactProvenance]
  | AudiverisHydratedMetadataSeed
      !Text
      ![ResolvedArtifactProvenance]
  | HostBinaryHydratedMetadataSeed
      ![ResolvedArtifactProvenance]

collectHydratedMetadataSeed ::
  Provisioning.EngineWriter w s q ->
  Provisioning.ProvisioningGrant s ->
  AppleProvisioningDeadlines ->
  FilePath ->
  MetalEngineArtifact ->
  ArtifactHydration s ->
  Provisioning.ProvisioningSession s HydratedMetadataSeed
collectHydratedMetadataSeed
  writer
  grant
  deadlines
  installRoot
  artifact
  hydration =
    case hydration of
      PythonHydration pythonTarget runtimeClosure -> do
        let pythonAdapter =
              Provisioning.candidatePythonTargetAdapter pythonTarget
        pythonOutcome <-
          Provisioning.queryPythonVersion
            writer
            grant
            (deadlineProvenanceQuery deadlines)
            pythonTarget
        pythonVersion <-
          requireNonemptyOutput "Apple engine Python version"
            =<< requireProvisioningSuccess
              "query Apple engine Python version"
              pythonOutcome
        provenanceOutcome <-
          Provisioning.queryPythonProvenance
            writer
            grant
            (deadlineProvenanceQuery deadlines)
            pythonTarget
        frozenPackages <-
          requireProvisioningSuccess
            "query Apple engine package provenance"
            provenanceOutcome
        packageProvenance <-
          requireProvisioningResolution
            "parse Apple engine Python provenance"
            (parseResolvedPythonProvenance frozenPackages)
        engineVersion <-
          requireProvisioningResolution
            "resolve primary Apple engine package version"
            (primaryPythonEngineVersion pythonAdapter packageProvenance)
        let pythonVersionText = Text.strip (Text.pack pythonVersion)
            provenance =
              packageProvenance
                <> installedRuntimeClosureProvenance
                  (metalEngineAdapterId artifact)
                  runtimeClosure
                <> [ ResolvedArtifactProvenance
                       "python"
                       pythonVersionText
                       ( Text.pack
                           ( installRoot
                               </> Provisioning.candidatePythonTargetRelativePath
                                 pythonTarget
                           )
                       )
                   ]
        pure
          (PythonHydratedMetadataSeed engineVersion pythonVersionText provenance)
      AudiverisHydration dmgDigest bundledJavaVersion runtimeClosure ->
        pure
          ( AudiverisHydratedMetadataSeed
              bundledJavaVersion
              ( installedRuntimeClosureProvenance
                  (metalEngineAdapterId artifact)
                  runtimeClosure
                  <> [ ResolvedArtifactProvenance
                         "Audiveris"
                         (Text.pack Provisioning.audiverisPinnedVersion)
                         ( Text.pack Provisioning.audiverisPinnedDmgUrl
                             <> "#"
                             <> dmgDigest
                         ),
                       ResolvedArtifactProvenance
                         "Audiveris-bundled-JVM"
                         bundledJavaVersion
                         ( Text.pack
                             ( installRoot
                                 </> "Audiveris.app"
                                 </> "Contents"
                                 </> "runtime"
                                 </> "Contents"
                                 </> "Home"
                                 </> "release"
                             )
                         )
                     ]
              )
          )
      HostBinaryHydration runtimeClosure ->
        pure
          ( HostBinaryHydratedMetadataSeed
              ( installedRuntimeClosureProvenance
                  (metalEngineAdapterId artifact)
                  runtimeClosure
              )
          )

finalizeHydratedMetadata ::
  MetalEngineArtifact ->
  Provisioning.AppleRuntimeVersion ->
  HydratedMetadataSeed ->
  HydratedMetadata
finalizeHydratedMetadata artifact runtimeVersion =
  finalizeSeed
  where
    smokeVersion =
      Provisioning.appleRuntimeVersionText runtimeVersion
    withSmokeProvenance provenance =
      provenance <> [smokeProvenance artifact smokeVersion]
    finalizeSeed seed =
      case seed of
        PythonHydratedMetadataSeed
          engineVersion
          pythonVersion
          provenance ->
            HydratedMetadata
              { hydratedEngineVersion = engineVersion,
                hydratedPythonVersion = Just pythonVersion,
                hydratedRuntimeVersion = smokeVersion,
                hydratedProvenance = withSmokeProvenance provenance
              }
        AudiverisHydratedMetadataSeed bundledJavaVersion provenance ->
          HydratedMetadata
            { hydratedEngineVersion =
                Text.pack Provisioning.audiverisPinnedVersion,
              hydratedPythonVersion = Nothing,
              hydratedRuntimeVersion =
                "Audiveris "
                  <> smokeVersion
                  <> "; bundled JVM "
                  <> bundledJavaVersion,
              hydratedProvenance = withSmokeProvenance provenance
            }
        HostBinaryHydratedMetadataSeed provenance ->
          HydratedMetadata
            { hydratedEngineVersion = smokeVersion,
              hydratedPythonVersion = Nothing,
              hydratedRuntimeVersion = smokeVersion,
              hydratedProvenance = withSmokeProvenance provenance
            }

installedRuntimeClosureProvenance ::
  Text ->
  Provisioning.InstalledMachORuntimeClosure s ->
  [ResolvedArtifactProvenance]
installedRuntimeClosureProvenance adapterId runtimeClosure =
  aggregateProvenance
    : zipWith
      sourceProvenance
      [(1 :: Int) ..]
      (Provisioning.installedMachORuntimeClosureSources runtimeClosure)
  where
    root = Provisioning.installedMachORuntimeClosureRoot runtimeClosure
    aggregateProvenance =
      ResolvedArtifactProvenance
        { resolvedProvenanceName = adapterId <> "-runtime-closure",
          resolvedProvenanceVersion =
            Provisioning.installedMachORuntimeClosureDigest runtimeClosure,
          resolvedProvenanceSource =
            "artifact-local:.;files="
              <> Text.pack
                (show (Provisioning.installedMachORuntimeClosureFiles runtimeClosure))
              <> ";bytes="
              <> Text.pack
                (show (Provisioning.installedMachORuntimeClosureBytes runtimeClosure))
        }
    sourceProvenance sourceIndex source =
      let ownedRelative =
            makeRelative
              root
              (Provisioning.installedRuntimeOwnedPath source)
          sourcePath =
            Provisioning.installedRuntimeSourcePath source
          renderedSource
            | pathContainedBy root sourcePath =
                "artifact-local:"
                  <> Text.pack (makeRelative root sourcePath)
            | otherwise = Text.pack sourcePath
       in ResolvedArtifactProvenance
            { resolvedProvenanceName =
                adapterId
                  <> "-runtime-closure-"
                  <> Text.pack (show sourceIndex)
                  <> ":"
                  <> Text.pack ownedRelative,
              resolvedProvenanceVersion =
                Provisioning.installedRuntimeSourceDigest source,
              resolvedProvenanceSource =
                renderedSource
                  <> "#"
                  <> Provisioning.installedRuntimeSourceDigest source
                  <> ";files="
                  <> Text.pack
                    (show (Provisioning.installedRuntimeSourceFiles source))
                  <> ";bytes="
                  <> Text.pack
                    (show (Provisioning.installedRuntimeSourceBytes source))
            }

pathContainedBy :: FilePath -> FilePath -> Bool
pathContainedBy root path
  | not (isAbsolute path) = False
  | isAbsolute relative = False
  | otherwise =
      case splitDirectories relative of
        ".." : _ -> False
        _ -> True
  where
    relative = makeRelative root path

smokeProvenance ::
  MetalEngineArtifact ->
  Text ->
  ResolvedArtifactProvenance
smokeProvenance artifact smokeVersion =
  ResolvedArtifactProvenance
    { resolvedProvenanceName = metalEngineAdapterId artifact <> "-runtime-smoke",
      resolvedProvenanceVersion = smokeVersion,
      resolvedProvenanceSource = metalEngineSourceRef artifact
    }

parseResolvedPythonProvenance ::
  String ->
  Either String [ResolvedArtifactProvenance]
parseResolvedPythonProvenance frozenOutput =
  List.sortOn resolvedProvenanceName
    <$> mapM parseFrozenLine nonemptyLines
  where
    nonemptyLines =
      filter
        (not . Text.null)
        (map Text.strip (Text.lines (Text.pack frozenOutput)))

parseFrozenLine :: Text -> Either String ResolvedArtifactProvenance
parseFrozenLine frozenLine =
  let (packageName, pinnedVersion) = Text.breakOn "==" frozenLine
      (directName, directSource) = Text.breakOn " @ " frozenLine
   in if
        | not (Text.null packageName),
          not (Text.null pinnedVersion) ->
            Right
              ResolvedArtifactProvenance
                { resolvedProvenanceName = packageName,
                  resolvedProvenanceVersion = Text.drop 2 pinnedVersion,
                  resolvedProvenanceSource = "pypi"
                }
        | not (Text.null directName),
          not (Text.null directSource) ->
            let source = Text.drop 3 directSource
             in Right
                  ResolvedArtifactProvenance
                    { resolvedProvenanceName = directName,
                      resolvedProvenanceVersion = directSourceVersion source,
                      resolvedProvenanceSource = source
                    }
        | otherwise ->
            Left
              ( "unversioned or unrecognized pip provenance record: "
                  <> Text.unpack frozenLine
              )

directSourceVersion :: Text -> Text
directSourceVersion source =
  case Text.breakOnEnd "@" source of
    ("", _) -> source
    (_, suffix)
      | Text.null suffix -> source
      | otherwise -> suffix

primaryPythonEngineVersion ::
  Provisioning.ApplePythonAdapterId ->
  [ResolvedArtifactProvenance] ->
  Either String Text
primaryPythonEngineVersion pythonAdapter provenance =
  case [ resolvedProvenanceVersion record
       | record <- provenance,
         normalizePackageName (resolvedProvenanceName record)
           == primaryPackageName pythonAdapter
       ] of
    version : _ -> Right version
    [] ->
      Left
        ( "resolved package provenance omitted primary Apple engine package "
            <> Text.unpack (primaryPackageName pythonAdapter)
        )

primaryPackageName :: Provisioning.ApplePythonAdapterId -> Text
primaryPackageName pythonAdapter
  | pythonAdapter == Provisioning.ctranslate2PythonAdapter = "ctranslate2"
  | pythonAdapter == Provisioning.onnxRuntimePythonAdapter = "onnxruntime"
  | pythonAdapter == Provisioning.mlxPythonAdapter = "mlx"
  | otherwise = "coremltools"

normalizePackageName :: Text -> Text
normalizePackageName =
  Text.map normalize
  where
    normalize character
      | character `elem` ['_', '.'] = '-'
      | otherwise = toLower character

requireProvisioningSuccess ::
  String ->
  Provisioning.ProvisioningOutcome ->
  Provisioning.ProvisioningSession s String
requireProvisioningSuccess label outcome =
  case outcome of
    Provisioning.ProvisioningSucceeded output -> pure output
    Provisioning.ProvisioningRejected failure ->
      failProvisioning ("rejected: " <> failure)
    Provisioning.ProvisioningFailedFatal failure ->
      failProvisioning ("target failed: " <> failure)
    Provisioning.ProvisioningFailedKernel failure ->
      failProvisioning ("kernel failed: " <> failure)
    Provisioning.ProvisioningTimedOut deadline ->
      failProvisioning
        ( "timed out after "
            <> show (Provisioning.provisioningDeadlineMicros deadline)
            <> " microseconds"
        )
  where
    failProvisioning failure =
      Provisioning.failProvisioningSession
        (label <> ": " <> failure)

requireProvisioningResolution ::
  String ->
  Either String result ->
  Provisioning.ProvisioningSession s result
requireProvisioningResolution label resolution =
  case resolution of
    Left failure ->
      Provisioning.failProvisioningSession
        (label <> ": " <> failure)
    Right value -> pure value

requireNonemptyOutput ::
  String ->
  String ->
  Provisioning.ProvisioningSession s String
requireNonemptyOutput label output
  | null (Text.unpack (Text.strip (Text.pack output))) =
      Provisioning.failProvisioningSession
        (label <> " returned empty output")
  | otherwise = pure output

manifestForHydratedMetalEngineArtifact ::
  FilePath ->
  MetalEngineArtifact ->
  Text ->
  Maybe Text ->
  Text ->
  [ResolvedArtifactProvenance] ->
  Text ->
  Either String EngineArtifactManifest
manifestForHydratedMetalEngineArtifact
  installRoot
  artifact
  engineVersion
  pythonVersion
  runtimeVersion
  provenance
  digest = do
    identity <-
      maybe
        ( Left
            ( "closed Apple artifact has no native identity: "
                <> Text.unpack (metalEngineAdapterId artifact)
            )
        )
        Right
        (parseNativeArtifactIdentity (metalEngineAdapterId artifact))
    recipeFingerprint <-
      currentArtifactRecipeFingerprint
        identity
        appleArtifactRuntimeExpectation
    target <-
      nativeArtifactTarget identity "apple-silicon" "arm64"
    pure
      EngineArtifactManifest
        { manifestAdapterId = metalEngineAdapterId artifact,
          manifestEngineName = metalEngineName artifact,
          manifestSubstrate = "apple-silicon",
          manifestArchitecture = "arm64",
          manifestArtifactKind = metalEngineArtifactKind artifact,
          manifestSourceRef = metalEngineSourceRef artifact,
          manifestEngineVersion = engineVersion,
          manifestPythonVersion = pythonVersion,
          manifestRuntimeVersion = runtimeVersion,
          manifestResolvedProvenance = provenance,
          manifestRecipeFingerprint = recipeFingerprint,
          manifestDigest = digest,
          manifestGenerationFingerprint = digest,
          manifestMinioObjectKey =
            "engine-artifacts/apple-silicon/arm64/"
              <> metalEngineAdapterId artifact
              <> "/"
              <> digestSuffix digest
              <> ".tar.zst",
          manifestLocalInstallRoot = installRoot,
          manifestTargetContractFingerprint =
            nativeArtifactTargetFingerprint target,
          manifestImageTargetEvidence = Nothing
        }

digestSuffix :: Text -> Text
digestSuffix digest =
  fromMaybe digest (Text.stripPrefix "sha256:" digest)

-- | Virtual environments embed their creation root in activation scripts,
-- console-script shebangs, and @pyvenv.cfg@. Rewrite those owned text files to
-- the final sibling root before smoke and hashing, then reject any residual
-- candidate-root byte sequence anywhere in the payload.
relocateCandidateVenvInSession ::
  Provisioning.EngineWriter w s q ->
  FilePath ->
  FilePath ->
  Provisioning.ProvisioningSession s ()
relocateCandidateVenvInSession =
  Provisioning.provisioningRelocateCandidateVenv

metalEngineLaneNotAppleMessage :: String
metalEngineLaneNotAppleMessage =
  "infernix internal materialize-metal-engines is Apple-only: it materializes Apple Metal/Core ML "
    <> "engine manifests through the Tart-free headless host lane. Run it on the Apple Silicon "
    <> "cohort host for the upstream MLX and Core ML runtime smokes."
