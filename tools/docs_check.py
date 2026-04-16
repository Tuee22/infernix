#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
MARKDOWN_EXTENSIONS = {".md"}
REQUIRED_DOCS = [
    Path("documents/README.md"),
    Path("documents/documentation_standards.md"),
    Path("documents/architecture/overview.md"),
    Path("documents/architecture/model_catalog.md"),
    Path("documents/architecture/runtime_modes.md"),
    Path("documents/architecture/web_ui_architecture.md"),
    Path("documents/development/frontend_contracts.md"),
    Path("documents/development/haskell_style.md"),
    Path("documents/development/local_dev.md"),
    Path("documents/development/testing_strategy.md"),
    Path("documents/engineering/build_artifacts.md"),
    Path("documents/engineering/docker_policy.md"),
    Path("documents/engineering/edge_routing.md"),
    Path("documents/engineering/k8s_native_dev_policy.md"),
    Path("documents/engineering/k8s_storage.md"),
    Path("documents/engineering/model_lifecycle.md"),
    Path("documents/engineering/object_storage.md"),
    Path("documents/engineering/storage_and_state.md"),
    Path("documents/operations/apple_silicon_runbook.md"),
    Path("documents/operations/cluster_bootstrap_runbook.md"),
    Path("documents/reference/api_surface.md"),
    Path("documents/reference/cli_reference.md"),
    Path("documents/reference/cli_surface.md"),
    Path("documents/reference/web_portal_surface.md"),
    Path("documents/tools/harbor.md"),
    Path("documents/tools/minio.md"),
    Path("documents/tools/pulsar.md"),
]
PHASE_DOCS = sorted(Path("DEVELOPMENT_PLAN").glob("phase-*.md"))
METADATA_LINES = [
    re.compile(r"^# .+"),
    re.compile(r"^\*\*Status\*\*: .+"),
    re.compile(r"^\*\*Referenced by\*\*: .+"),
]
LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        fail(f"missing required file: {path}")


def fail(message: str) -> None:
    print(f"docs-check: {message}", file=sys.stderr)
    raise SystemExit(1)


def validate_required_docs() -> None:
    for relative_path in REQUIRED_DOCS:
        full_path = REPO_ROOT / relative_path
        if not full_path.exists():
            fail(f"missing governed document: {relative_path}")


def validate_metadata(path: Path, text: str) -> None:
    lines = [line for line in text.splitlines() if line.strip()]
    if len(lines) < len(METADATA_LINES):
        fail(f"{path} is too short to contain the required metadata block")
    for pattern, line in zip(METADATA_LINES, lines):
        if not pattern.match(line):
            fail(f"{path} has invalid metadata line: {line!r}")


def resolve_link(source: Path, target: str) -> Path | None:
    if target.startswith(("http://", "https://", "mailto:")):
        return None
    if target.startswith("#"):
        return None
    clean_target = target.split("#", 1)[0]
    if not clean_target:
        return None
    return (REPO_ROOT / source.parent / clean_target).resolve()


def strip_fenced_code_blocks(text: str) -> str:
    lines = []
    in_fence = False
    for line in text.splitlines():
        if line.startswith("```"):
            in_fence = not in_fence
            continue
        if not in_fence:
            lines.append(line)
    return "\n".join(lines)


def validate_links(path: Path, text: str) -> None:
    for match in LINK_RE.finditer(strip_fenced_code_blocks(text)):
        target = match.group(1)
        resolved = resolve_link(path, target)
        if resolved is None:
            continue
        if not resolved.exists():
            fail(f"{path} links to missing path: {target}")


def validate_readme() -> None:
    readme = read_text(REPO_ROOT / "README.md")
    if "documents/" not in readme:
        fail("README.md must reference documents/")
    if "DEVELOPMENT_PLAN/" not in readme:
        fail("README.md must reference DEVELOPMENT_PLAN/")


def validate_phase_docs() -> None:
    for relative_path in PHASE_DOCS:
        full_path = REPO_ROOT / relative_path
        text = read_text(full_path)
        if "## Documentation Requirements" not in text:
            fail(f"{relative_path} is missing the Documentation Requirements section")


def iter_governed_markdown() -> list[Path]:
    doc_paths = sorted((REPO_ROOT / "documents").rglob("*.md"))
    plan_paths = [REPO_ROOT / path for path in PHASE_DOCS]
    plan_paths.extend(
        [
            REPO_ROOT / "DEVELOPMENT_PLAN/README.md",
            REPO_ROOT / "DEVELOPMENT_PLAN/00-overview.md",
            REPO_ROOT / "DEVELOPMENT_PLAN/system-components.md",
            REPO_ROOT / "DEVELOPMENT_PLAN/development_plan_standards.md",
            REPO_ROOT / "DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md",
        ]
    )
    return doc_paths + plan_paths


def main() -> None:
    validate_required_docs()
    validate_readme()
    validate_phase_docs()

    for path in iter_governed_markdown():
        if path.suffix not in MARKDOWN_EXTENSIONS:
            continue
        text = read_text(path)
        validate_metadata(path.relative_to(REPO_ROOT), text)
        validate_links(path.relative_to(REPO_ROOT), text)

    print("docs-check: ok")


if __name__ == "__main__":
    main()
