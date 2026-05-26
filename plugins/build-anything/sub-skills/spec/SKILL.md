---
name: build-anything-spec
description: Stages 1.A + 1.B + 1.C + 1.D + 3 — pre-spec product research (ck:research), BMAD-style multi-agent PRD generation, product-feature-coverage gate, stack-fitness gate, original spec atom builder, and adversarial red-team review; outputs testable atom brief + PRD or HALTs with ambiguity findings
---

# spec — L1 Spec Atom + PRD + Red-Team (v8.4)

**Maps to:** stages 1.A (pre-spec research), 1.B (spec + PRD with BMAD agents), 1.C (product feature coverage), 1.D (stack fitness — v8.4), 1 (original v7.5 spec atom — unchanged), and 3 (red-team spec) of `/build-anything` flow. Implements LAW-12 (adversarial framing) at spec layer **and** closes the v8.1 product-discovery gap **and** the v8.3 stack-misfit gap.

## v8.2 motivation

In v8.1 the spec stage took a 1–3 sentence user description (e.g. "youtube clone") and produced testable success criteria. The criteria themselves passed mechanical checks. But the **product itself** could be missing canonical features — e.g. a "YouTube clone" without upload+play. v8.1 had no mechanism to detect a *category-level* feature gap. v8.2 adds three new sub-stages BEFORE the original spec generation.

## v8.4 motivation (Stage 1.D)

v8.2 closed the *feature* coverage gap. But spec could still declare a stack that physically cannot serve the product type — e.g. YouTube clone on SQLite + multer-to-local-disk + no transcoder + no CDN. Feature list said "upload+play"; tests stubbed upload; PFC passed; product unshippable. Root cause: spec layer never reconciled feature catalog with infrastructure capabilities required at scale. v8.4 adds Stage 1.D GATE-STACK to disqualify toy stacks for non-toy product types BEFORE code is written.

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

## Stage 1.B — Spec Atom + PRD (BMAD-method, v8.4 — method not invocation)

**Key v8.4 correction:** v8.2 SKILL referenced `npx bmad-method run --workflow prd` which **does not exist** in the BMAD CLI (install / status / uninstall only). The skill now internalises BMAD's multi-persona pattern via Claude Code Task-tool dispatch with persona prompts defined under `references/personas/`. The npx `bmad-method` package remains optional and informational; its presence does NOT change gate behaviour, only the evidence trail.

### How Claude executes Stage 1.B

Read `references/personas/dispatch-instructions.md` for the full protocol. Summary:

1. Verify `{atom_dir}/research/product-features-<slug>.md` exists (Stage 1.A output).
2. Choose mode: `multi-persona` (default) or `single-persona` (`--fast` only, small atoms).
3. Dispatch persona Tasks **in parallel** (single message, multiple `Task` calls):
   - **PM persona** → `references/personas/pm-persona.md` → produces `{atom_dir}/prd.md`
   - **Architect persona** → `references/personas/architect-persona.md` → produces `{atom_dir}/architecture.md`
   - **UX persona** → `references/personas/ux-persona.md` → produces `{atom_dir}/ux-spec.md`
4. After all Tasks return, run `scripts/spec/bmad-prd-gate.sh --atom-dir {atom_dir} --project-root {project_root}` → emits `gate-spec/bmad-prd.json`.
5. On FAIL: gate's `details.artefacts[].status` identifies which persona produced incomplete output. Re-dispatch that single persona with status as context. Max 2 retries per persona.

### Why method-not-invocation

| Failure mode of "invoke BMAD" | Why method-not-invocation avoids it |
|--------------------------------|-------------------------------------|
| `npx bmad-method run` doesn't exist | Skill dispatches via Task tool; no external CLI dependency |
| npx package install hangs on interactive prompt | No install required for the gate to pass |
| BMAD version drift breaks the workflow | Persona prompts live in this skill, version-pinned with it |
| Single-author spec = single-context limitations | Each persona runs in a fresh Task context |
| Sequential PM → Architect → UX is wall-time slow | Parallel dispatch; wall time = max(P, A, U) |

### Required atom-brief fields (unchanged from v8.2)

```yaml
prd_ref: prd.md
arch_ref: architecture.md
ux_ref: ux-spec.md
research_refs: [research/product-features-<slug>.md]
canonical_features_covered:
  - feature_name: video upload
    journey: J-01
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

## Stage 1.D — Stack Fitness Gate (NEW v8.4)

Run `scripts/spec/stack-fitness-check.sh --atom-dir {atom_dir} --project-root {project_root}`.

The gate:
1. Reads `product_type` from `{atom_dir}/intent/verdict.json` (fallback: `gate-spec/product-feature-coverage.json`).
2. Resolves catalog key via fuzzy match: exact → suffix-strip (`-mvp`, `-lite`, `-basic`, `-prototype`, `-poc`, `-demo`, `-toy`, `-simple`, `-minimal`, `-vN`) → prefix-overlap. Lets `youtube-clone-mvp` resolve to `youtube-clone`.
3. Reads `stack_fitness.required_capabilities[]` from catalog for that product type. Each capability has `satisfies_keys`, `accept_values`, `disqualified_values`, `disqualified_packages`, `disqualified_schema_columns`.
4. For each required capability:
   - Walks `satisfies_keys` (e.g. `stack.media_storage`, `stack.database`) in atom brief / `.build-anything.json`.
   - Declared value MUST appear in `accept_values` AND NOT in `disqualified_values`.
   - Scans `package.json`/`requirements.txt`/`go.mod`/`Cargo.toml` against `disqualified_packages` (e.g. `multer` for blob_object_store, `better-sqlite3` for concurrent writer).
   - Scans `*.sql`/migrations for `disqualified_schema_columns`.
5. **PASS** → all required capabilities satisfied and no disqualifying signals found.
6. **FAIL** → missing capability OR disqualified pattern detected. Output lists `missing_capabilities[]` and `disqualified_violations[]` so spec author knows exactly what to swap.
7. **N/A_PENDING_REVIEWER** → product type has no catalog entry OR has empty `required_capabilities[]` (trivial types like `todo-app`). LAW-F6 — never vacuous PASS for unknown types.

Output: `{atom_dir}/gate-spec/stack-fitness.json`.

GATE-STACK is exempt from `--fast`. Toy stacks for serious products are NEVER acceptable; fast mode lowers confidence threshold, not stack disqualification.

### Example FAIL output (youtube-clone-mvp on toy stack)

```json
{
  "gate": "GATE-STACK",
  "verdict": "FAIL",
  "product_type_declared": "youtube-clone-mvp",
  "catalog_key_resolved": "youtube-clone",
  "missing_capabilities": [
    "blob_object_store",
    "transcode_worker",
    "cdn",
    "media_streaming_protocol",
    "relational_db_concurrent_writer"
  ],
  "disqualified_violations": [
    { "capability": "relational_db_concurrent_writer",
      "kind": "disqualified_package",
      "value": "better-sqlite3",
      "rationale": "SQLite is single-writer; cannot serve concurrent uploads/views" },
    { "capability": "blob_object_store",
      "kind": "disqualified_package",
      "value": "multer",
      "rationale": "multer-to-local-disk does not survive horizontal scaling; need S3/GCS/R2" }
  ],
  "confidence": 100,
  "ambiguities": []
}
```

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
- `{atom_dir}/gate-spec/stack-fitness.json` — GATE-STACK verdict (1.D, v8.4)
- `{atom_dir}/verdicts.json` entries for stages 1.A, 1.B, 1.C, 1.D, 1, 3

## Atom Brief Structure (required fields, v8.4)

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
stack:                                # NEW v8.4 — feeds GATE-STACK
  language: node                      # node|python|go|rust
  runtime: node-20
  database: postgres-15               # must satisfy relational_db_concurrent_writer for serious products
  media_storage: s3                   # must satisfy blob_object_store for video/image products
  transcode: ffmpeg-worker            # must satisfy transcode_worker for video products
  cdn: cloudfront                     # must satisfy cdn for any media product
  streaming_protocol: hls             # must satisfy media_streaming_protocol for video
  cache: redis                        # cache_layer
  queue: sqs                          # fanout_queue
  search: opensearch                  # search_index
  payment: stripe                     # payment_processor (ecommerce only)
  realtime: websocket                 # realtime_transport (chat/uber/twitter)
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

## Mechanical Pass Criteria (v8.4)

- GATE-0 (atom brief complete) → all required fields present including v8.2 fields (`product_type`, `prd_ref`, `research_refs`, `canonical_features_covered`) AND v8.4 fields (`stack.*`)
- **GATE-PFC** (product feature coverage) → PASS or N/A_PENDING_REVIEWER (never vacuous)
- **GATE-STACK** (stack fitness, v8.4) → PASS or N/A_PENDING_REVIEWER (never vacuous; FAIL HALTs spec stage)
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

## Tools Used (v8.4)

- `ck:research` skill — Stage 1.A pre-spec product discovery
- `bmad-method` (npx) — Stage 1.B PRD/Architecture/UX agents
- `scripts/spec/product-feature-coverage.sh` — Stage 1.C GATE-PFC enforcer
- `scripts/spec/stack-fitness-check.sh` — Stage 1.D GATE-STACK enforcer (v8.4)
- `scripts/spec/feature-catalog.json` — canonical feature catalog + stack-fitness capability requirements (v8.4)
- `/ck:plan` template for atom brief
- `/ck:predict` for failure forecast
- Skill tool to spawn spec-attacker subagent (fresh context, no implementer history)

## References

- Reviewer prompt: `references/reviewer-prompts/spec-attacker.md`
- Atom template: `templates/atom-brief.md`
- Local PM-substitute (BMAD fallback): `references/local-pm-substitute.md`
- LAW-12 multi-agent review: `docs/ubs-v8-technical-hardening.md` §Section A
- v8.2 skill composition: `references/v8-2-skill-composition.md`
