{-# LANGUAGE OverloadedStrings #-}

module Infernix.Engines.AppleSilicon
  ( ensureAppleSiliconRuntimeReady,
    MetalEngineArtifact (..),
    materializeMetalEngines,
    metalEngineBuildPlan,
    metalEngineArtifactAdapterIds,
    metalEngineInstallRoot,
    metalEngineVmBaseImage,
    metalEngineVmName,
    tartCloneArgs,
    tartRunBuildArgs,
    tartDeleteArgs,
  )
where

import Control.Monad (unless)
import Data.List (nubBy)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Config (Paths (..))
import Infernix.HostConfig (HostConfig)
import Infernix.HostTools (HostTool (HostTart), runHostTool)
import Infernix.Models (engineBindingsForMode)
import Infernix.Python (ensurePoetryExecutable, ensurePoetryProjectReady, pythonProjectDirectory)
import Infernix.Types (EngineBinding (..), RuntimeMode (AppleSilicon))
import System.Directory (createDirectoryIfMissing, doesFileExist)
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

-- | Phase 1 Sprint 1.13 — one allowlisted Apple Metal/Core ML engine
-- artifact built inside the headless @tart@ macOS VM. The guest image
-- carries Xcode (and thus @xcrun metal@/@metallib@ and
-- @coremlc@/@coremltools@); full Xcode needs UI interaction the
-- headless host workflow cannot provide, and Metal/the GPU are
-- unreachable from inside tart, so each artifact is built in the VM and
-- copied to @./.data/engines/<adapterId>/@ before the host engine loads
-- it against the real Metal GPU.
data MetalEngineArtifact = MetalEngineArtifact
  { metalEngineAdapterId :: Text,
    -- | The build command the guest VM runs. It is hermetic: the
    -- toolchain and source reach the guest through the tart file mount
    -- and the written build spec, never through inherited host @PATH@ or
    -- environment variables (see
    -- documents/architecture/configuration_doctrine.md).
    metalEngineGuestBuildCommand :: Text,
    -- | The artifact path the guest build writes into the mounted
    -- install root, then copied out to @./.data/engines/<adapterId>/@.
    metalEngineArtifactFile :: Text
  }
  deriving (Eq, Show)

-- | The supported base macOS guest image, reconciled into the local
-- @tart@ image store. Xcode is installed only in this image so the host
-- stays Xcode-free.
metalEngineVmBaseImage :: Text
metalEngineVmBaseImage = "infernix-metal-builder"

-- | The ephemeral guest clone name; created per build run and destroyed
-- once the allowlisted artifacts are copied out.
metalEngineVmName :: Text
metalEngineVmName = "infernix-metal-build"

-- | The allowlisted Metal/Core ML artifacts the tart lane builds. MLX
-- and @jax-metal@ are prebuilt host wheels, ONNX Runtime is a prebuilt
-- wheel or binary, and Audiveris is a JVM application, so none of those
-- need the tart lane and are intentionally excluded.
metalEngineBuildPlan :: [MetalEngineArtifact]
metalEngineBuildPlan =
  [ MetalEngineArtifact "llama-cpp-cli" "build-llama-cpp-metal" "bin/llama-cli",
    MetalEngineArtifact "whisper-cpp-cli" "build-whisper-cpp-metal" "bin/whisper-cli",
    MetalEngineArtifact "coreml-basic-pitch" "build-coreml-basic-pitch" "model/BasicPitch.mlmodelc",
    MetalEngineArtifact "coreml-stable-diffusion" "build-coreml-stable-diffusion" "model/StableDiffusion.mlmodelc",
    MetalEngineArtifact "coreml-omnizart" "build-coreml-omnizart" "model/Omnizart.mlmodelc"
  ]

metalEngineArtifactAdapterIds :: [Text]
metalEngineArtifactAdapterIds = map metalEngineAdapterId metalEngineBuildPlan

-- | The repo-local engine root each artifact is copied to.
metalEngineInstallRoot :: Paths -> Text -> FilePath
metalEngineInstallRoot paths adapterId =
  dataRoot paths </> "engines" </> Text.unpack adapterId

-- | @tart clone <baseImage> <guestName>@ (pure; unit-tested).
tartCloneArgs :: Text -> Text -> [String]
tartCloneArgs baseImage guestName =
  ["clone", Text.unpack baseImage, Text.unpack guestName]

-- | @tart run --no-graphics --dir engine-out:<installRoot> <guestName>@
-- (pure; unit-tested). The guest's baked startup reads the build spec
-- written into the mounted @engine-out@ directory and writes the built
-- artifact back into the same mount — no env var crosses the boundary.
tartRunBuildArgs :: Text -> FilePath -> [String]
tartRunBuildArgs guestName installRoot =
  [ "run",
    "--no-graphics",
    "--dir",
    "engine-out:" <> installRoot,
    Text.unpack guestName
  ]

-- | @tart delete <guestName>@ (pure; unit-tested).
tartDeleteArgs :: Text -> [String]
tartDeleteArgs guestName = ["delete", Text.unpack guestName]

-- | Phase 1 Sprint 1.13 — build the allowlisted Apple Metal/Core ML
-- engine artifacts inside the headless @tart@ macOS VM and copy them to
-- @./.data/engines/<adapterId>/@. Apple-only: the in-VM Metal/Core ML
-- build, artifact copy-out, and host Metal load are exercised in the
-- Apple cohort wave (Wave I Stage 2). On a non-Apple host the command
-- fails fast with a typed diagnostic rather than silently succeeding.
materializeMetalEngines :: Paths -> IO ()
materializeMetalEngines paths = do
  unless (os == "darwin") $
    ioError (userError metalEngineLaneNotAppleMessage)
  hostConfig <-
    case pathsHostConfig paths of
      Just config -> pure config
      Nothing ->
        ioError
          ( userError
              ( "the Apple Metal-engine build lane needs a staged host manifest; "
                  <> "materialize ./.build/infernix-host.dhall and rerun"
              )
          )
  mapM_ (materializeMetalEngineArtifact paths hostConfig) metalEngineBuildPlan

materializeMetalEngineArtifact :: Paths -> HostConfig -> MetalEngineArtifact -> IO ()
materializeMetalEngineArtifact paths hostConfig artifact = do
  let installRoot = metalEngineInstallRoot paths (metalEngineAdapterId artifact)
      guestName = metalEngineVmName
  createDirectoryIfMissing True installRoot
  -- Hermetic guest input: the build command crosses into the VM as a
  -- mounted spec file, not an env var.
  writeFile (installRoot </> "build-spec") (Text.unpack (metalEngineGuestBuildCommand artifact))
  runTartStep hostConfig (tartCloneArgs metalEngineVmBaseImage guestName) "clone the Metal build VM"
  runTartStep hostConfig (tartRunBuildArgs guestName installRoot) "run the in-VM Metal/Core ML build"
  runTartStep hostConfig (tartDeleteArgs guestName) "delete the ephemeral Metal build VM"

runTartStep :: HostConfig -> [String] -> String -> IO ()
runTartStep hostConfig args description = do
  exitCode <- runHostTool hostConfig HostTart args
  case exitCode of
    ExitSuccess -> pure ()
    _ ->
      ioError
        ( userError
            ("Apple Metal-engine build lane failed to " <> description <> " (tart " <> unwords args <> ")")
        )

metalEngineLaneNotAppleMessage :: String
metalEngineLaneNotAppleMessage =
  "infernix internal materialize-metal-engines is Apple-only: it builds Metal/Core ML "
    <> "artifacts inside a headless tart macOS VM. Run it on the Apple Silicon cohort host "
    <> "(Wave I Stage 2). tart is native arm64 macOS virtualization and is unavailable here."
