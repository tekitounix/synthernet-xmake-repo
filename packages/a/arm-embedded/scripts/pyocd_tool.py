#!/usr/bin/env python3
"""
pyOCD 統合デバッグツール

pyOCD Python API を直接使用し、CLI パースに依存しない安定した自動化を提供する。
MCU 自動検出（DBGMCU_IDCODE + pyOCD BoardInfo）、複数プローブ対応、
ゾンビプロセス管理を統合。

使い方:
    python3 tools/pyocd/pyocd_tool.py <command> [options]

コマンド:
    list                         接続プローブ一覧（MCU 自動検出）
    status  [--mcu MCU]          ターゲット状態
    flash   <binary> [--mcu MCU] フラッシュ書き込み
    read    <addr> <size> [--mcu MCU]  メモリ読み取り（halt→read→resume）
    read-symbol <elf> <symbol> [size] [--mcu MCU]  シンボル→メモリ読み取り
    read-symbols <elf> <symbol...> [--mcu MCU] 複数シンボルを単一セッションで読み取り
    regs    [--mcu MCU]          レジスタ読み取り
    reset   [--mcu MCU]          ターゲットリセット
    run-read <addr> <size> <ms> [--mcu MCU]  reset→run→halt→read
    cleanup                      ゾンビプロセス終了

MCU 自動検出の仕組み:
  1. pyOCD BoardInfo（Nucleo/Discovery 等は board_id から自動判別）
  2. DBGMCU_IDCODE レジスタ（DEV_ID で MCU ファミリ判定）
  3. probe_cache.json（検出結果のキャッシュ — 手動編集不要）
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import shutil
import signal
import struct
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

# pyOCD がインポートできない場合、pyocd を持つ Python で再起動を試みる
def _find_pyocd_python() -> str | None:
    """pyocd モジュールを持つ Python インタプリタを探す。"""
    candidates = [
        *sorted(Path.home().glob(".pyenv/versions/*/bin/python3"), reverse=True),
        Path("/opt/homebrew/bin/python3"),
        Path("/usr/local/bin/python3"),
    ]
    for p in candidates:
        if not p.exists():
            continue
        try:
            r = subprocess.run(
                [str(p), "-c", "import pyocd"],
                capture_output=True, timeout=5,
            )
            if r.returncode == 0:
                return str(p)
        except Exception:
            pass
    return None


def _maybe_reexec() -> None:
    """pyocd が使えない Python で起動された場合、正しい Python で再実行する。"""
    try:
        import pyocd  # noqa: F401
        return
    except ImportError:
        pass

    python_path = _find_pyocd_python()
    if python_path and python_path != sys.executable:
        os.execv(python_path, [python_path, *sys.argv])


_maybe_reexec()

# pyOCD のログを抑制（CoreSight ROM table エラーは H7 で常に出るため CRITICAL に）
logging.getLogger("pyocd").setLevel(logging.ERROR)
logging.getLogger("pyocd.board.board").setLevel(logging.CRITICAL)
logging.getLogger("pyocd.coresight.rom_table").setLevel(logging.CRITICAL)
logging.getLogger("pyocd.coresight.component").setLevel(logging.CRITICAL)
logging.getLogger("pyocd.coresight").setLevel(logging.CRITICAL)

# pyOCD imports
try:
    from pyocd.core.helpers import ConnectHelper
    from pyocd.core.session import Session
    from pyocd.flash.file_programmer import FileProgrammer
    from pyocd.flash.loader import MemoryLoader
    from pyocd.probe import aggregator
    PYOCD_API = True
except ImportError:
    PYOCD_API = False

SCRIPT_DIR = Path(__file__).resolve().parent
PROBE_CACHE_PATH = SCRIPT_DIR / "probe_cache.json"

DEFAULT_FLASH_BACKEND = os.environ.get("PYOCD_FLASH_BACKEND", "auto").strip().lower()
DEFAULT_FLASH_VERIFY = os.environ.get("PYOCD_FLASH_VERIFY", "0").strip().lower() in {
    "1", "true", "yes", "on"
}


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    val = raw.strip().lower()
    if val in {"1", "true", "yes", "on"}:
        return True
    if val in {"0", "false", "no", "off"}:
        return False
    return default


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        return int(raw.strip(), 0)
    except ValueError:
        return default


def _env_int_optional(name: str) -> int | None:
    raw = os.environ.get(name)
    if raw is None:
        return None
    try:
        return int(raw.strip(), 0)
    except ValueError:
        return None


DEFAULT_PYOCD_FREQ_HZ = _env_int("PYOCD_FREQ_HZ", 8_000_000)
DEFAULT_PYOCD_DEBUG_FREQ_HZ = _env_int_optional("PYOCD_DEBUG_FREQ_HZ")
DEFAULT_PYOCD_DOUBLE_BUFFER = _env_bool("PYOCD_DOUBLE_BUFFER", True)
DEFAULT_PYOCD_FAST_RESET = _env_bool("PYOCD_FAST_RESET", True)
DEFAULT_PYOCD_SMART_SKIP = _env_bool("PYOCD_SMART_SKIP", True)
DEFAULT_PYOCD_NO_RESET = _env_bool("PYOCD_NO_RESET", False)
DEFAULT_PYOCD_ERASE = os.environ.get("PYOCD_ERASE", "sector").strip().lower()
if DEFAULT_PYOCD_ERASE not in {"auto", "sector", "chip"}:
    DEFAULT_PYOCD_ERASE = "sector"

# PYOCD_DEBUG_FREQ_HZ が未指定のときのみ target family preset を使う。
DEFAULT_PYOCD_DEBUG_FREQ_PRESETS: list[tuple[str, int]] = [
    ("stm32h7", _env_int("PYOCD_DEBUG_FREQ_HZ_H7", 12_000_000)),
    ("stm32f7", _env_int("PYOCD_DEBUG_FREQ_HZ_F7", 10_000_000)),
    ("stm32f4", _env_int("PYOCD_DEBUG_FREQ_HZ_F4", 8_000_000)),
    ("stm32", _env_int("PYOCD_DEBUG_FREQ_HZ_STM32", 8_000_000)),
]


def resolve_default_debug_freq_hz(mcu: str) -> int:
    if DEFAULT_PYOCD_DEBUG_FREQ_HZ is not None:
        return max(int(DEFAULT_PYOCD_DEBUG_FREQ_HZ), 0)
    mcu_l = (mcu or "").strip().lower()
    for prefix, freq in DEFAULT_PYOCD_DEBUG_FREQ_PRESETS:
        if mcu_l.startswith(prefix):
            return max(int(freq), 0)
    return 0

# ── STM32 DEV_ID → MCU ファミリ ルックアップテーブル ──
# DBGMCU_IDCODE の下位 12bit (DEV_ID) → pyOCD target 名
# 各ファミリの Reference Manual (DBGMCU_IDCODE 章) から取得
STM32_DEV_ID_TABLE: dict[int, str] = {
    # Cortex-M0/M0+
    0x410: "stm32f100xx",   # F100 Value Line
    0x412: "stm32f103xx",   # F1 Low/Medium density (F101/F102/F103)
    0x414: "stm32f103xx",   # F1 High density (F101/F103)
    0x418: "stm32f103xx",   # F1 Connectivity (F105/F107)
    0x420: "stm32f100xx",   # F100 Medium density Value Line
    0x428: "stm32f100xx",   # F100 High density Value Line
    0x430: "stm32f103xx",   # F1 XL density (F101/F103)
    # Cortex-M3
    0x416: "stm32l151xx",   # L1 Cat.1/Cat.2
    0x427: "stm32l151xx",   # L1 Cat.3
    0x436: "stm32l151xx",   # L1 Cat.4/Cat.3
    0x437: "stm32l151xx",   # L1 Cat.5/Cat.6
    0x429: "stm32l151xx",   # L1 Cat.2
    # Cortex-M0 (F0/L0/G0)
    0x440: "stm32f030x8",   # F05x/F030x8
    0x444: "stm32f031x6",   # F03x
    0x442: "stm32f091xx",   # F09x/F07x
    0x445: "stm32f042xx",   # F04x
    0x448: "stm32f070xb",   # F07x/F070xB
    0x447: "stm32l011xx",   # L0 Cat.1
    0x425: "stm32l031xx",   # L0 Cat.2
    0x417: "stm32l053xx",   # L0 Cat.3
    0x447: "stm32l071xx",   # L0 Cat.5
    0x456: "stm32g051xx",   # G0x1
    0x460: "stm32g070xx",   # G0x0
    0x466: "stm32g031xx",   # G031/G041
    0x467: "stm32g0b1xx",   # G0B1/G0C1
    # Cortex-M4 (F3/F4/L4/G4/WB)
    0x422: "stm32f303xx",   # F302xB/F303xB/F358
    0x438: "stm32f334xx",   # F334
    0x439: "stm32f302x8",   # F301/F302x8/F318
    0x446: "stm32f303xx",   # F303xE/F398
    0x449: "stm32f446xx",   # F446
    0x413: "stm32f407xx",   # F405/F407/F415/F417
    0x419: "stm32f427xx",   # F427/F429/F437/F439
    0x421: "stm32f446xx",   # F446 (alt)
    0x423: "stm32f401xc",   # F401xB/F401xC
    0x431: "stm32f411xe",   # F411
    0x433: "stm32f401xe",   # F401xD/F401xE
    0x434: "stm32f469xx",   # F469/F479
    0x441: "stm32f412xx",   # F412
    0x458: "stm32f410xx",   # F410
    0x463: "stm32f413xx",   # F413/F423
    0x461: "stm32l496xx",   # L496/L4A6
    0x415: "stm32l476xx",   # L476/L486
    0x462: "stm32l451xx",   # L451/L452/L462
    0x435: "stm32l432xx",   # L43x/L44x
    0x464: "stm32l412xx",   # L41x/L42x
    0x470: "stm32l4r5xx",   # L4R5/L4R7/L4R9/L4S5/L4S7/L4S9
    0x471: "stm32l4p5xx",   # L4P5/L4Q5
    0x468: "stm32g431xx",   # G431/G441
    0x469: "stm32g471xx",   # G471/G473/G474/G483/G484
    0x479: "stm32g491xx",   # G491/G4A1
    0x495: "stm32wb55xx",   # WB55/WB35
    0x494: "stm32wb15xx",   # WB15/WB10
    0x496: "stm32wb5mxx",   # WB5M
    0x497: "stm32wle5xx",   # WLE5/WL55
    # Cortex-M7 (F7/H7)
    0x452: "stm32f72xxx",   # F72x/F73x
    0x449: "stm32f74xxx",   # F74x/F75x (shares with F446, distinguish by CPUID)
    0x451: "stm32f76xxx",   # F76x/F77x
    0x450: "stm32h750xx",   # H743/H750/H753/H755
    0x480: "stm32h7a3xx",   # H7A3/H7B3/H7B0
    0x483: "stm32h723xx",   # H723/H725/H730/H733/H735
    # Cortex-M33 (L5/U5/H5)
    0x472: "stm32l552xx",   # L552/L562
    0x474: "stm32u575xx",   # U575/U585
    0x476: "stm32u595xx",   # U595/U5A5/U599/U5A9
    0x482: "stm32u535xx",   # U535/U545
    0x484: "stm32h563xx",   # H563/H573
    0x478: "stm32h503xx",   # H503
}

# DBGMCU_IDCODE アドレス候補（ファミリによって異なる）
DBGMCU_ADDRS = [
    0xE0042000,  # F0/F1/F2/F3/F4/L0/L1/G0/G4/WB
    0x5C001000,  # H7
    0xE0044000,  # L5/U5/H5/WL
]


# ── Probe Cache ──

def load_probe_cache() -> dict[str, dict]:
    """probe_cache.json を読み込む。UID → {mcu, board, name} のマッピング。"""
    if PROBE_CACHE_PATH.exists():
        try:
            with open(PROBE_CACHE_PATH) as f:
                data = json.load(f)
            # v2 format: {probes: {uid: {mcu, board, name}}}
            return data.get("probes", {})
        except (json.JSONDecodeError, KeyError):
            return {}
    return {}


def save_probe_cache(cache: dict[str, dict]) -> None:
    """probe_cache.json を書き込む。"""
    with open(PROBE_CACHE_PATH, "w") as f:
        json.dump({"_comment": "Auto-generated by pyocd_tool.py. Do not edit manually.", "probes": cache}, f, indent=2, ensure_ascii=False)
        f.write("\n")


def update_probe_cache(uid: str, mcu: str, board: str | None = None, name: str | None = None) -> None:
    """キャッシュに1エントリ追加/更新。"""
    cache = load_probe_cache()
    cache[uid] = {"mcu": mcu, "board": board, "name": name}
    save_probe_cache(cache)


# ── MCU Auto-Detection ──

def detect_mcu_from_board_info(probe) -> str | None:
    """pyOCD BoardInfo から MCU ターゲット名を取得。
    Nucleo / Discovery 等の既知ボードで使用可能。"""
    board_info = getattr(probe, "associated_board_info", None)
    if board_info and hasattr(board_info, "target") and board_info.target:
        # pyOCD の target 名は "stm32f407vgtx" のような形式
        # pyOCD target_override に渡せる形式に正規化
        target = board_info.target.lower()
        return _normalize_target(target)
    return None


def detect_mcu_from_idcode(uid: str) -> str | None:
    """DBGMCU_IDCODE を読んで MCU ファミリを判定する。
    汎用プローブ（STLINK-V3 単体等）で使用。

    under-reset モードで接続し、IDCODE を読んでから切断する。
    ターゲットの状態に影響を与えない。
    """
    if not PYOCD_API:
        return None

    try:
        session = ConnectHelper.session_with_chosen_probe(
            unique_id=uid,
            options={"connect_mode": "under-reset", "resume_on_disconnect": False},
        )
        session.open()
    except Exception:
        return None

    try:
        target = session.target

        # CPUID を読んでコアタイプを確認
        try:
            cpuid = target.read32(0xE000ED00)
            partno = (cpuid >> 4) & 0xFFF
        except Exception:
            partno = 0

        # DBGMCU_IDCODE を複数アドレスから試行
        dev_id = None
        for addr in DBGMCU_ADDRS:
            try:
                idcode = target.read32(addr)
                if idcode != 0:
                    dev_id = idcode & 0xFFF
                    break
            except Exception:
                continue

        if dev_id is None:
            return None

        mcu = STM32_DEV_ID_TABLE.get(dev_id)
        if mcu:
            # DEV_ID 0x449 は F74x と F446 で重複 → CPUID で区別
            if dev_id == 0x449 and partno == 0xC24:
                mcu = "stm32f446xx"
            return mcu

        # 未知の DEV_ID — CPUID から Cortex コアタイプだけでも返す
        core_map = {0xC20: "cortex-m0", 0xC60: "cortex-m0+",
                    0xC23: "cortex-m3", 0xC24: "cortex-m4",
                    0xC27: "cortex-m7", 0xC33: "cortex-m33"}
        core_name = core_map.get(partno, f"unknown-core-0x{partno:03x}")
        return f"unknown_stm32_devid_0x{dev_id:03x}_{core_name}"
    finally:
        try:
            session.target.reset()
        except Exception:
            pass
        session.close()


def _normalize_target(target: str) -> str:
    """pyOCD target 名を正規化。
    'stm32f407vgtx' → 'stm32f407vg'  (末尾のパッケージコード除去)
    """
    # STM32 の target 名: stm32XXXXXX + パッケージ (t/tx/rx etc)
    m = re.match(r"(stm32[a-z]\d{3}[a-z]{2})", target)
    if m:
        return m.group(1)
    # フォールバック: そのまま返す
    return target


# ── Probe Discovery ──

def list_probes() -> list[dict]:
    """接続中の全プローブを取得。MCU を自動検出する。"""
    if not PYOCD_API:
        return _list_probes_cli()

    probes = aggregator.DebugProbeAggregator.get_all_connected_probes()
    cache = load_probe_cache()
    result = []

    for p in probes:
        uid = p.unique_id

        # 1. pyOCD BoardInfo から取得
        mcu = detect_mcu_from_board_info(p)
        board = None
        board_info = getattr(p, "associated_board_info", None)
        if board_info:
            board = getattr(board_info, "name", None)

        # 2. キャッシュから取得
        if not mcu and uid in cache:
            mcu = cache[uid].get("mcu")
            board = board or cache[uid].get("board")

        # 3. mcu がまだ不明 → DBGMCU_IDCODE で自動検出（初回のみ）
        if not mcu:
            detected = detect_mcu_from_idcode(uid)
            if detected:
                mcu = detected
                update_probe_cache(uid, mcu, board, p.product_name)

        # キャッシュ更新（BoardInfo で取得できた場合もキャッシュに反映）
        if mcu and (uid not in cache or cache[uid].get("mcu") != mcu):
            update_probe_cache(uid, mcu, board, p.product_name)

        result.append({
            "uid": uid,
            "vendor": p.vendor_name,
            "product": p.product_name,
            "mcu": mcu,
            "board": board,
            "name": f"{p.product_name}{' ' + board if board else ''}",
        })
    return result


def _list_probes_cli() -> list[dict]:
    """CLI フォールバック。"""
    try:
        r = subprocess.run(["pyocd", "list"], capture_output=True, text=True, timeout=10)
        probes = []
        for line in r.stdout.splitlines():
            m = re.match(r'\s*(\d+)\s+(.+?)\s+([0-9A-Fa-f]{16,})\s+(.*)', line)
            if m:
                probes.append({
                    "uid": m.group(3),
                    "vendor": "STMicroelectronics",
                    "product": m.group(2).strip(),
                    "mcu": None,
                    "board": None,
                    "name": m.group(2).strip(),
                })
        return probes
    except Exception:
        return []


def resolve_probe(mcu: str | None) -> tuple[str, str]:
    """
    MCU 名からプローブ UID と実際のターゲット名を解決する。

    MCU 自動検出により、ほとんどの場合 --mcu 指定不要。
    複数プローブ接続中は --mcu で対象を特定。

    Returns: (uid, mcu_target)
    """
    probes = list_probes()

    if not probes:
        raise RuntimeError("プローブが接続されていません")

    # MCU 指定なし → 1台なら自動選択
    if not mcu:
        if len(probes) == 1:
            p = probes[0]
            mcu_resolved = p["mcu"]
            if not mcu_resolved:
                raise RuntimeError(
                    f"プローブ {p['uid']} の MCU を自動検出できませんでした。\n"
                    f"  --mcu で明示指定してください"
                )
            return p["uid"], mcu_resolved
        else:
            probe_info = "\n".join(
                f"  {p.get('mcu', '?'):20s} — {p['name']} ({p['uid'][:12]}...)"
                for p in probes
            )
            raise RuntimeError(
                f"複数プローブ接続中 ({len(probes)}台)。--mcu で対象を指定してください:\n"
                + probe_info
            )

    # MCU 指定あり → 接続中プローブから検索
    mcu_lower = mcu.lower()

    # 完全一致
    for p in probes:
        if p.get("mcu") and p["mcu"].lower() == mcu_lower:
            return p["uid"], p["mcu"]

    # prefix マッチ（例: "stm32f407" → "stm32f407vg"）
    for p in probes:
        if p.get("mcu") and p["mcu"].lower().startswith(mcu_lower):
            return p["uid"], p["mcu"]

    # 逆 prefix マッチ（例: "stm32f407vg" → "stm32f407xx"）
    for p in probes:
        if p.get("mcu") and mcu_lower.startswith(p["mcu"].lower()[:10]):
            return p["uid"], mcu

    # 見つからない
    connected_info = "\n".join(
        f"  {p.get('mcu', '(未検出)'):20s} — {p['name']} ({p['uid'][:12]}...)"
        for p in probes
    )
    raise RuntimeError(
        f"MCU '{mcu}' に対応するプローブが見つかりません。\n"
        f"接続中のプローブ:\n{connected_info}\n\n"
        f"対処法:\n"
        f"  1. 対象ボードの USB を確認\n"
        f"  2. Run pyocd_tool.py list to see available probes"
    )


# ── Session Management ──

def open_session(
    uid: str,
    mcu: str,
    connect_mode: str = "attach",
    session_options: dict[str, Any] | None = None,
) -> Session:
    """pyOCD セッションを開く。

    接続失敗時は under-reset リカバリを1回だけ試みる。
    リカバリが安全な場合のみ（TransferFault 等の接続系エラー）実行する。
    """
    if not PYOCD_API:
        raise RuntimeError("pyOCD Python API が利用できません (pip install pyocd)")

    def _build_options(mode: str) -> dict[str, Any]:
        opts: dict[str, Any] = {
            "connect_mode": mode,
            "resume_on_disconnect": False,
        }
        freq_hz = resolve_default_debug_freq_hz(mcu)
        if freq_hz > 0:
            opts["frequency"] = freq_hz
        if session_options:
            opts.update(session_options)
        return opts

    def _try_open(mode: str) -> Session:
        s = ConnectHelper.session_with_chosen_probe(
            unique_id=uid,
            target_override=mcu,
            options=_build_options(mode),
        )
        s.open()
        return s

    # 1回目: 通常接続
    saved_err: Exception | None = None
    try:
        return _try_open(connect_mode)
    except Exception as first_err:
        err_str = str(first_err).lower()
        # リカバリ不能なエラー → 即座に失敗
        # （ターゲット名不正、プローブ未接続等）
        non_recoverable = ["no available debug probe", "probe not found",
                           "unknown target", "invalid", "not supported"]
        if any(s in err_str for s in non_recoverable):
            raise
        # Python 3 では except ブロック終了時に first_err が削除されるため保存
        saved_err = first_err

    # 2回目: under-reset でリカバリ → 再接続
    # （ターゲットが不安定 / ロックアップ / 再接続後の場合のみ有効）
    try:
        recovery = ConnectHelper.session_with_chosen_probe(
            unique_id=uid,
            target_override=mcu,
            options=_build_options("under-reset"),
        )
        recovery.open()
        recovery.target.reset()
        recovery.close()
        time.sleep(0.5)
    except Exception:
        # リカバリ失敗 → 元のエラーで失敗
        raise RuntimeError(
            f"ターゲット '{mcu}' (probe {uid[:12]}...) に接続できません。\n"
            f"  エラー: {saved_err}\n"
            f"  リカバリも失敗しました。USB 接続を確認してください。"
        ) from saved_err

    # 3回目: リセット後に再接続
    try:
        return _try_open(connect_mode)
    except Exception as retry_err:
        raise RuntimeError(
            f"ターゲット '{mcu}' (probe {uid[:12]}...) に接続できません。\n"
            f"  初回エラー: {saved_err}\n"
            f"  リカバリ後も失敗: {retry_err}\n"
            f"  USB を抜き差しするか、ターゲットの電源を確認してください"
        ) from retry_err


# ── Commands ──

def cmd_list(args: argparse.Namespace) -> dict:
    """接続プローブ一覧（MCU 自動検出付き）。"""
    probes = list_probes()
    return {"probes": probes, "count": len(probes)}


def cmd_status(args: argparse.Namespace) -> dict:
    """ターゲット状態。"""
    uid, mcu = resolve_probe(args.mcu)
    session = open_session(uid, mcu)
    try:
        target = session.target
        state = target.get_state().name
        return {
            "uid": uid,
            "mcu": mcu,
            "state": state,
            "part_number": target.part_number,
        }
    finally:
        session.close()


def _should_force_erased_readable(mcu: str, boot_region: Any) -> bool:
    """STM32 内蔵 Flash は erased sector の read が可能なため smart-skip を有効化できる。"""
    if not mcu.lower().startswith("stm32"):
        return False
    try:
        return bool(
            getattr(boot_region, "is_flash", False)
            and getattr(boot_region, "is_readable", False)
            and int(getattr(boot_region, "start", 0)) == 0x08000000
        )
    except Exception:
        return False


def _enable_double_buffer_if_supported(loader: MemoryLoader) -> int:
    """MemoryLoader 内の FlashBuilder で double buffer を有効化する。"""
    enabled = 0
    builders = getattr(loader, "_builders", {})
    for builder in builders.values():
        fn = getattr(builder, "enable_double_buffer", None)
        if callable(fn):
            fn(True)
            enabled += 1
    return enabled


def _flash_with_pyocd(
    session: Session,
    mcu: str,
    binary: Path,
    *,
    erase: str | None,
    trust_crc: bool,
    double_buffer: bool,
    smart_skip: bool,
) -> dict[str, Any]:
    """pyOCD backend の実装。

    .bin は MemoryLoader 経由で double buffer を有効化して高速化する。
    それ以外は FileProgrammer にフォールバックする。
    """
    if binary.suffix.lower() != ".bin":
        # For non-bin files we keep using FileProgrammer.
        FileProgrammer(
            session,
            chip_erase=erase,
            trust_crc=trust_crc,
            no_reset=True,
        ).program(str(binary))
        return {"double_buffer_regions": 0, "smart_skip_forced": False}

    target = session.target
    boot_memory = target.memory_map.get_boot_memory()
    if boot_memory is None:
        raise RuntimeError("boot memory が見つかりません")
    if not getattr(boot_memory, "is_flash", False):
        raise RuntimeError("boot memory が flash ではありません")

    force_erased_readable = smart_skip and _should_force_erased_readable(mcu, boot_memory)
    original_erased_readable = getattr(boot_memory, "are_erased_sectors_readable", None)
    if force_erased_readable:
        setattr(boot_memory, "are_erased_sectors_readable", True)

    try:
        data = binary.read_bytes()
        loader = MemoryLoader(
            session,
            chip_erase=erase,
            smart_flash=smart_skip,
            trust_crc=trust_crc,
            no_reset=True,  # We reset once at the end from cmd_flash().
        )
        loader.add_data(boot_memory.start, list(data))
        enabled_regions = _enable_double_buffer_if_supported(loader) if double_buffer else 0
        loader.commit()
        return {
            "double_buffer_regions": enabled_regions,
            "smart_skip_forced": force_erased_readable,
        }
    finally:
        if force_erased_readable and original_erased_readable is not None:
            setattr(boot_memory, "are_erased_sectors_readable", original_erased_readable)


def cmd_flash(args: argparse.Namespace) -> dict:
    """フラッシュ書き込み。"""
    uid, mcu = resolve_probe(args.mcu)
    binary = Path(args.binary)
    if not binary.exists():
        raise FileNotFoundError(f"バイナリが見つかりません: {binary}")

    backend = (getattr(args, "backend", DEFAULT_FLASH_BACKEND) or "auto").lower()
    verify = bool(getattr(args, "verify", DEFAULT_FLASH_VERIFY))

    # Fast path: STM32CubeProgrammer backend for .bin flashing.
    # This avoids pyOCD session startup overhead and is significantly faster on STM32.
    use_cube = (
        backend in {"auto", "stm32cube"} and
        binary.suffix.lower() == ".bin" and
        shutil.which("STM32_Programmer_CLI") is not None
    )
    if use_cube:
        try:
            t0 = time.monotonic()
            cmd = [
                "STM32_Programmer_CLI",
                "-q",
                "-c", f"port=SWD mode=UR sn={uid}",
                "-w", str(binary), "0x08000000",
            ]
            if verify:
                cmd.append("-v")
            cmd.append("-rst")
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
            if proc.returncode != 0:
                err = (proc.stdout or "") + (proc.stderr or "")
                raise RuntimeError(err.strip() or "STM32_Programmer_CLI flash failed")

            elapsed = time.monotonic() - t0
            return {
                "uid": uid,
                "mcu": mcu,
                "binary": str(binary),
                "size": binary.stat().st_size,
                "elapsed_s": round(elapsed, 2),
                "status": "ok",
                "flash_backend": "stm32cube",
                "verify": verify,
            }
        except Exception:
            # Explicit stm32cube request should fail loudly.
            if backend == "stm32cube":
                raise
            # auto mode: fallback to pyOCD backend.

    if backend == "stm32cube":
        raise RuntimeError("STM32CubeProgrammer backend unavailable for this target/file")

    freq_hz = int(getattr(args, "freq", DEFAULT_PYOCD_FREQ_HZ))
    double_buffer = bool(getattr(args, "double_buffer", DEFAULT_PYOCD_DOUBLE_BUFFER))
    fast_reset = bool(getattr(args, "fast_reset", DEFAULT_PYOCD_FAST_RESET))
    smart_skip = bool(getattr(args, "smart_skip", DEFAULT_PYOCD_SMART_SKIP))
    no_reset = bool(getattr(args, "no_reset", DEFAULT_PYOCD_NO_RESET))
    trust_crc = bool(getattr(args, "trust_crc", False))
    erase = (getattr(args, "erase", DEFAULT_PYOCD_ERASE) or DEFAULT_PYOCD_ERASE).strip().lower()
    if erase not in {"auto", "sector", "chip"}:
        raise ValueError(f"erase mode は auto/sector/chip のいずれか: {erase}")

    session_options: dict[str, Any] = {"hide_programming_progress": True}
    if freq_hz > 0:
        session_options["frequency"] = freq_hz
    if fast_reset:
        # Default reset delays (100ms + 100ms) are safe but slow.
        session_options["reset.hold_time"] = 0.0
        session_options["reset.post_delay"] = 0.0

    session = open_session(uid, mcu, connect_mode="halt", session_options=session_options)
    try:
        t0 = time.monotonic()
        pyocd_meta = _flash_with_pyocd(
            session,
            mcu,
            binary,
            erase=erase,
            trust_crc=trust_crc,
            double_buffer=double_buffer,
            smart_skip=smart_skip,
        )
        if not no_reset:
            session.target.reset()
        elapsed = time.monotonic() - t0
        return {
            "uid": uid,
            "mcu": mcu,
            "binary": str(binary),
            "size": binary.stat().st_size,
            "elapsed_s": round(elapsed, 2),
            "status": "ok",
            "flash_backend": "pyocd",
            "verify": True,
            "freq_hz": freq_hz,
            "double_buffer": double_buffer,
            "smart_skip": smart_skip,
            "fast_reset": fast_reset,
            "no_reset": no_reset,
            "erase": erase,
            "trust_crc": trust_crc,
            **pyocd_meta,
        }
    finally:
        session.close()


def cmd_read(args: argparse.Namespace) -> dict:
    """メモリ読み取り（halt → read → resume）。"""
    uid, mcu = resolve_probe(args.mcu)
    addr = int(args.addr, 0)
    size = int(args.size)

    session = open_session(uid, mcu)
    try:
        target = session.target
        core = target.cores[0]
        read_map = _read_blocks(target, core, [("mem", addr, size)])
        read = read_map["mem"]

        return {
            "uid": uid,
            "mcu": mcu,
            "address": f"0x{addr:08X}",
            "size": size,
            "words": read["words"],
            "hex": read["hex"],
        }
    finally:
        session.close()


def cmd_read_symbol(args: argparse.Namespace) -> dict:
    """ELF シンボル → アドレス解決 → メモリ読み取り。"""
    uid, mcu = resolve_probe(args.mcu)
    elf = args.elf
    symbol = args.symbol
    size = int(args.size) if args.size else None

    addr, sym_size = _resolve_symbol(elf, symbol)
    if size is None:
        size = sym_size if sym_size > 0 else 64

    session = open_session(uid, mcu)
    try:
        target = session.target
        core = target.cores[0]
        read_map = _read_blocks(target, core, [("sym", addr, size)])
        read = read_map["sym"]

        return {
            "uid": uid,
            "mcu": mcu,
            "symbol": symbol,
            "address": f"0x{addr:08X}",
            "size": size,
            "words": read["words"],
            "hex": read["hex"],
        }
    finally:
        session.close()


def cmd_read_symbols(args: argparse.Namespace) -> dict:
    """複数シンボルを単一セッションで読み取り。"""
    uid, mcu = resolve_probe(args.mcu)
    elf = args.elf
    symbols = list(args.symbols)
    if not symbols:
        raise ValueError("read-symbols には 1 つ以上のシンボル指定が必要です")

    resolved = _resolve_symbols(elf, symbols)
    blocks: list[tuple[str, int, int]] = []
    for sym in symbols:
        addr, sym_size = resolved[sym]
        size = sym_size if sym_size > 0 else 64
        blocks.append((sym, addr, size))

    session = open_session(uid, mcu)
    try:
        target = session.target
        core = target.cores[0]
        read_map = _read_blocks(target, core, blocks)

        result_symbols: dict[str, dict[str, Any]] = {}
        for sym in symbols:
            addr, sym_size = resolved[sym]
            entry = read_map[sym]
            result_symbols[sym] = {
                "address": f"0x{addr:08X}",
                "size": sym_size if sym_size > 0 else 64,
                "words": entry["words"],
                "hex": entry["hex"],
            }

        return {
            "uid": uid,
            "mcu": mcu,
            "elf": elf,
            "symbols": result_symbols,
        }
    finally:
        session.close()


def _read_blocks(
    target,
    core,
    blocks: list[tuple[str, int, int]],
    *,
    halt: bool = True,
) -> dict[str, dict[str, Any]]:
    """複数ブロックをまとめて読み取る。halt=True の場合は halt→read→resume。"""
    was_halted = target.get_state().name == "HALTED"
    did_halt = False
    if halt and not was_halted:
        core.halt()
        did_halt = True

    try:
        result: dict[str, dict[str, Any]] = {}
        for key, addr, size in blocks:
            word_count = (size + 3) // 4
            words = target.read_memory_block32(addr, word_count)
            raw = b"".join(struct.pack("<I", w) for w in words)[:size]
            result[key] = {
                "words": [f"0x{w:08X}" for w in words],
                "hex": raw.hex(),
            }
        return result
    finally:
        if did_halt:
            core.resume()


def _resolve_symbols(elf: str, names: list[str]) -> dict[str, tuple[int, int]]:
    """ELF から複数シンボルを解決する。name substring に一致する最初のシンボルを採用。"""
    r = subprocess.run(
        ["arm-none-eabi-nm", "--demangle", "--print-size", elf],
        capture_output=True, text=True, timeout=10,
    )
    if r.returncode != 0:
        detail = (r.stderr or r.stdout or "").strip()
        raise RuntimeError(f"arm-none-eabi-nm failed: {detail}")

    table: list[tuple[str, int, int]] = []
    for line in r.stdout.splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        symbol = parts[-1]
        try:
            addr = int(parts[0], 16)
        except ValueError:
            continue
        try:
            sym_size = int(parts[1], 16) if len(parts) >= 4 else 0
        except ValueError:
            sym_size = 0
        table.append((symbol, addr, sym_size))

    result: dict[str, tuple[int, int]] = {}
    for name in names:
        found: tuple[int, int] | None = None
        for symbol, addr, sym_size in table:
            if name in symbol:
                found = (addr, sym_size)
                break
        if found is None:
            raise ValueError(f"シンボル '{name}' が {elf} に見つかりません")
        result[name] = found
    return result


def _resolve_symbol(elf: str, name: str) -> tuple[int, int]:
    """ELF からシンボルのアドレスとサイズを取得。"""
    return _resolve_symbols(elf, [name])[name]


def cmd_regs(args: argparse.Namespace) -> dict:
    """コアレジスタ読み取り。"""
    uid, mcu = resolve_probe(args.mcu)
    session = open_session(uid, mcu)
    try:
        target = session.target
        core = target.cores[0]
        was_halted = target.get_state().name == "HALTED"

        if not was_halted:
            core.halt()

        reg_names = ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7",
                     "r8", "r9", "r10", "r11", "r12", "sp", "lr", "pc",
                     "xpsr", "msp", "psp", "control", "faultmask",
                     "basepri", "primask"]
        regs = {}
        for name in reg_names:
            try:
                val = core.read_core_register(name)
                regs[name] = f"0x{val:08X}"
            except Exception:
                pass

        if not was_halted:
            core.resume()

        return {"uid": uid, "mcu": mcu, "registers": regs}
    finally:
        session.close()


def cmd_reset(args: argparse.Namespace) -> dict:
    """ターゲットリセット。"""
    uid, mcu = resolve_probe(args.mcu)
    session = open_session(uid, mcu, connect_mode="attach")
    try:
        session.target.reset()
        state = session.target.get_state().name
        return {"uid": uid, "mcu": mcu, "state": state, "status": "ok"}
    finally:
        session.close()


def cmd_run_read(args: argparse.Namespace) -> dict:
    """reset → run → wait → halt → read。"""
    uid, mcu = resolve_probe(args.mcu)
    addr = int(args.addr, 0)
    size = int(args.size)
    run_ms = int(args.ms)

    session = open_session(uid, mcu, connect_mode="halt")
    try:
        target = session.target
        core = target.cores[0]

        target.reset()
        core.resume()
        time.sleep(run_ms / 1000.0)
        core.halt()

        word_count = (size + 3) // 4
        words = target.read_memory_block32(addr, word_count)

        core.resume()

        raw = b""
        for w in words:
            raw += struct.pack("<I", w)
        raw = raw[:size]

        return {
            "uid": uid,
            "mcu": mcu,
            "address": f"0x{addr:08X}",
            "size": size,
            "run_ms": run_ms,
            "words": [f"0x{w:08X}" for w in words],
            "hex": raw.hex(),
        }
    finally:
        session.close()


def _read_fault_info(target, core, *, verbose: bool = False) -> dict:
    """フォールトレジスタ + 例外スタックフレームを読み取る（セッション内で呼出）。

    Args:
        target: pyOCD target object
        core: pyOCD core object
        verbose: True の場合、追加レジスタ (SHCSR, DFSR, AFSR) と詳細説明を含める
    """
    # SCB フォールトレジスタ
    fault_regs = {}
    scb_map = {
        "ICSR":  0xE000ED04,
        "CFSR":  0xE000ED28,
        "HFSR":  0xE000ED2C,
        "MMFAR": 0xE000ED34,
        "BFAR":  0xE000ED38,
    }
    if verbose:
        scb_map.update({
            "SHCSR": 0xE000ED24,
            "DFSR":  0xE000ED30,
            "AFSR":  0xE000ED3C,
        })
    for name, addr in scb_map.items():
        try:
            val = target.read32(addr)
            fault_regs[name] = f"0x{val:08X}"
        except Exception:
            fault_regs[name] = "read_failed"

    # CFSR/HFSR 解析
    cfsr = target.read32(0xE000ED28)
    hfsr = target.read32(0xE000ED2C)
    icsr = target.read32(0xE000ED04)

    active_exception = icsr & 0x1FF
    faults = []

    # フォールトビット → (短縮名, 詳細説明)
    cfsr_bits = [
        (0x0001, "IACCVIOL",    "Instruction access violation"),
        (0x0002, "DACCVIOL",    "Data access violation"),
        (0x0008, "MUNSTKERR",   "MemManage unstacking error"),
        (0x0010, "MSTKERR",     "MemManage stacking error"),
        (0x0020, "MLSPERR",     "MemManage FP lazy state"),
        (0x0100, "IBUSERR",     "Instruction bus error"),
        (0x0200, "PRECISERR",   "Precise data bus error"),
        (0x0400, "IMPRECISERR", "Imprecise data bus error"),
        (0x0800, "UNSTKERR",    "BusFault unstacking error"),
        (0x1000, "STKERR",      "BusFault stacking error"),
        (0x2000, "LSPERR",      "BusFault FP lazy state"),
        (1 << 16, "UNDEFINSTR", "Undefined instruction"),
        (1 << 17, "INVSTATE",   "Invalid state - Thumb bit"),
        (1 << 18, "INVPC",      "Invalid PC load"),
        (1 << 19, "NOCP",       "No coprocessor"),
        (1 << 24, "UNALIGNED",  "Unaligned access"),
        (1 << 25, "DIVBYZERO",  "Division by zero"),
    ]
    hfsr_bits = [
        (1 << 30, "FORCED",  "HardFault escalated from other fault"),
        (1 << 1,  "VECTTBL", "Vector table read error"),
    ]
    for mask, name, desc in cfsr_bits:
        if cfsr & mask:
            faults.append(f"{name} ({desc})" if verbose else name)
    for mask, name, desc in hfsr_bits:
        if hfsr & mask:
            faults.append(f"{name} ({desc})" if verbose else name)

    # BFAR/MMFAR 有効チェック
    fault_addr = None
    if cfsr & 0x0080:  # BFARVALID
        fault_addr = f"0x{target.read32(0xE000ED38):08X} (BFAR)"
    elif cfsr & 0x0004:  # MMARVALID
        fault_addr = f"0x{target.read32(0xE000ED34):08X} (MMFAR)"

    # 例外スタックフレーム
    lr = core.read_core_register("lr")
    stack_frame = None
    if (lr & 0xFFFFFFF0) == 0xFFFFFFF0:
        use_psp = (lr & 0x4) != 0
        sp_name = "psp" if use_psp else "msp"
        sp_val = core.read_core_register(sp_name)
        try:
            frame = target.read_memory_block32(sp_val, 8)
            stack_frame = {
                "stack": sp_name,
                "sp": f"0x{sp_val:08X}",
                "r0":   f"0x{frame[0]:08X}",
                "r1":   f"0x{frame[1]:08X}",
                "r2":   f"0x{frame[2]:08X}",
                "r3":   f"0x{frame[3]:08X}",
                "r12":  f"0x{frame[4]:08X}",
                "lr":   f"0x{frame[5]:08X}",
                "pc":   f"0x{frame[6]:08X}",
                "xpsr": f"0x{frame[7]:08X}",
            }
        except Exception:
            stack_frame = {"error": "stack frame read failed"}

    exception_names = {
        0: "Thread", 2: "NMI", 3: "HardFault",
        4: "MemManage", 5: "BusFault", 6: "UsageFault",
        11: "SVCall", 12: "DebugMon", 14: "PendSV", 15: "SysTick",
    }
    exc_name = exception_names.get(active_exception,
        f"IRQ{active_exception - 16}" if active_exception >= 16 else f"Exception({active_exception})")

    info: dict[str, Any] = {
        "active_exception": exc_name,
        "faults": faults if faults else ["(none)"],
        "fault_registers": fault_regs,
    }
    if fault_addr:
        info["fault_address"] = fault_addr
    if stack_frame:
        info["exception_stack_frame"] = stack_frame

    return info


def cmd_step(args: argparse.Namespace) -> dict:
    """シングルステップ実行。N命令分実行してレジスタを返す。"""
    uid, mcu = resolve_probe(args.mcu)
    count = int(args.count) if args.count else 1

    session = open_session(uid, mcu)
    try:
        target = session.target
        core = target.cores[0]

        if not core.is_halted():
            core.halt()

        steps = []
        for i in range(count):
            pc_before = core.read_core_register("pc")
            core.step()
            pc_after = core.read_core_register("pc")
            steps.append({
                "step": i + 1,
                "pc_before": f"0x{pc_before:08X}",
                "pc_after": f"0x{pc_after:08X}",
            })

        # 最終状態のレジスタ
        regs = {}
        for name in ["pc", "sp", "lr", "r0", "r1", "r2", "r3", "xpsr"]:
            try:
                val = core.read_core_register(name)
                regs[name] = f"0x{val:08X}"
            except Exception:
                pass

        return {
            "uid": uid, "mcu": mcu,
            "steps": steps,
            "count": count,
            "registers": regs,
            "state": "HALTED",
        }
    finally:
        session.close()


def cmd_break_run(args: argparse.Namespace) -> dict:
    """ブレークポイント設定 → [前処理] → 実行 → ヒットまで待機 → レジスタ返却。

    使い方: break <addr> [--timeout <ms>] [--reset] [--set-pc <addr>]
                         [--write <addr:val,...>] [--mcu <mcu>]
    --reset: ブレークポイント設定後にリセットして実行開始
    --set-pc: resume 前に PC を変更（fault 再現テスト等）
    --write: resume 前にメモリ書き込み（addr:val,addr:val,...）
    タイムアウト内にヒットしなければ halt して状態を返す。

    全操作を単一セッション内で実行するため、ブレークポイントが有効。
    """
    uid, mcu = resolve_probe(args.mcu)
    addr = int(args.addr, 0)
    timeout_ms = int(args.timeout) if args.timeout else 5000
    do_reset = getattr(args, "reset", False)
    set_pc = getattr(args, "set_pc", None)
    write_spec = getattr(args, "write", None)

    session = open_session(uid, mcu, connect_mode="halt")
    try:
        target = session.target
        core = target.cores[0]

        # ブレークポイント設定
        core.set_breakpoint(addr)

        # 前処理: メモリ書き込み
        if write_spec:
            for spec in write_spec.split(","):
                if ":" in spec:
                    w_addr, w_val = spec.split(":", 1)
                    target.write32(int(w_addr.strip(), 0), int(w_val.strip(), 0))

        # 前処理: リセット or PC 変更
        if do_reset:
            target.reset_and_halt()
            # reset は FPB をクリアするため、ブレークポイントを再設定
            core.set_breakpoint(addr)
        elif set_pc:
            core.write_core_register("pc", int(set_pc, 0))

        # 実行開始
        core.resume()

        # ヒット待機
        t0 = time.monotonic()
        hit = False
        while (time.monotonic() - t0) * 1000 < timeout_ms:
            if core.is_halted():
                hit = True
                break
            time.sleep(0.01)

        if not hit:
            core.halt()

        # ブレークポイント除去
        core.remove_breakpoint(addr)

        # レジスタ読み取り
        reg_names = ["pc", "sp", "lr", "r0", "r1", "r2", "r3",
                     "r12", "xpsr", "msp", "psp", "control"]
        regs = {}
        for name in reg_names:
            try:
                val = core.read_core_register(name)
                regs[name] = f"0x{val:08X}"
            except Exception:
                pass

        halt_reason = "breakpoint" if hit else "timeout"

        result = {
            "uid": uid, "mcu": mcu,
            "breakpoint": f"0x{addr:08X}",
            "hit": hit,
            "halt_reason": halt_reason,
            "elapsed_ms": round((time.monotonic() - t0) * 1000, 1),
            "registers": regs,
        }

        # ヒット時: フォールト診断情報を付加（同一セッション内）
        if hit:
            result["fault_info"] = _read_fault_info(target, core)

        return result
    finally:
        session.close()


def cmd_wait_halt(args: argparse.Namespace) -> dict:
    """ターゲットが halt するまで待機。ブレークポイントヒット待ちに使用。

    注意: pyOCD はセッション終了時にハードウェアブレークポイントをクリアするため、
    bp-set → (セッション終了) → wait-halt ではブレークポイントが保持されない。
    ブレークポイント付き実行には `break` コマンド（単一セッション内で完結）を使用すること。
    """
    uid, mcu = resolve_probe(args.mcu)
    timeout_ms = int(args.timeout) if args.timeout else 5000

    session = open_session(uid, mcu)
    try:
        core = session.target.cores[0]

        t0 = time.monotonic()
        hit = False
        while (time.monotonic() - t0) * 1000 < timeout_ms:
            if core.is_halted():
                hit = True
                break
            time.sleep(0.01)

        if not hit:
            core.halt()

        regs = {}
        for name in ["pc", "sp", "lr", "r0", "r1", "r2", "r3", "xpsr"]:
            try:
                val = core.read_core_register(name)
                regs[name] = f"0x{val:08X}"
            except Exception:
                pass

        return {
            "uid": uid, "mcu": mcu,
            "halted": hit,
            "reason": "breakpoint_or_halt" if hit else "timeout",
            "elapsed_ms": round((time.monotonic() - t0) * 1000, 1),
            "registers": regs,
        }
    finally:
        session.close()


def cmd_watch(args: argparse.Namespace) -> dict:
    """ウォッチポイント設定 → 実行 → トリガーまで待機。

    メモリアドレスへの read/write を検知して停止する。
    """
    uid, mcu = resolve_probe(args.mcu)
    addr = int(args.addr, 0)
    size = int(args.size) if args.size else 4
    watch_type = args.type or "write"
    timeout_ms = int(args.timeout) if args.timeout else 5000

    session = open_session(uid, mcu, connect_mode="halt")
    try:
        target = session.target
        core = target.cores[0]

        # ウォッチポイントタイプ
        from pyocd.core.target import Target
        type_map = {
            "read": Target.WatchpointType.READ,
            "write": Target.WatchpointType.WRITE,
            "access": Target.WatchpointType.READ_WRITE,
        }
        wp_type = type_map.get(watch_type, Target.WatchpointType.WRITE)

        # ウォッチポイント設定
        ok = core.set_watchpoint(addr, size, wp_type)
        if not ok:
            raise RuntimeError(
                f"ウォッチポイントを設定できません (addr=0x{addr:08X}, size={size})。"
                f" HW ウォッチポイント数の上限に達している可能性があります。"
            )

        # 実行開始
        core.resume()

        # トリガー待機
        t0 = time.monotonic()
        hit = False
        while (time.monotonic() - t0) * 1000 < timeout_ms:
            if core.is_halted():
                hit = True
                break
            time.sleep(0.01)

        if not hit:
            core.halt()

        # ウォッチポイント除去
        core.remove_watchpoint(addr, size, wp_type)

        # 停止地点のレジスタ
        regs = {}
        for name in ["pc", "sp", "lr", "r0", "r1", "r2", "r3"]:
            try:
                val = core.read_core_register(name)
                regs[name] = f"0x{val:08X}"
            except Exception:
                pass

        # 対象メモリの現在値
        word_count = (size + 3) // 4
        words = target.read_memory_block32(addr, word_count)

        return {
            "uid": uid, "mcu": mcu,
            "watchpoint": f"0x{addr:08X}",
            "size": size,
            "type": watch_type,
            "hit": hit,
            "elapsed_ms": round((time.monotonic() - t0) * 1000, 1),
            "registers": regs,
            "memory": [f"0x{w:08X}" for w in words],
        }
    finally:
        session.close()


def cmd_write(args: argparse.Namespace) -> dict:
    """メモリ書き込み。テスト入力注入やデバッグ変数の設定に使用。"""
    uid, mcu = resolve_probe(args.mcu)
    addr = int(args.addr, 0)

    # 値をパース: "0x1234" or "1234" or "0x1234,0x5678"
    values_str = args.values
    words = []
    for v in values_str.split(","):
        v = v.strip()
        words.append(int(v, 0))

    session = open_session(uid, mcu)
    try:
        target = session.target
        core = target.cores[0]
        was_halted = target.get_state().name == "HALTED"

        if not was_halted:
            core.halt()

        target.write_memory_block32(addr, words)

        # 書き込み確認
        readback = target.read_memory_block32(addr, len(words))

        if not was_halted:
            core.resume()

        return {
            "uid": uid, "mcu": mcu,
            "address": f"0x{addr:08X}",
            "written": [f"0x{w:08X}" for w in words],
            "readback": [f"0x{w:08X}" for w in readback],
            "verified": words == readback,
        }
    finally:
        session.close()


def cmd_write_reg(args: argparse.Namespace) -> dict:
    """レジスタ書き込み。PC 変更やスタック復旧に使用。"""
    uid, mcu = resolve_probe(args.mcu)
    reg = args.reg.lower()
    value = int(args.value, 0)

    session = open_session(uid, mcu)
    try:
        target = session.target
        core = target.cores[0]

        if not core.is_halted():
            core.halt()

        old_val = core.read_core_register(reg)
        core.write_core_register(reg, value)
        new_val = core.read_core_register(reg)

        return {
            "uid": uid, "mcu": mcu,
            "register": reg,
            "old_value": f"0x{old_val:08X}",
            "new_value": f"0x{new_val:08X}",
            "verified": new_val == value,
        }
    finally:
        session.close()


def cmd_halt(args: argparse.Namespace) -> dict:
    """ターゲットを停止。"""
    uid, mcu = resolve_probe(args.mcu)
    session = open_session(uid, mcu)
    try:
        target = session.target
        core = target.cores[0]

        was_halted = core.is_halted()
        if not was_halted:
            core.halt()

        pc = core.read_core_register("pc")
        return {
            "uid": uid, "mcu": mcu,
            "was_halted": was_halted,
            "pc": f"0x{pc:08X}",
            "state": "HALTED",
        }
    finally:
        session.close()


def cmd_resume(args: argparse.Namespace) -> dict:
    """ターゲットの実行を再開。"""
    uid, mcu = resolve_probe(args.mcu)
    session = open_session(uid, mcu)
    try:
        target = session.target
        core = target.cores[0]

        was_halted = core.is_halted()
        pc = core.read_core_register("pc") if was_halted else 0
        core.resume()

        return {
            "uid": uid, "mcu": mcu,
            "was_halted": was_halted,
            "resume_pc": f"0x{pc:08X}" if was_halted else "N/A",
            "state": "RUNNING",
        }
    finally:
        session.close()


def cmd_bp_set(args: argparse.Namespace) -> dict:
    """ブレークポイント設定（resume しない）。"""
    uid, mcu = resolve_probe(args.mcu)
    addr = int(args.addr, 0)

    session = open_session(uid, mcu, connect_mode="halt")
    try:
        target = session.target
        core = target.cores[0]
        core.set_breakpoint(addr)

        return {
            "uid": uid, "mcu": mcu,
            "breakpoint": f"0x{addr:08X}",
            "action": "set",
            "note": "BP set in halted session; will be cleared when session closes",
        }
    finally:
        session.close()


def cmd_bp_clear(args: argparse.Namespace) -> dict:
    """ブレークポイント解除。"""
    uid, mcu = resolve_probe(args.mcu)
    addr = int(args.addr, 0)

    session = open_session(uid, mcu, connect_mode="halt")
    try:
        target = session.target
        core = target.cores[0]
        core.remove_breakpoint(addr)

        return {
            "uid": uid, "mcu": mcu,
            "breakpoint": f"0x{addr:08X}",
            "action": "cleared",
        }
    finally:
        session.close()


def cmd_diagnose(args: argparse.Namespace) -> dict:
    """フォールト診断。halt してフォールトレジスタ + スタックフレームを一括読み取り。

    クラッシュ原因の自動特定に使用。
    """
    uid, mcu = resolve_probe(args.mcu)
    session = open_session(uid, mcu)
    try:
        target = session.target
        core = target.cores[0]

        was_halted = core.is_halted()
        if not was_halted:
            core.halt()

        # コアレジスタ
        reg_names = ["pc", "sp", "lr", "r0", "r1", "r2", "r3",
                     "r12", "xpsr", "msp", "psp", "control"]
        regs = {}
        for name in reg_names:
            try:
                val = core.read_core_register(name)
                regs[name] = f"0x{val:08X}"
            except Exception:
                pass

        # フォールト解析（verbose=True で追加レジスタ + 詳細説明）
        fault_info = _read_fault_info(target, core, verbose=True)

        result = {
            "uid": uid, "mcu": mcu,
            "registers": regs,
        }
        result.update(fault_info)

        return result
    finally:
        session.close()


def cmd_cleanup(args: argparse.Namespace) -> dict:
    """ゾンビプロセス終了。"""
    killed = []
    found = []

    for proc_name in ["pyocd", "openocd", "arm-none-eabi-gdb"]:
        try:
            r = subprocess.run(
                ["pgrep", "-fl", proc_name],
                capture_output=True, text=True, timeout=5,
            )
            for line in r.stdout.strip().splitlines():
                if not line:
                    continue
                if "_server.py" in line or "mcp" in line or "pyocd_tool" in line:
                    continue
                pid = int(line.split()[0])
                if pid == os.getpid():
                    continue
                found.append({"pid": pid, "cmd": line})

                try:
                    os.kill(pid, signal.SIGTERM)
                    killed.append(pid)
                except ProcessLookupError:
                    pass
                except PermissionError:
                    pass
        except Exception:
            pass

    if killed:
        for i in range(6):
            time.sleep(0.5)
            remaining = []
            for pid in killed:
                try:
                    os.kill(pid, 0)
                    remaining.append(pid)
                except ProcessLookupError:
                    pass
            if not remaining:
                break
            if i == 5:
                for pid in remaining:
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except (ProcessLookupError, PermissionError):
                        pass

    return {"found": len(found), "killed": len(killed), "processes": found}


# ── CLI Entry Point ──

def main() -> None:
    parser = argparse.ArgumentParser(
        description="pyOCD 統合デバッグツール（MCU 自動検出対応）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="接続プローブ一覧（MCU 自動検出）")

    p = sub.add_parser("status", help="ターゲット状態")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    p = sub.add_parser("flash", help="フラッシュ書き込み")
    p.add_argument("binary", help="バイナリファイルパス")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")
    p.add_argument("--backend", choices=["auto", "pyocd", "stm32cube"],
                   default=DEFAULT_FLASH_BACKEND,
                   help=f"書き込みバックエンド (default: {DEFAULT_FLASH_BACKEND})")
    p.add_argument("--verify", action="store_true", default=DEFAULT_FLASH_VERIFY,
                   help=f"書き込み後検証を有効化 (default: {DEFAULT_FLASH_VERIFY})")
    p.add_argument("--freq", type=int, default=DEFAULT_PYOCD_FREQ_HZ,
                   help=f"pyOCD SWD 周波数 [Hz] (default: {DEFAULT_PYOCD_FREQ_HZ})")
    p.add_argument("--erase", choices=["auto", "sector", "chip"], default=DEFAULT_PYOCD_ERASE,
                   help=f"pyOCD erase mode (default: {DEFAULT_PYOCD_ERASE})")
    p.add_argument("--trust-crc", action="store_true", default=False,
                   help="pyOCD CRC ベース比較を有効化 (crc_supported ターゲットのみ有効)")
    p.add_argument("--double-buffer", action=argparse.BooleanOptionalAction, default=DEFAULT_PYOCD_DOUBLE_BUFFER,
                   help=f"pyOCD flash double buffer を有効化 (default: {DEFAULT_PYOCD_DOUBLE_BUFFER})")
    p.add_argument("--fast-reset", action=argparse.BooleanOptionalAction, default=DEFAULT_PYOCD_FAST_RESET,
                   help=f"pyOCD reset hold/post delay を 0 に短縮 (default: {DEFAULT_PYOCD_FAST_RESET})")
    p.add_argument("--smart-skip", action=argparse.BooleanOptionalAction, default=DEFAULT_PYOCD_SMART_SKIP,
                   help=f"既存 flash と比較して未変更ページをスキップ (default: {DEFAULT_PYOCD_SMART_SKIP})")
    p.add_argument("--no-reset", action="store_true", default=DEFAULT_PYOCD_NO_RESET,
                   help=f"書き込み後に target reset を実行しない (default: {DEFAULT_PYOCD_NO_RESET})")

    p = sub.add_parser("read", help="メモリ読み取り")
    p.add_argument("addr", help="開始アドレス (hex)")
    p.add_argument("size", help="バイト数")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    p = sub.add_parser("read-symbol", help="シンボル→メモリ読み取り")
    p.add_argument("elf", help="ELF ファイルパス")
    p.add_argument("symbol", help="シンボル名")
    p.add_argument("size", nargs="?", help="バイト数 (省略時はシンボルサイズ)")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    p = sub.add_parser("read-symbols", help="複数シンボル→メモリ読み取り（単一セッション）")
    p.add_argument("elf", help="ELF ファイルパス")
    p.add_argument("symbols", nargs="+", help="シンボル名（複数可）")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    p = sub.add_parser("regs", help="レジスタ読み取り")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    p = sub.add_parser("reset", help="ターゲットリセット")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    p = sub.add_parser("run-read", help="reset→run→halt→read")
    p.add_argument("addr", help="開始アドレス (hex)")
    p.add_argument("size", help="バイト数")
    p.add_argument("ms", help="実行時間 (ms)")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    # step
    p = sub.add_parser("step", help="シングルステップ実行")
    p.add_argument("count", nargs="?", default="1", help="ステップ数 (デフォルト: 1)")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    # break (breakpoint + run + wait)
    p = sub.add_parser("break", help="ブレークポイント設定→実行→ヒット待機")
    p.add_argument("addr", help="ブレークポイントアドレス (hex)")
    p.add_argument("--timeout", default="5000", help="タイムアウト (ms, デフォルト: 5000)")
    p.add_argument("--reset", action="store_true", help="リセットしてから実行開始")
    p.add_argument("--set-pc", help="resume 前に PC を変更 (hex)")
    p.add_argument("--write", help="resume 前にメモリ書き込み (addr:val,addr:val,...)")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    # wait-halt
    p = sub.add_parser("wait-halt", help="halt 待機（BP ヒット待ち）")
    p.add_argument("--timeout", default="5000", help="タイムアウト (ms, デフォルト: 5000)")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    # bp-set (set breakpoint without resume)
    p = sub.add_parser("bp-set", help="ブレークポイント設定（resume しない）")
    p.add_argument("addr", help="ブレークポイントアドレス (hex)")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    # bp-clear (clear breakpoint)
    p = sub.add_parser("bp-clear", help="ブレークポイント解除")
    p.add_argument("addr", help="ブレークポイントアドレス (hex)")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    # watch (watchpoint + run + wait)
    p = sub.add_parser("watch", help="ウォッチポイント設定→実行→トリガー待機")
    p.add_argument("addr", help="監視アドレス (hex)")
    p.add_argument("size", nargs="?", default="4", help="監視サイズ (バイト, デフォルト: 4)")
    p.add_argument("--type", choices=["read", "write", "access"], default="write",
                   help="トリガータイプ (デフォルト: write)")
    p.add_argument("--timeout", default="5000", help="タイムアウト (ms, デフォルト: 5000)")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    # write (memory)
    p = sub.add_parser("write", help="メモリ書き込み")
    p.add_argument("addr", help="書き込みアドレス (hex)")
    p.add_argument("values", help="書き込み値 (カンマ区切り, 例: 0x1234,0x5678)")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    # write-reg
    p = sub.add_parser("write-reg", help="レジスタ書き込み")
    p.add_argument("reg", help="レジスタ名 (例: pc, sp, r0)")
    p.add_argument("value", help="書き込み値 (hex)")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    # diagnose
    p = sub.add_parser("diagnose", help="フォールト診断（クラッシュ原因特定）")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    # halt
    p = sub.add_parser("halt", help="ターゲット停止")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    # resume
    p = sub.add_parser("resume", help="実行再開")
    p.add_argument("--mcu", help="MCU ターゲット（省略時は自動検出）")

    sub.add_parser("cleanup", help="ゾンビプロセス終了")

    args = parser.parse_args()

    commands = {
        "list": cmd_list,
        "status": cmd_status,
        "flash": cmd_flash,
        "read": cmd_read,
        "read-symbol": cmd_read_symbol,
        "read-symbols": cmd_read_symbols,
        "regs": cmd_regs,
        "reset": cmd_reset,
        "run-read": cmd_run_read,
        "step": cmd_step,
        "break": cmd_break_run,
        "watch": cmd_watch,
        "write": cmd_write,
        "write-reg": cmd_write_reg,
        "wait-halt": cmd_wait_halt,
        "diagnose": cmd_diagnose,
        "halt": cmd_halt,
        "resume": cmd_resume,
        "cleanup": cmd_cleanup,
    }

    try:
        result = commands[args.command](args)
        print(json.dumps(result, indent=2, ensure_ascii=False))
    except Exception as e:
        error = {"error": str(e), "command": args.command}
        print(json.dumps(error, indent=2, ensure_ascii=False), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
