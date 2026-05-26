---
name: build-anything-spec
description: Stages 1.A + 1.B + 1.C + 3 — pre-spec product research (ck:research), BMAD-style multi-agent PRD generation, product-feature-coverage gate, original spec atom builder, and adversarial red-team review; outputs testable atom brief + PRD or HALTs with ambiguity findings
---

# spec — L1 Spec Atom + PRD + Red-Team (v8.2)

**Maps to:** stages 1.A (pre-spec research), 1.B (spec + PRD with BMAD agents), 1.C (product feature coverage), 1 (original v7.5 spec atom — unchanged), and 3 (red-team spec) of `/build-anything` flow. Implements LAW-12 (adversarial framing) at spec layer **and** closes the v8.1 product-discovery gap.

## v8.2 motivation

In v8.1 the spec stage took a 1–3 sentence user description (e.g. "youtube clone") and produced testable success criteria. The criteria themselves passed mechanical checks. But the **product itself** could be missing canonical features — e.g. a "YouTube clone" without upload+play. v8.1 had no mechanism to detect a *category-level* feature gap. v8.2 adds three new sub-stages BEFORE the original spec generation.

## Stage 1.A — Pre-spec product research (NEW v8.2)

Invoke `ck:research` skill via Skill tool with this prompt:

```
Research what features are canonical/expected for a <product type> product.
Identify the MVP feature set, secondary features, and common anti-patterns or
missing features when developers build a minimal clone. Be concrete (file/route/page level).
Save report to {atom_dir}/research/product-features-<slug>.md.
Cap: 5 searches max.
```

Output → `{atom_dir}/research/product-features-<slug>.md`. Becomes feature inventory used downstream.

## Stage 1.B — Spec Atom + PRD (BMAD, NEW v8.2)

If `deps.json` shows `bmad-method.status ∈ {PRESENT, INSTALLED}`:

```
npx bmad-method run --module bmm --workflow prd --input "{atom_dir}/research/product-features-*.md"
```

BMAD produces:
- `docs/prd.md` — product requirements (epics, stories, acceptance criteria)
- `docs/architecture.md` — initial architecture sketch
- `docs/ux-spec.md` — UX flows (if `--with-ux`)

If `bmad-method.status ∈ {MISSING, INSTALL_FAILED}`, fall back to **local PM-substitute**: use `references/local-pm-substitute.md` to invoke a sub-agent with the PM persona and emit `{atom_dir}/prd.md` in the same shape.

The atom brief now includes additional required fields (see Atom Brief Structure below):

```yaml
prd_ref: docs/prd.md
research_refs: [research/product-features-<slug>.md]
canonical_features_covered:
  - feature_name: video upload
    journey: upload-video
    e2e_test_ref: tests/e2e/upload-video.spec.ts
```

## Stage 1.C — Product Feature Coverage Gate (NEW v8.2)

Run `scripts/spec/product-feature-coverage.sh --atom-dir {atom_dir}`.

The gate:
1. Reads `{atom_dir}/spec.md` (and optional `prd.md`).
2. Matches text against canonical product-type catalog (`scripts/spec/feature-catalog.json`).
3. If product type matches → asserts each must-have feature appears in spec OR PRD OR has explicit waiver.
4. FAIL → returns to Stage 1.A with missing-features as research query refinement.
5. No catalog match → `N/A_PENDING_REVIEWER` (LAW-F6, never vacuous PASS for novel types).

The catalog is extensible — reviewers add product types as encountered.

## Inputs

- 1–3 sentence feature description from user / orchestrator
- `.build-anything.json` project config
- (optional) parent plan reference from `## Plan Context`
- `{atom_dir}/deps.json` from Stage 0.5 (tells whether BMAD is available)

## Outputs

- `{atom_dir}/research/product-features-<slug>.md` — research report (1.A)
- `{atom_dir}/prd.md` OR `docs/prd.md` — PRD (1.B)
- `{atom_dir}/spec.md` — atom brief (unchanged)
- `{atom_dir}/gate-spec/product-feature-coverage.json` — GATE-PFC verdict (1.C)
- `{atom_dir}/verdicts.json` entries for stages 1.A, 1.B, 1.C, 1, 3

## Atom Brief Structure (required fields, v8.2)

```yaml
code: ATOM-{yyyymmdd}-{slug}
layer: L1
iter: 1
product_type: youtube-clone          # NEW v8.2 — must match catalog OR be "novel"
prd_ref: docs/prd.md                  # NEW v8.2 — path to PRD from Stage 1.B
research_refs:                        # NEW v8.2 — research artefacts from 1.A
  - research/product-features-youtube-clone.md
canonical_features_covered:           # NEW v8.2 — feeds GATE-PFC
  - feature_name: video upload
    journey: upload-video
    e2e_test_ref: tests/e2e/upload-video.spec.ts
  - feature_name: video playback
    journey: watch-video
    e2e_test_ref: tests/e2e/watch-video.spec.ts
allowlist:
  - src/foo/**
  - tests/foo/**
success_criteria:                    # MUST be testable
  - When {X} happens, system MUST {Y} within {Z}
  - DB invariant: SUM(orders.total) == SUM(items.subtotal) for atom-touched rows
rollback:
  - feature-flag {name} flip to OFF
  - DB migration {name} reverse
declared_budget:
  cost_usd: 5
  iterations: 5
  perf_budget_ms_p95: 200
predict_failures: []                 # filled by /ck:predict in stage 1
```

## Stage 1 — Spec Generation

1. Expand description into atom brief using template `templates/atom-brief.md`.
2. Invoke `/ck:predict` to forecast failure modes; add to `predict_failures`.
3. Mechanical check (GATE-0):
   - All required fields present
   - Every success criterion is testable (contains a measurable predicate or invariant query)
   - Rollback path present
4. If any criterion is non-testable → FAIL, return to user with the offending criterion.

## Stage 3 — Red-Team Spec

Invoke adversarial sub-agent (Opus 4.7) with reviewer prompt `references/reviewer-prompts/spec-attacker.md`. The attacker tries to:

- Find an input that satisfies the literal criterion but violates the intent
- Find a missing edge case (empty / max / negative / unicode / timezone / null)
- Find unspecified concurrency behaviour
- Find unspecified failure behaviour (what if upstream returns 500?)
- Find scope creep (criterion implies work outside allowlist)

**Pass:** attacker returns `{ "verdict": "PASS", "findings": [] }` AFTER actively trying to fail.
**Fail:** attacker returns findings. Orchestrator loops back to stage 1; user / agent refines criteria. Max 3 iter; further → HALT and escalate.

## Mechanical Pass Criteria (v8.2)

- GATE-0 (atom brief complete) → all required fields present including v8.2 fields (`product_type`, `prd_ref`, `research_refs`, `canonical_features_covered`)
- **GATE-PFC** (product feature coverage) → PASS or N/A_PENDING_REVIEWER (never vacuous)
- Spec-attacker reviewer → PASS
- `/ck:predict` returns ≥ 1 forecasted failure mode (zero = suspicious; force rerun)

## HALT Conditions

- Non-testable criterion after 3 refinement iters
- Spec-attacker FAIL after 3 iters
- Allowlist not specified
- Rollback not specified

## Retry Policy

- Max 3 spec refinement iterations per atom
- After 3 → escalate to user; do not silently downgrade to "good enough"

## Tools Used (v8.2)

- `ck:research` skill — Stage 1.A pre-spec product discovery
- `bmad-method` (npx) — Stage 1.B PRD/Architecture/UX agents
- `scripts/spec/product-feature-coverage.sh` — Stage 1.C GATE-PFC enforcer
- `scripts/spec/feature-catalog.json` — canonical feature catalog
- `/ck:plan` template for atom brief
- `/ck:predict` for failure forecast
- Skill tool to spawn spec-attacker subagent (fresh context, no implementer history)

## References

- Reviewer prompt: `references/reviewer-prompts/spec-attacker.md`
- Atom template: `templates/atom-brief.md`
- Local PM-substitute (BMAD fallback): `references/local-pm-substitute.md`
- LAW-12 multi-agent review: `docs/ubs-v8-technical-hardening.md` §Section A
- v8.2 skill composition: `references/v8-2-skill-composition.md`
