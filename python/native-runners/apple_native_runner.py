from __future__ import annotations

import argparse
import io
import math
import pathlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from dataclasses import dataclass


NATIVE_ARTIFACT_PREFIX = "infernix-native-artifact-file:"


@dataclass(frozen=True)
class RunnerArgs:
    adapter_id: str
    engine_name: str
    model_id: str
    selected_engine: str
    family: str
    install_root: pathlib.Path
    input_text: str
    input_object_ref: str
    input_file: str
    model_cache_root: pathlib.Path | None
    output_dir: pathlib.Path | None
    smoke_only: bool


def main() -> int:
    args = _parse_args()
    if args.smoke_only:
        return _run_smoke(args)
    try:
        _require_model_cache_ready(args)
        output = _run_inference(args)
    except RunnerFailure as exc:
        sys.stderr.write(str(exc) + "\n")
        return exc.exit_code
    print(output)
    return 0


class RunnerFailure(Exception):
    def __init__(self, message: str, exit_code: int = 70) -> None:
        super().__init__(message)
        self.exit_code = exit_code


def _parse_args() -> RunnerArgs:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--adapter-id", required=True)
    parser.add_argument("--engine-name", required=True)
    parser.add_argument("--model", default="")
    parser.add_argument("--engine", default="")
    parser.add_argument("--family", default="native")
    parser.add_argument("--install-root", default="")
    parser.add_argument("--input-text", default="")
    parser.add_argument("--input-object-ref", default="")
    parser.add_argument("--input-file", default="")
    parser.add_argument("--model-cache-root", default="")
    parser.add_argument("--model-cache-quota-bytes", default="")
    parser.add_argument("--minio-endpoint", default="")
    parser.add_argument("--minio-models-bucket", default="")
    parser.add_argument("--minio-demo-artifacts-bucket", default="infernix-demo-objects")
    parser.add_argument("--minio-region", default="")
    parser.add_argument("--output-dir", default="")
    parser.add_argument("--smoke", "--help", action="store_true", dest="smoke_only")
    parser.add_argument("--require-native-payload", action="store_true")
    parser.add_argument("--allow-missing-native-payload", action="store_true")
    parsed, _unknown = parser.parse_known_args()
    model_id = parsed.model or parsed.adapter_id
    install_root = pathlib.Path(parsed.install_root) if parsed.install_root else pathlib.Path.cwd()
    return RunnerArgs(
        adapter_id=parsed.adapter_id,
        engine_name=parsed.engine_name,
        model_id=model_id,
        selected_engine=parsed.engine,
        family=parsed.family,
        install_root=install_root,
        input_text=parsed.input_text,
        input_object_ref=parsed.input_object_ref,
        input_file=parsed.input_file,
        model_cache_root=pathlib.Path(parsed.model_cache_root) if parsed.model_cache_root else None,
        output_dir=pathlib.Path(parsed.output_dir) if parsed.output_dir else None,
        smoke_only=bool(parsed.smoke_only),
    )


def _run_smoke(args: RunnerArgs) -> int:
    if args.adapter_id == "llama-cpp-cli":
        _require_executable(pathlib.Path("/opt/homebrew/bin/llama-cli"))
    elif args.adapter_id == "whisper-cpp-cli":
        _require_executable(pathlib.Path("/opt/homebrew/bin/whisper-cli"))
    elif args.adapter_id == "jvm-native":
        _require_executable(_java_executable())
        _audiveris_executable(args.install_root)
    elif args.adapter_id in {"ctranslate2-native", "onnx-runtime-native", "mlx-native", "coreml-native"}:
        _smoke_python_runtime(args)
    else:
        raise RunnerFailure(f"unsupported Apple native adapter: {args.adapter_id}", 64)
    print(f"infernix apple native runtime smoke ok: {args.adapter_id}")
    return 0


def _smoke_python_runtime(args: RunnerArgs) -> None:
    # Phase 4 Sprint 4.25 — fail closed. The engine runtime lives in the
    # per-engine venv, so a smoke run under any other interpreter cannot
    # validate it; previously this returned green in that case, masking a
    # missing or broken venv. Require the venv interpreter, then import the
    # real engine runtime and surface any ImportError as a non-zero failure
    # rather than a silent pass.
    venv_root = (args.install_root / "venv").resolve()
    # Detect venv membership via sys.prefix (the venv root), not
    # pathlib(sys.executable).resolve(): the engine venv is created with
    # --symlinks, so resolving the interpreter follows the symlink out of the
    # venv to the base framework python and spuriously fails this check.
    # sys.prefix points at the venv root regardless of symlink-vs-copy mode.
    prefix = pathlib.Path(sys.prefix).resolve()
    if not _path_is_under(prefix, venv_root):
        raise RunnerFailure(
            f"apple native smoke for {args.adapter_id} must run under the engine venv "
            f"({venv_root}); the engine runtime cannot be validated from {sys.executable} "
            f"(interpreter prefix {prefix})",
            70,
        )
    adapter_id = args.adapter_id
    try:
        if adapter_id == "ctranslate2-native":
            import ctranslate2  # noqa: F401
            import faster_whisper  # noqa: F401
        elif adapter_id == "onnx-runtime-native":
            import onnxruntime  # noqa: F401
        elif adapter_id == "mlx-native":
            import mlx_lm  # noqa: F401
        elif adapter_id == "coreml-native":
            import basic_pitch  # noqa: F401
            import python_coreml_stable_diffusion.pipeline  # noqa: F401
        else:
            raise RunnerFailure(f"unsupported Python smoke adapter: {adapter_id}", 64)
    except ImportError as import_error:
        raise RunnerFailure(
            f"apple native engine runtime for {adapter_id} failed to import: {import_error}",
            70,
        ) from import_error


def _path_is_under(path: pathlib.Path, root: pathlib.Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def _require_model_cache_ready(args: RunnerArgs) -> None:
    if args.model_cache_root is None:
        return
    ready_path = args.model_cache_root / args.model_id / ".ready"
    if not ready_path.is_file():
        raise RunnerFailure(f"model_cache_not_populated: missing {ready_path}", 75)


def _run_inference(args: RunnerArgs) -> str:
    if args.adapter_id == "llama-cpp-cli":
        return _run_llama_cpp(args)
    if args.adapter_id == "whisper-cpp-cli":
        return _run_whisper_cpp(args)
    if args.adapter_id == "ctranslate2-native":
        return _run_ctranslate2(args)
    if args.adapter_id == "onnx-runtime-native":
        return _run_basic_pitch_onnx(args)
    if args.adapter_id == "mlx-native":
        return _run_mlx_lm(args)
    if args.adapter_id == "coreml-native":
        return _run_coreml(args)
    if args.adapter_id == "jvm-native":
        return _run_audiveris(args)
    raise RunnerFailure(f"unsupported Apple native adapter: {args.adapter_id}", 64)


def _model_dir(args: RunnerArgs) -> pathlib.Path:
    if args.model_cache_root is None:
        raise RunnerFailure("native model-cache root is required for real Apple inference", 70)
    return args.model_cache_root / args.model_id


def _model_payload(args: RunnerArgs) -> pathlib.Path:
    return _model_dir(args) / "payload"


def _require_file(path: pathlib.Path) -> pathlib.Path:
    if not path.is_file():
        raise RunnerFailure(f"native_payload_missing: {path}", 70)
    return path


def _require_executable(path: pathlib.Path) -> pathlib.Path:
    if not path.is_file() or not path.stat().st_mode & 0o111:
        raise RunnerFailure(f"native_payload_missing: {path}", 70)
    return path


def _require_input_file(args: RunnerArgs) -> pathlib.Path:
    if not args.input_file:
        raise RunnerFailure("native_payload_missing: input-file", 70)
    return _require_file(pathlib.Path(args.input_file))


def _require_output_dir(args: RunnerArgs) -> pathlib.Path:
    if args.output_dir is None:
        raise RunnerFailure("native artifact families require --output-dir", 64)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    return args.output_dir


def _native_runner_child_env() -> dict[str, str]:
    """Sprint 4.28 (managed-state-transition doctrine): give child subprocesses a
    real environment carrying HOME and TMPDIR, rather than an empty ``env={}``.

    Adapters must not read the process environment (the no-env-vars doctrine), so
    HOME is a fresh writable temp directory and TMPDIR is the system temp
    directory that ``tempfile`` already resolves. A minimal absolute PATH lets the
    child locate standard system tools without inheriting the operator's ambient
    PATH.
    """
    home_dir = tempfile.mkdtemp(prefix="infernix-native-home-")
    return {
        "HOME": home_dir,
        "TMPDIR": tempfile.gettempdir(),
        "PATH": "/usr/local/bin:/usr/bin:/bin",
    }


def _run_subprocess(
    command: list[str],
    *,
    cwd: pathlib.Path | None = None,
    timeout_seconds: int | None = None,
    require_output: bool = True,
) -> str:
    try:
        result = subprocess.run(
            command,
            cwd=str(cwd) if cwd is not None else None,
            env=_native_runner_child_env(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
            timeout=timeout_seconds,
        )
    except subprocess.TimeoutExpired as exc:
        detail = (exc.stderr or exc.stdout or "").strip()
        message = detail or f"command timed out after {timeout_seconds}s: {' '.join(command)}"
        raise RunnerFailure(message, 70) from exc
    if result.returncode != 0:
        raise RunnerFailure(result.stderr.strip() or f"command failed: {' '.join(command)}", 70)
    rendered = " ".join(result.stdout.split())
    if require_output and not rendered:
        raise RunnerFailure(f"command returned no output: {' '.join(command)}", 70)
    return rendered


def _run_llama_cpp(args: RunnerArgs) -> str:
    llama_cli = _require_executable(pathlib.Path("/opt/homebrew/bin/llama-cli"))
    model_path = _require_file(_model_payload(args))
    prompt = args.input_text or "Hello from Infernix"
    return _run_subprocess(
        [
            str(llama_cli),
            "-m",
            str(model_path),
            "-p",
            prompt,
            "-n",
            "8",
            "--ctx-size",
            "128",
            "--threads",
            "8",
            "--threads-batch",
            "8",
            "--no-warmup",
            "--gpu-layers",
            "all",
            "--no-display-prompt",
            "--single-turn",
            "--log-disable",
            "--simple-io",
        ],
        timeout_seconds=120,
    )


def _run_whisper_cpp(args: RunnerArgs) -> str:
    whisper_cli = _require_executable(pathlib.Path("/opt/homebrew/bin/whisper-cli"))
    model_path = _require_file(_model_payload(args))
    input_file = _require_input_file(args)
    return _run_subprocess(
        [
            str(whisper_cli),
            "-m",
            str(model_path),
            "-f",
            str(input_file),
            "-nt",
            "-np",
        ]
    )


def _run_ctranslate2(args: RunnerArgs) -> str:
    from faster_whisper import WhisperModel

    model_dir = _model_dir(args)
    _require_file(model_dir / "model.bin")
    input_file = _require_input_file(args)
    model = WhisperModel(str(model_dir), device="cpu", compute_type="default")
    segments, _info = model.transcribe(str(input_file), beam_size=1, vad_filter=False)
    text = " ".join(segment.text.strip() for segment in segments).strip()
    if not text:
        raise RunnerFailure("ctranslate2 produced an empty transcript", 70)
    return text


def _run_mlx_lm(args: RunnerArgs) -> str:
    from mlx_lm import generate, load

    model_dir = _model_dir(args)
    prompt = args.input_text or "Hello from Infernix"
    model, tokenizer = load(str(model_dir))
    output = generate(model, tokenizer, prompt=prompt, max_tokens=64, verbose=False)
    rendered = str(output).strip()
    if not rendered:
        raise RunnerFailure("MLX generated empty output", 70)
    return rendered


def _run_coreml(args: RunnerArgs) -> str:
    if "basic-pitch" in args.model_id:
        return _run_basic_pitch_coreml(args)
    if "stable-diffusion" in args.model_id:
        return _run_coreml_stable_diffusion(args)
    raise RunnerFailure(f"unsupported Core ML model id: {args.model_id}", 64)


def _run_basic_pitch_coreml(args: RunnerArgs) -> str:
    input_file = _require_input_file(args)
    output_dir = _require_output_dir(args)
    basic_pitch_cli = pathlib.Path(sys.executable).parent / "basic-pitch"
    _require_executable(basic_pitch_cli)
    result = subprocess.run(
        [str(basic_pitch_cli), str(output_dir), str(input_file)],
        env=_native_runner_child_env(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RunnerFailure(result.stderr.strip() or "basic-pitch Core ML invocation failed", 70)
    midi_path = _first_existing(output_dir, ["*.mid", "*/*.mid", "*.midi", "*/*.midi"])
    if midi_path is None:
        raise RunnerFailure("basic-pitch Core ML produced no MIDI artifact", 70)
    return NATIVE_ARTIFACT_PREFIX + str(midi_path)


def _run_coreml_stable_diffusion(args: RunnerArgs) -> str:
    model_dir = _model_dir(args)
    model_root = _first_existing_dir(
        model_dir,
        ["original/packages", "split_einsum/packages", "."],
    )
    output_dir = _require_output_dir(args)
    prompt = args.input_text or "a small red cube on a white table"
    command = [
        sys.executable,
        "-m",
        "python_coreml_stable_diffusion.pipeline",
        "--prompt",
        prompt,
        "-i",
        str(model_root),
        "-o",
        str(output_dir),
        "--model-version",
        "runwayml/stable-diffusion-v1-5",
        "--compute-unit",
        "CPU_AND_GPU",
        "--seed",
        "93",
        "--num-inference-steps",
        "2",
    ]
    _run_subprocess(command, timeout_seconds=900, require_output=False)
    image_path = _first_existing(output_dir, ["*.png", "*/*.png"])
    if image_path is None:
        raise RunnerFailure("Core ML Stable Diffusion produced no PNG artifact", 70)
    return NATIVE_ARTIFACT_PREFIX + str(image_path)


def _run_basic_pitch_onnx(args: RunnerArgs) -> str:
    import mido
    import numpy as np
    import onnxruntime as ort
    import scipy.signal
    import soundfile as sf

    model_path = _require_file(_model_payload(args))
    input_file = _require_input_file(args)
    output_dir = _require_output_dir(args)
    sample_rate = 22050
    fft_hop = 256
    n_samples = sample_rate * 2 - fft_hop
    annot_fps = 86
    annot_n_frames = annot_fps * 2
    overlap_frames = 30
    overlap_samples = overlap_frames * fft_hop
    hop_size = n_samples - overlap_samples
    onset_thresh = 0.5
    frame_thresh = 0.3
    energy_tol = 11
    midi_offset = 21
    max_freq_idx = 87
    min_note_len = int(round(127.70 / 1000.0 * (sample_rate / fft_hop)))

    audio, input_sample_rate = sf.read(str(input_file), dtype="float32", always_2d=True)
    audio = audio.mean(axis=1).astype("float32")
    if input_sample_rate != sample_rate:
        divisor = math.gcd(sample_rate, int(input_sample_rate))
        audio = scipy.signal.resample_poly(
            audio, sample_rate // divisor, int(input_sample_rate) // divisor
        ).astype("float32")
    original_len = int(audio.shape[0])
    if original_len <= 0:
        raise RunnerFailure("basic-pitch: empty audio after decode", 70)
    audio = np.concatenate(
        [np.zeros(overlap_samples // 2, dtype="float32"), audio]
    )

    session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name
    output_names = [
        "StatefulPartitionedCall:1",
        "StatefulPartitionedCall:2",
        "StatefulPartitionedCall:0",
    ]
    note_chunks: list[np.ndarray] = []
    onset_chunks: list[np.ndarray] = []
    for start in range(0, audio.shape[0], hop_size):
        window = audio[start : start + n_samples]
        if window.shape[0] < n_samples:
            window = np.pad(window, (0, n_samples - window.shape[0]))
        frame_input = window.reshape(1, n_samples, 1).astype("float32")
        note_out, onset_out, _contour_out = session.run(
            output_names, {input_name: frame_input}
        )
        note_chunks.append(note_out)
        onset_chunks.append(onset_out)

    frames = _unwrap_basic_pitch_chunks(note_chunks, original_len, hop_size)
    onsets = _unwrap_basic_pitch_chunks(onset_chunks, original_len, hop_size)
    n_frames = frames.shape[0]
    if n_frames < 1:
        raise RunnerFailure("basic-pitch: no frames produced", 70)

    onsets = _infer_basic_pitch_onsets(onsets, frames)
    peak_thresh_mat = np.zeros(onsets.shape)
    peaks = scipy.signal.argrelmax(onsets, axis=0)
    peak_thresh_mat[peaks] = onsets[peaks]
    onset_idx = np.where(peak_thresh_mat >= onset_thresh)
    remaining = frames.copy()
    events: list[tuple[int, int, int, float]] = []
    for note_start, freq_idx in zip(onset_idx[0][::-1], onset_idx[1][::-1]):
        if note_start >= n_frames - 1:
            continue
        i = int(note_start) + 1
        k = 0
        while i < n_frames - 1 and k < energy_tol:
            k = k + 1 if remaining[i, freq_idx] < frame_thresh else 0
            i += 1
        i -= k
        if i - note_start <= min_note_len:
            continue
        remaining[note_start:i, freq_idx] = 0
        if freq_idx < max_freq_idx:
            remaining[note_start:i, freq_idx + 1] = 0
        if freq_idx > 0:
            remaining[note_start:i, freq_idx - 1] = 0
        amplitude = float(np.mean(frames[note_start:i, freq_idx]))
        events.append((int(note_start), int(i), int(freq_idx + midi_offset), amplitude))

    while np.max(remaining) > frame_thresh:
        i_mid, freq_idx = np.unravel_index(np.argmax(remaining), remaining.shape)
        remaining[i_mid, freq_idx] = 0
        i = int(i_mid) + 1
        k = 0
        while i < n_frames - 1 and k < energy_tol:
            k = k + 1 if remaining[i, freq_idx] < frame_thresh else 0
            remaining[i, freq_idx] = 0
            if freq_idx < max_freq_idx:
                remaining[i, freq_idx + 1] = 0
            if freq_idx > 0:
                remaining[i, freq_idx - 1] = 0
            i += 1
        i_end = i - 1 - k
        i = int(i_mid) - 1
        k = 0
        while i > 0 and k < energy_tol:
            k = k + 1 if remaining[i, freq_idx] < frame_thresh else 0
            remaining[i, freq_idx] = 0
            if freq_idx < max_freq_idx:
                remaining[i, freq_idx + 1] = 0
            if freq_idx > 0:
                remaining[i, freq_idx - 1] = 0
            i -= 1
        i_start = i + 1 + k
        if i_end - i_start <= min_note_len:
            continue
        amplitude = float(np.mean(frames[i_start:i_end, freq_idx]))
        events.append((int(i_start), int(i_end), int(freq_idx + midi_offset), amplitude))

    if not events:
        raise RunnerFailure("basic-pitch: produced no notes", 70)

    times = _basic_pitch_frame_times(n_frames, fft_hop, sample_rate, annot_n_frames)
    midi = mido.MidiFile(ticks_per_beat=480)
    track = mido.MidiTrack()
    midi.tracks.append(track)
    track.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(120), time=0))

    def seconds_to_ticks(seconds: float) -> int:
        return int(round(seconds * 480 * 2))

    raw_events: list[tuple[int, int, int, int]] = []
    for start_frame, end_frame, pitch, amplitude in events:
        start_tick = seconds_to_ticks(float(times[start_frame]))
        end_tick = seconds_to_ticks(float(times[min(end_frame, n_frames - 1)]))
        velocity = max(1, min(127, int(round(127 * amplitude))))
        raw_events.append((start_tick, 1, pitch, velocity))
        raw_events.append((end_tick, 0, pitch, 0))
    raw_events.sort(key=lambda row: (row[0], row[1]))
    previous_tick = 0
    for tick, is_on, pitch, velocity in raw_events:
        delta = tick - previous_tick
        previous_tick = tick
        message = "note_on" if is_on else "note_off"
        track.append(mido.Message(message, note=pitch, velocity=velocity, time=delta))

    output_path = output_dir / f"{args.model_id}.mid"
    midi.save(output_path)
    if output_path.stat().st_size <= 0:
        raise RunnerFailure("basic-pitch: failed to write MIDI artifact", 70)
    return NATIVE_ARTIFACT_PREFIX + str(output_path)


def _unwrap_basic_pitch_chunks(
    chunks: list["np.ndarray"], original_len: int, hop_size: int
) -> "np.ndarray":
    import numpy as np

    overlap_frames = 30
    annot_fps = 86
    arr = np.concatenate(chunks, axis=0)
    drop = int(0.5 * overlap_frames)
    if drop > 0:
        arr = arr[:, drop:-drop, :]
    arr = arr.reshape(arr.shape[0] * arr.shape[1], arr.shape[2])
    frames_per_window = (2 * annot_fps) - overlap_frames
    keep = int((original_len / hop_size) * frames_per_window)
    return arr[:keep, :]


def _infer_basic_pitch_onsets(
    onset_mat: "np.ndarray", frame_mat: "np.ndarray", n_diff: int = 2
) -> "np.ndarray":
    import numpy as np

    diffs = []
    for n_value in range(1, n_diff + 1):
        padded = np.concatenate(
            [np.zeros((n_value, frame_mat.shape[1]), dtype=frame_mat.dtype), frame_mat],
            axis=0,
        )
        diffs.append(padded[n_value:, :] - padded[:-n_value, :])
    frame_diff = np.min(diffs, axis=0)
    frame_diff[frame_diff < 0] = 0
    frame_diff[:n_diff, :] = 0
    max_frame_diff = np.max(frame_diff)
    if max_frame_diff > 0:
        frame_diff = np.max(onset_mat) * frame_diff / max_frame_diff
    return np.max([onset_mat, frame_diff], axis=0)


def _basic_pitch_frame_times(
    count: int, fft_hop: int, sample_rate: int, annot_n_frames: int
) -> "np.ndarray":
    import numpy as np

    base = np.arange(count) * fft_hop / sample_rate
    window_numbers = np.floor(np.arange(count) / annot_n_frames)
    window_offset = (fft_hop / sample_rate) * (annot_n_frames - ((sample_rate * 2 - fft_hop) / fft_hop)) + 0.0018
    return base - window_offset * window_numbers


def _run_audiveris(args: RunnerArgs) -> str:
    audiveris_cli = _audiveris_executable(args.install_root)
    input_file = _require_input_file(args)
    output_dir = _require_output_dir(args)
    with tempfile.TemporaryDirectory(prefix="infernix-audiveris-home-") as home:
        result = subprocess.run(
            [
                str(audiveris_cli),
                "-batch",
                "-export",
                "-option",
                "org.audiveris.omr.sheet.BookManager.useCompression=false",
                "-output",
                str(output_dir),
                str(input_file),
            ],
            env={"HOME": home, "TMPDIR": home, "PATH": "/usr/local/bin:/usr/bin:/bin"},
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
    if result.returncode != 0:
        raise RunnerFailure(result.stderr.strip() or "audiveris failed", 70)
    artifact_path = _first_existing(
        output_dir,
        ["*.musicxml", "*/*.musicxml", "*.xml", "*/*.xml", "*.mxl", "*/*.mxl"],
    )
    if artifact_path is None:
        raise RunnerFailure("audiveris produced no MusicXML artifact", 70)
    return NATIVE_ARTIFACT_PREFIX + str(artifact_path)


def _audiveris_executable(install_root: pathlib.Path) -> pathlib.Path:
    candidates = [
        install_root / "Audiveris.app" / "Contents" / "MacOS" / "Audiveris",
        pathlib.Path("/Applications/Audiveris.app/Contents/MacOS/Audiveris"),
    ]
    for candidate in candidates:
        if candidate.is_file():
            return _require_executable(candidate)
    java_path = _java_executable()
    jar_path = install_root / "lib" / "audiveris.jar"
    if jar_path.is_file():
        wrapper = install_root / "bin" / "audiveris-java-wrapper"
        wrapper.parent.mkdir(parents=True, exist_ok=True)
        wrapper.write_text(
            "#!/bin/sh\n"
            "set -eu\n"
            f"exec {java_path} -jar {jar_path} \"$@\"\n",
            encoding="utf-8",
        )
        wrapper.chmod(0o755)
        return wrapper
    raise RunnerFailure(
        "native_payload_missing: Audiveris.app or lib/audiveris.jar under "
        f"{install_root}",
        70,
    )


def _java_executable() -> pathlib.Path:
    return _require_executable(pathlib.Path("/opt/homebrew/opt/openjdk/bin/java"))


def _first_existing(root: pathlib.Path, patterns: list[str]) -> pathlib.Path | None:
    for pattern in patterns:
        for candidate in sorted(root.glob(pattern)):
            if candidate.is_file() and candidate.stat().st_size > 0:
                return candidate
    return None


def _first_existing_dir(root: pathlib.Path, relative_paths: list[str]) -> pathlib.Path:
    for relative_path in relative_paths:
        candidate = root / relative_path
        if candidate.is_dir():
            return candidate
    raise RunnerFailure(f"native_payload_missing: Core ML model directory under {root}", 70)


def _zip_directory(output_path: pathlib.Path, root: pathlib.Path) -> None:
    with zipfile.ZipFile(output_path, "w") as archive:
        for path in sorted(root.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(root).as_posix())


def _copy_file(source: pathlib.Path, destination: pathlib.Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)


if __name__ == "__main__":
    raise SystemExit(main())
