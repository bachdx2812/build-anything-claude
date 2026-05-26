---
name: build-anything-gate-perf
description: Stage 12 — Lighthouse / CWV / bundle / load smoke + a11y + observability presence; per-project-type thresholds
---

# gate-perf — Stage 12 Performance + Observability Gate

**Maps to:** stage 12 of `/build-anything`. Implements LAW-15 + GATE-14 (perf) + GATE-15 (observability) + a11y category. Addresses journal §4.4 + §4.5 + §4.15.

## Inputs

- Atom diff
- Project type (frontend / backend / library / infra)
- Perf budgets from `.build-anything.json` `gates.performance.*` (override Section C of v8.0 doc)
- Baseline metrics from previous atom (for delta check)

## Outputs

- `{atom_dir}/gate-perf/lighthouse.json`
- `{atom_dir}/gate-perf/bundle.json`
- `{atom_dir}/gate-perf/load.json`
- `{atom_dir}/gate-perf/observability.json`
- Verdict `{ "stage": 12, "verdict": "PASS|FAIL", "findings": [...] }`

## Frontend Sub-Checks

| ID | Tool | Pass criteria |
|----|------|---------------|
| Lighthouse perf | `lighthouse-ci` via `/ck:chrome-devtools` | ≥ 90 mobile, ≥ 95 desktop |
| CWV | Lighthouse + Web Vitals | LCP ≤ 2.5 s, INP ≤ 200 ms, CLS ≤ 0.1 |
| Bundle delta | `size-limit` | ≤ +5 KB gz |
| A11y | Lighthouse a11y + `pa11y` | ≥ 95 score; zero violations |

## Backend Sub-Checks

| ID | Tool | Pass criteria |
|----|------|---------------|
| p95 latency smoke | `autocannon` or `k6` | ≤ baseline + 5 % |
| N+1 detection | query log analysis | no new N+1 patterns |
| Bundle delta | `size-limit` (if applicable) | ≤ +10 KB |

## Observability Sub-Checks (LAW-13 / GATE-15)

| ID | Method | Pass criteria |
|----|--------|---------------|
| Log emission | grep diff for `logger.{level}(...)` / `log.{level}(...)` | ≥ 1 per new code path |
| Metric instrumentation | grep for counter / histogram / gauge increments | ≥ 1 metric per new endpoint or job |
| Alert rule | check `alerts.yaml` (or project-configured) diff | ≥ 1 alert per new endpoint OR documented N/A |
| No debug leftovers | grep | 0 `console.log` / `print(...)` / `pdb` / `debugger` |

## Tool Delegation

- `/ck:chrome-devtools` (Phase 01 Discovery) — provides Puppeteer headless + Lighthouse runner
- Per-language load tester wrapped in `scripts/mechanical/load-test-smoke.sh`
- `scripts/mechanical/observability-check.sh` is diff-grep, language-agnostic

## HALT Conditions

- Any sub-check FAIL
- Baseline absent (first atom of project) → emit baseline AND PASS with note
- A11y violations CRITICAL → HALT

## Retry Policy

- AL ≤ 2: HALT
- AL ≥ 3: `/ck:autoresearch` with `lighthouse-check.sh` exit code as Verify command; max 5 iter per AL-4 breaker

## Why Observability Lives Here Not Earlier

Observability needs the implementation to grep; we run it after build. Stage 5 (mechanical) cannot reliably grep yet because the implementer might still be refactoring. Stage 12 is the freeze point before evidence bundle.

## Baseline Tracking

Per project, this sub-skill maintains `.build-anything/baselines/{project_type}.json` with rolling baselines (last 10 atoms). Delta threshold compares against the rolling median, not the previous atom (smooths noise).

## A11y Note (P2 from journal)

A11y is included in stage 12 even though it is P2 in the gap analysis — Lighthouse already includes the a11y category, so cost of including is zero. Full a11y depth (axe-core full audit, screen-reader pass) is a follow-up.

## References

- v8.0 LAW-15 + GATE-14: `docs/ubs-v8-technical-hardening.md`
- v8.0 LAW-13 + GATE-15: same
- `/ck:chrome-devtools` skill (Phase 01 catalogue)
- Scripts: `scripts/mechanical/lighthouse-check.sh`, `bundle-budget.sh`, `load-test-smoke.sh`, `observability-check.sh`
