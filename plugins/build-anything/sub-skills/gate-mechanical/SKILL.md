---
name: build-anything-gate-mechanical
description: Stage 5 — coverage + mutation + property-based + lint + type-check + bundle-budget mechanical gates; no opinion, only numbers
---

# gate-mechanical — Stage 5 Mechanical Gates

**Maps to:** stage 5 of `/build-anything` flow. Implements LAW-11 + GATE-10 + GATE-11 + GATE-16 (property test category).

## Inputs

- Atom diff from stage 4
- Thresholds from `.build-anything.json` `gates.mechanical` (overrides Section C of v8.0 doc)
- `project_type` for selecting per-type thresholds

## Outputs

- `{atom_dir}/gate-mechanical/{gate}.json` per gate
- Aggregated verdict `{ "stage": 5, "verdict": "PASS|FAIL", "findings": [...] }`

## Gates Executed

| ID | Script | Pass criteria | Threshold source |
|----|--------|---------------|------------------|
| GATE-10 line cov | `scripts/mechanical/coverage-check.sh` | ≥ threshold per project_type | Section C |
| GATE-10 branch cov | same | ≥ threshold | Section C |
| GATE-11 mutation | `scripts/mechanical/mutation-test.sh` | ≥ threshold; scope = changed files + 1-hop | Section C |
| GATE-16 property | `scripts/mechanical/property-test-runner.sh` | every public pure function in diff has ≥ 1 property test | n/a (binary) |
| **GATE-25-E2E (mandatory for project_type ∈ {frontend, mixed})** | `scripts/mechanical/e2e-playwright.sh` | Playwright spec files cover every declared `e2e.journeys[]`, `npx playwright test` exits 0, ≥1 passed, 0 failed, 0 vacuous-runs | binary |
| lint | `scripts/mechanical/lint-check.sh` | zero errors | n/a |
| type-check | `scripts/mechanical/type-check.sh` | zero errors | n/a |
| build green | (project build cmd) | exit 0 | n/a |

**GATE-25-E2E (Playwright runner) is mandatory for any atom where `project_type ∈ {frontend, mixed}`** — declared-but-not-executed Playwright is a vacuous PASS and forbidden by LAW-F6. The orchestrator MUST:
1. Run `npm ci` (or `pnpm i --frozen-lockfile`) in the frontend stack-dir.
2. Boot backend (`go run ./cmd/api &` or equivalent) AND frontend (`npm run dev &`) — both on declared ports.
3. Wait until both `GET /healthz` (backend) and `GET /` (frontend) return 200 OR fail GATE-25-E2E with `boot-failed`.
4. Run `e2e-playwright.sh` against the live stack.
5. Tear down on completion.

Justification (added 2026-05-27 from atom 260527-0141-youtube-like-share post-mortem): the user-visible bugs "fail to load feed" + "watch page never renders" + "Upload nav ambiguous" were ALL trivially catchable by a 30-line Playwright smoke spec; the prior skill version declared GATE-25-E2E in the orchestrator table but the mechanical-gate sub-skill table omitted it, so it was never executed. This is the hole that fix closes.

All scripts emit a single-number primary metric to stdout (usable as `/ck:autoresearch` Verify command in AL-4 self-heal).

## Parallel Execution

Stage 5 runs all 7 gates in parallel via background bash. Orchestrator (`/build-anything`) collects exit codes + JSON outputs.

## HALT Conditions

- Any single gate FAIL
- Total runtime > 15 min (forced timeout — investigate)
- Mutation testing on > 200 files in scope (refuse; tighten scope via diff or escalate)

## Retry Policy (AL-aware)

- AL ≤ 2: HALT and return to user
- AL ≥ 3: invoke `/ck:autoresearch` with failed gate's script as Verify command; max 5 iter per atom (per AL-4 breaker)
- Mutation FAIL with surviving mutants: auto-generate a follow-up atom with the mutant locations as "must-cover" criteria (advisory; not auto-merged)

## Tools Used

- Coverage: language-native (`c8`, `coverage.py`, `go test -cover`, `cargo tarpaulin`)
- Mutation: `stryker` (JS/TS) / `mutmut` (Python) / `gremlins` (Go) / `cargo-mutants` (Rust)
- Property: `fast-check` (JS/TS) / `hypothesis` (Python) / `gopter` (Go) / `proptest` (Rust)
- Lint: project-native (eslint / ruff / golangci-lint / clippy)
- Type: tsc / mypy / go vet / cargo check

## Threshold Source of Truth

Defaults in v8.0 Section C. Overrides per-project in `.build-anything.json`:

```json
{
  "gates": {
    "mechanical": {
      "coverage_line": 80,
      "coverage_branch": 75,
      "mutation_score": 60,
      "lint_max_errors": 0
    }
  }
}
```

Overrides MUST include a `justification` field; logged with atom; counts against tech-debt budget.

## Single-Number Output Contract

Each script writes `{atom_dir}/gate-mechanical/{gate}.json`:

```json
{ "gate": "GATE-10-line", "score": 84.2, "threshold": 80, "passed": true, "delta": 4.2 }
```

`score` is the single number the AL-4 self-heal loop maximises. Orchestrator computes `passed = score >= threshold`.

## Tool Delegation

This sub-skill delegates COVERAGE to `/ck:test` per Phase 01 Discovery (already has coverage analysis built-in). The script `coverage-check.sh` is a thin wrapper that calls `/ck:test --coverage` and extracts the number.

## References

- Threshold table: `docs/ubs-v8-technical-hardening.md` Section C
- Scripts: `scripts/mechanical/*.sh`
- AL-4 breaker: `references/al4-circuit-breaker.md`
