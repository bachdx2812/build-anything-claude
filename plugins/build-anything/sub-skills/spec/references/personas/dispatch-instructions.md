# Stage 1.B dispatch instructions (BMAD-method, not BMAD-invocation)

The skill internalises BMAD's multi-persona pattern. There is **no** dependency on `npx bmad-method run` (which does not exist in the BMAD CLI). The npx package is installed only when present and used informationally; absence is not a blocker.

## How Claude dispatches Stage 1.B

When the skill reaches Stage 1.B, Claude (the orchestrator) MUST:

1. Confirm Stage 1.A artefact exists: `{atom_dir}/research/product-features-<slug>.md`.
2. Confirm `{atom_dir}/intent/verdict.json.next_action == "READY"`.
3. Decide dispatch mode:
   - **default** → `multi-persona` (3 parallel Task dispatches)
   - **`--fast`** → `single-persona` (one combined Task dispatch)
   - **`--strict`** → `multi-persona` AND red-team review of each artefact before Stage 1.C

4. Dispatch personas via `Task` tool (Agent tool in Claude Code), one call per persona, **in a single message** so they run concurrently:

   ```
   Task 1 — PM persona
   prompt: contents of sub-skills/spec/references/personas/pm-persona.md
           + "Atom dir: {atom_dir}. Project root: {project_root}. Read inputs listed in the persona file. Produce {atom_dir}/prd.md."

   Task 2 — Architect persona
   prompt: contents of sub-skills/spec/references/personas/architect-persona.md
           + "Atom dir: {atom_dir}. Project root: {project_root}. PRD will appear at {atom_dir}/prd.md once Task 1 completes. If Task 1 has not finished, read research + intent first; reconcile with PRD after."

   Task 3 — UX persona
   prompt: contents of sub-skills/spec/references/personas/ux-persona.md
           + "Atom dir: {atom_dir}. Project root: {project_root}. PRD + architecture will appear once Tasks 1+2 complete. Begin from research + intent if those are not yet ready."
   ```

5. After all three Tasks return, run `scripts/spec/bmad-prd-gate.sh --atom-dir {atom_dir} --project-root {project_root}` (mode auto-resolves).
6. If gate FAILs: identify which persona's artefact is incomplete, dispatch that single persona again with the gate's `details.artefacts[].status` as context. Max 2 retries per persona.
7. If 2 retries still FAIL → HALT, escalate to user with structured failure (which persona, which section).

## Why dispatching via Task is the right invocation

- Each persona runs in a fresh context — no cross-pollination of priors, which is the failure mode v8.1 hit (single-author spec).
- Personas run in parallel — wall time = max(P, A, U) not P+A+U.
- The persona prompts live in this skill, not in an external package — no `npx` race, no version drift, no install failure.
- The gate verifies **outputs**, not the dispatch — if a future Claude version improves persona dispatch, the gate still passes.

## What `bmad-method` (the npx package) does and does NOT do

| Capability | Status |
|------------|--------|
| `npx bmad-method install` | works — installs agent persona files into project. Used by `ensure-deps.sh` to detect presence. |
| `npx bmad-method status` | works — reports installed modules. |
| `npx bmad-method run` | **does not exist.** Earlier skill versions referenced this command in error. |
| BMAD agent files at `_bmad/bmm/agents/*.md` | These ARE the personas BMAD's docs assume Claude will read. The skill's own persona files (this directory) supersede them and are self-contained. |

## When to fall back to single-persona

Only when `--fast` is set AND the atom is genuinely small (single file, < 50 LOC, no cross-component change). The single-persona output MUST still contain Vision + MVP Scope + Acceptance Criteria sections with body — the gate enforces this. Combined PRDs frequently miss the architectural reconciliation step; the gate cannot detect that omission, so the cost of choosing single-persona is paid downstream at GATE-STACK or GATE-PFC.

## Output checklist (the gate enforces these mechanically)

`multi-persona` mode:
- `{atom_dir}/prd.md` — sections `Vision`, `MVP Scope`, `Acceptance Criteria` each with body
- `{atom_dir}/architecture.md` — sections `Stack`, `Components`, `Data model` each with body
- `{atom_dir}/ux-spec.md` — sections `Page inventory`, `Per-page UX`, `Accessibility` each with body

`single-persona` mode:
- `{atom_dir}/prd.md` — sections `Vision`, `MVP Scope`, `Acceptance Criteria` each with body

Any header without a body line = stub = FAIL. The gate does not negotiate.
