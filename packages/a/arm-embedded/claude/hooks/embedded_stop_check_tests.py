#!/usr/bin/env python3
# claude-hook: event=Stop
"""Stop hook: block if lib/ C++ files changed during this session without testing.

Compares current lib/ file checksums against the reference snapshot
(tested > baseline > git diff fallback). If changes are detected and
no test has passed since the changes, exit code 2 blocks the stop.

Exit codes:
  0 = allow (no untested changes)
  2 = block (untested lib/ changes detected)

Packaged by: arm-embedded
"""

from __future__ import annotations

import json
import os
import sys


def _import_lib_checksum():
    """Import lib_checksum from package scripts directory."""
    scripts_dir = os.path.join(
        os.path.expanduser("~"), ".xmake", "rules", "embedded", "scripts"
    )
    if os.path.isdir(scripts_dir):
        sys.path.insert(0, scripts_dir)
    import lib_checksum
    return lib_checksum


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError, ValueError):
        data = {}

    try:
        lib_checksum = _import_lib_checksum()
    except ImportError:
        return

    sid = data.get("session_id", "")
    if sid:
        lib_checksum.set_session_id(sid)

    changed = lib_checksum.changed_files()
    if changed:
        count = len(changed)
        print(
            f"このセッションで lib/ の C++ ファイルが {count} 個変更されています。"
            "テスト (`xmake test` or MCP `run_tests`) を実行して全テスト pass を確認してください。",
            file=sys.stderr,
        )
        sys.exit(2)


if __name__ == "__main__":
    main()
