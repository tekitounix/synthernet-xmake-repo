#!/usr/bin/env python3
# claude-hook: event=PostToolUse matcher=Edit|Write
"""PostToolUse gateway: dispatch actions based on edited file path.

Single entry point for all post-edit automation. Each action is a lightweight
check — no heavy operations are performed synchronously.

Actions:
  1. clang-format: auto-format .cc/.hh files
  2. dev-sync:     auto-run `xmake dev-sync` when xmake-repo/ is edited

Packaged by: coding-rules
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path


def _clang_format(file_path: str) -> None:
    """Run clang-format -i on C++ source files."""
    p = Path(file_path)
    if p.suffix not in (".cc", ".hh"):
        return
    if not p.exists():
        return
    clang_format = shutil.which("clang-format")
    if clang_format is None:
        return
    try:
        subprocess.run([clang_format, "-i", str(p)], timeout=10, capture_output=True)
    except (subprocess.TimeoutExpired, OSError):
        pass


def _dev_sync(file_path: str) -> None:
    """Run xmake dev-sync when xmake-repo/ files are edited.

    xmake-repo/ contains custom packages installed to ~/.xmake/.
    Source edits are NOT picked up until `xmake dev-sync` is run.
    """
    if "xmake-repo/" not in file_path:
        return
    xmake = shutil.which("xmake")
    if xmake is None:
        return
    try:
        result = subprocess.run(
            [xmake, "dev-sync"],
            timeout=30,
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            print("xmake dev-sync completed (xmake-repo/ change detected)", file=sys.stderr)
        else:
            print(f"xmake dev-sync failed: {result.stderr.strip()}", file=sys.stderr)
    except subprocess.TimeoutExpired:
        print("xmake dev-sync timed out", file=sys.stderr)
    except OSError:
        pass


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError, ValueError):
        return

    file_path = data.get("tool_input", {}).get("file_path", "")
    if not file_path:
        return

    _clang_format(file_path)
    _dev_sync(file_path)


if __name__ == "__main__":
    main()
