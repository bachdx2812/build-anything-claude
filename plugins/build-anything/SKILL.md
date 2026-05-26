---
name: build-anything
description: UBS v8.1 atomic build orchestrator — 15-stage pipeline (spec → schema → red-team-spec → build → mechanical gates → backend integrity → cloud/prod reality → security → architecture → patterns → adversarial review → perf+obs → evidence bundle → prod-verify) with multi-agent adversarial review, mechanical gates, and production-reality gates (IaC, rate limit, cache, SLO/RTO, CI seal, scaling) that replace "Devin says done"
---

# /build-anything — UBS v8.1 Orchestrator

**Philosophy:** UBS v7.5 + v8.0 hardening laws (LAW-11..17) + v8.1 production-reality layer (GATE-22..28). See `docs/ubs-v8-technical-hardening.md` (v8.0) and `docs/ubs-v8-1-image-mapping.md` (v8.1) for canonical specs. This skill is the executable expression of that spec.

**Anti-rationalisation rule (inherited from `/ck:cook`):** at every HARD-GATE you HALT and produce evidence. Do not rationalise around a failed gate. Do not skip a stage because "the test was probably fine."

## Autonomous Loop (the headline)

This skill IS a closed loop. No human-in-the-loop required between stages. Sequence:

```
PLAN     stages 1–3   spec → schema → red-team-spec   (self-iterate on ambiguity)
BUILD    stage  4     implementer writes diff within allowlist
VERIFY   stages 5–12  mechanical + backend + cloud + security + arch + review + perf
SELF-HEAL on FAIL    /ck:autoresearch feeds the failing gate's stdout back as
                     the Verify command; patch within allowlist only; re-VERIFY
SEAL     stage  13   evidence manifest + external witness (LAW-17)
SHIP     stage  14   prod-verify with explicit user confirm (LAW-10)
```

Loop terminates on:
- All gates PASS + manifest witnessed → atom advances.
- AL-4 breaker: 5 iter / $5 atom / $20 hour / oscillation detected → HALT with diagnosis.
- LAW-10 prompt (prod write) → wait for user.

**Why it converges.** Every gate emits a single integer score on stdout + a JSON verdict on disk. Each self-heal iteration shrinks that score toward 0 because the patch is bounded to the allowlist and the Verify command is the exact failing gate. The script set is stack-agnostic (Node / Python / Go / Rust adapters).

## Entry — Pre-flight

Before any stage:
1. Read `.build-anything.json` at project root. If absent, run `templates/build-anything-config.json` interactively.
2. Detect `project_type` (frontend / backend / library / infra / mixed).
3. Detect `automation_level` (AL-0..AL-4). Default AL-2 (agent writes, human confirms).
4. Set per-atom budget (cost ceiling default $5, iteration ceiling default 5).
5. Read active plan (if any) from injected `## Plan Context`.
6. **Resolve operating mode** (see "Operating Modes" below). One of: `bootstrap` (new project from zero) | `atom_on_existing` (task inside existing repo). Default: `atom_on_existing` if `.git` exists, else `bootstrap`.

## Operating Modes

This skill works for both **new builds** and **tasks inside an existing codebase**. The verification rules (LAW-F6 no vacuous PASS, mechanical gates, evidence manifest) are identical. Only scope discovery differs.

| Mode | Scope source (in priority order) | Use when |
|------|----------------------------------|----------|
| `atom_on_existing` (default) | 1. `scope.paths[]` (explicit) → 2. `git diff <scope.base_ref>` → 3. `scope.bootstrap_glob[]` fallback | adding a feature, fixing a bug, refactoring inside an existing repo |
| `bootstrap` | `scope.bootstrap_glob[]` (e.g. `["src","backend"]`) — scans the declared dirs as the atom surface | greenfield project, day-1 scaffold, or atom that creates the repo |

Config block (`.build-anything.json`):

```json
"scope": {
  "mode": "atom_on_existing",     // or "bootstrap"
  "base_ref": "origin/main",      // git ref to diff against (atom_on_existing only)
  "paths": [                       // explicit override — wins over git diff
    "backend/routes/orders.js",
    "frontend/components/cart.tsx"
  ],
  "bootstrap_glob": ["backend","frontend"]  // last-resort fallback / bootstrap surface
}
```

**Resolution algorithm** (`mechanical/_common.sh#changed_files`):

```
if scope.paths is non-empty → use those files (verbatim)
elif mode == "atom_on_existing" AND git diff <base_ref> is non-empty → use that
elif scope.bootstrap_glob is non-empty → list source files inside those dirs
else → emit N/A_PENDING_REVIEWER (LAW-F6: never vacuous PASS)
```

**Stack root in subdirs.** If `package.json` / `pyproject.toml` / `go.mod` is not at repo root, set `stack.dir` (e.g. `"stack": { "dir": "backend", "lang": "node", "test_cmd": "npm test" }`). Mechanical scripts cd into `stack.dir` before running build/test commands.

**F6 corollary.** Empty scope is NEVER a PASS. It is `N/A_PENDING_REVIEWER`, which a human must convert to either an explicit PASS (with justification) or to a populated scope.

## 14-Stage Flow

| # | Stage | Sub-skill | Gates fired | HALT on |
|---|-------|-----------|-------------|---------|
| 0 | Pre-flight | (this file) | config / context | missing config |
| 1 | Spec Atom (L1) | `spec` | GATE-0 brief complete | non-testable criteria |
| 2 | Schema / Service (L2) | `schema` | GATE-1 allowlist | unauthorised file touch |
| 3 | Red-team Spec | `spec` (adversarial mode) | spec-attacker pre-check | spec ambiguity remains |
| 4 | Build (L3) | `implementer` | GATE-1 + GATE-2 | allowlist violation |
| 5 | Mechanical Gates | `gate-mechanical` | GATE-10 GATE-11 GATE-16 lint type | coverage / mutation / property below threshold |
| 6 | Backend Integrity | `gate-backend` | GATE-18 a–f, GATE-19, GATE-20, GATE-21, GATE-23, GATE-24 | any sub-gate fail |
| 6.5 | Cloud / Prod Reality (v8.1) | `gate-cloud` | GATE-22 IaC, GATE-25 deploy runbook, GATE-26 SLO+RTO, GATE-27 CI seal, GATE-28 scaling | drift / no rollback / SLO breach / mergeable main / p95 breach |
| 7 | Security | `gate-security` | GATE-12 (LAW-16) | any CRITICAL / HIGH |
| 8 | Architecture | `gate-arch` | GATE-13 | new cycle / layer violation |
| 9 | Code Patterns | `gate-pattern` | (advisory) | anti-pattern severity HIGH |
| 10 | Spec-compliance + spec-attacker review (L4) | `review` | GATE-17 | reviewer FAIL |
| 11 | Code-quality review (L4) | `review` | GATE-17 | reviewer FAIL |
| 12 | Perf + Observability | `gate-perf` | GATE-14 GATE-15 | budget breach / missing instrumentation |
| 13 | Evidence Bundle | `evidence` | LAW-17 | manifest hash mismatch |
| 14 | Prod-Verify | `verify` | GATE-6 (v7.5) + GATE-16 rollback drill | post-deploy regression |

**Stages 5-12 may run in parallel within their gate group when independent.** Orchestrator (this file) dispatches sub-skills and aggregates verdicts; consensus rule = ANY reviewer FAIL → atom FAIL.

## Mode Flags

| Flag | Behaviour |
|------|-----------|
| `--auto` (default) | Detect intent from feature description; pick mode |
| `--fast` | Skip stages 3, 9, 11 (red-team spec, pattern review, secondary code-quality review). For prototype atoms only. |
| `--strict` | All 14 stages, thresholds at max per Section C of v8.0 doc |
| `--parallel` | Stages 5-12 run sub-skills in parallel where independent |
| `--dry-run` | Run pipeline against staging only; skip stage 14 |

## Dispatch Pattern

For each stage, this skill invokes the corresponding sub-skill via the `Skill` tool. Each sub-skill returns a JSON verdict:

```json
{ "stage": 5, "verdict": "PASS|FAIL|N/A", "findings": [...], "evidence_refs": [...] }
```

Orchestrator writes all verdicts to `{atom_dir}/verdicts.json` then computes terminal status.

## HARD-GATE before code

Before stage 4 (build), every preceding stage's verdict MUST be PASS. If stage 3 (red-team spec) returns ambiguity findings, return to stage 1 and refine. No exception.

## AL-4 self-heal loop

If `automation_level == 4`, on stage 5–12 FAIL, orchestrator invokes `/ck:autoresearch` with the failed gate's mechanical script as the `Verify` command. Subject to AL-4 circuit breaker (see `references/al4-circuit-breaker.md`).

## LAW-10 NO AUTO-DESTRUCTIVE enforcement

Stage 14 (prod-verify) MUST require explicit user confirmation before any production write (deploy, feature-flag flip, payment, email). This is a hard gate inside `verify` sub-skill; orchestrator cannot bypass.

## Outputs per atom

```
{project_root}/.build-anything/atoms/{atom_code}/
├── spec.md
├── schema/                # OpenAPI, SQL DDL, type defs
├── diff.patch             # build output
├── verdicts.json          # aggregated stage results
├── review/                # reviewer JSONs
├── evidence/              # screenshots, query results, contract reports
├── manifest.json          # LAW-17 crypto bundle
└── manifest.sha256        # binds the manifest
```

## References

- v8.0 spec: `docs/ubs-v8-technical-hardening.md` (project repo)
- 14-stage flow detail: `references/14-stage-flow.md`
- Multi-agent protocol: `references/multi-agent-review-protocol.md`
- Backend gates detail: `references/backend-integrity-gates.md`
- Evidence collection: `references/evidence-collection.md`
- Automation ladder: `references/automation-ladder.md`
- AL-4 breaker: `references/al4-circuit-breaker.md`
- UBS philosophy (v7.5 preserved): `references/ubs-philosophy.md`

## Sub-skill index

| Sub-skill | Path |
|-----------|------|
| spec | `sub-skills/spec/SKILL.md` |
| schema | `sub-skills/schema/SKILL.md` |
| implementer (stage 4 build) | `sub-skills/implementer/SKILL.md` |
| gate-mechanical | `sub-skills/gate-mechanical/SKILL.md` |
| gate-backend | `sub-skills/gate-backend/SKILL.md` |
| gate-cloud (v8.1) | `sub-skills/gate-cloud/SKILL.md` |
| gate-security | `sub-skills/gate-security/SKILL.md` |
| gate-arch | `sub-skills/gate-arch/SKILL.md` |
| gate-pattern | `sub-skills/gate-pattern/SKILL.md` |
| review | `sub-skills/review/SKILL.md` |
| gate-perf | `sub-skills/gate-perf/SKILL.md` |
| evidence | `sub-skills/evidence/SKILL.md` |
| verify | `sub-skills/verify/SKILL.md` |

## When to invoke

- User says "build X", "implement X", "add X feature" — any atomic delivery
- User says "ship X" — same flow with stage 14 forced on
- User says "verify X built correctly" — start at stage 5 (skip 1-4)
- User says "/build-anything <feature>" — explicit entry

## When NOT to invoke

- Pure research / exploration (use `/ck:plan` or `Agent` with researcher)
- Doc-only changes (no L3 build)
- Trivial refactor (single function rename) — use direct edit

## Quality stance

This skill EXISTS to make "Devin says done" auditable. If you are tempted to shortcut a gate to finish faster, STOP. The shortcut is the bug.
