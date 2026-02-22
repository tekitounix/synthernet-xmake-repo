#!/usr/bin/env python3
"""lib/ C++ file checksum utilities for session-level change detection.

Used by Claude Code hooks to:
1. Snapshot lib/ file checksums at session start (baseline)
2. Update snapshot after successful test runs (tested checkpoint)
3. Detect untested changes at session stop

Two snapshot files per session:
- baseline: captured at SessionStart ($TMPDIR/claude_lib_baseline_<sid>.json)
- tested:   updated after test pass  ($TMPDIR/claude_lib_tested_<sid>.json)

Stop hook compares current state against the NEWER of baseline/tested.
This ensures that once tests pass, the hook doesn't re-fire until new changes occur.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
from pathlib import Path

_EXTENSIONS = ("*.cc", "*.hh")

# Module-level session_id, set by hooks via set_session_id()
_session_id: str = ""


def set_session_id(sid: str) -> None:
    """Set session ID for per-session snapshot isolation."""
    global _session_id  # noqa: PLW0603
    _session_id = sid


def _resolve_project_dir() -> str:
    """Resolve project root from env or git."""
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", "")
    if project_dir:
        return project_dir
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return result.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""


def _tmpdir() -> Path:
    return Path(os.environ.get("TMPDIR", "/tmp"))


def _baseline_path() -> Path:
    """Baseline snapshot: captured at SessionStart."""
    d = _tmpdir()
    if _session_id:
        return d / f"claude_lib_baseline_{_session_id[-12:]}.json"
    return d / "claude_lib_baseline.json"


def _tested_path() -> Path:
    """Tested snapshot: updated after successful test run."""
    d = _tmpdir()
    if _session_id:
        return d / f"claude_lib_tested_{_session_id[-12:]}.json"
    return d / "claude_lib_tested.json"


def compute_checksums(project_dir: str) -> dict[str, str]:
    """Compute MD5 checksums for all lib/**/*.{cc,hh} files."""
    lib_dir = Path(project_dir) / "lib"
    checksums: dict[str, str] = {}
    if not lib_dir.is_dir():
        return checksums
    for ext in _EXTENSIONS:
        for f in lib_dir.rglob(ext):
            try:
                data = f.read_bytes()
                checksums[str(f.relative_to(project_dir))] = hashlib.md5(data).hexdigest()
            except OSError:
                pass
    return checksums


def _write_json(path: Path, data: dict) -> None:
    try:
        path.write_text(json.dumps(data))
    except OSError:
        pass


def _read_json(path: Path) -> dict[str, str] | None:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def save_snapshot() -> None:
    """Save current lib/ checksums as session baseline.

    Called at SessionStart. Also removes any stale tested snapshot
    so a fresh session starts clean.
    """
    project_dir = _resolve_project_dir()
    if not project_dir:
        return
    checksums = compute_checksums(project_dir)
    _write_json(_baseline_path(), checksums)
    # Clear stale tested snapshot from previous session with same suffix
    try:
        tp = _tested_path()
        if tp.exists():
            tp.unlink()
    except OSError:
        pass


def mark_tested() -> None:
    """Update tested snapshot to current state.

    Called after successful test run. From this point, Stop hook
    will only fire if files change AFTER the test.
    """
    project_dir = _resolve_project_dir()
    if not project_dir:
        return
    checksums = compute_checksums(project_dir)
    _write_json(_tested_path(), checksums)


def _load_reference() -> dict[str, str] | None:
    """Load the most recent reference snapshot.

    Prefers tested (post-test) over baseline (session start).
    Falls back to shared baselines if session-specific not found.
    """
    # 1. Session-specific tested snapshot (best: tests already passed)
    ref = _read_json(_tested_path())
    if ref is not None:
        return ref

    # 2. Session-specific baseline
    ref = _read_json(_baseline_path())
    if ref is not None:
        return ref

    # 3. Shared fallbacks (no session_id, or different session)
    if _session_id:
        d = _tmpdir()
        for name in ("claude_lib_tested.json", "claude_lib_baseline.json"):
            ref = _read_json(d / name)
            if ref is not None:
                return ref

    return None


def changed_files() -> list[str]:
    """Return list of lib/ C++ files changed since last reference point.

    Reference point = tested snapshot (if tests ran) or baseline (session start).
    Falls back to `git diff` if no snapshot is available.
    """
    project_dir = _resolve_project_dir()
    if not project_dir:
        return []

    old = _load_reference()
    if old is None:
        return _git_diff_fallback()

    current = compute_checksums(project_dir)
    changed = []
    for path, checksum in current.items():
        if old.get(path) != checksum:
            changed.append(path)
    for path in old:
        if path not in current:
            changed.append(path)
    return changed


def _git_diff_fallback() -> list[str]:
    """Fallback: detect unstaged lib/ C++ changes via git."""
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", "--", "lib/"],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return []
    files = [f for f in result.stdout.strip().split("\n") if f]
    return [f for f in files if f.endswith((".cc", ".hh"))]


def cleanup_snapshot() -> None:
    """Remove all session snapshot files."""
    for path_fn in (_baseline_path, _tested_path):
        try:
            p = path_fn()
            if p.exists():
                p.unlink()
        except OSError:
            pass
