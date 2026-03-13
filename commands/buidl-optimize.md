---
description: "Optimize a metric (gas, bundle_size, test_time, throughput) via automated experimentation"
argument-hint: '<metric> [--target N] [--max-cycles 10]'
allowed-tools: ["Read", "Write", "Edit", "Bash(bash:*)", "Grep", "Glob"]
---

# Autoresearch Optimize Mode

You are running an optimization loop that iterates toward a measurable improvement target. Follow the cycle below. Do not skip steps.

## FORBIDDEN

1. **No mainnet transactions.** All experiments run on testnet or local only.
2. **No modifying locked acceptance tests.** Files in `artifacts/acceptance-tests/` are immutable.
3. **No test regressions.** Every cycle must pass the full test suite before keeping changes.
4. **No unrelated changes.** Only touch code that affects the target metric.

## Parse Input

Arguments: `$ARGUMENTS`

Supported metrics:
- `gas` — Reduce contract gas consumption
- `bundle_size` — Reduce frontend bundle size (bytes)
- `test_time` — Reduce test suite execution time (seconds)
- `throughput` — Increase transactions per second

Default `--max-cycles`: 10
Default `--target`: metric-dependent (gas: -10%, bundle_size: -15%, test_time: -20%, throughput: +20%)

## Step 0: Baseline

1. Run the full test suite to confirm all tests pass. If any fail, STOP and report.
2. Measure the current value of the target metric:
   - `gas`: compile contract, read gas report from build output
   - `bundle_size`: run `npm run build` and measure `dist/` size
   - `test_time`: time the test suite execution
   - `throughput`: run benchmark suite if available
3. Record the baseline in `artifacts/optimize/baseline.json`:
   ```json
   {
     "metric": "<metric>",
     "baseline_value": <number>,
     "target_value": <number>,
     "unit": "<unit>",
     "timestamp": "<ISO-8601>"
   }
   ```

## Optimization Cycle

Repeat up to `max_cycles` times:

### 1. Hypothesize

State a specific hypothesis: "Changing X in file Y will reduce metric by approximately Z because [reason]."

Write the hypothesis to `artifacts/optimize/cycle-<N>-hypothesis.md`.

### 2. Implement

Make the minimal code change to test the hypothesis. Keep changes small and reversible.

### 3. Benchmark

1. Run the full test suite. If any test fails, REVERT immediately and try a different hypothesis.
2. Measure the target metric with the same method as Step 0.
3. Record the result in `artifacts/optimize/cycle-<N>-result.json`:
   ```json
   {
     "cycle": <N>,
     "hypothesis": "<summary>",
     "metric_before": <number>,
     "metric_after": <number>,
     "delta": <number>,
     "delta_pct": <number>,
     "tests_pass": true,
     "kept": <boolean>
   }
   ```

### 4. Keep or Revert

- If the metric improved AND all tests pass: KEEP the change. Update the running best.
- If the metric worsened OR any test failed: REVERT via `git checkout -- .` to discard all uncommitted changes.
- If the metric is unchanged: REVERT (no point keeping neutral changes).

### 5. Check Target

- If the cumulative improvement meets or exceeds the target: STOP, declare success.
- If `cycle >= max_cycles`: STOP, report best result achieved.
- Otherwise: continue to next cycle.

## Output

When done, write:

1. `artifacts/optimize/summary.md`:
   ```markdown
   # Optimization Summary

   ## Target
   Metric: <metric>
   Baseline: <value> <unit>
   Target: <value> <unit>
   Best achieved: <value> <unit> (<delta_pct>% improvement)

   ## Cycles
   | Cycle | Hypothesis | Before | After | Delta | Kept |
   |-------|-----------|--------|-------|-------|------|
   | 1 | ... | ... | ... | ... | Y/N |

   ## Conclusion
   [Summary of what worked, what did not, and why]
   ```

2. `artifacts/optimize/best-result.json`:
   ```json
   {
     "metric": "<metric>",
     "baseline_value": <number>,
     "best_value": <number>,
     "improvement_pct": <number>,
     "target_met": <boolean>,
     "cycles_used": <number>,
     "max_cycles": <number>
   }
   ```

3. Create a PR with the kept changes:
   ```bash
   git checkout -b optimize/<metric>-<timestamp>
   git add -A
   git commit -m "optimize: reduce <metric> by <delta_pct>%"
   gh pr create --title "optimize: <metric> -<delta_pct>%" --body "..."
   ```

Print the PR URL when done.
