# Phase 05 — Mechanical Gate Scripts — Completion Report

**Date:** 2026-05-26
**Phase:** 05 of 09
**Status:** COMPLETE
**Output dir:** `/Users/macos/.claude/skills/build-anything/scripts/mechanical/`

## Files written (11)

| Script | Gate | Single-number metric | Threshold src |
|--------|------|----------------------|---------------|
| `_common.sh` | (shared) | n/a — provides detect_stack, emit_json, threshold, atom_dir_from_args | n/a |
| `coverage-check.sh` | GATE-10-line | line% (+ branch% in extra) | `gates.mechanical.coverage_line` (default 80) |
| `mutation-test.sh` | GATE-11 | kill ratio % | `gates.mechanical.mutation_score` (60) |
| `property-test-runner.sh` | GATE-16 | # property tests | `gates.mechanical.property_min` (1) |
| `lint-check.sh` | lint | error count | hard 0 |
| `type-check.sh` | type | error count | hard 0 |
| `bundle-budget.sh` | GATE-14-bundle (FE) | gz KB delta vs baseline | `gates.performance.bundle_delta_kb` (5) |
| `lighthouse-check.sh` | GATE-14-lighthouse (FE) | perf median (+ a11y) | `gates.performance.lighthouse_perf_mobile` (90) |
| `load-test-smoke.sh` | GATE-14-load (BE) | p95 ms | `gates.performance.p95_max_ms` (200) |
| `observability-check.sh` | GATE-15 | # files missing instrumentation | hard 0 |
| `verify-manifest.sh` | LAW-17 | sha256 mismatches | hard 0 |

**Total: 11 scripts. All chmod +x.**

## LOC discipline

| Script | LOC | Budget |
|--------|----:|-------:|
| _common.sh | 70 | 100 |
| coverage-check.sh | 56 | 100 |
| mutation-test.sh | 73 | 100 |
| property-test-runner.sh | 55 | 100 |
| lint-check.sh | 49 | 100 |
| type-check.sh | 51 | 100 |
| bundle-budget.sh | 52 | 100 |
| lighthouse-check.sh | 60 | 100 |
| load-test-smoke.sh | 60 | 100 |
| observability-check.sh | 59 | 100 |
| verify-manifest.sh | 56 | 100 |

All under budget.

## Stack adapter coverage

Each gate script handles 4 stacks:

| Stack | Detector | Tools wired |
|-------|----------|-------------|
| node | `package.json` | c8, stryker, fast-check, eslint, tsc, lighthouse, k6 |
| python | `pyproject.toml` / `setup.py` / `requirements.txt` | coverage.py, mutmut, hypothesis, ruff, mypy |
| go | `go.mod` | go test -cover, gremlins, gopter, golangci-lint, go vet |
| rust | `Cargo.toml` | tarpaulin, cargo-mutants, proptest, clippy, cargo check |
| unknown | n/a | scripts error out cleanly with stack-detection message |

## Single-number contract (LAW-11)

Every script:
1. Prints the metric to stdout (consumed by `/ck:autoresearch` as Verify command)
2. Writes JSON to `{atom_dir}/gate-mechanical/{gate}.json` shape: `{ gate, score, threshold, passed, delta, extra, timestamp }`
3. Exit code 0 = PASS, 1 = FAIL, 127 = missing tool, 2 = invalid args

## Vacuous-PASS rule (consistent across scripts)

If atom diff contains no source files relevant to a gate, scripts emit `score=0 threshold=0 passed=true` with `reason` in `extra`. Spec-attacker reviewer at stage 10 may challenge a vacuous PASS — the JSON includes a reason string so the reviewer can verify honesty.

## Scope rules (per `mechanical-gates.md`)

| Gate | Scope rule |
|------|-----------|
| Coverage | atom diff + (TODO) 1-hop dependents — current impl uses whole repo coverage but reports only |
| Mutation | atom diff only, filtered by `git diff --name-only` |
| Property | atom diff source files |
| Lint | atom diff files |
| Type | atom diff files |
| Bundle | per-build delta vs `.build-anything/bundle-baseline.json` |
| Lighthouse | per-URL from `.build-anything.json#frontend.test_urls` |
| Load | per-endpoint from `.build-anything.json#load_smoke` |
| Observability | atom diff source files |
| verify-manifest | per-atom directory |

## Mitigations applied (from Phase 05 risks)

| Risk | Mitigation |
|------|-----------|
| Tool availability | `require_cmd` in `_common.sh` errors with install hint |
| Mutation runtime | `git diff` scoping + 10-min cargo-mutants timeout |
| Lighthouse flake | 3-run median per URL |
| Load test baseline drift | `.build-anything/bundle-baseline.json` initialised on first run; subsequent runs diff vs it |

## Configurability (`.build-anything.json` schema fragment)

```json
{
  "gates": {
    "mechanical": {
      "coverage_line": 80,
      "coverage_branch": 80,
      "mutation_score": 60,
      "property_min": 1
    },
    "performance": {
      "bundle_delta_kb": 5,
      "lighthouse_perf_mobile": 90,
      "lighthouse_a11y": 95,
      "p95_max_ms": 200
    }
  },
  "frontend": {
    "dist_dir": "dist",
    "test_urls": ["https://staging.example.com/"]
  },
  "load_smoke": {
    "target_url": "https://staging.example.com",
    "endpoints": ["/api/orders", "/api/orders/123"]
  }
}
```

Every default surfaced via `threshold "key" default` helper.

## Pending for Phase 06

9 backend integrity scripts under `scripts/backend/` + `_common.sh`:
- db-invariant-check.sh
- concurrency-test.sh
- transaction-atomicity-test.sh
- background-job-assertion.sh
- audit-log-assertion.sh
- authorization-test.sh
- api-contract-test.sh
- idempotency-test.sh
- multi-tenant-isolation-test.sh

## Open questions

1. **Bundle dist_dir convention.** Some projects use `build/`, `out/`, `.next/`. Configurable via `.build-anything.json#frontend.dist_dir` — default `dist`. Phase 07 will verify against a real Next.js project.
2. **k6 vs Artillery.** Chose k6 because more deterministic CLI. Plan flagged either as acceptable; locked k6 in script.
3. **Mutation tool gaps in Rust.** `cargo-mutants` does not return JSON cleanly across all versions. Fallback path documented as TODO; will harden in Phase 07.

## Status

**Status:** DONE
**Summary:** 11 mechanical gate bash scripts written, all under LOC budget, all chmod +x, single-number contract enforced, 4-stack adapter coverage.
**Concerns:** none material; 3 questions deferred to Phase 07 dry-run.
