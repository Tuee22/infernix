#!/usr/bin/env python3

from __future__ import annotations

import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
CHECK_SUFFIXES = {".cabal", ".hs", ".js", ".md", ".mjs", ".proto", ".py", ".yaml", ".yml"}
CHECK_FILES = {"cabal.project", "AGENTS.md", "CLAUDE.md", "README.md"}
SKIP_PARTS = {"node_modules", ".git", ".data", ".build", ".tmp", "dist-newstyle"}


def should_check(path: Path) -> bool:
    if any(part in SKIP_PARTS for part in path.parts):
        return False
    return path.suffix in CHECK_SUFFIXES or path.name in CHECK_FILES


def main() -> int:
    failures: list[str] = []
    for path in REPO_ROOT.rglob("*"):
        if not path.is_file() or not should_check(path.relative_to(REPO_ROOT)):
            continue
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        for line_number, line in enumerate(lines, start=1):
            if line.rstrip(" \t") != line:
                failures.append(f"{path.relative_to(REPO_ROOT)}:{line_number}: trailing whitespace")
            if "\t" in line:
                failures.append(f"{path.relative_to(REPO_ROOT)}:{line_number}: tab character")
        if text and not text.endswith("\n"):
            failures.append(f"{path.relative_to(REPO_ROOT)}: missing trailing newline")

    if failures:
        for failure in failures:
            print(f"lint-check: {failure}", file=sys.stderr)
        return 1

    print("lint-check: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
