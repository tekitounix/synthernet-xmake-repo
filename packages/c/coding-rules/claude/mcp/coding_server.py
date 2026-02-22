#!/usr/bin/env python3
"""coding-rules MCP Server — lint/format tools for Claude Code.

Wraps `xmake lint --json` and `xmake format` as structured MCP tools.
Designed to run standalone or be merged into a unified server.

Registration:
  claude mcp add coding -- python3 <path>/coding_server.py

Dependencies:
  pip install "mcp[cli]"
"""

from __future__ import annotations

import json
import subprocess
import sys

from mcp.server.fastmcp import FastMCP

app = FastMCP("coding")


def _run(args: list[str], timeout: int = 120) -> dict:
    """Run subprocess with timeout."""
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return {
            "success": r.returncode == 0,
            "stdout": r.stdout.strip(),
            "stderr": r.stderr.strip(),
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "stdout": "", "stderr": f"Timed out ({timeout}s)"}
    except FileNotFoundError as e:
        return {"success": False, "stdout": "", "stderr": str(e)}


@app.tool()
def lint_files(files: str = "", target: str = "", checks: str = "", changed: bool = False) -> str:
    """clang-tidy を compile_commands.json ベースで実行して結果を返す。

    Args:
        files: カンマ区切りファイルパス（空なら全ファイル）
        target: ターゲット名フィルタ
        checks: clang-tidy チェック指定（空ならプロジェクト .clang-tidy に従う）
        changed: True なら git diff のファイルのみ
    """
    args = ["xmake", "lint", "--json"]
    if files:
        args.extend(["--files", files])
    if target:
        args.extend(["--target", target])
    if checks:
        args.extend(["--checks", checks])
    if changed:
        args.append("--changed")
    result = _run(args, timeout=120)

    # JSON output from xmake lint --json
    if result["success"] and result["stdout"]:
        try:
            parsed = json.loads(result["stdout"])
            return json.dumps(parsed, indent=2)
        except json.JSONDecodeError:
            pass
    return json.dumps(result, indent=2)


@app.tool()
def format_file(file: str) -> str:
    """指定ファイルを clang-format で整形する。

    Args:
        file: フォーマットするファイルパス
    """
    args = ["xmake", "format", "--files", file]
    result = _run(args, timeout=30)
    return json.dumps({"success": result["success"], "output": result["stdout"]}, indent=2)


@app.tool()
def format_check(files: str = "") -> str:
    """clang-format の差分を確認する（修正はしない）。

    Args:
        files: カンマ区切りファイルパス（空なら全ファイル）
    """
    args = ["xmake", "format", "--dry-run"]
    if files:
        args.extend(["--files", files])
    result = _run(args, timeout=60)
    return json.dumps({"success": result["success"], "output": result["stdout"]}, indent=2)


@app.tool()
def run_scan_all(scope: str = "all", workers: int = 8) -> str:
    """プロジェクト全体の clang-tidy スキャンを実行する。

    Args:
        scope: スキャン対象 ("all", "changed")
        workers: 並列ワーカー数 (デフォルト: 8)
    """
    args = ["xmake", "lint", "--json"]
    if scope == "changed":
        args.append("--changed")
    result = _run(args, timeout=300)  # longer timeout for full scan

    if result["success"] and result["stdout"]:
        try:
            parsed = json.loads(result["stdout"])
            return json.dumps(parsed, indent=2)
        except json.JSONDecodeError:
            pass
    return json.dumps(result, indent=2)


if __name__ == "__main__":
    app.run()
