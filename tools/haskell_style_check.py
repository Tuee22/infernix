#!/usr/bin/env python3

from __future__ import annotations

import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
import os
import platform
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
BUILD_ROOT = Path(os.environ.get("INFERNIX_BUILD_ROOT", REPO_ROOT / ".build")).resolve()
TOOLS_ROOT = BUILD_ROOT / "haskell-style-tools"
CACHE_ROOT = TOOLS_ROOT / "cache"
BIN_ROOT = TOOLS_ROOT / "bin"

ORMOLU_RELEASES = {
    ("Darwin", "arm64"): (
        "https://github.com/tweag/ormolu/releases/download/0.8.0.2/ormolu-aarch64-darwin.zip",
        "ormolu-aarch64-darwin.zip",
    ),
    ("Darwin", "x86_64"): (
        "https://github.com/tweag/ormolu/releases/download/0.8.0.2/ormolu-x86_64-darwin.zip",
        "ormolu-x86_64-darwin.zip",
    ),
    ("Linux", "x86_64"): (
        "https://github.com/tweag/ormolu/releases/download/0.8.0.2/ormolu-x86_64-linux.zip",
        "ormolu-x86_64-linux.zip",
    ),
}

HLINT_RELEASES = {
    ("Darwin", "arm64"): (
        "https://github.com/ndmitchell/hlint/releases/download/v3.10/hlint-3.10-x86_64-osx.tar.gz",
        "hlint-3.10-x86_64-osx.tar.gz",
    ),
    ("Darwin", "x86_64"): (
        "https://github.com/ndmitchell/hlint/releases/download/v3.10/hlint-3.10-x86_64-osx.tar.gz",
        "hlint-3.10-x86_64-osx.tar.gz",
    ),
    ("Linux", "x86_64"): (
        "https://github.com/ndmitchell/hlint/releases/download/v3.10/hlint-3.10-x86_64-linux.tar.gz",
        "hlint-3.10-x86_64-linux.tar.gz",
    ),
}


def fail(message: str) -> None:
    print(f"haskell-style-check: {message}", file=sys.stderr)
    raise SystemExit(1)


def detect_platform() -> tuple[str, str]:
    system = platform.system()
    machine = platform.machine()
    machine_aliases = {
        "aarch64": "arm64",
        "amd64": "x86_64",
    }
    return system, machine_aliases.get(machine, machine)


def ensure_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def download(url: str, target: Path) -> None:
    if target.exists():
        return
    ensure_directory(target.parent)
    with urllib.request.urlopen(url) as response, target.open("wb") as handle:
        shutil.copyfileobj(response, handle)


def extract_ormolu(archive_path: Path, output_path: Path) -> None:
    if output_path.exists():
        return
    ensure_directory(output_path.parent)
    with zipfile.ZipFile(archive_path) as archive:
        archive.extract("ormolu", output_path.parent)
    output_path.chmod(0o755)


def extract_hlint(archive_path: Path, output_path: Path) -> None:
    if output_path.exists():
        return
    ensure_directory(output_path.parent)
    with tarfile.open(archive_path, "r:gz") as archive:
        member = next((item for item in archive.getmembers() if item.name.endswith("/hlint")), None)
        if member is None:
            fail(f"{archive_path.name} did not contain an hlint executable")
        member.name = "hlint"
        archive.extract(member, output_path.parent)
    output_path.chmod(0o755)


def ensure_ormolu() -> Path:
    system_key = detect_platform()
    release = ORMOLU_RELEASES.get(system_key)
    if release is None:
        fail(f"no repo-owned ormolu bootstrap is configured for {system_key[0]} {system_key[1]}")
    url, archive_name = release
    archive_path = CACHE_ROOT / archive_name
    output_path = BIN_ROOT / "ormolu"
    download(url, archive_path)
    extract_ormolu(archive_path, output_path)
    return output_path


def ensure_hlint() -> Path:
    system_key = detect_platform()
    release = HLINT_RELEASES.get(system_key)
    if release is None:
        fail(f"no repo-owned hlint bootstrap is configured for {system_key[0]} {system_key[1]}")
    url, archive_name = release
    archive_path = CACHE_ROOT / archive_name
    output_path = BIN_ROOT / "hlint"
    download(url, archive_path)
    extract_hlint(archive_path, output_path)
    return output_path


def run(command: list[str]) -> None:
    result = subprocess.run(command, cwd=REPO_ROOT, check=False)
    if result.returncode != 0:
        raise SystemExit(result.returncode)


def haskell_sources() -> list[str]:
    files = [REPO_ROOT / "Setup.hs"]
    for folder in ("app", "src", "test"):
        files.extend(sorted((REPO_ROOT / folder).rglob("*.hs")))
    return [str(path.relative_to(REPO_ROOT)) for path in files]


def check_cabal_manifest() -> None:
    source_path = REPO_ROOT / "infernix.cabal"
    with tempfile.TemporaryDirectory() as temp_dir:
        formatted_path = Path(temp_dir) / source_path.name
        formatted_path.write_text(source_path.read_text(encoding="utf-8"), encoding="utf-8")
        result = subprocess.run(
            ["cabal", "format", str(formatted_path)],
            cwd=REPO_ROOT,
            check=False,
        )
        if result.returncode != 0:
            raise SystemExit(result.returncode)
        if formatted_path.read_text(encoding="utf-8") != source_path.read_text(encoding="utf-8"):
            fail("infernix.cabal is not cabal-format clean")


def main() -> None:
    ensure_directory(CACHE_ROOT)
    ensure_directory(BIN_ROOT)
    ormolu = ensure_ormolu()
    hlint = ensure_hlint()
    sources = haskell_sources()
    run([str(ormolu), "--mode", "check", *sources])
    run([str(hlint), "Setup.hs", "app", "src", "test"])
    check_cabal_manifest()
    print("haskell-style-check: ok")


if __name__ == "__main__":
    main()
