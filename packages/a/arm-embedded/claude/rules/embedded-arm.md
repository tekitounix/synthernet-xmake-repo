---
globs:
  - "**/*.cc"
  - "**/*.hh"
---

# ARM Embedded Rules

- `volatile` is required for ISR-visible and debugger-visible variables
- DMA buffers must NOT be placed in CCM (DMA cannot access CCM)
- Check full memory map when modifying linker script MEMORY sections
- Register access (`reinterpret_cast`) should be restricted to the PAL (Platform Abstraction Layer)
- Handler naming: `snake_case` (e.g., `pendsv_handler`), NOT CMSIS `PascalCase_Handler`
- `extern "C"` only for: asm-referenced symbols, linker ENTRY, ABI symbols (`__cxa_*`, `main`, `_start`)
