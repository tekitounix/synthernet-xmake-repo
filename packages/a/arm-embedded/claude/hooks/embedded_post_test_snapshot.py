#!/usr/bin/env python3
# claude-hook: event=PostToolUse matcher=run_tests
"""PostToolUse hook: update tested snapshot after successful test run.

Triggered by:
  - PostToolUse(run_tests): MCP test tool success (any server's run_tests)
  - PostToolUse(Bash): `xmake test` command success

On success, updates the "tested" snapshot so the Stop hook knows
that tests have passed for the current state of lib/ files.

Exit codes:
  0 = always (post-hook, never blocks)

Packaged by: arm-embedded
"""

from __future__ import annotations

import json
import os
import re
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
        return

    try:
        lib_checksum = _import_lib_checksum()
    except ImportError:
        return

    sid = data.get("session_id", "")
    if sid:
        lib_checksum.set_session_id(sid)

    tool_name = data.get("tool_name", "")

    # Match any MCP server's run_tests tool (e.g., mcp__umi__run_tests, mcp__embedded__run_tests)
    if tool_name.endswith("run_tests") and tool_name != "Bash":
        lib_checksum.mark_tested()
        return

    if tool_name == "Bash":
        command = data.get("tool_input", {}).get("command", "")
        if re.search(r"\bxmake\s+test\b", command):
            lib_checksum.mark_tested()
            return


if __name__ == "__main__":
    main()
