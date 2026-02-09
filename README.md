# ARM Embedded XMake Repository

A custom xmake package repository for ARM embedded development.

## Package Architecture

### File Flow

```
xmake-repo/synthernet/           -- Source of truth (git-managed)
  packages/a/arm-embedded/
    rules/embedded/xmake.lua     -- Embedded build rule
    rules/embedded/modules/      -- Lua modules (launch_generator etc.)
    rules/embedded/database/     -- MCU/core/toolchain JSON databases
    rules/vscode/xmake.lua       -- VSCode integration rule
    plugins/flash/xmake.lua      -- Flash task
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

### Installed Locations

| Source | Installed to | Loaded by |
|--------|-------------|-----------|
| `rules/embedded/xmake.lua` | `~/.xmake/rules/embedded/xmake.lua` | `add_rules("embedded")` |
| `rules/embedded/database/*.json` | `~/.xmake/rules/embedded/database/` | Rule `on_load()` |
| `rules/embedded/modules/*.lua` | `~/.xmake/rules/embedded/modules/` | `import("modules.xxx")` |
| `rules/embedded/linker/common.ld` | `~/.xmake/rules/embedded/linker/` | Linker |
| `rules/vscode/xmake.lua` | `~/.xmake/rules/embedded.vscode/` | `add_deps("embedded.vscode")` |
| `rules/host.test/xmake.lua` | `~/.xmake/rules/host.test/` | `add_rules("host.test")` |
| `plugins/flash/xmake.lua` | `~/.xmake/plugins/flash/` | `xmake flash` |
| `plugins/debug/xmake.lua` | `~/.xmake/plugins/debug/` | `xmake debug` |

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

### When to Use Which

| Scenario | Method |
|----------|--------|
| Editing rules/plugins during development | `xmake dev-sync` |
| Validating before release | `xmake require --force arm-embedded` |
| CI / fresh environment | `xmake require arm-embedded` (normal install) |
| Debugging install issues | Delete `~/.xmake/rules/embedded/` + `xmake require --force` |

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

## License

MIT License