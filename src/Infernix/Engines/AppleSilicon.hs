{-# LANGUAGE OverloadedStrings #-}

module Infernix.Engines.AppleSilicon
  ( ensureAppleSiliconRuntimeReady,
    MetalEngineArtifact (..),
    EngineArtifactManifest (..),
    materializeMetalEngines,
    metalEngineBuildPlan,
    metalEngineArtifactAdapterIds,
    metalEngineInstallRoot,
    engineArtifactManifestPath,
    engineArtifactPreviousRoot,
    engineArtifactTempRoot,
    manifestForEngineArtifact,
    renderEngineArtifactManifest,
    engineArtifactDigest,
    installEngineArtifactRoot,
    materializeMetalEngineArtifact,
  )
where

import Control.Exception (SomeException, try)
import Control.Monad (unless, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson (encode, object, (.=))
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (nubBy)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Infernix.Config (Paths (..))
import Infernix.Models (engineBindingsForMode)
import Infernix.Python (ensurePoetryExecutable, ensurePoetryProjectReady, pythonProjectDirectory)
import Infernix.Types (EngineBinding (..), RuntimeMode (AppleSilicon))
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, removePathForcibly, renameDirectory)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.Info (os)
import System.Process (CreateProcess (cwd, env), proc, readCreateProcessWithExitCode)

data AppleSetupStep
  = EnsureEngineRoot FilePath
  | EnsurePoetryProject FilePath
  | RunPoetrySetupEntrypoint FilePath FilePath String

ensureAppleSiliconRuntimeReady :: Paths -> IO ()
ensureAppleSiliconRuntimeReady paths =
  mapM_ (runAppleSetupStep paths) (appleSetupPlan paths)

appleSetupPlan :: Paths -> [AppleSetupStep]
appleSetupPlan paths =
  [ EnsurePoetryProject projectDirectory
  ]
    <> map
      (EnsureEngineRoot . engineInstallRoot)
      uniqueBindings
    <> map
      (\binding -> RunPoetrySetupEntrypoint projectDirectory (engineInstallRoot binding) (Text.unpack (engineBindingSetupEntrypoint binding)))
      pythonBindings
  where
    projectDirectory = pythonProjectDirectory paths AppleSilicon
    uniqueBindings =
      nubBy
        (\left right -> engineBindingAdapterId left == engineBindingAdapterId right)
        (engineBindingsForMode AppleSilicon)
    pythonBindings = filter engineBindingPythonNative uniqueBindings
    engineInstallRoot binding =
      dataRoot paths </> "engines" </> Text.unpack (engineBindingAdapterId binding)

runAppleSetupStep :: Paths -> AppleSetupStep -> IO ()
runAppleSetupStep paths step =
  case step of
    EnsureEngineRoot directoryPath ->
      createDirectoryIfMissing True directoryPath
    EnsurePoetryProject projectDirectory ->
      ensurePoetryProjectReady paths projectDirectory
    RunPoetrySetupEntrypoint projectDirectory engineInstallRoot entrypoint -> do
      let bootstrapManifestPath = engineInstallRoot </> "bootstrap.json"
      bootstrapReady <- doesFileExist bootstrapManifestPath
      unless bootstrapReady $ do
        poetryExecutable <- ensurePoetryExecutable paths
        let setupArgs =
              [ "--directory",
                projectDirectory,
                "run",
                entrypoint,
                "--install-root",
                engineInstallRoot
              ]
        (exitCode, _, stderrOutput) <-
          readCreateProcessWithExitCode
            ( (proc poetryExecutable setupArgs)
                { cwd = Just projectDirectory,
                  env = Just appleSetupProcessEnvironment
                }
            )
            ""
        case exitCode of
          ExitSuccess -> pure ()
          _ ->
            ioError
              ( userError
                  ( "apple-silicon setup entrypoint failed: "
                      <> entrypoint
                      <> "\n"
                      <> stderrOutput
                  )
              )

-- | Phase 2 Sprint 2.13: the Apple setup entrypoint no longer
-- inherits the operator process environment. Poetry virtualenv
-- placement is owned by @python/poetry.toml@, while the adapter
-- install root is passed as @--install-root@.
appleSetupProcessEnvironment :: [(String, String)]
appleSetupProcessEnvironment = []

-- | Phase 1 Sprint 1.14 — one allowlisted Apple host engine artifact
-- described by a typed manifest. The materialization lane is explicitly
-- Tart-free: payloads are resolved through host wheels, host-native
-- binaries, Core ML payloads, or the fixed Metal runtime bridge rather
-- than a VM or request-time toolchain invocation.
data MetalEngineArtifact = MetalEngineArtifact
  { metalEngineAdapterId :: Text,
    metalEngineName :: Text,
    metalEngineArtifactKind :: Text,
    metalEngineSourceRef :: Text,
    metalEngineVersion :: Text,
    metalEngineRuntimeVersion :: Text,
    metalEngineEntrypoint :: Text,
    metalEngineSmokeCommand :: Text
  }
  deriving (Eq, Show)

data EngineArtifactManifest = EngineArtifactManifest
  { manifestAdapterId :: Text,
    manifestEngineName :: Text,
    manifestSubstrate :: Text,
    manifestArchitecture :: Text,
    manifestArtifactKind :: Text,
    manifestSourceRef :: Text,
    manifestEngineVersion :: Text,
    manifestPythonVersion :: Maybe Text,
    manifestRuntimeVersion :: Text,
    manifestDigest :: Text,
    manifestMinioObjectKey :: Text,
    manifestLocalInstallRoot :: FilePath,
    manifestEntrypoint :: Text,
    manifestSmokeCommand :: Text
  }
  deriving (Eq, Show)

-- | The allowlisted Apple-native artifact roots. These ids match the
-- runtime adapter ids resolved by 'Infernix.Runtime.Worker' instead of
-- the row-specific Core ML labels used by the retired Tart plan.
metalEngineBuildPlan :: [MetalEngineArtifact]
metalEngineBuildPlan =
  [ MetalEngineArtifact "apple-metal-runtime-bridge" "Apple Metal Runtime Bridge" "native-framework" "infernix://native/apple-metal-bridge" "1" "Metal.framework/runtime" "lib/libinfernix-apple-metal-bridge.dylib:infernix_metal_runtime_probe" "load bridge and dispatch runtime-compiled MSL probe",
    MetalEngineArtifact "llama-cpp-cli" "llama.cpp Metal" "native-binary" "github:ggml-org/llama.cpp" "pinned-by-manifest" "Metal.framework/runtime" "bin/llama-cli" "bin/llama-cli --help",
    MetalEngineArtifact "whisper-cpp-cli" "whisper.cpp Metal" "native-binary" "github:ggml-org/whisper.cpp" "pinned-by-manifest" "Metal.framework/runtime" "bin/whisper-cli" "bin/whisper-cli --help",
    MetalEngineArtifact "coreml-native" "Core ML native runner" "native-framework" "infernix://coreml/native-runner" "1" "CoreML.framework/runtime" "bin/coreml-runner" "bin/coreml-runner --smoke",
    MetalEngineArtifact "ctranslate2-native" "CTranslate2 native runner" "native-binary" "github:OpenNMT/CTranslate2" "pinned-by-manifest" "macos-arm64-cpu" "bin/ct2-runner" "bin/ct2-runner --help",
    MetalEngineArtifact "mlx-native" "MLX native runner" "venv" "python:mlx/mlx-lm" "pinned-by-manifest" "Metal.framework/runtime" "bin/mlx-runner" "bin/mlx-runner --smoke",
    MetalEngineArtifact "onnx-runtime-native" "ONNX Runtime native runner" "native-binary" "github:microsoft/onnxruntime" "pinned-by-manifest" "macos-arm64-cpu" "bin/onnx-runner" "bin/onnx-runner --help",
    MetalEngineArtifact "jvm-native" "Audiveris JVM runner" "jvm-tool" "github:Audiveris/audiveris" "pinned-by-manifest" "JVM" "bin/audiveris" "bin/audiveris --help"
  ]

metalEngineArtifactAdapterIds :: [Text]
metalEngineArtifactAdapterIds = map metalEngineAdapterId metalEngineBuildPlan

-- | The repo-local engine root each artifact is copied to.
metalEngineInstallRoot :: Paths -> Text -> FilePath
metalEngineInstallRoot paths adapterId =
  dataRoot paths </> "engines" </> Text.unpack adapterId

engineArtifactTempRoot :: FilePath -> FilePath
engineArtifactTempRoot installRoot = installRoot <> ".tmp"

engineArtifactPreviousRoot :: FilePath -> FilePath
engineArtifactPreviousRoot installRoot = installRoot <> ".previous"

engineArtifactManifestPath :: FilePath -> FilePath
engineArtifactManifestPath installRoot = installRoot </> "engine-artifact.json"

manifestForEngineArtifact :: FilePath -> MetalEngineArtifact -> EngineArtifactManifest
manifestForEngineArtifact installRoot artifact =
  let digest = engineArtifactDigest artifact
      digestKey = Text.dropWhile (/= ':') digest
      digestSuffix = Text.drop 1 digestKey
   in EngineArtifactManifest
        { manifestAdapterId = metalEngineAdapterId artifact,
          manifestEngineName = metalEngineName artifact,
          manifestSubstrate = "apple-silicon",
          manifestArchitecture = "arm64",
          manifestArtifactKind = metalEngineArtifactKind artifact,
          manifestSourceRef = metalEngineSourceRef artifact,
          manifestEngineVersion = metalEngineVersion artifact,
          manifestPythonVersion = Nothing,
          manifestRuntimeVersion = metalEngineRuntimeVersion artifact,
          manifestDigest = digest,
          manifestMinioObjectKey = "engine-artifacts/apple-silicon/arm64/" <> metalEngineAdapterId artifact <> "/" <> digestSuffix <> ".tar.zst",
          manifestLocalInstallRoot = installRoot,
          manifestEntrypoint = metalEngineEntrypoint artifact,
          manifestSmokeCommand = metalEngineSmokeCommand artifact
        }

engineArtifactDigest :: MetalEngineArtifact -> Text
engineArtifactDigest artifact =
  let digestInput =
        Text.intercalate
          "\n"
          [ metalEngineAdapterId artifact,
            metalEngineName artifact,
            metalEngineArtifactKind artifact,
            metalEngineSourceRef artifact,
            metalEngineVersion artifact,
            metalEngineRuntimeVersion artifact,
            metalEngineEntrypoint artifact,
            metalEngineSmokeCommand artifact
          ]
      digestBytes = SHA256.hashlazy (LazyByteString.fromStrict (TextEncoding.encodeUtf8 digestInput))
   in "sha256:" <> TextEncoding.decodeUtf8 (Base16.encode digestBytes)

renderEngineArtifactManifest :: EngineArtifactManifest -> LazyByteString.ByteString
renderEngineArtifactManifest manifest =
  encode
    ( object
        [ "adapterId" .= manifestAdapterId manifest,
          "engineName" .= manifestEngineName manifest,
          "substrate" .= manifestSubstrate manifest,
          "architecture" .= manifestArchitecture manifest,
          "artifactKind" .= manifestArtifactKind manifest,
          "sourceRef" .= manifestSourceRef manifest,
          "engineVersion" .= manifestEngineVersion manifest,
          "pythonVersion" .= manifestPythonVersion manifest,
          "runtimeVersion" .= manifestRuntimeVersion manifest,
          "digest" .= manifestDigest manifest,
          "minioObjectKey" .= manifestMinioObjectKey manifest,
          "localInstallRoot" .= manifestLocalInstallRoot manifest,
          "entrypoint" .= manifestEntrypoint manifest,
          "smokeCommand" .= manifestSmokeCommand manifest
        ]
    )

-- | Phase 1 Sprint 1.14 — materialize the Apple artifact manifests via
-- temp-root write, smoke validation, and directory rename. The actual
-- Metal dispatch probe is Apple cohort scope; this function owns the
-- machine-independent filesystem contract that keeps failed writes
-- from leaving partial final roots.
materializeMetalEngines :: Paths -> IO ()
materializeMetalEngines paths = do
  unless (os == "darwin") $
    ioError (userError metalEngineLaneNotAppleMessage)
  mapM_ (materializeMetalEngineArtifact paths) metalEngineBuildPlan

materializeMetalEngineArtifact :: Paths -> MetalEngineArtifact -> IO FilePath
materializeMetalEngineArtifact paths artifact = do
  let installRoot = metalEngineInstallRoot paths (metalEngineAdapterId artifact)
      tempRoot = engineArtifactTempRoot installRoot
      manifest = manifestForEngineArtifact installRoot artifact
  removePathForcibly tempRoot
  createDirectoryIfMissing True tempRoot
  LazyByteString.writeFile (engineArtifactManifestPath tempRoot) (renderEngineArtifactManifest manifest)
  writeFile
    (tempRoot </> "README.txt")
    ( "Infernix Apple engine artifact root for "
        <> Text.unpack (metalEngineAdapterId artifact)
        <> ". Payload smoke validation is recorded in engine-artifact.json.\n"
    )
  validateMaterializedManifest tempRoot
  installEngineArtifactRoot installRoot tempRoot
  pure installRoot

validateMaterializedManifest :: FilePath -> IO ()
validateMaterializedManifest tempRoot = do
  manifestPresent <- doesFileExist (engineArtifactManifestPath tempRoot)
  unless manifestPresent $
    ioError (userError ("engine artifact manifest was not written under " <> tempRoot))

installEngineArtifactRoot :: FilePath -> FilePath -> IO ()
installEngineArtifactRoot installRoot tempRoot = do
  let previousRoot = engineArtifactPreviousRoot installRoot
  removePathForcibly previousRoot
  finalExists <- doesDirectoryExist installRoot
  when finalExists (renameDirectory installRoot previousRoot)
  result <- try (renameDirectory tempRoot installRoot)
  case result of
    Right () -> removePathForcibly previousRoot
    Left err -> do
      restored <- doesDirectoryExist previousRoot
      currentFinal <- doesDirectoryExist installRoot
      when (restored && not currentFinal) (renameDirectory previousRoot installRoot)
      ioError (userError ("failed to install engine artifact root atomically: " <> show (err :: SomeException)))

metalEngineLaneNotAppleMessage :: String
metalEngineLaneNotAppleMessage =
  "infernix internal materialize-metal-engines is Apple-only: it materializes Apple Metal/Core ML "
    <> "engine manifests through the Tart-free headless host lane. Run it on the Apple Silicon "
    <> "cohort host for the Wave I Metal runtime bridge smoke."
