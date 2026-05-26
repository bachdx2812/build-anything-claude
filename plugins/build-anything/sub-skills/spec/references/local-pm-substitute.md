# Local PM-Substitute — BMAD fallback prompt

Use when `deps.json` shows `bmad-method.status ∈ {MISSING, INSTALL_FAILED}` and the user did not pass `--strict`. This template runs in a fresh sub-agent context to mimic BMAD's PM + Architect + UX three-way review without the npx package.

## Required inputs

- `{atom_dir}/research/product-features-<slug>.md` — produced by Stage 1.A (ck:research)
- User's original 1–3 sentence atom description
- Project's `.build-anything.json`

## Prompt template

```
You are a Product Manager + Solution Architect + UX Designer running a unified PRD workshop.

User description: "<atom description>"
Research findings (must read fully): {atom_dir}/research/product-features-<slug>.md

Your job: produce three artefacts in one pass.

1. {atom_dir}/prd.md — Product Requirements
   - Sections: Vision, Goals, MVP Scope (numbered features), Out-of-Scope (numbered),
     User Personas, User Journeys (numbered with steps), Acceptance Criteria per journey,
     Non-functional requirements (perf, security, accessibility).
   - Each feature MUST link to a journey. Each journey MUST link to a test reference
     path under tests/e2e/ even if the test does not yet exist (used by GATE-25-E2E).

2. {atom_dir}/architecture.md — Solution Architecture
   - Sections: Stack chosen + why, Major components, Data model (tables/collections),
     API surface (endpoints), Deployment topology, Trade-offs considered.
   - Must reconcile with the user's described stack constraints in .build-anything.json.

3. {atom_dir}/ux-spec.md — UX flows
   - Sections: Page inventory, Per-page UX notes (states: empty, loading, error, success),
     Key components needed, Accessibility considerations, Mobile vs desktop deltas.

Rules:
- Do NOT invent features absent from the research file unless explicitly user-requested.
- Mark anything ambiguous as "PENDING_REVIEWER" — do not paper over gaps.
- For each MVP feature, you MUST list at least one acceptance criterion that is
  mechanically testable (a specific endpoint + status code, a specific UI element +
  state, a DB invariant, or a Playwright assertion).
- Cite which research source line motivates each feature.
- Output strictly as three separate markdown files at the paths above. No prose.
```

## After running

Orchestrator:
1. Reads back `{atom_dir}/prd.md` and asserts presence of all three sections (Vision, MVP Scope, Acceptance Criteria).
2. If any section is missing or empty → FAIL Stage 1.B; loop back once. After 2 fails → escalate.
3. Passes the PRD to Stage 1.C (GATE-PFC) as supplementary input alongside spec.md.

## Why local PM-substitute, not just "skip BMAD"

Skipping the PM-style review repeats the v8.1 failure mode where a single-author spec misses category-level features. The local substitute is intentionally cheaper and less structured than BMAD, but still enforces the *separation of concerns* (PRD → architecture → UX as three artefacts) so GATE-PFC has somewhere to look.
