{-# LANGUAGE OverloadedStrings #-}

module Infernix.Engines.LinuxNative
  ( LinuxNativeEngineArtifact (..),
    linuxNativeEngineArtifactAdapterIds,
    linuxNativeEngineBuildPlan,
    linuxNativeEngineImageRoot,
    linuxNativeEngineInstallRoot,
    linuxNativeRunnerScript,
    manifestForLinuxNativeEngineArtifact,
    materializeLinuxNativeEngineArtifact,
    materializeLinuxNativeEngines,
    materializeLinuxNativeEnginesAt,
  )
where

import Control.Monad (unless)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Infernix.Engines.AppleSilicon
  ( EngineArtifactManifest (..),
    engineArtifactManifestPath,
    engineArtifactTempRoot,
    installEngineArtifactRoot,
    renderEngineArtifactManifest,
  )
import System.Directory
  ( createDirectoryIfMissing,
    doesFileExist,
    getPermissions,
    removePathForcibly,
    setOwnerExecutable,
    setPermissions,
  )
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath (takeDirectory, (</>))
import System.Info (arch, os)
import System.Process (proc, readCreateProcessWithExitCode)

data LinuxNativeEngineArtifact = LinuxNativeEngineArtifact
  { linuxNativeEngineAdapterId :: Text,
    linuxNativeEngineName :: Text,
    linuxNativeEngineArtifactKind :: Text,
    linuxNativeEngineSourceRef :: Text,
    linuxNativeEngineVersion :: Text,
    linuxNativeRuntimeVersion :: Text,
    linuxNativeEntrypoint :: Text,
    linuxNativeSmokeCommand :: Text
  }
  deriving (Eq, Show)

linuxNativeEngineBuildPlan :: [LinuxNativeEngineArtifact]
linuxNativeEngineBuildPlan =
  [ LinuxNativeEngineArtifact "llama-cpp-cli" "llama.cpp Linux runner" "native-binary" "github:ggml-org/llama.cpp" "pinned-by-manifest" "linux-native" "bin/llama-cli" "bin/llama-cli --smoke",
    LinuxNativeEngineArtifact "whisper-cpp-cli" "whisper.cpp Linux runner" "native-binary" "github:ggml-org/whisper.cpp" "pinned-by-manifest" "linux-native" "bin/whisper-cli" "bin/whisper-cli --smoke",
    LinuxNativeEngineArtifact "onnx-runtime-native" "ONNX Runtime Linux runner" "native-binary" "github:microsoft/onnxruntime" "pinned-by-manifest" "linux-native" "bin/onnx-runner" "bin/onnx-runner --smoke",
    LinuxNativeEngineArtifact "ctranslate2-native" "CTranslate2 Linux runner" "native-binary" "github:OpenNMT/CTranslate2" "pinned-by-manifest" "linux-native" "bin/ct2-runner" "bin/ct2-runner --smoke",
    LinuxNativeEngineArtifact "jvm-native" "Audiveris JVM Linux runner" "jvm-tool" "github:Audiveris/audiveris" "pinned-by-manifest" "linux-native-jvm" "bin/audiveris" "bin/audiveris --smoke"
  ]

linuxNativeEngineArtifactAdapterIds :: [Text]
linuxNativeEngineArtifactAdapterIds = map linuxNativeEngineAdapterId linuxNativeEngineBuildPlan

linuxNativeEngineImageRoot :: FilePath
linuxNativeEngineImageRoot = "/opt/infernix/engines"

linuxNativeEngineInstallRoot :: FilePath -> Text -> FilePath
linuxNativeEngineInstallRoot baseRoot adapterId =
  baseRoot </> Text.unpack adapterId

materializeLinuxNativeEngines :: IO ()
materializeLinuxNativeEngines = do
  unless (os == "linux") $
    ioError (userError linuxNativeLaneNotLinuxMessage)
  materializeLinuxNativeEnginesAt linuxNativeEngineImageRoot

materializeLinuxNativeEnginesAt :: FilePath -> IO ()
materializeLinuxNativeEnginesAt baseRoot =
  mapM_ (materializeLinuxNativeEngineArtifact baseRoot) linuxNativeEngineBuildPlan

materializeLinuxNativeEngineArtifact :: FilePath -> LinuxNativeEngineArtifact -> IO FilePath
materializeLinuxNativeEngineArtifact baseRoot artifact = do
  let installRoot = linuxNativeEngineInstallRoot baseRoot (linuxNativeEngineAdapterId artifact)
      tempRoot = engineArtifactTempRoot installRoot
      manifest = manifestForLinuxNativeEngineArtifact installRoot artifact
  removePathForcibly tempRoot
  createDirectoryIfMissing True tempRoot
  LazyByteString.writeFile (engineArtifactManifestPath tempRoot) (renderEngineArtifactManifest manifest)
  writeLinuxNativeRunner tempRoot artifact
  writeFile
    (tempRoot </> "README.txt")
    ( "Infernix Linux native engine artifact root for "
        <> Text.unpack (linuxNativeEngineAdapterId artifact)
        <> ". The current machine-independent artifact is a runner-contract payload; Wave I replaces it "
        <> "with the external engine binary payload and records real-output validation.\n"
    )
  validateLinuxNativeArtifact tempRoot artifact
  installEngineArtifactRoot installRoot tempRoot
  pure installRoot

manifestForLinuxNativeEngineArtifact :: FilePath -> LinuxNativeEngineArtifact -> EngineArtifactManifest
manifestForLinuxNativeEngineArtifact installRoot artifact =
  let digest = linuxNativeEngineArtifactDigest artifact
      digestSuffix = Text.drop 1 (Text.dropWhile (/= ':') digest)
   in EngineArtifactManifest
        { manifestAdapterId = linuxNativeEngineAdapterId artifact,
          manifestEngineName = linuxNativeEngineName artifact,
          manifestSubstrate = "linux-native",
          manifestArchitecture = linuxNativeArchitecture,
          manifestArtifactKind = linuxNativeEngineArtifactKind artifact,
          manifestSourceRef = linuxNativeEngineSourceRef artifact,
          manifestEngineVersion = linuxNativeEngineVersion artifact,
          manifestPythonVersion = Nothing,
          manifestRuntimeVersion = linuxNativeRuntimeVersion artifact,
          manifestDigest = digest,
          manifestMinioObjectKey =
            "engine-artifacts/linux/"
              <> linuxNativeArchitecture
              <> "/"
              <> linuxNativeEngineAdapterId artifact
              <> "/"
              <> digestSuffix
              <> ".tar.zst",
          manifestLocalInstallRoot = installRoot,
          manifestEntrypoint = linuxNativeEntrypoint artifact,
          manifestSmokeCommand = linuxNativeSmokeCommand artifact
        }

linuxNativeEngineArtifactDigest :: LinuxNativeEngineArtifact -> Text
linuxNativeEngineArtifactDigest artifact =
  let digestInput =
        Text.intercalate
          "\n"
          [ linuxNativeEngineAdapterId artifact,
            linuxNativeEngineName artifact,
            linuxNativeEngineArtifactKind artifact,
            linuxNativeEngineSourceRef artifact,
            linuxNativeEngineVersion artifact,
            linuxNativeRuntimeVersion artifact,
            linuxNativeEntrypoint artifact,
            linuxNativeSmokeCommand artifact
          ]
      digestBytes = SHA256.hashlazy (LazyByteString.fromStrict (TextEncoding.encodeUtf8 digestInput))
   in "sha256:" <> TextEncoding.decodeUtf8 (Base16.encode digestBytes)

linuxNativeArchitecture :: Text
linuxNativeArchitecture =
  case arch of
    "x86_64" -> "amd64"
    "aarch64" -> "arm64"
    other -> Text.pack other

writeLinuxNativeRunner :: FilePath -> LinuxNativeEngineArtifact -> IO ()
writeLinuxNativeRunner tempRoot artifact = do
  let runnerPath = tempRoot </> Text.unpack (linuxNativeEntrypoint artifact)
  createDirectoryIfMissing True (takeDirectory runnerPath)
  writeFile runnerPath (linuxNativeRunnerScript artifact)
  permissions <- getPermissions runnerPath
  setPermissions runnerPath (setOwnerExecutable True permissions)

linuxNativeRunnerScript :: LinuxNativeEngineArtifact -> String
linuxNativeRunnerScript artifact =
  unlines
    [ "#!/bin/sh",
      "set -eu",
      "adapter_id=" <> shellLiteral (Text.unpack (linuxNativeEngineAdapterId artifact)),
      "engine_name=" <> shellLiteral (Text.unpack (linuxNativeEngineName artifact)),
      "for arg in \"$@\"; do",
      "  case \"${arg}\" in",
      "    --smoke|--help)",
      "      printf '%s\\n' \"infernix linux native runner-contract smoke ok: ${adapter_id}\"",
      "      exit 0",
      "      ;;",
      "  esac",
      "done",
      "",
      "model_id=\"\"",
      "selected_engine=\"\"",
      "family=\"\"",
      "install_root=\"\"",
      "input_text=\"\"",
      "input_object_ref=\"\"",
      "model_cache_root=\"\"",
      "demo_artifacts_bucket=\"infernix-demo-objects\"",
      "output_dir=\"\"",
      "",
      "while [ \"$#\" -gt 0 ]; do",
      "  case \"$1\" in",
      "    --model)",
      "      [ \"$#\" -ge 2 ] || { printf '%s\\n' \"missing value for --model\" >&2; exit 64; }",
      "      model_id=\"$2\"",
      "      shift 2",
      "      ;;",
      "    --engine)",
      "      [ \"$#\" -ge 2 ] || { printf '%s\\n' \"missing value for --engine\" >&2; exit 64; }",
      "      selected_engine=\"$2\"",
      "      shift 2",
      "      ;;",
      "    --family)",
      "      [ \"$#\" -ge 2 ] || { printf '%s\\n' \"missing value for --family\" >&2; exit 64; }",
      "      family=\"$2\"",
      "      shift 2",
      "      ;;",
      "    --install-root)",
      "      [ \"$#\" -ge 2 ] || { printf '%s\\n' \"missing value for --install-root\" >&2; exit 64; }",
      "      install_root=\"$2\"",
      "      shift 2",
      "      ;;",
      "    --input-text)",
      "      [ \"$#\" -ge 2 ] || { printf '%s\\n' \"missing value for --input-text\" >&2; exit 64; }",
      "      input_text=\"$2\"",
      "      shift 2",
      "      ;;",
      "    --input-object-ref)",
      "      [ \"$#\" -ge 2 ] || { printf '%s\\n' \"missing value for --input-object-ref\" >&2; exit 64; }",
      "      input_object_ref=\"$2\"",
      "      shift 2",
      "      ;;",
      "    --model-cache-root)",
      "      [ \"$#\" -ge 2 ] || { printf '%s\\n' \"missing value for --model-cache-root\" >&2; exit 64; }",
      "      model_cache_root=\"$2\"",
      "      shift 2",
      "      ;;",
      "    --output-dir)",
      "      [ \"$#\" -ge 2 ] || { printf '%s\\n' \"missing value for --output-dir\" >&2; exit 64; }",
      "      output_dir=\"$2\"",
      "      shift 2",
      "      ;;",
      "    --model-cache-quota-bytes|--minio-endpoint|--minio-models-bucket|--minio-region)",
      "      [ \"$#\" -ge 2 ] || { printf '%s\\n' \"missing value for $1\" >&2; exit 64; }",
      "      shift 2",
      "      ;;",
      "    --minio-demo-artifacts-bucket)",
      "      [ \"$#\" -ge 2 ] || { printf '%s\\n' \"missing value for --minio-demo-artifacts-bucket\" >&2; exit 64; }",
      "      demo_artifacts_bucket=\"$2\"",
      "      shift 2",
      "      ;;",
      "    *)",
      "      shift",
      "      ;;",
      "  esac",
      "done",
      "",
      "[ -n \"$model_id\" ] || model_id=\"$adapter_id\"",
      "[ -n \"$family\" ] || family=\"native\"",
      "if [ -n \"$model_cache_root\" ]; then",
      "  model_ready_path=\"${model_cache_root}/${model_id}/.ready\"",
      "  if [ ! -f \"$model_ready_path\" ]; then",
      "    printf '%s\\n' \"model_cache_not_populated: missing ${model_ready_path}\" >&2",
      "    exit 75",
      "  fi",
      "fi",
      "",
      "emit_artifact_ref() {",
      "  suffix=\"$1\"",
      "  description=\"$2\"",
      "  if [ -n \"$output_dir\" ]; then",
      "    mkdir -p \"$output_dir\"",
      "    artifact_path=\"${output_dir}/${model_id}${suffix}\"",
      "    printf '%s\\n' \"$description\" > \"$artifact_path\"",
      "    printf '%s\\n' \"infernix-native-artifact-file:${artifact_path}\"",
      "  else",
      "    printf '%s\\n' \"${demo_artifacts_bucket}/linux-native/runner-contract/${model_id}${suffix}\"",
      "  fi",
      "}",
      "",
      "case \"$family\" in",
      "  llm)",
      "    printf '%s\\n' \"Linux ${engine_name} native output for ${model_id}: ${input_text:-prompt accepted}\"",
      "    ;;",
      "  speech)",
      "    printf '%s\\n' \"Linux ${engine_name} native transcript for ${model_id}: ${input_object_ref:-audio accepted}\"",
      "    ;;",
      "  audio)",
      "    case \"$model_id\" in",
      "      *demucs*|*open-unmix*|*unmix*) suffix='.zip' ;;",
      "      *basic-pitch*) suffix='.mid' ;;",
      "      *bark*) suffix='.wav' ;;",
      "      *) suffix='.wav' ;;",
      "    esac",
      "    emit_artifact_ref \"$suffix\" \"Linux ${engine_name} native artifact for ${model_id}: ${input_text:-${input_object_ref:-artifact accepted}}\"",
      "    ;;",
      "  music)",
      "    emit_artifact_ref '.mid' \"Linux ${engine_name} native music artifact for ${model_id}: ${input_object_ref:-music accepted}\"",
      "    ;;",
      "  image)",
      "    emit_artifact_ref '.png' \"Linux ${engine_name} native image artifact for ${model_id}: ${input_text:-image accepted}\"",
      "    ;;",
      "  video)",
      "    emit_artifact_ref '.mp4' \"Linux ${engine_name} native video artifact for ${model_id}: ${input_text:-video accepted}\"",
      "    ;;",
      "  tool)",
      "    emit_artifact_ref '.musicxml' \"Linux ${engine_name} native tool artifact for ${model_id}: ${input_object_ref:-tool accepted}\"",
      "    ;;",
      "  *)",
      "    printf '%s\\n' \"Linux ${engine_name} native output for ${model_id}\"",
      "    ;;",
      "esac"
    ]

validateLinuxNativeArtifact :: FilePath -> LinuxNativeEngineArtifact -> IO ()
validateLinuxNativeArtifact tempRoot artifact = do
  let manifestPath = engineArtifactManifestPath tempRoot
      runnerPath = tempRoot </> Text.unpack (linuxNativeEntrypoint artifact)
  manifestPresent <- doesFileExist manifestPath
  unless manifestPresent $
    ioError (userError ("engine artifact manifest was not written under " <> tempRoot))
  runnerPresent <- doesFileExist runnerPath
  unless runnerPresent $
    ioError (userError ("native engine runner was not written under " <> runnerPath))
  (exitCode, _, stderrOutput) <- readCreateProcessWithExitCode (proc runnerPath ["--smoke"]) ""
  case exitCode of
    ExitSuccess -> pure ()
    _ -> ioError (userError ("native engine smoke failed for " <> runnerPath <> "\n" <> stderrOutput))

shellLiteral :: String -> String
shellLiteral rawValue = "'" <> concatMap escapeCharacter rawValue <> "'"
  where
    escapeCharacter '\'' = "'\\''"
    escapeCharacter character = [character]

linuxNativeLaneNotLinuxMessage :: String
linuxNativeLaneNotLinuxMessage =
  "infernix internal materialize-linux-native-engines is Linux-only: it bakes image-owned "
    <> "native runner roots under /opt/infernix/engines/<adapterId>/ for the Linux substrate images."
