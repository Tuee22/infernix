from __future__ import annotations

import argparse
import importlib.metadata
import json
import math
import os
import pathlib
import sys
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
    generation_bound: int
    input_text: str
    input_object_ref: str
    input_file: str
    model_cache_root: pathlib.Path | None
    output_dir: pathlib.Path | None
    expected_python_prefix: pathlib.Path
    expected_unavailable_source_directories: tuple[pathlib.Path, ...]
    expected_unavailable_source_files: tuple[pathlib.Path, ...]
    expected_unavailable_source_write_probe: pathlib.Path | None
    source_isolation_receipt: str
    smoke_only: bool


def main() -> int:
    args = _parse_args()
    try:
        _verify_expected_source_isolation(args)
        if args.smoke_only:
            return _run_smoke(args)
        _require_execution_shape(args)
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


def _require_execution_shape(args: RunnerArgs) -> None:
    if args.generation_bound <= 0:
        raise RunnerFailure("native execution requires a positive generation bound", 64)


def _parse_args() -> RunnerArgs:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--adapter-id", required=True)
    parser.add_argument("--engine-name", required=True)
    parser.add_argument("--model", default="")
    parser.add_argument("--engine", default="")
    parser.add_argument("--family", default="native")
    parser.add_argument("--install-root", default="")
    parser.add_argument("--generation-bound", type=int, default=0)
    parser.add_argument("--input-text", default="")
    parser.add_argument("--input-object-ref", default="")
    parser.add_argument("--input-file", default="")
    parser.add_argument("--model-cache-root", default="")
    parser.add_argument("--model-cache-quota-bytes", default="")
    parser.add_argument("--minio-endpoint", default="")
    parser.add_argument("--minio-models-bucket", default="")
    parser.add_argument(
        "--minio-demo-artifacts-bucket", default="infernix-demo-objects"
    )
    parser.add_argument("--minio-region", default="")
    parser.add_argument("--output-dir", default="")
    parser.add_argument("--expected-python-prefix", required=True)
    parser.add_argument(
        "--expected-unavailable-source-directory", action="append", default=[]
    )
    parser.add_argument(
        "--expected-unavailable-source-file", action="append", default=[]
    )
    parser.add_argument("--expected-unavailable-source-write-probe", default="")
    parser.add_argument("--source-isolation-receipt", default="")
    parser.add_argument("--smoke", action="store_true", dest="smoke_only")
    parser.add_argument("--require-native-payload", action="store_true")
    parser.add_argument("--allow-missing-native-payload", action="store_true")
    parsed = parser.parse_args()
    model_id = parsed.model or parsed.adapter_id
    install_root = (
        pathlib.Path(parsed.install_root) if parsed.install_root else pathlib.Path.cwd()
    )
    return RunnerArgs(
        adapter_id=parsed.adapter_id,
        engine_name=parsed.engine_name,
        model_id=model_id,
        selected_engine=parsed.engine,
        family=parsed.family,
        install_root=install_root,
        generation_bound=parsed.generation_bound,
        input_text=parsed.input_text,
        input_object_ref=parsed.input_object_ref,
        input_file=parsed.input_file,
        model_cache_root=(
            pathlib.Path(parsed.model_cache_root) if parsed.model_cache_root else None
        ),
        output_dir=pathlib.Path(parsed.output_dir) if parsed.output_dir else None,
        expected_python_prefix=pathlib.Path(parsed.expected_python_prefix),
        expected_unavailable_source_directories=tuple(
            pathlib.Path(path) for path in parsed.expected_unavailable_source_directory
        ),
        expected_unavailable_source_files=tuple(
            pathlib.Path(path) for path in parsed.expected_unavailable_source_file
        ),
        expected_unavailable_source_write_probe=(
            pathlib.Path(parsed.expected_unavailable_source_write_probe)
            if parsed.expected_unavailable_source_write_probe
            else None
        ),
        source_isolation_receipt=str(parsed.source_isolation_receipt),
        smoke_only=bool(parsed.smoke_only),
    )


def _verify_expected_source_isolation(args: RunnerArgs) -> None:
    directories = args.expected_unavailable_source_directories
    files = args.expected_unavailable_source_files
    writable_probe = args.expected_unavailable_source_write_probe
    receipt = args.source_isolation_receipt
    if not directories and not files and writable_probe is None and not receipt:
        return
    source_paths = (*directories, *files)
    digest = receipt.removeprefix("sha256:")
    if (
        not args.smoke_only
        or len(directories) != 1
        or len(files) > 512
        or len({str(path) for path in source_paths}) != len(source_paths)
        or any(not path.is_absolute() for path in source_paths)
        or writable_probe is None
        or writable_probe not in files
        or not writable_probe.is_absolute()
        or len(digest) != 64
        or any(character not in "0123456789abcdef" for character in digest)
        or receipt != "sha256:" + digest
    ):
        raise RunnerFailure("invalid installed Python source-isolation contract", 64)
    allowed_sentinel = pathlib.Path(__file__)
    try:
        with allowed_sentinel.open("rb") as handle:
            sentinel_byte = handle.read(1)
    except OSError as exc:
        raise RunnerFailure(
            f"installed runner sentinel became unreadable: {allowed_sentinel}", 70
        ) from exc
    if not sentinel_byte:
        raise RunnerFailure(
            f"installed runner sentinel is empty: {allowed_sentinel}", 70
        )
    for source_directory in directories:
        try:
            next(source_directory.iterdir())
        except PermissionError:
            pass
        except StopIteration as exc:
            raise RunnerFailure(
                f"expected source directory is readable and empty: {source_directory}",
                70,
            ) from exc
        except OSError as exc:
            raise RunnerFailure(
                f"expected source directory denial was not PermissionError: "
                f"{source_directory}: {exc}",
                70,
            ) from exc
        else:
            raise RunnerFailure(
                f"expected source directory remains readable: {source_directory}", 70
            )
    for source_file in files:
        try:
            with source_file.open("rb") as handle:
                handle.read(1)
        except PermissionError:
            pass
        except OSError as exc:
            raise RunnerFailure(
                f"expected source file denial was not PermissionError: "
                f"{source_file}: {exc}",
                70,
            ) from exc
        else:
            raise RunnerFailure(
                f"expected source file remains readable: {source_file}", 70
            )
    try:
        writable_probe_fd = os.open(writable_probe, os.O_WRONLY)
    except PermissionError:
        pass
    except OSError as exc:
        raise RunnerFailure(
            f"expected writable source probe denial was not PermissionError: "
            f"{writable_probe}: {exc}",
            70,
        ) from exc
    else:
        os.close(writable_probe_fd)
        raise RunnerFailure(
            f"expected source write probe remains writable: {writable_probe}", 70
        )
    sys.stderr.write(f"infernix-source-isolation-v1:{len(source_paths)}:{receipt}\n")
    sys.stderr.flush()


def _run_smoke(args: RunnerArgs) -> int:
    if args.adapter_id in {
        "ctranslate2-native",
        "onnx-runtime-native",
        "mlx-native",
        "coreml-native",
    }:
        packages = _smoke_python_runtime(args)
    elif args.adapter_id in {
        "llama-cpp-cli",
        "whisper-cpp-cli",
        "jvm-native",
    }:
        raise RunnerFailure(
            f"{args.adapter_id} smoke must use Haskell direct-target supervision",
            70,
        )
    else:
        raise RunnerFailure(f"unsupported Apple native adapter: {args.adapter_id}", 64)
    print(
        json.dumps(
            {
                "adapterId": args.adapter_id,
                "packages": packages,
                "schemaVersion": 1,
            },
            separators=(",", ":"),
            sort_keys=True,
        )
    )
    return 0


def _smoke_python_runtime(args: RunnerArgs) -> dict[str, str]:
    # Phase 4 Sprint 4.25 — fail closed. The engine runtime lives in the
    # per-engine venv, so a smoke run under any other interpreter cannot
    # validate it; previously this returned green in that case, masking a
    # missing or broken venv. Require the venv interpreter, then import the
    # real engine runtime and surface any ImportError as a non-zero failure
    # rather than a silent pass.
    venv_root = args.expected_python_prefix.resolve()
    # Detect venv membership via sys.prefix (the venv root), not
    # pathlib(sys.executable).resolve(): the interpreter path is not the venv
    # identity, and upstream packages may still contain contained links even
    # though provisioning creates the interpreter with --copies. sys.prefix
    # points at the venv root independently of either representation.
    prefix = pathlib.Path(sys.prefix).resolve()
    if not _path_is_under(prefix, venv_root):
        raise RunnerFailure(
            f"native smoke for {args.adapter_id} must run under its sealed Python prefix "
            f"({venv_root}); the engine runtime cannot be validated from {sys.executable} "
            f"(interpreter prefix {prefix})",
            70,
        )
    adapter_id = args.adapter_id
    try:
        if adapter_id == "ctranslate2-native":
            import ctranslate2  # noqa: F401
            import faster_whisper  # noqa: F401

            return {
                "ctranslate2": importlib.metadata.version("ctranslate2"),
                "faster-whisper": importlib.metadata.version("faster-whisper"),
            }
        elif adapter_id == "onnx-runtime-native":
            import onnxruntime  # noqa: F401

            return {"onnxruntime": importlib.metadata.version("onnxruntime")}
        elif adapter_id == "mlx-native":
            import mlx.core as mx
            import mlx_lm  # noqa: F401

            previous_device = mx.default_device()
            try:
                mx.set_default_device(mx.gpu)
                observed = mx.array([41], dtype=mx.int32) + 1
                mx.eval(observed)
                mx.synchronize()
                if observed.item() != 42:
                    raise RunnerFailure(
                        f"upstream MLX GPU smoke produced {observed.item()}, expected 42",
                        70,
                    )
                return {
                    "mlx": importlib.metadata.version("mlx"),
                    "mlx-lm": importlib.metadata.version("mlx-lm"),
                }
            finally:
                mx.set_default_device(previous_device)
        elif adapter_id == "coreml-native":
            import basic_pitch  # noqa: F401
            import coremltools as ct
            import python_coreml_stable_diffusion.pipeline  # noqa: F401

            devices = ct.models.MLModel.get_available_compute_devices()
            if not devices:
                raise RunnerFailure(
                    "upstream coremltools reported no available Core ML compute devices",
                    70,
                )
            return {
                "apple-ml-stable-diffusion": importlib.metadata.version(
                    "python-coreml-stable-diffusion"
                ),
                "basic-pitch": importlib.metadata.version("basic-pitch"),
                "coremltools": ct.__version__,
            }
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
    if args.adapter_id == "ctranslate2-native":
        return _run_ctranslate2(args)
    if args.adapter_id == "onnx-runtime-native":
        return _run_basic_pitch_onnx(args)
    if args.adapter_id == "mlx-native":
        return _run_mlx_lm(args)
    if args.adapter_id == "coreml-native":
        return _run_coreml(args)
    if args.adapter_id in {
        "llama-cpp-cli",
        "whisper-cpp-cli",
        "jvm-native",
    }:
        raise RunnerFailure(
            f"{args.adapter_id} inference must use Haskell direct-target supervision",
            70,
        )
    raise RunnerFailure(f"unsupported Apple native adapter: {args.adapter_id}", 64)


def _model_dir(args: RunnerArgs) -> pathlib.Path:
    if args.model_cache_root is None:
        raise RunnerFailure(
            "native model-cache root is required for real Apple inference", 70
        )
    return args.model_cache_root / args.model_id


def _model_payload(args: RunnerArgs) -> pathlib.Path:
    return _model_dir(args) / "payload"


def _require_file(path: pathlib.Path) -> pathlib.Path:
    if not path.is_file():
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


def _require_nonempty_output(
    output_dir: pathlib.Path, artifact_path: pathlib.Path, description: str
) -> pathlib.Path:
    if output_dir.is_symlink():
        raise RunnerFailure(
            f"{description} output root may not be a symbolic link: {output_dir}",
            70,
        )
    resolved_output_dir = output_dir.resolve()
    absolute_artifact = artifact_path.absolute()
    try:
        relative_artifact = absolute_artifact.relative_to(output_dir.absolute())
    except ValueError as exc:
        raise RunnerFailure(
            f"{description} produced an artifact outside {output_dir.absolute()}: "
            f"{absolute_artifact}",
            70,
        ) from exc
    current_path = output_dir.absolute()
    for component in relative_artifact.parts:
        current_path /= component
        if current_path.is_symlink():
            raise RunnerFailure(
                f"{description} artifact path contains a symbolic link: {current_path}",
                70,
            )
    resolved_artifact = artifact_path.resolve()
    if not _path_is_under(resolved_artifact, resolved_output_dir):
        raise RunnerFailure(
            f"{description} produced an artifact outside {resolved_output_dir}: "
            f"{resolved_artifact}",
            70,
        )
    try:
        artifact_size = resolved_artifact.stat().st_size
    except OSError as exc:
        raise RunnerFailure(
            f"{description} did not produce the expected artifact "
            f"{resolved_artifact}: {exc}",
            70,
        ) from exc
    if not resolved_artifact.is_file() or artifact_size <= 0:
        raise RunnerFailure(
            f"{description} produced an empty or non-regular artifact: "
            f"{resolved_artifact}",
            70,
        )
    return resolved_artifact


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
    output = generate(
        model,
        tokenizer,
        prompt=prompt,
        max_tokens=args.generation_bound,
        verbose=False,
    )
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
    from basic_pitch import ICASSP_2022_MODEL_PATH
    from basic_pitch.inference import predict_and_save

    input_file = _require_input_file(args)
    output_dir = _require_output_dir(args)
    predict_and_save(
        [input_file],
        output_dir,
        save_midi=True,
        sonify_midi=False,
        save_model_outputs=False,
        save_notes=False,
        model_or_model_path=ICASSP_2022_MODEL_PATH,
    )
    midi_path = _require_nonempty_output(
        output_dir,
        output_dir / f"{input_file.stem}_basic_pitch.mid",
        "basic-pitch Core ML",
    )
    return NATIVE_ARTIFACT_PREFIX + str(midi_path)


def _run_coreml_stable_diffusion(args: RunnerArgs) -> str:
    from python_coreml_stable_diffusion import pipeline

    model_dir = _model_dir(args)
    model_root = _first_existing_dir(
        model_dir,
        ["original/packages", "split_einsum/packages", "."],
    )
    output_dir = _require_output_dir(args)
    prompt = args.input_text or "a small red cube on a white table"
    pipeline_args = argparse.Namespace(
        prompt=prompt,
        i=str(model_root),
        o=str(output_dir),
        seed=93,
        model_version="runwayml/stable-diffusion-v1-5",
        compute_unit="CPU_AND_GPU",
        scheduler=None,
        num_inference_steps=2,
        guidance_scale=7.5,
        controlnet=None,
        controlnet_inputs=None,
        negative_prompt=None,
        unet_batch_one=False,
        model_sources=None,
    )
    pipeline.main(pipeline_args)
    image_path = _require_nonempty_output(
        output_dir,
        pathlib.Path(pipeline.get_image_path(pipeline_args)),
        "Core ML Stable Diffusion",
    )
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
    audio = np.concatenate([np.zeros(overlap_samples // 2, dtype="float32"), audio])

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
        events.append(
            (int(i_start), int(i_end), int(freq_idx + midi_offset), amplitude)
        )

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
    window_offset = (fft_hop / sample_rate) * (
        annot_n_frames - ((sample_rate * 2 - fft_hop) / fft_hop)
    ) + 0.0018
    return base - window_offset * window_numbers


def _first_existing_dir(root: pathlib.Path, relative_paths: list[str]) -> pathlib.Path:
    for relative_path in relative_paths:
        candidate = root / relative_path
        if candidate.is_dir():
            return candidate
    raise RunnerFailure(
        f"native_payload_missing: Core ML model directory under {root}", 70
    )


if __name__ == "__main__":
    raise SystemExit(main())
