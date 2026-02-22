#!/usr/bin/env python3
"""
Embedded MCP Server — ARM 組込み開発ツールサーバ for Claude Code.

umitest, umibench, umirtm, pyOCD を統合し、
Claude Code から構造化 API として呼び出せるようにする。

pyOCD 操作は pyocd_tool.py の Python API を直接使用し、
CLI パースに依存しない安定した自動化を提供する。
複数プローブ対応: --mcu 引数で自動的に正しいプローブが選択される。

登録:
  xmake setup-claude で自動登録

依存:
  pip install "mcp[cli]"
"""

from __future__ import annotations

import json
import re
import struct
import subprocess
import sys
import time
from pathlib import Path

from mcp.server.fastmcp import FastMCP

# pyocd_tool をインポートできるようにパスを追加
# パッケージ同梱 scripts/ (arm-embedded/scripts/ → ~/.xmake/rules/embedded/scripts/)
_pkg_scripts = Path(__file__).resolve().parent.parent.parent / "scripts"

if (_pkg_scripts / "pyocd_tool.py").exists():
    sys.path.insert(0, str(_pkg_scripts))

import pyocd_tool  # noqa: E402

app = FastMCP("embedded")

# ---------------------------------------------------------------------------
# ヘルパー
# ---------------------------------------------------------------------------


def _run(args: list[str], timeout: int = 30) -> dict:
    """タイムアウト付き subprocess 実行。"""
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


def _get_current_mode() -> str | None:
    """xmake の現在のビルドモードを取得する（xmake show の出力をパース）。"""
    r = _run(["xmake", "show"], timeout=10)
    output = r["stdout"] + "\n" + r["stderr"]
    for line in output.splitlines():
        # ANSI エスケープ除去してから検索
        clean = re.sub(r"\x1b\[[0-9;]*m", "", line)
        m = re.match(r"\s*mode\s*[:=]\s*(\w+)", clean)
        if m:
            return m.group(1)
    return None


# ===================================================================
# umitest — テスト実行
# ===================================================================


@app.tool()
def run_tests(filter: str = "") -> str:
    """xmake テストを実行する。

    Args:
        filter: テストフィルタ（例: "test_umidbg/*"）。空なら全テスト。
    """
    args = ["xmake", "test"]
    if filter:
        args.append(filter)
    result = _run(args, timeout=120)

    m = re.findall(r"(\d+)/(\d+)\s+tests?\s+passed", result["stdout"])
    if m:
        passed, total = int(m[-1][0]), int(m[-1][1])
        result["passed"] = passed
        result["total"] = total
        result["all_passed"] = passed == total
    return json.dumps(result, indent=2)


@app.tool()
def build_target(target: str, mode: str = "release") -> str:
    """xmake ターゲットをビルドする。
    release でビルド失敗した場合は自動的に debug にフォールバックする。
    ビルド完了後、元のモードに復元する（他ターゲットへの副作用を防止）。

    Args:
        target: ビルドターゲット名（例: "stm32f4_os", "test_umidbg"）
        mode: ビルドモード（"debug" or "release"）
    """
    original_mode = _get_current_mode()

    def _restore_mode() -> None:
        """ビルド前のモードに復元する。"""
        if original_mode:
            _run(["xmake", "f", "-m", original_mode, "-y"], timeout=30)

    cfg = _run(["xmake", "f", "-m", mode, "-y"], timeout=30)
    if not cfg["success"]:
        return json.dumps({"error": "Config failed", "detail": cfg}, indent=2)

    build = _run(["xmake", "build", target], timeout=120)
    if build["success"]:
        build["mode"] = mode
        _restore_mode()
        return json.dumps(build, indent=2)

    # release 失敗時は debug にフォールバック
    if mode == "release":
        cfg2 = _run(["xmake", "f", "-m", "debug", "-y"], timeout=30)
        if cfg2["success"]:
            build2 = _run(["xmake", "build", target], timeout=120)
            build2["mode"] = "debug"
            build2["fallback_from"] = "release"
            if not build2["success"]:
                build2["release_error"] = build.get("stdout", "")
            _restore_mode()
            return json.dumps(build2, indent=2)

    build["mode"] = mode
    _restore_mode()
    return json.dumps(build, indent=2)


# ===================================================================
# xmake 汎用ツール — ターゲット発見、実行、サイズ計測
# ===================================================================


@app.tool()
def list_targets(filter: str = "") -> str:
    """xmake ターゲットを一覧表示する。
    フィルタで名前パターンを絞り込める。

    Args:
        filter: 名前フィルタ（例: "test_", "bench", "wasm", "renode"）。空なら全ターゲット。
    """
    r = _run(["xmake", "show", "-l", "targets"], timeout=10)
    if not r["success"]:
        return json.dumps({"error": "Failed to list targets", "detail": r}, indent=2)
    # ANSI 除去してターゲット名を抽出
    clean = re.sub(r"\x1b\[[0-9;]*m", "", r["stdout"])
    targets = sorted(set(t.strip() for t in re.split(r"[\s,]+", clean) if t.strip()))
    if filter:
        targets = [t for t in targets if filter.lower() in t.lower()]
    return json.dumps({"targets": targets, "count": len(targets)}, indent=2)


@app.tool()
def run_target(target: str, timeout_s: int = 60) -> str:
    """xmake ターゲットをビルドして実行する（ベンチマーク、テスト、任意の実行可能ターゲット）。

    Args:
        target: ターゲット名（例: "umibench_host", "test_umidbg"）
        timeout_s: 実行タイムアウト秒数（デフォルト: 60）
    """
    build = _run(["xmake", "build", target], timeout=120)
    if not build["success"]:
        return json.dumps({"error": "Build failed", "detail": build}, indent=2)
    run = _run(["xmake", "run", target], timeout=timeout_s)
    return json.dumps({"build": build, "run": run}, indent=2)


@app.tool()
def run_benchmark(target: str) -> str:
    """ベンチマークターゲットをビルドして実行する。

    Args:
        target: ベンチマークターゲット名（例: "umibench_host"）
    """
    return run_target(target, timeout_s=60)


def _parse_build_size(stdout: str) -> dict | None:
    """ビルド出力から Memory Usage Summary をパースする。"""
    flash_m = re.search(r"Flash:\s+(\d+)\s*/\s*(\d+)\s*bytes\s*\(([0-9.]+)%\)", stdout)
    ram_m = re.search(
        r"RAM:\s+(\d+)\s*/\s*(\d+)\s*bytes\s*\(([0-9.]+)%\)"
        r"(?:\s*\[data:\s*(\d+),\s*bss:\s*(\d+)\])?",
        stdout,
    )
    if not flash_m:
        return None
    result: dict = {
        "flash_used": int(flash_m.group(1)),
        "flash_total": int(flash_m.group(2)),
        "flash_percent": float(flash_m.group(3)),
    }
    if ram_m:
        result["ram_used"] = int(ram_m.group(1))
        result["ram_total"] = int(ram_m.group(2))
        result["ram_percent"] = float(ram_m.group(3))
        if ram_m.group(4):
            result["ram_data"] = int(ram_m.group(4))
            result["ram_bss"] = int(ram_m.group(5))
    return result


@app.tool()
def build_size(target: str, mode: str = "release") -> str:
    """ARM ターゲットをビルドして Flash/RAM 使用量を返す。

    Args:
        target: ビルドターゲット名（例: "stm32f4_os"）
        mode: ビルドモード（"debug" or "release"）
    """
    result_str = build_target(target, mode)
    result = json.loads(result_str)
    if not result.get("success"):
        return result_str
    size = _parse_build_size(result.get("stdout", ""))
    if size:
        result["size"] = size
    return json.dumps(result, indent=2)


# ===================================================================
# pyOCD — デバッグプローブ（pyocd_tool.py API 直接使用）
# ===================================================================


@app.tool()
def probe_list() -> str:
    """接続されている全デバッグプローブを一覧表示する。
    複数プローブ接続時はそれぞれの UID、MCU、ボード名を返す。
    """
    probes = pyocd_tool.list_probes()
    return json.dumps({"probes": probes, "count": len(probes)}, indent=2)


@app.tool()
def cleanup_processes() -> str:
    """孤立したデバッグプロセス（pyocd, openocd, gdb）を終了する。"""
    ns = type("NS", (), {"command": "cleanup"})()
    result = pyocd_tool.cmd_cleanup(ns)
    return json.dumps(result, indent=2)


@app.tool()
def flash(binary: str, mcu: str = "") -> str:
    """ファームウェアをフラッシュする。
    複数プローブ接続時は mcu で対象を指定。1台のみなら自動選択。

    Args:
        binary: .bin/.elf ファイルのパス
        mcu: MCU ターゲット（例: "stm32f407vg", "stm32h750xx"）。空なら自動選択。
    """
    ns = type("NS", (), {"binary": binary, "mcu": mcu or None})()
    try:
        result = pyocd_tool.cmd_flash(ns)
        return json.dumps(result, indent=2)
    except Exception as e:
        import traceback
        return json.dumps({"error": str(e), "traceback": traceback.format_exc()}, indent=2)


@app.tool()
def reset(mcu: str = "") -> str:
    """ターゲット MCU をリセットする。

    Args:
        mcu: MCU ターゲット。空なら自動選択。
    """
    ns = type("NS", (), {"mcu": mcu or None})()
    try:
        result = pyocd_tool.cmd_reset(ns)
        return json.dumps(result, indent=2)
    except Exception as e:
        import traceback
        return json.dumps({"error": str(e), "traceback": traceback.format_exc()}, indent=2)


@app.tool()
def target_status(mcu: str = "") -> str:
    """ターゲットの現在の状態を取得する（RUNNING/HALTED/SLEEPING等）。

    Args:
        mcu: MCU ターゲット。空なら自動選択。
    """
    ns = type("NS", (), {"mcu": mcu or None})()
    try:
        result = pyocd_tool.cmd_status(ns)
        return json.dumps(result, indent=2)
    except Exception as e:
        import traceback
        return json.dumps({"error": str(e), "traceback": traceback.format_exc()}, indent=2)


@app.tool()
def read_memory(address: str, size: int = 4, mcu: str = "") -> str:
    """ターゲットのメモリを読み取る（自動で halt→read→resume）。

    Args:
        address: 16進アドレス（例: "0x20000230"）
        size: 読み取りバイト数
        mcu: MCU ターゲット。空なら自動選択。
    """
    ns = type("NS", (), {"addr": address, "size": str(size), "mcu": mcu or None})()
    try:
        result = pyocd_tool.cmd_read(ns)
        return json.dumps(result, indent=2)
    except Exception as e:
        import traceback
        return json.dumps({"error": str(e), "traceback": traceback.format_exc()}, indent=2)


@app.tool()
def read_memory_after_run(
    address: str, size: int = 4, run_ms: int = 5000, mcu: str = ""
) -> str:
    """リセット→指定ms実行→halt→メモリ読み取り。

    Args:
        address: 16進アドレス
        size: 読み取りバイト数
        run_ms: 実行ミリ秒数
        mcu: MCU ターゲット。空なら自動選択。
    """
    ns = type("NS", (), {
        "addr": address, "size": str(size), "ms": str(run_ms), "mcu": mcu or None,
    })()
    try:
        result = pyocd_tool.cmd_run_read(ns)
        return json.dumps(result, indent=2)
    except Exception as e:
        import traceback
        return json.dumps({"error": str(e), "traceback": traceback.format_exc()}, indent=2)


@app.tool()
def read_symbol(elf: str, symbol: str, size: int = 0, mcu: str = "") -> str:
    """ELF シンボル名からメモリを読み取る。

    Args:
        elf: ELF ファイルのパス
        symbol: シンボル名（例: "latency_hist"）
        size: 読み取りバイト数（0ならシンボルサイズから自動判定）
        mcu: MCU ターゲット。空なら自動選択。
    """
    ns = type("NS", (), {
        "elf": elf, "symbol": symbol,
        "size": str(size) if size > 0 else None,
        "mcu": mcu or None,
    })()
    try:
        result = pyocd_tool.cmd_read_symbol(ns)
        return json.dumps(result, indent=2)
    except Exception as e:
        import traceback
        return json.dumps({"error": str(e), "traceback": traceback.format_exc()}, indent=2)


@app.tool()
def read_symbols(elf: str, symbols: str, mcu: str = "") -> str:
    """ELF シンボル名を複数まとめて読み取る。

    Args:
        elf: ELF ファイルのパス
        symbols: カンマ区切りシンボル名（例: "umi::dbg::usb,umi::dbg::audio"）
        mcu: MCU ターゲット。空なら自動選択。
    """
    symbol_list = [s.strip() for s in symbols.split(",") if s.strip()]
    if not symbol_list:
        return json.dumps({"error": "symbols is empty"}, indent=2)

    ns = type("NS", (), {
        "elf": elf,
        "symbols": symbol_list,
        "mcu": mcu or None,
    })()
    try:
        result = pyocd_tool.cmd_read_symbols(ns)
        return json.dumps(result, indent=2)
    except Exception as e:
        import traceback
        return json.dumps({"error": str(e), "traceback": traceback.format_exc()}, indent=2)


def _read_symbols_series_data(
    *,
    elf: str,
    symbol_list: list[str],
    mcu: str,
    repeat: int,
    interval_ms: int,
    halt: bool,
) -> dict:
    if repeat < 1:
        raise ValueError("repeat must be >= 1")
    if interval_ms < 0:
        raise ValueError("interval_ms must be >= 0")
    if not symbol_list:
        raise ValueError("symbol_list is empty")

    uid, mcu_resolved = pyocd_tool.resolve_probe(mcu or None)
    resolved = pyocd_tool._resolve_symbols(elf, symbol_list)
    blocks: list[tuple[str, int, int]] = []
    for sym in symbol_list:
        addr, sym_size = resolved[sym]
        blocks.append((sym, addr, sym_size if sym_size > 0 else 64))

    session = pyocd_tool.open_session(uid, mcu_resolved)
    try:
        target = session.target
        core = target.cores[0]
        t0 = time.monotonic()
        samples: list[dict] = []
        for i in range(repeat):
            read_map = pyocd_tool._read_blocks(target, core, blocks, halt=halt)
            symbols_out: dict[str, dict] = {}
            for sym in symbol_list:
                addr, sym_size = resolved[sym]
                symbols_out[sym] = {
                    "address": f"0x{addr:08X}",
                    "size": sym_size if sym_size > 0 else 64,
                    "words": read_map[sym]["words"],
                    "hex": read_map[sym]["hex"],
                }
            samples.append({
                "index": i,
                "t_ms": round((time.monotonic() - t0) * 1000.0, 3),
                "symbols": symbols_out,
            })
            if i + 1 < repeat and interval_ms > 0:
                time.sleep(interval_ms / 1000.0)

        return {
            "uid": uid,
            "mcu": mcu_resolved,
            "elf": elf,
            "symbols": symbol_list,
            "repeat": repeat,
            "interval_ms": interval_ms,
            "halt": halt,
            "samples": samples,
        }
    finally:
        session.close()


@app.tool()
def read_symbols_series(
    elf: str,
    symbols: str,
    repeat: int = 5,
    interval_ms: int = 100,
    mcu: str = "",
    halt: bool = False,
) -> str:
    """ELF シンボルを単一セッションで時系列サンプリングする。

    Args:
        elf: ELF ファイルのパス
        symbols: カンマ区切りシンボル名
        repeat: サンプル回数 (>=1)
        interval_ms: サンプル間隔ミリ秒 (>=0)
        mcu: MCU ターゲット。空なら自動選択。
        halt: True の場合、各サンプルで halt->read->resume を実施
    """
    symbol_list = [s.strip() for s in symbols.split(",") if s.strip()]
    if not symbol_list:
        return json.dumps({"error": "symbols is empty"}, indent=2)
    try:
        result = _read_symbols_series_data(
            elf=elf,
            symbol_list=symbol_list,
            mcu=mcu,
            repeat=int(repeat),
            interval_ms=int(interval_ms),
            halt=bool(halt),
        )
        return json.dumps(result, indent=2)
    except Exception as e:
        import traceback
        return json.dumps({"error": str(e), "traceback": traceback.format_exc()}, indent=2)


@app.tool()
def usb_audio_counters(
    elf: str,
    symbols: str,
    repeat: int = 5,
    interval_ms: int = 100,
    mcu: str = "",
    halt: bool = False,
) -> str:
    """USB Audio デバッグカウンタを時系列サンプリングする。

    Args:
        elf: ELF ファイルのパス
        symbols: カンマ区切りシンボル名（例: "ns::dbg::usb,ns::dbg::audio"）
        repeat: サンプル回数 (>=1)
        interval_ms: サンプル間隔ミリ秒 (>=0)
        mcu: MCU ターゲット。空なら自動選択。
        halt: True の場合、各サンプルで halt->read->resume を実施
    """
    symbol_list = [s.strip() for s in symbols.split(",") if s.strip()]
    if not symbol_list:
        return json.dumps({"error": "symbols is empty"}, indent=2)
    try:
        result = _read_symbols_series_data(
            elf=elf,
            symbol_list=symbol_list,
            mcu=mcu,
            repeat=int(repeat),
            interval_ms=int(interval_ms),
            halt=bool(halt),
        )
        return json.dumps(result, indent=2)
    except Exception as e:
        import traceback
        return json.dumps({"error": str(e), "traceback": traceback.format_exc()}, indent=2)


@app.tool()
def resolve_symbol(elf: str, name: str) -> str:
    """ELF 内のシンボル名をアドレスに解決する。

    Args:
        elf: ELF ファイルのパス
        name: シンボル名またはパターン
    """
    try:
        addr, sym_size = pyocd_tool._resolve_symbol(elf, name)
        return json.dumps({
            "symbol": name,
            "address": f"0x{addr:08X}",
            "size": sym_size,
        }, indent=2)
    except Exception as e:
        import traceback
        return json.dumps({"error": str(e), "traceback": traceback.format_exc()}, indent=2)


@app.tool()
def read_registers(mcu: str = "") -> str:
    """全コアレジスタを読み取る。

    Args:
        mcu: MCU ターゲット。空なら自動選択。
    """
    ns = type("NS", (), {"mcu": mcu or None})()
    try:
        result = pyocd_tool.cmd_regs(ns)
        return json.dumps(result, indent=2)
    except Exception as e:
        import traceback
        return json.dumps({"error": str(e), "traceback": traceback.format_exc()}, indent=2)


# ===================================================================
# DMA バッファ解析
# ===================================================================


@app.tool()
def read_dma_audio(address: str, size: int = 512, mcu: str = "") -> str:
    """DMA I2S バッファを読み取り、24-bit オーディオサンプルとしてデコードする。

    Args:
        address: 16進アドレス (例: "0x2000CBE0")
        size: 読み取りバイト数 (デフォルト: 512)
        mcu: MCU ターゲット。空なら自動選択。
    """
    addr = int(address, 16) if isinstance(address, str) else address

    try:
        uid, mcu_resolved = pyocd_tool.resolve_probe(mcu or None)
        session = pyocd_tool.open_session(uid, mcu_resolved)
        try:
            target = session.target
            target.halt()
            data = target.read_memory_block8(addr, size)
            target.resume()
        finally:
            session.close()

        # Convert bytes to uint32 words (little-endian)
        words = []
        for i in range(0, len(data), 4):
            w = struct.unpack_from("<I", bytes(data[i : i + 4]))[0]
            words.append(w)

        # Decode I2S 24-bit frames
        frames = []
        for i in range(0, len(words), 2):
            if i + 1 >= len(words):
                break
            w0 = words[i]
            w1 = words[i + 1]
            # ARM little-endian I2S layout
            l_hi = w0 & 0xFFFF
            l_lo = (w0 >> 16) & 0xFFFF
            r_hi = w1 & 0xFFFF
            r_lo = (w1 >> 16) & 0xFFFF
            l_val = ((l_hi << 16) | l_lo) >> 8
            r_val = ((r_hi << 16) | r_lo) >> 8
            # Sign extend from 24-bit
            if l_val & 0x800000:
                l_val -= 0x1000000
            if r_val & 0x800000:
                r_val -= 0x1000000
            frames.append({"L": l_val, "R": r_val})

        # Analysis
        l_vals = [f["L"] for f in frames]
        r_vals = [f["R"] for f in frames]
        max_24 = 8388607

        l_crosses = sum(
            1 for i in range(1, len(l_vals)) if (l_vals[i] >= 0) != (l_vals[i - 1] >= 0)
        )
        r_crosses = sum(
            1 for i in range(1, len(r_vals)) if (r_vals[i] >= 0) != (r_vals[i - 1] >= 0)
        )
        lr_match = sum(1 for l, r in zip(l_vals, r_vals) if l == r)
        all_zero = sum(1 for l, r in zip(l_vals, r_vals) if l == 0 and r == 0)

        return json.dumps(
            {
                "success": True,
                "address": f"0x{addr:08X}",
                "frames": len(frames),
                "analysis": {
                    "L_range": [min(l_vals), max(l_vals)],
                    "R_range": [min(r_vals), max(r_vals)],
                    "L_range_pct": [
                        round(min(l_vals) / max_24 * 100, 1),
                        round(max(l_vals) / max_24 * 100, 1),
                    ],
                    "R_range_pct": [
                        round(min(r_vals) / max_24 * 100, 1),
                        round(max(r_vals) / max_24 * 100, 1),
                    ],
                    "L_zero_crossings": l_crosses,
                    "R_zero_crossings": r_crosses,
                    "LR_match": f"{lr_match}/{len(frames)}",
                    "all_zero_frames": f"{all_zero}/{len(frames)}",
                },
                "sample_data": frames[:8],  # First 8 frames as preview
            },
            indent=2,
        )
    except Exception as e:
        import traceback

        return json.dumps(
            {"success": False, "error": str(e), "traceback": traceback.format_exc()},
            indent=2,
        )


# ===================================================================
# umirtm — RTT キャプチャ
# ===================================================================


@app.tool()
def rtt_capture(duration: int = 5, mcu: str = "") -> str:
    """RTT 出力を指定秒数キャプチャする。

    Args:
        duration: キャプチャ秒数（デフォルト: 5）
        mcu: MCU ターゲット。空なら自動選択。
    """
    try:
        uid, mcu_resolved = pyocd_tool.resolve_probe(mcu or None)
        result = _run(
            ["pyocd", "rtt", "-u", uid, "-t", mcu_resolved],
            timeout=duration + 5,
        )
        return json.dumps(result, indent=2)
    except Exception as e:
        import traceback
        return json.dumps({"error": str(e), "traceback": traceback.format_exc()}, indent=2)


# ---------------------------------------------------------------------------
# エントリポイント
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    app.run()
