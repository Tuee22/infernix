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
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, getPermissions, removePathForcibly, renameDirectory, setOwnerExecutable, setPermissions)
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
  [ MetalEngineArtifact "apple-metal-runtime-bridge" "Apple Metal Runtime Bridge" "native-framework" "infernix://native/apple-metal-bridge" "1" "Metal.framework/runtime" "lib/libinfernix-apple-metal-bridge.dylib:infernix_metal_runtime_probe" "bin/infernix-apple-metal-bridge-smoke",
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
  writeMetalEngineArtifactPayload tempRoot artifact
  writeFile
    (tempRoot </> "README.txt")
    ( "Infernix Apple engine artifact root for "
        <> Text.unpack (metalEngineAdapterId artifact)
        <> ". The materialized payload and smoke command are recorded in engine-artifact.json.\n"
    )
  validateMaterializedManifest tempRoot
  installEngineArtifactRoot installRoot tempRoot
  pure installRoot

writeMetalEngineArtifactPayload :: FilePath -> MetalEngineArtifact -> IO ()
writeMetalEngineArtifactPayload tempRoot artifact =
  when (metalEngineAdapterId artifact == "apple-metal-runtime-bridge") $ do
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

makeExecutable :: FilePath -> IO ()
makeExecutable filePath = do
  permissions <- getPermissions filePath
  setPermissions filePath (setOwnerExecutable True permissions)

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
