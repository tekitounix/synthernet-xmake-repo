---
name: debug-verify
description: Build, flash, and verify debug instrumentation on embedded hardware. Supports multiple probes via MCU auto-selection.
argument-hint: "[target] [mcu]"
---

# Hardware Debug Verification

Build firmware, flash to hardware, run briefly, then read debug variables from memory to verify they are being updated correctly.

Arguments: `$ARGUMENTS`
- First argument: xmake target name (e.g., `stm32f4_os`). Required.
- Second argument: MCU target (e.g., `stm32f407vg`, `stm32h750xx`). Optional — auto-resolved.

## IMPORTANT: Use MCP tools

Prefer MCP tools over CLI commands. They provide structured JSON and automatic halt→read→resume.

## Workflow

1. **Pre-flight** — use MCP `cleanup_processes` and `probe_list`.

2. **Build** — use MCP `build_target` with the target name.
   - `build_target` auto-fallbacks from release to debug on failure.
   - Response includes `mode` and optionally `fallback_from`.

3. **Determine MCU** — if not specified, read the target's `xmake.lua` for `set_values("embedded.mcu", ...)`.

4. **Find binary and ELF** — locate outputs dynamically:
   ```bash
   find build/$0 -name "$0.bin" -type f
   find build/$0 -name "$0" -not -name "*.bin" -not -name "*.hex" -type f
   ```

5. **Discover debug symbols** — use MCP `resolve_symbol` with common patterns:
   ```
   resolve_symbol(elf, "dbg::*")
   ```
   Use project-specific debug symbol prefixes (e.g., `umi::dbg::*`, `app::dbg::*`).
   If no symbols found, search the ELF:
   ```bash
   arm-none-eabi-nm --demangle <elf> | grep -i 'dbg\|debug\|counter\|hist'
   ```

6. **Flash** — use MCP `flash` with binary path and MCU.

7. **Read debug counters** — use MCP `read_symbol` / `read_symbols` with discovered symbols:
   - Read once, wait a few seconds, read again
   - Compare values to verify monotonic increase
   - For high-frequency checks, use `read_symbols_series(elf, symbols_csv, repeat, interval_ms, mcu, halt=false)`

8. **Report** pass/fail:
   - Values non-zero → firmware is running and updating
   - Counters monotonically increasing between reads

## Safety

- MCP tools automatically handle halt→read→resume
- Probe selection is automatic via hardware MCU auto-detection
- Cleanup hook prevents zombie processes
