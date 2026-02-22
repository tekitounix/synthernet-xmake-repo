---
name: read-memory
description: Read memory from embedded target at a symbol address or raw address. Supports multiple probes.
argument-hint: "<symbol-or-address> [elf-path] [mcu]"
---

# Read Memory

Read raw memory from a halted embedded target, decoding values against struct definitions.

Arguments: `$ARGUMENTS`
- First argument: Symbol name (e.g., `latency_hist`) or hex address (e.g., `0x20000230`). Required.
- Second argument: ELF path. Optional — find with `find build/ -name "*.elf" -o -type f -perm +111 | grep -v '.bin\|.hex'`.
- Third argument: MCU target (e.g., `stm32f407vg`, `stm32h750xx`). Optional — auto-resolved.

## IMPORTANT: Use MCP tools

Prefer MCP tools for all memory operations. They provide structured JSON and automatic halt→read→resume.

## Workflow

### By Symbol Name (with ELF)

Use MCP `read_symbol` — automatically resolves symbol → address → halt → read → resume.

### By Raw Address

Use MCP `read_memory` with hex address and byte count.

### After Reset + Run

Use MCP `read_memory_after_run` to reset, run for N ms, halt, then read.

### Decode

Map the JSON output (words array) to struct fields from the header definition.

## Common Memory Regions (Cortex-M)

| Region | F407 Address | H750 Address | Description |
|--------|-------------|-------------|-------------|
| Flash | 0x08000000+ | 0x08000000+ | Program memory |
| SRAM | 0x20000000+ | 0x24000000+ | Main RAM (H750: AXI SRAM) |
| CCM | 0x10000000+ | — | Core-Coupled Memory |
| DTCM | — | 0x20000000+ | Data TCM (H750) |
| DWT CYCCNT | 0xE0001004 | 0xE0001004 | Cycle counter |
| SysTick | 0xE000E010 | 0xE000E010 | System timer |
