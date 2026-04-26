#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root/python"
export PYTHONPATH="$repo_root/python/adapters:$repo_root/tools/generated_proto${PYTHONPATH:+:$PYTHONPATH}"
export MYPYPATH="$repo_root/python/adapters:$repo_root/tools/generated_proto${MYPYPATH:+:$MYPYPATH}"

poetry run mypy --strict adapters
poetry run black --check adapters
poetry run ruff check adapters
