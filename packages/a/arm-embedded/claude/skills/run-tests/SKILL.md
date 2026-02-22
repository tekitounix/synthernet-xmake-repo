---
name: run-tests
description: Run xmake tests and report structured results with pass/fail details. Use when running unit tests or checking for regressions.
argument-hint: "[filter]"
---

# Run Tests

Execute the project test suite and report structured results.

Arguments: `$ARGUMENTS`
- Optional filter pattern (e.g., `test_<library>/*`, `*_wasm/*`). Omit to run all tests.
- Special aliases: `wasm` → `*_wasm/*`, `all` → run all tests.

## IMPORTANT: Use MCP tools

Use MCP `run_tests` when available. It runs tests and parses pass/fail counts automatically.

## Workflow

1. **Run tests** — use MCP `run_tests` with optional filter argument.

2. **Check results** — the MCP response includes:
   - `passed` / `total` counts
   - `all_passed` boolean
   - Full stdout with individual test results

3. **Report** in structured format:
   ```
   Test Results: X/Y passed
   - test_name: PASS
   - test_name: FAIL (file.cc:42 — expected 0, got 1)
   ```

4. **On failure**, read the failing test source to understand what was being tested, then suggest a fix.

## Discover Test Targets

Use MCP `list_targets` with filter `"test_"` to discover all available test targets dynamically.
Do NOT rely on a hardcoded list — targets may be added or removed.

## Build Before Test

If tests fail to compile, use MCP `build_target` first to get detailed compiler errors.
