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
        <> "payloads under /opt/infernix/native-payloads. The runner emits only real engine "
        <> "output or exits non-zero; missing payloads fail closed and the Haskell worker passes "
        <> "--require-native-payload.\n"
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
      "whisper_cli=\"\"",
      "for whisper_candidate in \\",
      "  \"${payload_root}/whisper.cpp/whisper-bin-ubuntu-arm64/whisper-cli\" \\",
      "  \"${payload_root}/whisper.cpp/whisper-bin-ubuntu-x64/whisper-cli\"; do",
      "  [ -x \"$whisper_candidate\" ] || continue",
      "  whisper_cli=\"$whisper_candidate\"",
      "  break",
      "done",
      "basic_pitch_model=\"${payload_root}/basic-pitch/nmp.onnx\"",
      "audiveris_java=\"/opt/infernix/audiveris-jre/bin/java\"",
      "audiveris_classpath=\"/opt/audiveris/lib/app/*\"",
      "model_dir=\"\"",
      "model_payload=\"\"",
      "if [ -n \"$model_cache_root\" ]; then",
      "  model_dir=\"${model_cache_root}/${model_id}\"",
      "  model_payload=\"${model_dir}/payload\"",
      "fi",
      "",
      "payload_missing() {",
      "  missing_path=\"$1\"",
      "  if [ \"$strict_payloads\" -ne 1 ] && [ \"$smoke_only\" -eq 1 ]; then",
      "    printf '%s\\n' \"infernix linux native runtime smoke skipped missing payload: ${adapter_id}: ${missing_path}\"",
      "    exit 0",
      "  fi",
      "  printf '%s\\n' \"native_payload_missing: ${adapter_id}: ${missing_path}\" >&2",
      "  exit 70",
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
      "run_audiveris() {",
      "  require_executable \"$audiveris_java\"",
      "  require_file \"/opt/audiveris/lib/app/audiveris.jar\"",
      "  \"$audiveris_java\" -cp \"$audiveris_classpath\" Audiveris \"$@\"",
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
      "      run_audiveris -help >/dev/null",
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
      "      printf '%s\\n' \"$rendered\"",
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
      "          printf '%s\\n' \"$rendered\"",
      "        else",
      "          cat \"$tmp_error\" >&2",
      "          exit 70",
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
      "segments, _info = model.transcribe(input_file, beam_size=1, vad_filter=False)",
      "text = ' '.join(segment.text.strip() for segment in segments).strip()",
      "print(text)",
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
      "        [ -n \"$input_file\" ] || payload_missing \"input-file\"",
      "        [ -n \"$output_dir\" ] || { printf '%s\\n' \"basic-pitch requires --output-dir\" >&2; exit 64; }",
      "        mkdir -p \"$output_dir\"",
      "        \"$native_python\" - \"$basic_pitch_model\" \"$input_file\" \"$output_dir\" \"$model_id\" <<'PY'",
      "import math",
      "import os",
      "import sys",
      "",
      "import numpy as np",
      "import scipy.signal",
      "import soundfile as sf",
      "import onnxruntime as ort",
      "from mido import Message, MetaMessage, MidiFile, MidiTrack, bpm2tempo",
      "",
      "model_path, input_file, output_dir, model_id = sys.argv[1:5]",
      "",
      "SR = 22050",
      "FFT_HOP = 256",
      "N_SAMPLES = SR * 2 - FFT_HOP",
      "ANNOT_FPS = 86",
      "ANNOT_N_FRAMES = ANNOT_FPS * 2",
      "OVERLAP_FRAMES = 30",
      "OVERLAP_SAMPLES = OVERLAP_FRAMES * FFT_HOP",
      "HOP_SIZE = N_SAMPLES - OVERLAP_SAMPLES",
      "ONSET_THRESH = 0.5",
      "FRAME_THRESH = 0.3",
      "ENERGY_TOL = 11",
      "MIDI_OFFSET = 21",
      "MAX_FREQ_IDX = 87",
      "MIN_NOTE_LEN = int(round(127.70 / 1000.0 * (SR / FFT_HOP)))",
      "INPUT_NAME = 'serving_default_input_2:0'",
      "OUTPUT_NAMES = ['StatefulPartitionedCall:1', 'StatefulPartitionedCall:2', 'StatefulPartitionedCall:0']",
      "",
      "audio, in_sr = sf.read(input_file, dtype='float32', always_2d=True)",
      "audio = audio.mean(axis=1).astype('float32')",
      "if in_sr != SR:",
      "    g = math.gcd(SR, int(in_sr))",
      "    audio = scipy.signal.resample_poly(audio, SR // g, int(in_sr) // g).astype('float32')",
      "orig_len = int(audio.shape[0])",
      "if orig_len <= 0:",
      "    sys.stderr.write('basic-pitch: empty audio after decode\\n')",
      "    sys.exit(70)",
      "audio = np.concatenate([np.zeros(OVERLAP_SAMPLES // 2, dtype='float32'), audio])",
      "",
      "session = ort.InferenceSession(model_path, providers=['CPUExecutionProvider'])",
      "input_name = session.get_inputs()[0].name or INPUT_NAME",
      "acc = {'note': [], 'onset': [], 'contour': []}",
      "for start in range(0, audio.shape[0], HOP_SIZE):",
      "    window = audio[start:start + N_SAMPLES]",
      "    if window.shape[0] < N_SAMPLES:",
      "        window = np.pad(window, (0, N_SAMPLES - window.shape[0]))",
      "    x = window.reshape(1, N_SAMPLES, 1).astype('float32')",
      "    note_out, onset_out, contour_out = session.run(OUTPUT_NAMES, {input_name: x})",
      "    acc['note'].append(note_out)",
      "    acc['onset'].append(onset_out)",
      "    acc['contour'].append(contour_out)",
      "",
      "def unwrap(chunks):",
      "    arr = np.concatenate(chunks, axis=0)",
      "    drop = int(0.5 * OVERLAP_FRAMES)",
      "    if drop > 0:",
      "        arr = arr[:, drop:-drop, :]",
      "    arr = arr.reshape(arr.shape[0] * arr.shape[1], arr.shape[2])",
      "    frames_per_window = (2 * ANNOT_FPS) - OVERLAP_FRAMES",
      "    keep = int((orig_len / HOP_SIZE) * frames_per_window)",
      "    return arr[:keep, :]",
      "",
      "frames = unwrap(acc['note'])",
      "onsets = unwrap(acc['onset'])",
      "n_frames = frames.shape[0]",
      "if n_frames < 1:",
      "    sys.stderr.write('basic-pitch: no frames produced\\n')",
      "    sys.exit(70)",
      "",
      "def infer_onsets(onset_mat, frame_mat, n_diff=2):",
      "    diffs = []",
      "    for n in range(1, n_diff + 1):",
      "        padded = np.concatenate([np.zeros((n, frame_mat.shape[1]), dtype=frame_mat.dtype), frame_mat], axis=0)",
      "        diffs.append(padded[n:, :] - padded[:-n, :])",
      "    frame_diff = np.min(diffs, axis=0)",
      "    frame_diff[frame_diff < 0] = 0",
      "    frame_diff[:n_diff, :] = 0",
      "    frame_diff = np.max(onset_mat) * frame_diff / np.max(frame_diff)",
      "    return np.max([onset_mat, frame_diff], axis=0)",
      "",
      "onsets = infer_onsets(onsets, frames)",
      "",
      "peak_thresh_mat = np.zeros(onsets.shape)",
      "peaks = scipy.signal.argrelmax(onsets, axis=0)",
      "peak_thresh_mat[peaks] = onsets[peaks]",
      "onset_idx = np.where(peak_thresh_mat >= ONSET_THRESH)",
      "onset_times = onset_idx[0][::-1]",
      "onset_freqs = onset_idx[1][::-1]",
      "remaining = frames.copy()",
      "events = []",
      "for note_start, freq_idx in zip(onset_times, onset_freqs):",
      "    if note_start >= n_frames - 1:",
      "        continue",
      "    i = note_start + 1",
      "    k = 0",
      "    while i < n_frames - 1 and k < ENERGY_TOL:",
      "        k = k + 1 if remaining[i, freq_idx] < FRAME_THRESH else 0",
      "        i += 1",
      "    i -= k",
      "    if i - note_start <= MIN_NOTE_LEN:",
      "        continue",
      "    remaining[note_start:i, freq_idx] = 0",
      "    if freq_idx < MAX_FREQ_IDX:",
      "        remaining[note_start:i, freq_idx + 1] = 0",
      "    if freq_idx > 0:",
      "        remaining[note_start:i, freq_idx - 1] = 0",
      "    amplitude = float(np.mean(frames[note_start:i, freq_idx]))",
      "    events.append((int(note_start), int(i), int(freq_idx + MIDI_OFFSET), amplitude))",
      "",
      "while np.max(remaining) > FRAME_THRESH:",
      "    i_mid, freq_idx = np.unravel_index(np.argmax(remaining), remaining.shape)",
      "    remaining[i_mid, freq_idx] = 0",
      "    i = i_mid + 1",
      "    k = 0",
      "    while i < n_frames - 1 and k < ENERGY_TOL:",
      "        k = k + 1 if remaining[i, freq_idx] < FRAME_THRESH else 0",
      "        remaining[i, freq_idx] = 0",
      "        if freq_idx < MAX_FREQ_IDX:",
      "            remaining[i, freq_idx + 1] = 0",
      "        if freq_idx > 0:",
      "            remaining[i, freq_idx - 1] = 0",
      "        i += 1",
      "    i_end = i - 1 - k",
      "    i = i_mid - 1",
      "    k = 0",
      "    while i > 0 and k < ENERGY_TOL:",
      "        k = k + 1 if remaining[i, freq_idx] < FRAME_THRESH else 0",
      "        remaining[i, freq_idx] = 0",
      "        if freq_idx < MAX_FREQ_IDX:",
      "            remaining[i, freq_idx + 1] = 0",
      "        if freq_idx > 0:",
      "            remaining[i, freq_idx - 1] = 0",
      "        i -= 1",
      "    i_start = i + 1 + k",
      "    if i_end - i_start <= MIN_NOTE_LEN:",
      "        continue",
      "    amplitude = float(np.mean(frames[i_start:i_end, freq_idx]))",
      "    events.append((int(i_start), int(i_end), int(freq_idx + MIDI_OFFSET), amplitude))",
      "",
      "if not events:",
      "    sys.stderr.write('basic-pitch: produced no notes\\n')",
      "    sys.exit(70)",
      "",
      "def model_frames_to_time(count):",
      "    base = np.arange(count) * FFT_HOP / SR",
      "    window_numbers = np.floor(np.arange(count) / ANNOT_N_FRAMES)",
      "    window_offset = (FFT_HOP / SR) * (ANNOT_N_FRAMES - (N_SAMPLES / FFT_HOP)) + 0.0018",
      "    return base - window_offset * window_numbers",
      "",
      "times = model_frames_to_time(n_frames)",
      "",
      "TICKS_PER_BEAT = 480",
      "midi = MidiFile(ticks_per_beat=TICKS_PER_BEAT)",
      "track = MidiTrack()",
      "midi.tracks.append(track)",
      "track.append(MetaMessage('set_tempo', tempo=bpm2tempo(120), time=0))",
      "",
      "def seconds_to_ticks(seconds):",
      "    return int(round(seconds * TICKS_PER_BEAT * 2))",
      "",
      "raw_events = []",
      "for start_frame, end_frame, pitch, amplitude in events:",
      "    start_tick = seconds_to_ticks(times[start_frame])",
      "    end_tick = seconds_to_ticks(times[min(end_frame, n_frames - 1)])",
      "    velocity = max(1, min(127, int(round(127 * amplitude))))",
      "    raw_events.append((start_tick, 1, pitch, velocity))",
      "    raw_events.append((end_tick, 0, pitch, 0))",
      "raw_events.sort(key=lambda r: (r[0], r[1]))",
      "prev_tick = 0",
      "for tick, is_on, pitch, velocity in raw_events:",
      "    delta = tick - prev_tick",
      "    prev_tick = tick",
      "    message = 'note_on' if is_on else 'note_off'",
      "    track.append(Message(message, note=pitch, velocity=velocity, time=delta))",
      "",
      "output_path = os.path.join(output_dir, model_id + '.mid')",
      "midi.save(output_path)",
      "if not os.path.isfile(output_path) or os.path.getsize(output_path) <= 0:",
      "    sys.stderr.write('basic-pitch: failed to write MIDI artifact\\n')",
      "    sys.exit(70)",
      "print('infernix-native-artifact-file:' + os.path.abspath(output_path))",
      "PY",
      "        ;;",
      "      *)",
      "        printf '%s\\n' \"unsupported native audio model: ${model_id}\" >&2",
      "        exit 64",
      "        ;;",
      "    esac",
      "    ;;",
      "  music|image|video)",
      "    printf '%s\\n' \"native family ${family} is not served by the linux-native runner: ${model_id}\" >&2",
      "    exit 64",
      "    ;;",
      "  tool)",
      "    [ -n \"$input_file\" ] || payload_missing \"input-file\"",
      "    [ -n \"$output_dir\" ] || { printf '%s\\n' \"audiveris requires --output-dir\" >&2; exit 64; }",
      "    mkdir -p \"$output_dir\"",
      "    # Audiveris is a JVM tool that derives its data/config folders from HOME",
      "    # and aborts at class init when HOME is unset (the worker runs with a",
      "    # minimal environment). Give it a writable per-invocation HOME outside",
      "    # the export directory so it cannot clash with the collected MusicXML.",
      "    audiveris_home=\"$(mktemp -d)\"",
      "    # Export uncompressed MusicXML (.xml) rather than the default compressed",
      "    # .mxl container so the artifact matches the OMR result contract",
      "    # (.musicxml/.xml) and is directly parseable by the in-browser renderer.",
      "    if HOME=\"$audiveris_home\" run_audiveris -batch -export -option org.audiveris.omr.sheet.BookManager.useCompression=false -output \"$output_dir\" \"$input_file\" >&2; then",
      "      artifact_path=''",
      "      for candidate in \"$output_dir\"/*.mxl \"$output_dir\"/*/*.mxl \"$output_dir\"/*.musicxml \"$output_dir\"/*/*.musicxml \"$output_dir\"/*.xml \"$output_dir\"/*/*.xml; do",
      "        [ -f \"$candidate\" ] || continue",
      "        artifact_path=\"$candidate\"",
      "        break",
      "      done",
      "      if [ -n \"$artifact_path\" ]; then",
      "        printf '%s\\n' \"infernix-native-artifact-file:${artifact_path}\"",
      "      else",
      "        printf '%s\\n' \"audiveris produced no MusicXML for ${model_id}\" >&2",
      "        exit 70",
      "      fi",
      "    else",
      "      printf '%s\\n' \"audiveris failed for ${model_id}\" >&2",
      "      exit 70",
      "    fi",
      "    ;;",
      "  *)",
      "    printf '%s\\n' \"unsupported native family: ${family}\" >&2",
      "    exit 64",
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
