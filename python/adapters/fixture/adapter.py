from __future__ import annotations

import sys


def run_adapter(input_text: str) -> str:
    return input_text.strip()


def main() -> int:
    payload = sys.stdin.read()
    sys.stdout.write(run_adapter(payload))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
