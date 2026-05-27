# v8.7.1 — Compensating-coverage safety net (GATE-COMP-COV)

## Why

User finding: cannot enumerate every software shape. v8.5.1 covered web (Playwright). v8.6 covered mobile (Maestro). v8.7 covered desktop-browser (CDP+WPT). Every other shape — library, CLI, SDK, daemon, worker, firmware, kernel module, game runtime, ML model, data pipeline, browser extension, plugin, DSL compiler, GPU shader — falls through with no behavioral floor. Without a safety net, an atom with project_type=`cli` or `library` PASSes the pipeline with a single stub test.

LAW-F6 holds: never silent PASS. So for uncovered project_types, the agent MUST declare a compensating strategy = aggressive unit + branch coverage with thresholds raised above the default backend bar.

## Trigger

GATE-COMP-COV fires when:

1. `project_type` is NOT in the specialized-coverage set `{frontend, mixed, backend, mobile-*, desktop-browser-*}`, OR
2. `compensating_coverage.enabled = true` (explicit opt-in for atoms inside a covered type that still want raised rigor).

Otherwise → `N/A_PENDING_REVIEWER`.

## Required config (when fired)

```json
{
  "compensating_coverage": {
    "enabled": true,
    "reason": "library/CLI atom — no UI surface, no HTTP boundary; behavioral testing not applicable",
    "coverage_cmd": "pytest --cov=src --cov-report=json:coverage/coverage.json",
    "coverage_report_path": "coverage/coverage.json",
    "coverage_report_format": "istanbul",
    "thresholds": { "line": 90, "branch": 85 }
  }
}
```

- `reason` non-empty mandatory — agent must justify WHY no behavioral path.
- `coverage_cmd` non-empty — the gate executes it.
- `coverage_report_path` non-empty + file exists post-run.
- `coverage_report_format` ∈ {istanbul, simple, text}.
  - **istanbul**: Node/JS `coverage-summary.json`-style `{total:{lines:{pct:..}, branches:{pct:..}}}`.
  - **simple**: `{line: 0-100, branch: 0-100}` flat JSON the atom emits.
  - **text**: greps `lines\.\s+([0-9.]+)%` + `branches\.\s+([0-9.]+)%` from the cmd's stdout file.

## Default thresholds

- `line ≥ 90` (vs backend default 80)
- `branch ≥ 85` (vs backend default 70)

Atom can raise, can NOT lower below these defaults — the gate clamps.

## FAIL conditions

- Trigger fires, `compensating_coverage` block missing → FAIL.
- Any required field empty → FAIL.
- `coverage_cmd` exits non-zero → FAIL.
- `coverage_report_path` missing after run → FAIL.
- Parsed `line` < threshold OR `branch` < threshold → FAIL.
- Vacuous: parsed `line = 0` AND `branch = 0` → FAIL (no real tests ran).

## Meta-gate fixtures (6)

1. `project_type=frontend` → N/A (covered by Playwright).
2. `project_type=library`, no `compensating_coverage` block → FAIL (LAW-F6).
3. `project_type=library`, `enabled=true`, `coverage_cmd` missing → FAIL.
4. `project_type=library`, line=92, branch=88 → PASS.
5. `project_type=library`, line=75 (below 90) → FAIL.
6. `project_type=cli`, line=0 branch=0 (vacuous) → FAIL.

## Deferred

- Per-module coverage floor (don't let one untested module hide behind well-tested ones) — v8.7.2.
- Mutation-testing requirement for compensating atoms — v8.7.2.
- Property-test mandatory for compensating atoms — v8.7.2.
- LCOV / Cobertura native parsers — atom currently must convert to istanbul or simple.
