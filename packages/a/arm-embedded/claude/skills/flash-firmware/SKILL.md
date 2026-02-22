---
name: flash-firmware
description: Build firmware and flash to embedded hardware. Automatically selects the correct probe when multiple ST-Links are connected.
argument-hint: "[target] [mcu]"
---

# Flash Firmware

Build and flash firmware to the connected board.

Arguments: `$ARGUMENTS`
- First argument: xmake target name (e.g., `stm32f4_os`). Required.
- Second argument: MCU target (e.g., `stm32f407vg`, `stm32h750xx`). Optional — auto-detected from hardware.

## IMPORTANT: Use MCP tools

Prefer MCP tools over CLI commands when available. They provide structured JSON responses and automatic error handling.

## Workflow

1. **Pre-flight** — check probes and cleanup:
   - Use MCP `cleanup_processes` and `probe_list`

2. **Determine MCU** — if not specified, read the target's `xmake.lua` for `set_values("embedded.mcu", ...)`.

3. **Build** — use MCP `build_target`:
   - If release fails (e.g., LTO error with GCC), retry with `mode: "debug"`

4. **Find binary** — locate the .bin file:
   ```bash
   find build/$0 -name "$0.bin" -type f
   ```
   The binary may be in `build/$0/debug/` or `build/$0/release/` depending on build mode.

5. **Flash** — use MCP `flash` with the binary path and MCU.

6. **Verify** — use MCP `target_status` and `read_registers`:
   - PC should be in flash range (0x08xxxxxx), not stuck at reset vector.

## Multi-Probe

When multiple ST-Links are connected, `--mcu` is required to select the correct probe.
MCU is auto-detected from hardware (no manual config needed).

## Troubleshooting

| Problem | Solution |
|---------|----------|
| No available debug probes | Check USB connection |
| LTO thin error in release | Build with `mode: "debug"` instead |
| Target not responding | Use MCP `reset` |
| Flash fails | Erase first: `pyocd erase -t <mcu> --chip` |
| Wrong probe selected | Use MCP `probe_list` to check |
