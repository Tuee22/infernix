#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root/python"

poetry run mypy --strict adapters
poetry run black --check adapters
poetry run ruff check adapters
