---
name: run-bench
description: Run benchmarks and report cycle counts. Use when measuring performance or checking for regressions.
argument-hint: "[target]"
---

# Run Benchmarks

Build and execute benchmarks, reporting performance metrics.

Arguments: `$ARGUMENTS`
- Benchmark target name. Required. If not specified, discover targets first.

## IMPORTANT: Use MCP tools

Use MCP `run_benchmark` or `run_target` when available. They build and run in one call with structured output.

## Workflow

1. **Find target** — if the user doesn't specify one, use MCP `list_targets` with filter `"bench"` to discover available benchmark targets dynamically.

2. **Build and run** — use MCP `run_benchmark` with the target name.

3. **Parse output** for:
   - Operation name
   - Cycle count (min/avg/max)
   - Throughput (ops/sec or samples/sec)
   - Iterations

4. **Report** in table format:
   ```
   Benchmark: <target>
   | Operation       | Cycles (avg) | Throughput  |
   |-----------------|-------------|-------------|
   | biquad_process  | 142         | 1.18M ops/s |
   ```

5. **Regression check**: Flag any operation > 10% slower than previous known baseline.

## ARM On-Target Benchmarks

For hardware cycle counts, combine with `/debug-verify`:
1. Build for ARM target
2. Flash and run
3. Read DWT cycle counters (0xE0001004) from memory
