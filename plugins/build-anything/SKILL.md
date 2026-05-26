---
name: build-anything
description: UBS v8.3 atomic build orchestrator — 17-stage pipeline (intent-declaration → deps-bootstrap → research → spec [BMAD] → schema → red-team-spec → build → mechanical gates [+playwright-e2e] → backend integrity → cloud/prod reality → security → architecture → patterns → ui-ux gate → adversarial review → perf+obs → evidence bundle → prod-verify) with confidence-loop law (LAW-CL-95), multi-agent adversarial review, mechanical gates, production-reality gates (IaC, rate limit, cache, SLO/RTO, CI seal, scaling), and three-skill composition (research + BMAD + ui-ux-pro-max) that replace "Devin says done"
---

# /build-anything — UBS v8.3 Orchestrator

**Philosophy:** UBS hardening laws (LAW-11..17) + production-reality layer (GATE-22..28) + product-discovery + UI/UX + E2E layer (GATE-PFC, GATE-UIUX, GATE-25-E2E) + confidence-loop layer (LAW-CL-95, GATE-INTENT, meta-gate runner). Canonical doc: `docs/ubs.md` (single source of truth — versioned suffixes retired).

**v8.3 motivation** — Every prior version assumed the user's brief was right. A v8.2 audit showed the spec stage can produce internally-consistent specs for the wrong product (e.g. "YouTube clone with no upload"). Root cause: the agent inferred narrower intent than the user implied and never verified back. No downstream gate can recover from a misread brief. v8.3 fixes the read.

**LAW-CL-95 (Confidence-Loop Law).** No stage may advance to the next until its self-reported confidence ≥ 95 AND its LAW-F6 vacuous-PASS guard holds (no PASS with empty evidence). On confidence < 95, the stage MUST loop: probe ambiguities → ask the user → re-extract → re-score. Max 5 iter per stage. If still < 95 at iter 5 → HALT with structured open-questions. This applies to **every stage**, not only intent.

**v8.2 motivation** — A v8.1 audit shipped a "YouTube clone" with NO upload and NO play functions. Stage 1 (spec) declared PASS because criteria were "testable" in isolation, but the spec had a fundamental product gap. Stages 4–13 cannot recover from spec gaps. v8.2 closes the loop by composing three additional skills at the spec/UI layer:

| Skill | Where injected | What it prevents |
|-------|----------------|-------------------|
| `research` (ck:research) | Stage 1.A (pre-spec discovery) | Feature catalog ignorance — research reveals canonical features for "X clone" before spec atom is drafted |
| `bmad-method` (npx) | Stage 1.B (PRD + Architecture + UX agent personas) | Single-author spec — multi-agent PM/Architect/UX coverage |
| `ui-ux-pro-max` | Stage 6.7 (UI quality hard gate) | Ugly / inaccessible UI — design system + 8 statically-enforced rules |

Plus two new gates:
- **GATE-PFC** (product-feature-coverage) in Stage 1.C: matches product type against catalog → fails if must-have features absent from spec.
- **GATE-25-E2E** (playwright-e2e) in Stage 5: enforces Playwright tests cover declared user journeys.

**Anti-rationalisation rule (inherited from `/ck:cook`):** at every HARD-GATE you HALT and produce evidence. Do not rationalise around a failed gate. Do not skip a stage because "the test was probably fine."

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

## Entry — Stage 0 Pre-flight

Before any stage:
1. Read `.build-anything.json` at project root. If absent, run `templates/build-anything-config.json` interactively.
2. Detect `project_type` (frontend / backend / library / infra / mixed).
3. Detect `automation_level` (AL-0..AL-4). Default AL-2 (agent writes, human confirms).
4. Set per-atom budget (cost ceiling default $5, iteration ceiling default 5).
5. Read active plan (if any) from injected `## Plan Context`.
6. **Resolve operating mode** (see "Operating Modes" below). One of: `bootstrap` (new project from zero) | `atom_on_existing` (task inside existing repo). Default: `atom_on_existing` if `.git` exists, else `bootstrap`.

## Stage 0.1 — INTENT DECLARATION (v8.3, MANDATORY FIRST STAGE)

**No stage may run before Stage 0.1 returns READY.** This is the closed-loop fix for the v8.2 finding that the spec stage produced wrong-product specs because nobody verified the agent's read of the user's brief.

Protocol (delegated to `sub-skills/intent/SKILL.md`):

1. Save the raw prompt to `{atom_dir}/intent/raw-prompt.md`.
2. Run `scripts/intent/declare-intent.sh --prompt <file> --atom-dir <dir> --project-root <dir>` to scaffold `intent.json`.
3. Agent extracts `declared = { product_type, primary_user, core_flows[], success_criteria[], out_of_scope[], constraints[] }` from prompt.
4. Agent scores `confidence` 0-100 using the rubric in `sub-skills/intent/SKILL.md` (start at 100, subtract for each gap; floor at 0). **Confidence is the agent's self-report and is gated by LAW-F6 — high confidence with empty `declared.*` fields automatically HALTs.**
5. Re-run the script to compute `next_action`:
   - `READY` → confidence ≥ 95 AND vacuous-PASS guard holds → advance to Stage 0.5.
   - `NEEDS_USER` → present `ambiguities[]` via `AskUserQuestion` (Claude Code) or harness-equivalent. Append answers to `raw-prompt.md` under `## iter-N answers:`. Re-run script. iter++.
   - `HALT` → iter ≥ 5 OR vacuous-PASS guard triggered. Stop. Report structured open-questions to caller.
6. Verdict frozen to `{atom_dir}/intent/verdict.json` consumed by orchestrator + downstream stages (1.A reads `product_type`, 1.B reads full declared block, 1.C reads `product_type` again, 3 reads `out_of_scope`).

Mode flags affect threshold/iter: `--fast` (80/2), default (95/5), `--strict` (99/10). `--no-intent-loop` deprecated — must pair with `--ack-no-discovery` + user-authored `intent.json`.

**This stage is exempt from being skipped by `--fast`.** Fast mode lowers the threshold; it does not bypass intent declaration. Without intent, the build is undefined.

7. **Run Stage 0.5 — ensure-deps** (v8.2): execute `scripts/ensure-deps.sh --project-root <root> --atom-dir <atom_dir>`. This verifies that `research` and `ui-ux-pro-max` skills exist under `~/.claude/skills/`, and installs `bmad-method` via `npx bmad-method install --modules bmm --tools claude-code --yes` if not already present in the project. Emits `{atom_dir}/deps.json`. HALT if any required dep is missing AND cannot be auto-installed. **Skip auto-install only if user passes `--no-bmad` flag** (degrades Stage 1.B to local PM-substitute agent — still enforces GATE-PFC).

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

## 17-Stage Flow (v8.3)

| # | Stage | Sub-skill | Gates fired | HALT on |
|---|-------|-----------|-------------|---------|
| 0 | Pre-flight | (this file) | config / context | missing config |
| **0.1** | **Intent Declaration (v8.3)** | `sub-skills/intent` + `scripts/intent/declare-intent.sh` | GATE-INTENT, LAW-CL-95, LAW-F6 | iter ≥ 5 with conf < 95, OR vacuous PASS (conf ≥ 95 with empty declared) |
| **0.5** | **Deps bootstrap (v8.2)** | `scripts/ensure-deps.sh` | dep-presence | research/uiux missing, bmad install failed (unless `--no-bmad`) |
| **1.A** | **Pre-spec product research (v8.2)** | `research` | discovery | research returns 0 sources |
| **1.B** | **Spec Atom + PRD (L1)** | `spec` + bmad PM/Architect/UX agents | GATE-0 brief complete | non-testable criteria, no PRD produced |
| **1.C** | **Product Feature Coverage (v8.2)** | `spec/product-feature-coverage.sh` | GATE-PFC | declared product type has must-have features missing from spec |
| 2 | Schema / Service (L2) | `schema` | GATE-1 allowlist | unauthorised file touch |
| 3 | Red-team Spec | `spec` (adversarial mode) | spec-attacker pre-check | spec ambiguity remains |
| 4 | Build (L3) | `implementer` | GATE-1 + GATE-2 | allowlist violation |
| 5 | Mechanical Gates | `gate-mechanical` | GATE-10 GATE-11 GATE-16 lint type **+ GATE-25-E2E (v8.2)** | coverage / mutation / property below threshold / Playwright fail |
| 6 | Backend Integrity | `gate-backend` | GATE-18 a–f, GATE-19, GATE-20, GATE-21, GATE-23, GATE-24 | any sub-gate fail |
| 6.5 | Cloud / Prod Reality (v8.1) | `gate-cloud` | GATE-22 IaC, GATE-25 deploy runbook, GATE-26 SLO+RTO, GATE-27 CI seal, GATE-28 scaling | drift / no rollback / SLO breach / mergeable main / p95 breach |
| **6.7** | **UI/UX hard gate (v8.2)** | `gate-ui-ux` | GATE-UIUX | CRITICAL findings >0 OR HIGH > threshold |
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
| `--confidence-floor=N` | LAW-CL-95 machine enforcement. After gates finish, if `summary.min_confidence < N` the orchestrator exits 2 (even when all gates PASS/N/A). Default 0 = advisory only. Recommended: fast=80, default=95, strict=99. |
| `--no-witness` | Skip cosign witness step (for local smoke-tests and CI runs where the manifest is consumed in-process, not archived). Production runs MUST keep witnessing on. |

## Meta-gates (skill self-regression)

The skill itself ships with mechanical regression tests under `scripts/meta/`. These guard the LAW-F6 (no vacuous PASS) and LAW-CL-95 (honest confidence) invariants against silent skill rot.

| Meta-gate | Asserts |
|-----------|---------|
| `no-vacuous-pass-test.sh` | Empty atom → 0 PASS gates. Any gate emitting PASS against empty input is a LAW-F6 hole. |
| `real-atom-smoke-test.sh` | Real 1-file + 1-test atom → ≥3 PASS with `confidence=100`, 0 ERROR (silent-drop guard live), no PASS with `confidence=null` or `=0` (LAW-CL-95 retrofit hole), and `--confidence-floor=80` on an N/A-only run exits 2. |
| `run-all-meta-gates.sh` | Runs every sibling meta-gate and aggregates verdicts. Exit 0 = no regression, 1 = skill regression, 2 = harness rot. Wire into CI / pre-ship. |

```bash
# One-line skill regression check
bash scripts/meta/run-all-meta-gates.sh
```

## Dispatch Pattern

For each stage, this skill invokes the corresponding sub-skill via the `Skill` tool. Each sub-skill returns a JSON verdict:

```json
{ "stage": 5, "verdict": "PASS|FAIL|N/A", "findings": [...], "evidence_refs": [...] }
```

Orchestrator writes all verdicts to `{atom_dir}/verdicts.json` then computes terminal status.

## HARD-GATE before code

Before stage 4 (build), every preceding stage's verdict MUST be PASS. If stage 3 (red-team spec) returns ambiguity findings, return to stage 1 and refine. **And Stage 0.1 intent verdict MUST be READY** — without confirmed intent the spec is built on guessing.

## LAW-CL-95 — Confidence Loop Law (applies to every stage)

Every stage emits, in addition to `passed`:

```json
{
  "confidence": 0-100,
  "ambiguities": [{ "field": "...", "question": "...", "required": true|false }],
  "iter": <int>,
  "max_iter": 5
}
```

If `confidence < 95` AND `iter < max_iter`, the stage MUST loop:

1. Present `ambiguities` to user via `AskUserQuestion` (Claude Code) or harness-equivalent.
2. Apply answers to the stage's input state.
3. Re-run the stage. `iter++`.

If `iter == max_iter` AND `confidence < 95` → HALT with structured open-questions. Do NOT advance.

LAW-F6 vacuous-PASS guard applies on top: even if `confidence ≥ 95`, if the stage's evidence body is empty (no scope_files, no testcases run, no declared output), the stage MUST emit `passed: false` with `na_pending_reason` — not PASS.

Threshold per mode:
- `--fast` → 80
- default → 95
- `--strict` → 99

Stages exempt from skip-by-fast: 0.1 (intent), 1.C (PFC), 6.7 (UI/UX), 13 (evidence). Fast mode lowers the threshold; it does not bypass these gates.

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

- Canonical: `docs/ubs.md` (project repo) — single source of truth, all laws + gates + stages
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
| **intent (v8.3)** | `sub-skills/intent/SKILL.md` |
| spec | `sub-skills/spec/SKILL.md` |
| schema | `sub-skills/schema/SKILL.md` |
| implementer (stage 4 build) | `sub-skills/implementer/SKILL.md` |
| gate-mechanical | `sub-skills/gate-mechanical/SKILL.md` |
| gate-backend | `sub-skills/gate-backend/SKILL.md` |
| gate-cloud (v8.1) | `sub-skills/gate-cloud/SKILL.md` |
| **gate-ui-ux (v8.2)** | `sub-skills/gate-ui-ux/SKILL.md` |
| gate-security | `sub-skills/gate-security/SKILL.md` |

## External skills composed (v8.2)

| Skill | Source | Invoked at |
|-------|--------|------------|
| `ck:research` | local: `~/.claude/skills/research/` | Stage 1.A (pre-spec discovery) |
| `ck:ui-ux-pro-max` | local: `~/.claude/skills/ui-ux-pro-max/` | Stage 6.7 (UI hard gate) |
| `bmad-method` | npx package (`npx bmad-method install`) | Stage 1.B (PRD/Architect/UX agents) |

Auto-installer: `scripts/ensure-deps.sh` runs at Stage 0.5 and produces `deps.json`. See `references/v8-2-skill-composition.md` for the full integration contract.
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
