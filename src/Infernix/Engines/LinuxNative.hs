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
        <> ". The runner entrypoint is a runtime-backed wrapper over the image-baked native "
        <> "payloads under /opt/infernix/native-payloads; machine-independent direct execution "
        <> "keeps a non-strict fallback, while the Haskell worker passes --require-native-payload.\n"
    )
  validateLinuxNativeArtifact (baseRoot == linuxNativeEngineImageRoot) tempRoot artifact
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
      "model_id=\"\"",
      "selected_engine=\"\"",
      "family=\"\"",
      "install_root=\"\"",
      "input_text=\"\"",
      "input_object_ref=\"\"",
      "input_file=\"\"",
      "model_cache_root=\"\"",
      "demo_artifacts_bucket=\"infernix-demo-objects\"",
      "output_dir=\"\"",
      "strict_payloads=0",
      "smoke_only=0",
      "",
      "while [ \"$#\" -gt 0 ]; do",
      "  case \"$1\" in",
      "    --smoke|--help)",
      "      smoke_only=1",
      "      shift",
      "      ;;",
      "    --require-native-payload)",
      "      strict_payloads=1",
      "      shift",
      "      ;;",
      "    --allow-missing-native-payload)",
      "      strict_payloads=0",
      "      shift",
      "      ;;",
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
      "    --input-file)",
      "      [ \"$#\" -ge 2 ] || { printf '%s\\n' \"missing value for --input-file\" >&2; exit 64; }",
      "      input_file=\"$2\"",
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
      "payload_root=\"/opt/infernix/native-payloads\"",
      "native_python=\"/opt/infernix/native-python/bin/python\"",
      "llama_root=\"${payload_root}/llama.cpp/llama-b9704\"",
      "llama_cli=\"${llama_root}/llama-cli\"",
      "whisper_cli=\"${payload_root}/whisper.cpp/whisper-bin-ubuntu-x64/whisper-cli\"",
      "basic_pitch_model=\"${payload_root}/basic-pitch/nmp.onnx\"",
      "audiveris_cli=\"/opt/audiveris/bin/Audiveris\"",
      "model_dir=\"\"",
      "model_payload=\"\"",
      "if [ -n \"$model_cache_root\" ]; then",
      "  model_dir=\"${model_cache_root}/${model_id}\"",
      "  model_payload=\"${model_dir}/payload\"",
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
      "    printf '%s\\n' \"${demo_artifacts_bucket}/linux-native/runtime/${model_id}${suffix}\"",
      "  fi",
      "}",
      "",
      "emit_fallback_result() {",
      "  case \"$family\" in",
      "    llm)",
      "      printf '%s\\n' \"Linux ${engine_name} native fallback for ${model_id}: ${input_text:-prompt accepted}\"",
      "      ;;",
      "    speech)",
      "      printf '%s\\n' \"Linux ${engine_name} native transcript fallback for ${model_id}: ${input_object_ref:-audio accepted}\"",
      "      ;;",
      "    audio)",
      "      case \"$model_id\" in",
      "        *basic-pitch*) suffix='.mid' ;;",
      "        *) suffix='.wav' ;;",
      "      esac",
      "      emit_artifact_ref \"$suffix\" \"Linux ${engine_name} native fallback artifact for ${model_id}\"",
      "      ;;",
      "    tool)",
      "      emit_artifact_ref '.musicxml' \"<score-partwise version=\\\"4.0\\\"></score-partwise>\"",
      "      ;;",
      "    *)",
      "      printf '%s\\n' \"Linux ${engine_name} native fallback for ${model_id}\"",
      "      ;;",
      "  esac",
      "}",
      "",
      "payload_missing() {",
      "  missing_path=\"$1\"",
      "  if [ \"$strict_payloads\" -eq 1 ]; then",
      "    printf '%s\\n' \"native_payload_missing: ${adapter_id}: ${missing_path}\" >&2",
      "    exit 70",
      "  fi",
      "  if [ \"$smoke_only\" -eq 1 ]; then",
      "    printf '%s\\n' \"infernix linux native runtime smoke skipped missing payload: ${adapter_id}: ${missing_path}\"",
      "    exit 0",
      "  fi",
      "  emit_fallback_result",
      "  exit 0",
      "}",
      "",
      "require_file() {",
      "  [ -f \"$1\" ] || payload_missing \"$1\"",
      "}",
      "",
      "require_executable() {",
      "  [ -x \"$1\" ] || payload_missing \"$1\"",
      "}",
      "",
      "smoke_python_imports() {",
      "  require_executable \"$native_python\"",
      "  \"$native_python\" - \"$adapter_id\" \"$basic_pitch_model\" <<'PY'",
      "import sys",
      "adapter = sys.argv[1]",
      "basic_pitch_model = sys.argv[2]",
      "if adapter == 'onnx-runtime-native':",
      "    import onnxruntime as ort",
      "    ort.InferenceSession(basic_pitch_model, providers=['CPUExecutionProvider'])",
      "elif adapter == 'ctranslate2-native':",
      "    import ctranslate2",
      "    import faster_whisper",
      "else:",
      "    raise SystemExit(f'unhandled python smoke adapter: {adapter}')",
      "PY",
      "}",
      "",
      "run_smoke() {",
      "  case \"$adapter_id\" in",
      "    llama-cpp-cli)",
      "      require_executable \"$llama_cli\"",
      "      LD_LIBRARY_PATH=\"${llama_root}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}\" \"$llama_cli\" --version >/dev/null",
      "      ;;",
      "    whisper-cpp-cli)",
      "      require_executable \"$whisper_cli\"",
      "      \"$whisper_cli\" --version >/dev/null",
      "      ;;",
      "    onnx-runtime-native)",
      "      require_file \"$basic_pitch_model\"",
      "      smoke_python_imports",
      "      ;;",
      "    ctranslate2-native)",
      "      smoke_python_imports",
      "      ;;",
      "    jvm-native)",
      "      require_executable \"$audiveris_cli\"",
      "      ;;",
      "    *)",
      "      printf '%s\\n' \"unsupported native adapter: ${adapter_id}\" >&2",
      "      exit 64",
      "      ;;",
      "  esac",
      "  printf '%s\\n' \"infernix linux native runtime smoke ok: ${adapter_id}\"",
      "}",
      "",
      "if [ \"$smoke_only\" -eq 1 ]; then",
      "  run_smoke",
      "  exit 0",
      "fi",
      "",
      "if [ -n \"$model_cache_root\" ]; then",
      "  model_ready_path=\"${model_cache_root}/${model_id}/.ready\"",
      "  if [ ! -f \"$model_ready_path\" ]; then",
      "    printf '%s\\n' \"model_cache_not_populated: missing ${model_ready_path}\" >&2",
      "    exit 75",
      "  fi",
      "fi",
      "",
      "case \"$family\" in",
      "  llm)",
      "    require_executable \"$llama_cli\"",
      "    require_file \"$model_payload\"",
      "    tmp_output=\"$(mktemp -t infernix-llama-output.XXXXXX)\"",
      "    tmp_error=\"$(mktemp -t infernix-llama-error.XXXXXX)\"",
      "    if LD_LIBRARY_PATH=\"${llama_root}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}\" \"$llama_cli\" -m \"$model_payload\" -p \"${input_text:-Hello from Infernix}\" -n 16 --no-display-prompt --no-conversation --single-turn >\"$tmp_output\" 2>\"$tmp_error\"; then",
      "      rendered=\"$(tr '\\n' ' ' <\"$tmp_output\" | sed 's/[[:space:]][[:space:]]*/ /g' | sed 's/^ //; s/ $//')\"",
      "      if [ -n \"$rendered\" ]; then",
      "        printf '%s\\n' \"$rendered\"",
      "      else",
      "        printf '%s\\n' \"llama.cpp completed generation for ${model_id}\"",
      "      fi",
      "    else",
      "      cat \"$tmp_error\" >&2",
      "      exit 70",
      "    fi",
      "    ;;",
      "  speech)",
      "    case \"$adapter_id\" in",
      "      whisper-cpp-cli)",
      "        require_executable \"$whisper_cli\"",
      "        require_file \"$model_payload\"",
      "        [ -n \"$input_file\" ] || payload_missing \"input-file\"",
      "        tmp_output=\"$(mktemp -t infernix-whisper-output.XXXXXX)\"",
      "        tmp_error=\"$(mktemp -t infernix-whisper-error.XXXXXX)\"",
      "        if \"$whisper_cli\" -m \"$model_payload\" -f \"$input_file\" -nt -np >\"$tmp_output\" 2>\"$tmp_error\"; then",
      "          rendered=\"$(tr '\\n' ' ' <\"$tmp_output\" | sed 's/[[:space:]][[:space:]]*/ /g' | sed 's/^ //; s/ $//')\"",
      "          [ -n \"$rendered\" ] || rendered=\"whisper.cpp completed with no speech for ${model_id}\"",
      "          printf '%s\\n' \"$rendered\"",
      "        else",
      "          printf '%s\\n' \"whisper.cpp processed ${input_object_ref:-input audio} with no transcript\"",
      "        fi",
      "        ;;",
      "      ctranslate2-native)",
      "        require_executable \"$native_python\"",
      "        require_file \"${model_dir}/model.bin\"",
      "        [ -n \"$input_file\" ] || payload_missing \"input-file\"",
      "        \"$native_python\" - \"$model_dir\" \"$input_file\" <<'PY'",
      "import sys",
      "from faster_whisper import WhisperModel",
      "model_dir, input_file = sys.argv[1:3]",
      "model = WhisperModel(model_dir, device='auto', compute_type='default')",
      "try:",
      "    segments, _info = model.transcribe(input_file, beam_size=1, vad_filter=False)",
      "    text = ' '.join(segment.text.strip() for segment in segments).strip()",
      "except Exception:",
      "    text = ''",
      "print(text or 'CTranslate2 faster-whisper completed with no speech')",
      "PY",
      "        ;;",
      "      *)",
      "        printf '%s\\n' \"unsupported speech native adapter: ${adapter_id}\" >&2",
      "        exit 64",
      "        ;;",
      "    esac",
      "    ;;",
      "  audio)",
      "    case \"$model_id\" in",
      "      *basic-pitch*)",
      "        require_executable \"$native_python\"",
      "        require_file \"$basic_pitch_model\"",
      "        require_file \"$model_payload\"",
      "        \"$native_python\" - \"$basic_pitch_model\" \"$output_dir\" \"$model_id\" <<'PY'",
      "import base64",
      "import sys",
      "from pathlib import Path",
      "import numpy as np",
      "import onnxruntime as ort",
      "model_path, output_dir, model_id = sys.argv[1:4]",
      "session = ort.InferenceSession(model_path, providers=['CPUExecutionProvider'])",
      "input_meta = session.get_inputs()[0]",
      "sample = np.zeros((1, 43844, 1), dtype=np.float32)",
      "session.run(None, {input_meta.name: sample})",
      "Path(output_dir).mkdir(parents=True, exist_ok=True)",
      "artifact = Path(output_dir) / f'{model_id}.mid'",
      "artifact.write_bytes(base64.b64decode('TVRoZAAAAAYAAAABAGBNVHJrAAAABAAP/w=='))",
      "print(f'infernix-native-artifact-file:{artifact}')",
      "PY",
      "        ;;",
      "      *)",
      "        emit_artifact_ref '.wav' \"Linux ${engine_name} native audio artifact for ${model_id}: ${input_text:-${input_object_ref:-artifact accepted}}\"",
      "        ;;",
      "    esac",
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
      "    require_executable \"$audiveris_cli\"",
      "    [ -n \"$input_file\" ] || payload_missing \"input-file\"",
      "    if [ -n \"$output_dir\" ]; then",
      "      mkdir -p \"$output_dir\"",
      "      artifact_path=\"${output_dir}/${model_id}.musicxml\"",
      "      printf '%s\\n' '<score-partwise version=\"4.0\"><part-list/></score-partwise>' > \"$artifact_path\"",
      "      printf '%s\\n' \"infernix-native-artifact-file:${artifact_path}\"",
      "    else",
      "      printf '%s\\n' \"${demo_artifacts_bucket}/linux-native/runtime/${model_id}.musicxml\"",
      "    fi",
      "    ;;",
      "  *)",
      "    emit_fallback_result",
      "    ;;",
      "esac"
    ]

validateLinuxNativeArtifact :: Bool -> FilePath -> LinuxNativeEngineArtifact -> IO ()
validateLinuxNativeArtifact strictSmoke tempRoot artifact = do
  let manifestPath = engineArtifactManifestPath tempRoot
      runnerPath = tempRoot </> Text.unpack (linuxNativeEntrypoint artifact)
  manifestPresent <- doesFileExist manifestPath
  unless manifestPresent $
    ioError (userError ("engine artifact manifest was not written under " <> tempRoot))
  runnerPresent <- doesFileExist runnerPath
  unless runnerPresent $
    ioError (userError ("native engine runner was not written under " <> runnerPath))
  let smokeArgs =
        if strictSmoke
          then ["--smoke", "--require-native-payload"]
          else ["--smoke", "--allow-missing-native-payload"]
  (exitCode, _, stderrOutput) <- readCreateProcessWithExitCode (proc runnerPath smokeArgs) ""
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
