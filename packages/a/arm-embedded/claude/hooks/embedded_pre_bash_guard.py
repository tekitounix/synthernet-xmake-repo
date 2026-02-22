#!/usr/bin/env python3
# claude-hook: event=PreToolUse matcher=Bash
"""PreToolUse(Bash) guard: enforce CLAUDE.md safety rules + pyOCD probe exclusion.

Combines:
  - rm guard (use `trash` instead)
  - git checkout guard (must stash first)
  - pyOCD probe cleanup before probe commands

Exit codes:
  0 = allow
  2 = block (stderr sent to Claude as feedback)

Packaged by: arm-embedded
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


# ── Safety Guards ──


def _check_rm(command: str) -> str | None:
    """Block rm commands on project files. Allow rm on /tmp/ and build/."""
    if not re.search(r"\brm\s", command):
        return None
    safe_patterns = [
        r"\brm\s[^;|&]*(/tmp/|/var/|build/|\$TMPDIR)",
        r"\brm\s+-f\s+\$TMPDIR",
    ]
    for pattern in safe_patterns:
        if re.search(pattern, command):
            return None
    return (
        "rm はプロジェクトファイルに対して使用禁止です。"
        "代わりに `trash` コマンドを使用してください (CLAUDE.md: 'use trash not rm')。"
        "build/ や /tmp/ への rm は許可されています。"
    )


def _check_git_checkout(command: str) -> str | None:
    """Warn about git checkout/switch without stash."""
    is_checkout = re.search(r"\bgit\s+checkout\b", command)
    is_switch = re.search(r"\bgit\s+switch\b", command)
    if not is_checkout and not is_switch:
        return None
    if is_checkout:
        if re.search(r"\bgit\s+checkout\s+--\s", command):
            return None
        if re.search(r"\bgit\s+checkout\s+-b\b", command):
            return None
    if is_switch:
        if re.search(r"\bgit\s+switch\s+(-c|--create)\b", command):
            return None
    return (
        "git checkout/switch でブランチ切替する前に `git stash` を実行してください "
        "(CLAUDE.md: 'MUST git stash before checkout')。"
        "新規ブランチ作成 (-b / -c) やファイル単位の checkout (-- file) は許可されています。"
    )


# ── pyOCD Probe Cleanup ──

PROBE_COMMANDS = re.compile(
    r"pyocd\s+(flash|commander|rtt|gdbserver|reset|erase)"
)


def _cleanup_pyocd_if_needed(command: str) -> None:
    """Auto-cleanup orphaned pyOCD processes before probe commands."""
    if not PROBE_COMMANDS.search(command):
        return

    # Find pyocd_tool.py in package scripts directory
    tool = Path.home() / ".xmake" / "rules" / "embedded" / "scripts" / "pyocd_tool.py"
    if not tool.exists():
        return
    try:
        result = subprocess.run(
            [sys.executable, str(tool), "cleanup"],
            capture_output=True, text=True, timeout=10,
        )
        if result.returncode == 0:
            info = json.loads(result.stdout)
            if info.get("killed", 0) > 0:
                print(
                    f"pyOCD: {info['killed']} orphaned process(es) cleaned up",
                    file=sys.stderr,
                )
    except Exception:
        pass


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError, ValueError):
        return

    command = data.get("tool_input", {}).get("command", "")
    if not command:
        return

    # Safety guards (block on failure)
    checks = [_check_rm, _check_git_checkout]
    for check in checks:
        reason = check(command)
        if reason is not None:
            print(reason, file=sys.stderr)
            sys.exit(2)

    # pyOCD cleanup (non-blocking)
    _cleanup_pyocd_if_needed(command)


if __name__ == "__main__":
    main()
