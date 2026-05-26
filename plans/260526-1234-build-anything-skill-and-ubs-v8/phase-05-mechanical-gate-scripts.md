# Phase 05 — Mechanical Gate Scripts

## Context Links

- UBS v8.0 GATE-10/11/14/15 (Phase 02 output)
- Phase 03 sub-skills/gate-mechanical/SKILL.md

## Overview

- Priority: P0
- Status: pending
- Brief: bash scripts implementing strict mechanical thresholds — cov 80%, mut 60%, perf tight

## Key Insights

- User picked STRICT thresholds — scripts must FAIL fast at threshold violation
- Multi-stack: scripts need adapters (Node/Python/Go/Rust at minimum)
- Mutation testing slow → scope to changed files + 1-hop deps only (per journal risk 13.3)
- Property-based test runner = orchestrator, not test author

## Requirements

**Functional script list:**

| Script | Gate | Threshold | Tools |
|--------|------|-----------|-------|
| `coverage-check.sh` | GATE-10 | ≥80% line + ≥80% branch | nyc/jest/c8 (JS), pytest-cov (Py), go test -cover (Go), tarpaulin (Rust) |
| `mutation-test.sh` | GATE-11 | ≥60% killed | stryker (JS), mutmut (Py), gremlins (Go), mutagen (Rust) |
| `property-test-runner.sh` | (part of GATE-10) | all property tests pass | fast-check (JS), hypothesis (Py), gopter (Go), proptest (Rust) |
| `lint-check.sh` | (part of GATE-10) | zero error | eslint, ruff, golangci-lint, clippy |
| `type-check.sh` | (part of GATE-10) | zero error | tsc, mypy, go vet, cargo check |
| `bundle-budget.sh` | GATE-14 frontend | per-route budget | webpack-bundle-analyzer, vite-bundle-visualizer |
| `lighthouse-check.sh` | GATE-14 frontend | perf ≥90, a11y ≥95 | lighthouse CLI |
| `load-test-smoke.sh` | GATE-14 backend | p95 < baseline+10% | k6 or artillery |
| `observability-check.sh` | GATE-15 | log+metric+alert present in diff | grep + parser |

**Non-functional:**
- Each script ≤ 100 LOC
- Exit code 0 = PASS, non-zero = FAIL with stderr findings
- Output JSON summary for orchestrator parsing
- Stack detection via package.json / pyproject.toml / go.mod / Cargo.toml

## Architecture

```
~/.claude/skills/build-anything/scripts/mechanical/
├── _common.sh                # stack detection, JSON output helpers
├── coverage-check.sh
├── mutation-test.sh
├── property-test-runner.sh
├── lint-check.sh
├── type-check.sh
├── bundle-budget.sh
├── lighthouse-check.sh
├── load-test-smoke.sh
└── observability-check.sh
```

## Related Code Files

**Create:** 10 scripts above

**Modify:**
- `sub-skills/gate-mechanical/SKILL.md` → reference these scripts

## Implementation Steps

1. Write `_common.sh` — stack detection function, JSON emit helper
2. Write `coverage-check.sh`:
   - Detect stack
   - Run coverage tool with reporter=json
   - Parse line%/branch%
   - Compare ≥80%, exit accordingly
3. Write `mutation-test.sh`:
   - Detect stack
   - Scope to changed files (git diff) + 1-hop deps
   - Run mutation tool
   - Parse killed ratio
   - Compare ≥60%
4. Write `property-test-runner.sh`:
   - Detect stack
   - Run property test suite
   - Capture seed for reproducibility (per risk 13.4)
5. Write `lint-check.sh` + `type-check.sh` — straightforward, exit code passthrough
6. Write `bundle-budget.sh` — read budget config from `.build-anything.json`, compare
7. Write `lighthouse-check.sh` — headless lighthouse CLI, parse JSON, threshold check
8. Write `load-test-smoke.sh` — k6 script template, baseline read from `.build-anything.json`
9. Write `observability-check.sh` — grep diff for log/metric/alert patterns per stack
10. Test each script on toy project (defer full test to Phase 07)

## Todo List

- [ ] _common.sh
- [ ] coverage-check.sh
- [ ] mutation-test.sh
- [ ] property-test-runner.sh
- [ ] lint-check.sh
- [ ] type-check.sh
- [ ] bundle-budget.sh
- [ ] lighthouse-check.sh
- [ ] load-test-smoke.sh
- [ ] observability-check.sh

## Success Criteria

- All 10 scripts executable
- Each emits structured JSON on stderr
- Exit code reflects pass/fail
- Stack detection works for Node/Python/Go/Rust
- Mutation script scoped (does not run full suite)

## Risk Assessment

- Tool availability per env (mitigation: each script `command -v` check + clear error)
- Mutation runtime explosion (mitigation: scoping + timeout 10min hard cap)
- Lighthouse flaky in CI (mitigation: 3-run median)
- Load test baseline drift (mitigation: baseline file versioned + auto-update on explicit confirm)

## Security Considerations

- Scripts read code but don't transmit
- No secrets in script default args
- All thresholds configurable via `.build-anything.json` (no hardcoded prod URLs)

## Next Steps

- Phase 06 implements backend integrity scripts (parallel)
- Phase 07 dry-run validates all scripts end-to-end
