#!/usr/bin/env python3
# claude-hook: event=SessionStart
# claude-hook: event=SessionEnd
"""SessionStart/SessionEnd hook: pyOCD process cleanup + lib/ snapshot management.

Combines:
  - pyOCD zombie process cleanup (SessionStart + SessionEnd)
  - lib/ file checksum baseline snapshot (SessionStart)

Packaged by: arm-embedded
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
from pathlib import Path


def _cleanup_pyocd() -> None:
    """Kill orphaned pyocd/openocd/gdb processes."""
    for proc_name in ("pyocd", "openocd", "arm-none-eabi-gdb"):
        try:
            r = subprocess.run(
                ["pgrep", "-fl", proc_name],
                capture_output=True, text=True, timeout=5,
            )
            for line in r.stdout.strip().splitlines():
                if not line:
                    continue
                # Don't kill MCP server or tool processes
                if "_server.py" in line or "mcp" in line.lower() or "pyocd_tool" in line:
                    continue
                pid = int(line.split()[0])
                if pid == os.getpid():
                    continue
                try:
                    os.kill(pid, signal.SIGTERM)
                except (ProcessLookupError, PermissionError):
                    pass
        except Exception:
            pass


def _save_lib_snapshot(session_id: str) -> None:
    """Save lib/ file checksums as session baseline for change detection."""
    # Import lib_checksum from package scripts directory
    scripts_dir = os.path.join(
        os.path.expanduser("~"), ".xmake", "rules", "embedded", "scripts"
    )
    if os.path.isdir(scripts_dir):
        sys.path.insert(0, scripts_dir)

    try:
        import lib_checksum
        if session_id:
            lib_checksum.set_session_id(session_id)
        lib_checksum.save_snapshot()
    except ImportError:
        pass


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError, ValueError):
        data = {}

    session_id = data.get("session_id", "")
    event = data.get("event", "")

    # Always cleanup pyOCD processes
    _cleanup_pyocd()

    # SessionStart: also save baseline snapshot
    if event == "SessionStart" or not event:
        _save_lib_snapshot(session_id)


if __name__ == "__main__":
    main()
