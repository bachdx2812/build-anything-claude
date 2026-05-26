# Mechanical Gates — Reference

Canonical source: `docs/ubs-v8-technical-hardening.md` Section B + C. This file enumerates the scripts and their single-number outputs.

## Why "mechanical"

A mechanical gate is one whose pass/fail is determined by a script that emits a single number, comparable against a threshold. No opinion. No "looks fine." If the script says 79.8 and threshold is 80, the gate FAILs — full stop.

## Script catalogue

All scripts live under `~/.claude/skills/build-anything/scripts/mechanical/`.

| Script | Gate | Single-number output | Threshold key |
|--------|------|----------------------|---------------|
| `coverage-check.sh` | GATE-10 line/branch | line% / branch% | `gates.mechanical.coverage_line` |
| `mutation-test.sh` | GATE-11 | mutation score % | `gates.mechanical.mutation_score` |
| `property-test-runner.sh` | GATE-16 property | # pure functions tested | `gates.mechanical.property_min` |
| `lint-check.sh` | lint | error count | hard 0 |
| `type-check.sh` | type | error count | hard 0 |
| `bundle-budget.sh` | GATE-14 (FE) | delta KB gz | `gates.performance.bundle_delta_kb` |
| `lighthouse-check.sh` | GATE-14 (FE) | perf score 0-100 | `gates.performance.lighthouse_perf_*` |
| `load-test-smoke.sh` | GATE-14 (BE) | p95 ms | `gates.performance.p95_max_ms` |
| `observability-check.sh` | GATE-15 | (binary) missing instrumentation count | hard 0 |
| `verify-manifest.sh` | LAW-17 | hash mismatches | hard 0 |

## Single-number contract

Every script writes its primary metric to stdout AND a JSON file `{atom_dir}/gate-mechanical/{gate}.json`:

```json
{ "gate": "GATE-10-line", "score": 84.2, "threshold": 80, "passed": true, "delta": 4.2 }
```

stdout is consumed by `/ck:autoresearch` as Verify command (per Phase 01 Discovery 2). The single-number contract makes the autonomous self-heal loop trivial: maximise `score`.

## Stack adapters

`scripts/mechanical/_common.sh` provides language-detection helpers and delegates to per-language adapters:

```
Node/TS:  c8 / stryker / fast-check / eslint / tsc / size-limit
Python:   coverage.py / mutmut / hypothesis / ruff / mypy / pip-audit
Go:       go test -cover / gremlins / gopter / golangci-lint / go vet / govulncheck
Rust:     cargo tarpaulin / cargo-mutants / proptest / clippy / cargo check / cargo audit
```

Each adapter is a thin shell function in `_common.sh` that:
1. Detects the project's primary language
2. Invokes the appropriate tool
3. Parses the tool output into the single-number contract
4. Writes the JSON file

## Scope rules

| Gate | Scope |
|------|-------|
| Coverage | atom diff + 1-hop dependents |
| Mutation | atom diff only (full-repo is unaffordable) |
| Property | atom diff — only pure functions |
| Lint | atom diff (lint full repo is project's CI job, not atom's) |
| Type-check | atom diff (same logic) |
| Lighthouse | per-page entry in atom |
| Load smoke | per-endpoint in atom |
| Observability | atom diff |

## Failure response

| AL | On gate FAIL |
|----|--------------|
| 0–1 | Report to human; do nothing automatic |
| 2 | Report; suggest fix; await human |
| 3 | Spawn `/ck:autoresearch` self-heal loop, max 5 iter, capped at $5 |
| 4 | Same as AL-3 but breaker fully armed (see `al4-circuit-breaker.md`) |

## Why mutation is bounded scope

Full-repo mutation tests take hours. Per atom we mutate only the changed files + 1 hop of dependents. This keeps per-atom mutation time under 10 min. Trade-off documented; not a silent compromise.

## Property-test minimum

Every pure function added or modified in the atom MUST have at least one property test (input invariant). If no pure function exists, this gate emits `score=0, threshold=0, passed=true` (vacuously true). Spec-attacker reviewer is informed and may challenge.
