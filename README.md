# Synthernet XMake Repository

A custom xmake package repository for ARM embedded development and UMI package consumption.

## Package Architecture

### File Flow

```
xmake-repo/synthernet/           -- Source of truth (git-managed)
  packages/a/arm-embedded/
    rules/embedded/xmake.lua     -- Embedded build rule
    rules/embedded/database/     -- MCU/core/toolchain JSON databases
    rules/vscode/xmake.lua       -- VSCode integration rule
    rules/compdb/xmake.lua       -- compile_commands.json rule
    plugins/flash/xmake.lua      -- Flash task
    plugins/test/xmake.lua       -- Test runner task
    ...
        |
        | xmake require --force arm-embedded
        v
~/.xmake/packages/a/arm-embedded/X.Y.Z/   -- Package cache (version-keyed)
        |
        | on_load() -- always overwrites
        v
~/.xmake/rules/embedded/         -- Active rules (xmake loads from here)
~/.xmake/plugins/flash/          -- Active plugins
```

**Key design decisions:**
- `on_load()` always overwrites `~/.xmake/rules/` — no content-comparison caching
- Package cache is the source for `on_load()` copies
- Source edits require either `xmake require --force` or `xmake dev-sync` to take effect
- `arm-embedded` installs generic embedded rules only. Toolchains are explicit
  consumer dependencies, UMI-specific rules live in `umibuild`, and AI agent
  adapters are owned by tazuna / consuming projects, not this provider package.

### Installed Locations

#### arm-embedded

| Source | Installed to | Loaded by |
|--------|-------------|-----------|
| `rules/embedded/xmake.lua` | `~/.xmake/rules/embedded/` | `add_rules("embedded")` |
| `rules/embedded/database/*.json` | `~/.xmake/rules/embedded/database/` | Rule `on_load()` |
| `rules/embedded/linker/common.ld` | `~/.xmake/rules/embedded/linker/` | Linker |
| `rules/vscode/xmake.lua` | `~/.xmake/rules/embedded.vscode/` | `add_deps("embedded.vscode")` |
| `rules/vscode/modules/*.lua` | `~/.xmake/rules/embedded.vscode/modules/` | `import("modules.xxx")` |
| `rules/compdb/xmake.lua` | `~/.xmake/rules/embedded.compdb/` | `add_rules("embedded.compdb")` |
| `rules/embedded.test/xmake.lua` | `~/.xmake/rules/embedded.test/` | `add_rules("embedded.test")` |
| `rules/firmware/xmake.lua` | `~/.xmake/rules/firmware/` | `add_rules("firmware")` |
| `rules/host.test/xmake.lua` | `~/.xmake/rules/host.test/` | `add_rules("host.test")` |
| `plugins/flash/xmake.lua` | `~/.xmake/plugins/flash/` | `xmake flash` |
| `plugins/test/xmake.lua` | `~/.xmake/plugins/test/` | `xmake test` |
| `plugins/compdb/xmake.lua` | `~/.xmake/plugins/compdb/` | `xmake compdb` |
| `scripts/` | `~/.xmake/rules/embedded/scripts/` | pyocd_tool.py etc. |

Note: `rule_name_map` transforms source directory names: `vscode` → `embedded.vscode`, `compdb` → `embedded.compdb`.

## Development Guide

### Local Development Workflow

Two methods to apply source changes to `~/.xmake/`:

#### A. `xmake dev-sync` (instant, dev only)

Copies source files directly from `xmake-repo/synthernet/` to `~/.xmake/`,
bypassing the package cache entirely. Use during active development iteration.

```bash
# Edit source
vim xmake-repo/synthernet/packages/a/arm-embedded/rules/embedded/xmake.lua

# Sync to ~/.xmake/ (instant)
xmake dev-sync

# Clear depend cache so xmake regenerates .vscode/ files
rm -f build/.gens/rules/embedded.vscode.d

# Rebuild (triggers regeneration of settings/tasks/launch.json)
xmake build <target>
```

**Important:**
- `xmake dev-sync` is defined in the umi project's `tools/dev-sync.lua`, not in the package itself.
- After sync, xmake's depend cache may skip regeneration of `.vscode/` files.
  Delete `build/.gens/rules/embedded.vscode.d` to force regeneration.

#### B. `xmake require --force` (full pipeline)

Reinstalls the package through xmake's package system. Updates both the package
cache and `~/.xmake/rules/`. Use for release validation or when the dev-sync task
is not available.

```bash
# Edit source
vim xmake-repo/synthernet/packages/a/arm-embedded/rules/embedded/xmake.lua

# Reinstall (updates cache + rules)
xmake require --force arm-embedded

# Verify
xmake build <target>
```

**Note:** `xmake dev-sync` support lives in the consuming repository. For
release validation, prefer `xmake require --force arm-embedded` with an
isolated `HOME`.

### When to Use Which

| Scenario | Method |
|----------|--------|
| Editing arm-embedded during development | `xmake dev-sync` |
| Validating before release | `xmake require --force arm-embedded` |
| CI / fresh environment | `xmake require arm-embedded` (normal install) |
| Debugging install issues | Delete `~/.xmake/rules/embedded/` + `xmake require --force` |

### Source Overlay Providers

UMI-owned packages use `UMI_SOURCE` only as a package provider switch. It must
point at a UMI repository root and must not be used by consumers as an include
or source path.

Consumers that need UMI parse-time xmake helpers such as `umi_app()` or
`umi_app_matrix()` may include
`packages/u/umibuild/source_overlay_bootstrap.lua` from this provider checkout
while using the source-overlay lane. That bootstrap is transitional: it keeps
the consumer dependency surface on the package repository provider and resolves
the helper implementation from `UMI_SOURCE/build-rules/umibuild` internally.
It is not a released-lane substitute for a future `umibuild` archive.

External providers use their own source roots. `umipal` uses
`UMIPAL_SOURCE=<path-to-umipal-repository>`, pointing directly at the upstream
`tekitounix/umipal` checkout. Do not route it through
`UMI_SOURCE/external/providers/umipal`; that would make the UMI worktree a path
broker for an external provider.

### Troubleshooting

**Changes not reflected after editing source:**
- Source edits are NOT automatically picked up. Run `xmake dev-sync` or `xmake require --force`.
- If `dev-sync` was run but `.vscode/` files are stale, delete `build/.gens/rules/embedded.vscode.d` and rebuild.

**`~/.xmake/rules/` has different content than source:**
- This means either `dev-sync` was not run, or the package cache is stale.
- Fix: `xmake dev-sync` (quick) or delete `~/.xmake/packages/a/arm-embedded/` + `xmake require --force` (thorough).

**"ARM Embedded: Removed stale compile_commands.json" message:**
- This was a legacy bug (toolchain-mismatch check deleted root compile_commands.json).
- Fixed: the check was removed from the embedded rule. If you still see this, run `xmake dev-sync`.

## Packages

| Package | Type | Description |
|---------|------|-------------|
| `arm-embedded` | meta | Generic ARM embedded build automation (rules, plugins, databases). Toolchains are explicit consumer dependencies |
| `clang-arm` | toolchain | ARM LLVM Embedded Toolchain for Arm |
| `gcc-arm` | toolchain | ARM GNU Toolchain (GCC) |
| `renode` | binary | Renode hardware emulator |
| `pyocd` | binary | PyOCD debug probe interface (python3 + venv) |
| `python3` | binary | System Python venv wrapper |
| `umibench` | library (headeronly) | UMI benchmark framework |
| `umibuild` | meta | UMI build rules, profiles, MCU database, and operator tooling |
| `umimmio` | library (headeronly) | MMIO abstraction layer |
| `umipal` | library (headeronly) | External PAL provider consumed through release archives or `UMIPAL_SOURCE` source overlay |
| `umiport` | library | Platform infrastructure |
| `umirtm` | library (headeronly) | RTT monitor |
| `umitest` | library (headeronly) | Test framework |
| `umi.primitive.*`, `umi.contract.*`, `umicoro`, `umiutil`, `umimath`, `umidbg`, `umidi`, `umidsp`, `umiusb`, `umihal`, `umisync`, `umidevice`, `umipio` | library (headeronly) | UMI public libraries consumed through public release archives or `UMI_SOURCE` source overlay |
| `umibm`, `umiboot`, `umios.*`, `umifwk.*` | framework/runtime | UMI runtime packages consumed through `UMI_SOURCE` source overlay for framework profile validation |

## License

MIT License
