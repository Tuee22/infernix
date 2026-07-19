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

import Control.Exception (IOException, bracket_, throwIO, try)
import Control.Monad (unless, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson (encode, object, (.=))
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (toLower)
import Data.List (isInfixOf, nubBy)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.Config (Paths (..))
import Infernix.HostConfig qualified as HostConfig
import Infernix.Models (engineBindingsForMode)
import Infernix.Python (ensurePoetryExecutable, ensurePoetryProjectReady, pythonProjectDirectory)
import Infernix.Types (EngineBinding (..), RuntimeMode (AppleSilicon))
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, getPermissions, removePathForcibly, renameDirectory, setOwnerExecutable, setPermissions)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath (takeDirectory, (</>))
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
        appleSetupEnv <- Subprocess.renderSubprocessEnv <$> Subprocess.clusterSubprocessEnv paths
        (exitCode, _, stderrOutput) <-
          readCreateProcessWithExitCode
            ( (proc poetryExecutable setupArgs)
                { cwd = Just projectDirectory,
                  env = Just appleSetupEnv
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
-- | Sprint 4.28 (managed-state-transition doctrine): the payload smoke command
-- runs with a real environment carrying @HOME@ and @TMPDIR@ (rooted at the
-- writable artifact directory) plus a minimal absolute @PATH@, rather than the
-- previous empty @env = Just []@.
appleSmokeProcessEnvironment :: FilePath -> [(String, String)]
appleSmokeProcessEnvironment root =
  [ ("HOME", root),
    ("TMPDIR", root </> "tmp"),
    ("PATH", "/usr/local/bin:/usr/bin:/bin"),
    ("LANG", "C.UTF-8"),
    ("LC_ALL", "C.UTF-8")
  ]

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
  [ MetalEngineArtifact "apple-metal-runtime-bridge" "Apple Metal Runtime Bridge" "native-framework" "infernix://native/apple-metal-bridge" "1" "Metal.framework/runtime" "lib/libinfernix-apple-metal-bridge.dylib:infernix_metal_runtime_probe" "bin/infernix-apple-metal-bridge-smoke",
    MetalEngineArtifact "llama-cpp-cli" "llama.cpp Metal" "native-binary" "github:ggml-org/llama.cpp" "pinned-by-manifest" "Metal.framework/runtime" "bin/llama-cli" "bin/llama-cli --help",
    MetalEngineArtifact "whisper-cpp-cli" "whisper.cpp Metal" "native-binary" "github:ggml-org/whisper.cpp" "pinned-by-manifest" "Metal.framework/runtime" "bin/whisper-cli" "bin/whisper-cli --help",
    MetalEngineArtifact "coreml-native" "Core ML native runner" "native-framework" "infernix://coreml/native-runner" "1" "CoreML.framework/runtime" "bin/coreml-runner" "bin/coreml-runner --smoke",
    MetalEngineArtifact "ctranslate2-native" "CTranslate2 native runner" "native-binary" "github:OpenNMT/CTranslate2" "pinned-by-manifest" "macos-arm64-cpu" "bin/ct2-runner" "bin/ct2-runner --help",
    MetalEngineArtifact "mlx-native" "MLX native runner" "venv" "python:mlx/mlx-lm" "pinned-by-manifest" "Metal.framework/runtime" "bin/mlx-runner" "bin/mlx-runner --smoke",
    MetalEngineArtifact "onnx-runtime-native" "ONNX Runtime native runner" "native-binary" "github:microsoft/onnxruntime" "pinned-by-manifest" "macos-arm64-cpu" "bin/onnx-runner" "bin/onnx-runner --help",
    MetalEngineArtifact "jvm-native" "Audiveris JVM runner" "jvm-tool" (Text.pack audiverisMacosArm64DmgUrl) audiverisMacosArm64Version "JVM" "bin/audiveris" "bin/audiveris --help"
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
  mapM_ materializeAndHydrate metalEngineBuildPlan
  where
    materializeAndHydrate artifact = do
      installRoot <- materializeMetalEngineArtifact paths artifact
      hydrateAppleNativeEngineArtifact paths installRoot artifact
      validateInstalledAppleNativePayloadSmoke installRoot artifact

materializeMetalEngineArtifact :: Paths -> MetalEngineArtifact -> IO FilePath
materializeMetalEngineArtifact paths artifact = do
  let installRoot = metalEngineInstallRoot paths (metalEngineAdapterId artifact)
      tempRoot = engineArtifactTempRoot installRoot
      manifest = manifestForEngineArtifact installRoot artifact
  removePathForcibly tempRoot
  createDirectoryIfMissing True tempRoot
  LazyByteString.writeFile (engineArtifactManifestPath tempRoot) (renderEngineArtifactManifest manifest)
  writeMetalEngineArtifactPayload paths tempRoot artifact
  writeFile
    (tempRoot </> "README.txt")
    ( "Infernix Apple engine artifact root for "
        <> Text.unpack (metalEngineAdapterId artifact)
        <> ". The materialized payload and smoke command are recorded in engine-artifact.json.\n"
    )
  validateMaterializedManifest tempRoot

  -- Venv-backed native runners cannot execute their payload smoke until the
  -- engine venv is hydrated (which happens after install), so the pre-install
  -- payload smoke is skipped for them here; the post-hydration installed smoke
  -- runs the same command against the created venv and stays authoritative.
  unless (appleNativeAdapterRequiresVenv artifact) $
    validateMaterializedPayloadSmoke tempRoot artifact
  installEngineArtifactRoot installRoot tempRoot
  pure installRoot

writeMetalEngineArtifactPayload :: Paths -> FilePath -> MetalEngineArtifact -> IO ()
writeMetalEngineArtifactPayload paths tempRoot artifact =
  case metalEngineAdapterId artifact of
    "apple-metal-runtime-bridge" -> writeAppleMetalBridgePayload tempRoot
    "coreml-native" -> writeCoreMlNativeRunnerPayload paths tempRoot
    adapterId
      | adapterId `elem` appleNativeRunnerAdapterIds ->
          writeAppleNativeRunnerPayload paths tempRoot artifact
    _ -> pure ()

appleNativeRunnerAdapterIds :: [Text]
appleNativeRunnerAdapterIds =
  [ "llama-cpp-cli",
    "whisper-cpp-cli",
    "ctranslate2-native",
    "mlx-native",
    "onnx-runtime-native",
    "jvm-native"
  ]

writeAppleNativeRunnerPayload :: Paths -> FilePath -> MetalEngineArtifact -> IO ()
writeAppleNativeRunnerPayload paths tempRoot artifact = do
  writeAppleNativeRunnerLibrary paths tempRoot
  let runnerPath = tempRoot </> Text.unpack (metalEngineEntrypoint artifact)
  createDirectoryIfMissing True (takeDirectory runnerPath)
  writeFile runnerPath (appleNativeRunnerScript artifact)
  makeExecutable runnerPath

writeAppleMetalBridgePayload :: FilePath -> IO ()
writeAppleMetalBridgePayload tempRoot = do
  let sourceRoot = tempRoot </> "src"
      binRoot = tempRoot </> "bin"
      headerPath = sourceRoot </> "infernix_apple_metal_bridge.h"
      bridgeSourcePath = sourceRoot </> "infernix_apple_metal_bridge.m"
      smokeSourcePath = sourceRoot </> "infernix_apple_metal_bridge_smoke.c"
      smokeScriptPath = binRoot </> "infernix-apple-metal-bridge-smoke"
  createDirectoryIfMissing True sourceRoot
  createDirectoryIfMissing True binRoot
  writeFile headerPath appleMetalBridgeHeader
  writeFile bridgeSourcePath appleMetalBridgeSource
  writeFile smokeSourcePath appleMetalBridgeSmokeSource
  writeFile smokeScriptPath appleMetalBridgeSmokeScript
  makeExecutable smokeScriptPath

writeCoreMlNativeRunnerPayload :: Paths -> FilePath -> IO ()
writeCoreMlNativeRunnerPayload paths tempRoot = do
  let sourceRoot = tempRoot </> "src"
      binRoot = tempRoot </> "bin"
      smokeSourcePath = sourceRoot </> "infernix_coreml_runner_smoke.m"
      runnerScriptPath = binRoot </> "coreml-runner"
  createDirectoryIfMissing True sourceRoot
  createDirectoryIfMissing True binRoot
  writeAppleNativeRunnerLibrary paths tempRoot
  writeFile smokeSourcePath coreMlRunnerSmokeSource
  writeFile runnerScriptPath coreMlRunnerScript
  makeExecutable runnerScriptPath

writeAppleNativeRunnerLibrary :: Paths -> FilePath -> IO ()
writeAppleNativeRunnerLibrary paths tempRoot = do
  let sourcePath = repoRoot paths </> "python" </> "native-runners" </> "apple_native_runner.py"
      destinationPath = tempRoot </> "lib" </> "apple_native_runner.py"
  createDirectoryIfMissing True (takeDirectory destinationPath)
  source <- readFile sourcePath
  writeFile destinationPath source

hydrateAppleNativeEngineArtifact :: Paths -> FilePath -> MetalEngineArtifact -> IO ()
hydrateAppleNativeEngineArtifact paths installRoot artifact =
  case metalEngineAdapterId artifact of
    "jvm-native" -> hydrateAudiverisJvmTool paths installRoot
    adapterId ->
      case appleNativePythonRequirements adapterId of
        [] -> pure ()
        requirements -> do
          pythonExecutable <- resolveAppleNativePython paths adapterId
          let venvRoot = installRoot </> "venv"
              venvPython = venvRoot </> "bin" </> "python"
          removePathForcibly venvRoot
          runAppleNativeProcess
            "failed to create Apple native engine venv"
            installRoot
            pythonExecutable
            ["-m", "venv", "--clear", "--symlinks", venvRoot]
          runAppleNativeProcess
            "failed to upgrade Apple native engine pip"
            installRoot
            venvPython
            ["-m", "pip", "install", "--upgrade", "pip"]
          runAppleNativeProcess
            ("failed to hydrate Apple native engine packages for " <> Text.unpack adapterId)
            installRoot
            venvPython
            (["-m", "pip", "install"] <> requirements)

audiverisMacosArm64Version :: Text
audiverisMacosArm64Version = "5.10.2"

audiverisMacosArm64DmgName :: String
audiverisMacosArm64DmgName = "Audiveris-5.10.2-macosx-arm64.dmg"

audiverisMacosArm64DmgUrl :: String
audiverisMacosArm64DmgUrl =
  "https://github.com/Audiveris/audiveris/releases/download/5.10.2/" <> audiverisMacosArm64DmgName

hydrateAudiverisJvmTool :: Paths -> FilePath -> IO ()
hydrateAudiverisJvmTool paths installRoot = do
  let cacheRoot = dataRoot paths </> "downloads" </> "engines"
      dmgPath = cacheRoot </> audiverisMacosArm64DmgName
      mountRoot = installRoot </> "audiveris-dmg"
      mountedApp = mountRoot </> "Audiveris.app"
      installedApp = installRoot </> "Audiveris.app"
  createDirectoryIfMissing True cacheRoot
  dmgExists <- doesFileExist dmgPath
  unless dmgExists $
    runAppleNativeProcess
      "failed to download Audiveris macOS arm64 DMG"
      installRoot
      "/usr/bin/curl"
      ["-fL", "--retry", "3", "--output", dmgPath, audiverisMacosArm64DmgUrl]
  removePathForcibly mountRoot
  createDirectoryIfMissing True mountRoot
  bracket_
    ( runAppleNativeProcessWithInput
        "failed to mount Audiveris macOS arm64 DMG"
        installRoot
        "/usr/bin/hdiutil"
        ["attach", "-nobrowse", "-readonly", "-mountpoint", mountRoot, dmgPath]
        "Y\n"
    )
    ( runAppleNativeProcess
        "failed to detach Audiveris macOS arm64 DMG"
        installRoot
        "/usr/bin/hdiutil"
        ["detach", mountRoot]
    )
    ( do
        appPresent <- doesDirectoryExist mountedApp
        unless appPresent $
          ioError (userError ("Audiveris DMG did not contain " <> mountedApp))
        removePathForcibly installedApp
        runAppleNativeProcess
          "failed to copy Audiveris.app into the Apple native engine root"
          installRoot
          "/usr/bin/ditto"
          [mountedApp, installedApp]
    )
  removePathForcibly mountRoot

appleNativePythonRequirements :: Text -> [String]
appleNativePythonRequirements adapterId =
  case adapterId of
    "ctranslate2-native" ->
      [ "ctranslate2>=4.8.0",
        "faster-whisper>=1.2.0",
        "soundfile>=0.12"
      ]
    "mlx-native" ->
      [ "mlx-lm>=0.29.0,<0.30.0",
        "transformers>=4.46,<5"
      ]
    "onnx-runtime-native" ->
      [ "mido>=1.3",
        "numpy>=1.26",
        "onnxruntime>=1.27.0",
        "scipy>=1.13",
        "soundfile>=0.12"
      ]
    "coreml-native" ->
      -- Pin setuptools < 81: setuptools 81 removed the legacy `pkg_resources`
      -- module, which `basic-pitch`'s transitive dependency `resampy` (0.4.2)
      -- imports at load time (`resampy/filters.py`). Without this pin a fresh
      -- resolve pulls setuptools >= 81 and every basic-pitch invocation crashes
      -- with `ModuleNotFoundError: No module named 'pkg_resources'`. resampy's own
      -- deprecation warning recommends exactly this bound ("pin to Setuptools<81").
      [ "setuptools<81",
        "basic-pitch>=0.4.0",
        "git+https://github.com/apple/ml-stable-diffusion.git"
      ]
    _ -> []

-- | A native runner is venv-backed exactly when it declares Python
-- requirements: `hydrateAppleNativeEngineArtifact` creates the engine venv only
-- for those adapters. Their payload smoke resolves `venv/bin/python`, so it can
-- only run after hydration; the pre-install smoke is skipped for them.
appleNativeAdapterRequiresVenv :: MetalEngineArtifact -> Bool
appleNativeAdapterRequiresVenv artifact =
  not (null (appleNativePythonRequirements (metalEngineAdapterId artifact)))

resolveAppleNativePython :: Paths -> Text -> IO FilePath
resolveAppleNativePython paths adapterId = do
  let configured =
        case pathsHostConfig paths of
          Just hostConfig -> [Text.unpack (HostConfig.hostPython3 (HostConfig.hostToolPaths hostConfig))]
          Nothing -> []
      candidates
        | adapterId == "coreml-native" =
            [ "/opt/homebrew/bin/python3.11",
              "/opt/homebrew/bin/python3.10"
            ]
              <> configured
        | otherwise =
            configured
              <> [ "/opt/homebrew/bin/python3.12",
                   "/opt/homebrew/bin/python3",
                   "/usr/bin/python3"
                 ]
  firstUsablePython (appleNativePythonVersionCheck adapterId) (appleNativePythonRequirementMessage adapterId) candidates

appleNativePythonVersionCheck :: Text -> String
appleNativePythonVersionCheck adapterId
  | adapterId == "coreml-native" =
      "import sys; v=sys.version_info[:2]; raise SystemExit(0 if (3, 10) <= v < (3, 12) else 1)"
  | otherwise =
      "import sys; raise SystemExit(0 if (3, 12) <= sys.version_info[:2] < (4, 0) else 1)"

appleNativePythonRequirementMessage :: Text -> String
appleNativePythonRequirementMessage adapterId
  | adapterId == "coreml-native" =
      "Apple Core ML Basic Pitch hydration requires a Python 3.10 or 3.11 executable from the fixed Homebrew fallback paths"
  | otherwise =
      "Apple native engine hydration requires a Python 3.12+ executable from HostConfig.toolPaths.python3 or the fixed Homebrew fallback paths"

firstUsablePython :: String -> String -> [FilePath] -> IO FilePath
firstUsablePython _ message [] =
  ioError
    (userError message)
firstUsablePython versionCheck message (candidate : rest) = do
  exists <- doesFileExist candidate
  if not exists
    then firstUsablePython versionCheck message rest
    else do
      (exitCode, _, _) <-
        readCreateProcessWithExitCode
          (proc candidate ["-c", versionCheck])
          ""
      case exitCode of
        ExitSuccess -> pure candidate
        _ -> firstUsablePython versionCheck message rest

runAppleNativeProcess :: String -> FilePath -> FilePath -> [String] -> IO ()
runAppleNativeProcess label workingDirectory executable args =
  runAppleNativeProcessWithInput label workingDirectory executable args ""

runAppleNativeProcessWithInput :: String -> FilePath -> FilePath -> [String] -> String -> IO ()
runAppleNativeProcessWithInput label workingDirectory executable args inputPayload = do
  (exitCode, stdoutOutput, stderrOutput) <-
    readCreateProcessWithExitCode
      ((proc executable args) {cwd = Just workingDirectory})
      inputPayload
  case exitCode of
    ExitSuccess -> pure ()
    _ ->
      ioError
        ( userError
            ( label
                <> ": "
                <> executable
                <> " "
                <> unwords args
                <> "\nstdout:\n"
                <> stdoutOutput
                <> "\nstderr:\n"
                <> stderrOutput
            )
        )

validateInstalledAppleNativePayloadSmoke :: FilePath -> MetalEngineArtifact -> IO ()
validateInstalledAppleNativePayloadSmoke installRoot artifact =
  case metalEngineAdapterId artifact of
    "jvm-native" -> runPayloadSmokeCommand installRoot artifact ("bin/audiveris", ["--help"])
    _ -> validateMaterializedPayloadSmoke installRoot artifact

makeExecutable :: FilePath -> IO ()
makeExecutable filePath = do
  permissions <- getPermissions filePath
  setPermissions filePath (setOwnerExecutable True permissions)

validateMaterializedManifest :: FilePath -> IO ()
validateMaterializedManifest tempRoot = do
  manifestPresent <- doesFileExist (engineArtifactManifestPath tempRoot)
  unless manifestPresent $
    ioError (userError ("engine artifact manifest was not written under " <> tempRoot))

validateMaterializedPayloadSmoke :: FilePath -> MetalEngineArtifact -> IO ()
validateMaterializedPayloadSmoke tempRoot artifact =
  when (os == "darwin") $
    maybe (pure ()) (runPayloadSmokeCommand tempRoot artifact) (payloadSmokeCommand artifact)

runPayloadSmokeCommand :: FilePath -> MetalEngineArtifact -> (FilePath, [String]) -> IO ()
runPayloadSmokeCommand root artifact (smokeExecutable, smokeArgs) = do
  let smokePath = root </> smokeExecutable
  smokeExists <- doesFileExist smokePath
  unless smokeExists $
    ioError (userError ("engine artifact smoke command was not written: " <> smokePath))
  createDirectoryIfMissing True (root </> "tmp")
  (exitCode, stdoutOutput, stderrOutput) <-
    readCreateProcessWithExitCode
      ( (proc smokePath smokeArgs)
          { cwd = Just root,
            env = Just (appleSmokeProcessEnvironment root)
          }
      )
      ""
  case exitCode of
    ExitSuccess -> pure ()
    _ ->
      ioError
        ( userError
            ( "engine artifact smoke command failed for "
                <> Text.unpack (metalEngineAdapterId artifact)
                <> ": "
                <> smokePath
                <> " "
                <> unwords smokeArgs
                <> "\nstdout:\n"
                <> stdoutOutput
                <> "\nstderr:\n"
                <> stderrOutput
            )
        )

payloadSmokeCommand :: MetalEngineArtifact -> Maybe (FilePath, [String])
payloadSmokeCommand artifact =
  case metalEngineAdapterId artifact of
    "apple-metal-runtime-bridge" -> Just ("bin/infernix-apple-metal-bridge-smoke", [])
    "coreml-native" -> Just ("bin/coreml-runner", ["--smoke"])
    "jvm-native" -> Nothing
    adapterId
      | adapterId `elem` appleNativeRunnerAdapterIds ->
          Just (Text.unpack (metalEngineEntrypoint artifact), ["--help"])
    _ -> Nothing

installEngineArtifactRoot :: FilePath -> FilePath -> IO ()
installEngineArtifactRoot installRoot tempRoot = do
  let previousRoot = engineArtifactPreviousRoot installRoot
  removePathForcibly previousRoot
  backupExists <- moveExistingArtifactRoot installRoot previousRoot
  result <- try (renameDirectory tempRoot installRoot) :: IO (Either IOException ())
  case result of
    Right () -> removePathForcibly previousRoot
    Left err -> do
      when backupExists (restorePreviousArtifactRoot installRoot previousRoot)
      ioError (userError ("failed to install engine artifact root: " <> show err))

moveExistingArtifactRoot :: FilePath -> FilePath -> IO Bool
moveExistingArtifactRoot installRoot previousRoot = do
  finalExists <- doesDirectoryExist installRoot
  if not finalExists
    then pure False
    else do
      result <- try (renameDirectory installRoot previousRoot) :: IO (Either IOException ())
      case result of
        Right () -> pure True
        Left err
          | supportsReplaceFallback err -> do
              -- Docker overlay can reject moving a lower-layer image root to a
              -- sibling backup path. The temp root has already been fully
              -- written and smoke-validated, so replace the generated final
              -- root in place for idempotent image-layer reruns.
              removePathForcibly installRoot
              pure False
          | otherwise -> throwIO err

restorePreviousArtifactRoot :: FilePath -> FilePath -> IO ()
restorePreviousArtifactRoot installRoot previousRoot = do
  restored <- doesDirectoryExist previousRoot
  currentFinal <- doesDirectoryExist installRoot
  when (restored && not currentFinal) (renameDirectory previousRoot installRoot)

supportsReplaceFallback :: IOException -> Bool
supportsReplaceFallback err =
  any
    (`isInfixOf` failureText)
    [ "cross-device",
      "invalid cross-device link",
      "unsupported operation"
    ]
  where
    failureText = map toLower (show err)

metalEngineLaneNotAppleMessage :: String
metalEngineLaneNotAppleMessage =
  "infernix internal materialize-metal-engines is Apple-only: it materializes Apple Metal/Core ML "
    <> "engine manifests through the Tart-free headless host lane. Run it on the Apple Silicon "
    <> "cohort host for the Wave I Metal runtime bridge smoke."

appleMetalBridgeHeader :: String
appleMetalBridgeHeader =
  unlines
    [ "#ifndef INFERNIX_APPLE_METAL_BRIDGE_H",
      "#define INFERNIX_APPLE_METAL_BRIDGE_H",
      "",
      "#include <stddef.h>",
      "",
      "#ifdef __cplusplus",
      "extern \"C\" {",
      "#endif",
      "",
      "int infernix_metal_runtime_probe(char *diagnostic, size_t diagnostic_size);",
      "",
      "#ifdef __cplusplus",
      "}",
      "#endif",
      "",
      "#endif"
    ]

appleMetalBridgeSource :: String
appleMetalBridgeSource =
  unlines
    [ "#import \"infernix_apple_metal_bridge.h\"",
      "",
      "#import <Foundation/Foundation.h>",
      "#import <Metal/Metal.h>",
      "",
      "#include <stdio.h>",
      "",
      "static void infernix_write_diagnostic(char *diagnostic, size_t diagnostic_size, const char *message) {",
      "  if (diagnostic != NULL && diagnostic_size > 0) {",
      "    snprintf(diagnostic, diagnostic_size, \"%s\", message);",
      "  }",
      "}",
      "",
      "static const char *infernix_nsstring_utf8(NSString *value) {",
      "  return value == nil ? \"unknown\" : [value UTF8String];",
      "}",
      "",
      "int infernix_metal_runtime_probe(char *diagnostic, size_t diagnostic_size) {",
      "  @autoreleasepool {",
      "    id<MTLDevice> device = MTLCreateSystemDefaultDevice();",
      "    if (device == nil) {",
      "      infernix_write_diagnostic(diagnostic, diagnostic_size, \"MTLCreateSystemDefaultDevice returned nil\");",
      "      return 2;",
      "    }",
      "",
      "    NSString *source = @\"#include <metal_stdlib>\\n\"",
      "                       @\"using namespace metal;\\n\"",
      "                       @\"kernel void infernix_add_one(device int *value [[buffer(0)]], uint id [[thread_position_in_grid]]) {\\n\"",
      "                       @\"  if (id == 0) { value[0] = value[0] + 1; }\\n\"",
      "                       @\"}\\n\";",
      "    NSError *error = nil;",
      "    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];",
      "    if (library == nil) {",
      "      char message[1024];",
      "      snprintf(message, sizeof(message), \"Metal runtime compilation failed: %s\", infernix_nsstring_utf8([error localizedDescription]));",
      "      infernix_write_diagnostic(diagnostic, diagnostic_size, message);",
      "      return 3;",
      "    }",
      "",
      "    id<MTLFunction> function = [library newFunctionWithName:@\"infernix_add_one\"];",
      "    if (function == nil) {",
      "      infernix_write_diagnostic(diagnostic, diagnostic_size, \"Metal probe function was not found in the runtime library\");",
      "      return 4;",
      "    }",
      "",
      "    id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&error];",
      "    if (pipeline == nil) {",
      "      char message[1024];",
      "      snprintf(message, sizeof(message), \"Metal compute pipeline creation failed: %s\", infernix_nsstring_utf8([error localizedDescription]));",
      "      infernix_write_diagnostic(diagnostic, diagnostic_size, message);",
      "      return 5;",
      "    }",
      "",
      "    id<MTLCommandQueue> queue = [device newCommandQueue];",
      "    if (queue == nil) {",
      "      infernix_write_diagnostic(diagnostic, diagnostic_size, \"Metal command queue creation failed\");",
      "      return 6;",
      "    }",
      "",
      "    int value = 41;",
      "    id<MTLBuffer> buffer = [device newBufferWithBytes:&value length:sizeof(value) options:MTLResourceStorageModeShared];",
      "    if (buffer == nil) {",
      "      infernix_write_diagnostic(diagnostic, diagnostic_size, \"Metal shared buffer allocation failed\");",
      "      return 7;",
      "    }",
      "",
      "    id<MTLCommandBuffer> commandBuffer = [queue commandBuffer];",
      "    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];",
      "    if (commandBuffer == nil || encoder == nil) {",
      "      infernix_write_diagnostic(diagnostic, diagnostic_size, \"Metal command encoding setup failed\");",
      "      return 8;",
      "    }",
      "",
      "    [encoder setComputePipelineState:pipeline];",
      "    [encoder setBuffer:buffer offset:0 atIndex:0];",
      "    MTLSize gridSize = MTLSizeMake(1, 1, 1);",
      "    MTLSize threadgroupSize = MTLSizeMake(1, 1, 1);",
      "    [encoder dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];",
      "    [encoder endEncoding];",
      "    [commandBuffer commit];",
      "    [commandBuffer waitUntilCompleted];",
      "",
      "    if ([commandBuffer status] != MTLCommandBufferStatusCompleted) {",
      "      infernix_write_diagnostic(diagnostic, diagnostic_size, \"Metal command buffer did not complete successfully\");",
      "      return 9;",
      "    }",
      "",
      "    int observed = ((int *)[buffer contents])[0];",
      "    if (observed != 42) {",
      "      char message[256];",
      "      snprintf(message, sizeof(message), \"Metal probe produced %d, expected 42\", observed);",
      "      infernix_write_diagnostic(diagnostic, diagnostic_size, message);",
      "      return 10;",
      "    }",
      "",
      "    char message[512];",
      "    snprintf(message, sizeof(message), \"Metal runtime probe passed on %s\", infernix_nsstring_utf8([device name]));",
      "    infernix_write_diagnostic(diagnostic, diagnostic_size, message);",
      "    return 0;",
      "  }",
      "}"
    ]

appleMetalBridgeSmokeSource :: String
appleMetalBridgeSmokeSource =
  unlines
    [ "#include \"infernix_apple_metal_bridge.h\"",
      "",
      "#include <stdio.h>",
      "",
      "int main(void) {",
      "  char diagnostic[1024] = {0};",
      "  int result = infernix_metal_runtime_probe(diagnostic, sizeof(diagnostic));",
      "  if (diagnostic[0] != '\\0') {",
      "    fprintf(result == 0 ? stdout : stderr, \"%s\\n\", diagnostic);",
      "  }",
      "  return result;",
      "}"
    ]

appleMetalBridgeSmokeScript :: String
appleMetalBridgeSmokeScript =
  unlines
    [ "#!/bin/bash",
      "set -euo pipefail",
      "",
      "script_path=\"${BASH_SOURCE[0]}\"",
      "script_dir=\"${script_path%/*}\"",
      "root=\"$(CDPATH= cd -- \"$script_dir/..\" && pwd)\"",
      "src=\"$root/src/infernix_apple_metal_bridge.m\"",
      "smoke_src=\"$root/src/infernix_apple_metal_bridge_smoke.c\"",
      "lib_dir=\"$root/lib\"",
      "bin_dir=\"$root/bin\"",
      "lib=\"$lib_dir/libinfernix-apple-metal-bridge.dylib\"",
      "runner=\"$bin_dir/infernix-apple-metal-bridge-smoke-runner\"",
      "",
      "if [[ \"$(/usr/bin/uname -s)\" != \"Darwin\" ]]; then",
      "  printf '%s\\n' \"Apple Metal runtime bridge smoke must run on Darwin/Apple Silicon\" >&2",
      "  exit 70",
      "fi",
      "",
      "/bin/mkdir -p \"$lib_dir\" \"$bin_dir\"",
      "/usr/bin/clang -fobjc-arc -dynamiclib -framework Foundation -framework Metal -install_name \"@rpath/libinfernix-apple-metal-bridge.dylib\" \"$src\" -o \"$lib\"",
      "/usr/bin/clang -I \"$root/src\" \"$smoke_src\" -L \"$lib_dir\" -linfernix-apple-metal-bridge -Wl,-rpath,\"$lib_dir\" -o \"$runner\"",
      "\"$runner\""
    ]

coreMlRunnerSmokeSource :: String
coreMlRunnerSmokeSource =
  unlines
    [ "#import <CoreML/CoreML.h>",
      "#import <Foundation/Foundation.h>",
      "",
      "#include <stdio.h>",
      "",
      "int main(void) {",
      "  @autoreleasepool {",
      "    Class modelClass = NSClassFromString(@\"MLModel\");",
      "    Class configurationClass = NSClassFromString(@\"MLModelConfiguration\");",
      "    if (modelClass == Nil || configurationClass == Nil) {",
      "      fprintf(stderr, \"Core ML runtime classes are unavailable\\n\");",
      "      return 2;",
      "    }",
      "",
      "    MLModelConfiguration *configuration = [[MLModelConfiguration alloc] init];",
      "    if (configuration == nil) {",
      "      fprintf(stderr, \"Core ML model configuration allocation failed\\n\");",
      "      return 3;",
      "    }",
      "",
      "    printf(\"Core ML runtime probe passed\\n\");",
      "    return 0;",
      "  }",
      "}"
    ]

-- | Phase 1 Sprint 1.15 — the Core ML runner keeps its real Darwin clang
-- smoke on @--smoke@/@--help@, then delegates normal invocations to the
-- shared Apple native runner module copied into the artifact root.
coreMlRunnerScript :: String
coreMlRunnerScript =
  unlines
    [ "#!/bin/bash",
      "set -euo pipefail",
      "",
      "adapter_id=\"coreml-native\"",
      "engine_name=\"Core ML native runner\"",
      "script_path=\"${BASH_SOURCE[0]}\"",
      "script_dir=\"${script_path%/*}\"",
      "root=\"$(CDPATH= cd -- \"$script_dir/..\" && pwd)\"",
      "src=\"$root/src/infernix_coreml_runner_smoke.m\"",
      "bin_dir=\"$root/bin\"",
      "runner=\"$bin_dir/infernix-coreml-runner-smoke\"",
      "",
      "case \"${1:-}\" in",
      "  --smoke|--help)",
      "    if [[ \"$(/usr/bin/uname -s)\" != \"Darwin\" ]]; then",
      "      printf '%s\\n' \"Core ML native runner smoke must run on Darwin/Apple Silicon\" >&2",
      "      exit 70",
      "    fi",
      "    /bin/mkdir -p \"$bin_dir\"",
      "    /usr/bin/clang -fobjc-arc -framework Foundation -framework CoreML \"$src\" -o \"$runner\"",
      "    \"$runner\"",
      "    exit 0",
      "    ;;",
      "esac",
      ""
    ]
    <> appleNativeRunnerExecBody "coreml-native" "Core ML native runner"

-- | Phase 1 Sprint 1.15 — generated Apple native runners preserve the
-- native worker argument contract and delegate to a copied Python module
-- that invokes real host-native engines or exits non-zero.
appleNativeRunnerScript :: MetalEngineArtifact -> String
appleNativeRunnerScript artifact =
  appleNativeRunnerShellScript
    "#!/bin/sh"
    "set -eu"
    (Text.unpack (metalEngineAdapterId artifact))
    (Text.unpack (metalEngineName artifact))

appleNativeRunnerShellScript :: String -> String -> String -> String -> String
appleNativeRunnerShellScript shebang setFlags adapterId engineName =
  unlines
    ( [ shebang,
        setFlags,
        ""
      ]
        <> lines (appleNativeRunnerExecBody adapterId engineName)
    )

appleNativeRunnerExecBody :: String -> String -> String
appleNativeRunnerExecBody adapterId engineName =
  unlines
    [ "adapter_id=" <> shellLiteral adapterId,
      "engine_name=" <> shellLiteral engineName,
      "script_path=\"$0\"",
      "script_dir=\"${script_path%/*}\"",
      "root=\"$(CDPATH= cd -- \"$script_dir/..\" && pwd)\"",
      "python=\"$root/venv/bin/python\"",
      "if [ ! -x \"$python\" ]; then",
      "  if [ -x /opt/homebrew/bin/python3.12 ]; then",
      "    python=/opt/homebrew/bin/python3.12",
      "  elif [ -x /opt/homebrew/bin/python3 ]; then",
      "    python=/opt/homebrew/bin/python3",
      "  else",
      "    printf '%s\\n' \"native_payload_missing: Apple native Python 3.12 runtime\" >&2",
      "    exit 70",
      "  fi",
      "fi",
      "exec \"$python\" \"$root/lib/apple_native_runner.py\" --adapter-id \"$adapter_id\" --engine-name \"$engine_name\" --install-root \"$root\" \"$@\""
    ]

shellLiteral :: String -> String
shellLiteral rawValue = "'" <> concatMap escapeCharacter rawValue <> "'"
  where
    escapeCharacter '\'' = "'\\''"
    escapeCharacter character = [character]
