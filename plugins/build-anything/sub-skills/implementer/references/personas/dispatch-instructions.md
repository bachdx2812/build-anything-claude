# Stage 4 dispatch instructions (BMAD-method implementer, v8.4)

The skill internalises BMAD's multi-persona pattern at the BUILD stage. Three personas — backend, frontend, tests — work in parallel within their allowlist subsets. Same wall-clock benefit as Stage 1.B: total time ≈ max(B, F, T) rather than B+F+T.

There is **no** dependency on any `npx` workflow. Persona prompts live in `references/personas/`; dispatch happens via Claude Code's `Agent` (Task) tool.

## When to dispatch multi vs single

Resolved from the atom's allowlist by `scripts/implementer/concern-split.sh`:

| Allowlist shape | Mode | Reason |
|-----------------|------|--------|
| ≥ 2 concern groups present (backend ∧ frontend, or any pair + tests) | `multi-persona` | Genuine parallelism available. |
| Single concern group (e.g. backend-only or frontend-only atom) | `single-persona` | No parallelism to extract; one fullstack-developer agent. |
| Allowlist is a single file (< 50 LOC bug fix) | `single-persona` (forced) | Persona overhead > work. |
| `--fast` flag | `single-persona` (forced) | Caller has opted in to lower thresholds. |
| `--strict` flag | `multi-persona` (when ≥ 2 concerns) | Maximise independent context coverage. |

The split script writes `{atom_dir}/implementer/concern-split.json`:

```json
{
  "mode": "multi-persona",
  "concerns": {
    "backend":  { "globs": ["backend/**","api/**","db/migrations/**"], "files": [...], "dispatch": true },
    "frontend": { "globs": ["frontend/**","src/components/**","*.tsx"], "files": [...], "dispatch": true },
    "tests":    { "globs": ["e2e/**","tests/e2e/**","playwright/**"],   "files": [...], "dispatch": true }
  },
  "uncategorised": []
}
```

If any allowlist glob does not match a known concern → it lands in `uncategorised`. Reviewer must categorise before dispatch or the atom HALTs (LAW-F6: unknown allowlist surface is not a vacuous PASS).

## Dispatch protocol

When Stage 4 is reached, Claude (the orchestrator) MUST:

1. Verify Stage 3 (red-team spec) returned PASS.
2. Run `scripts/implementer/concern-split.sh --atom-dir <dir>` to produce `concern-split.json`.
3. If `mode == "single-persona"` → spawn one `fullstack-developer` agent with the full allowlist + TDD discipline (existing Stage 4 behaviour, unchanged).
4. If `mode == "multi-persona"` → dispatch the relevant personas in **a single message** with multiple `Agent` (Task) calls so they run concurrently:

   ```
   Task 1 — Dev-Backend persona  (if concerns.backend.dispatch)
     prompt: contents of references/personas/dev-backend-persona.md
             + "Atom dir: {atom_dir}. Project root: {project_root}.
                Your allowlist subset: {concerns.backend.globs}.
                Test runner: {.build-anything.json#stack.test_cmd}.
                Commit in TDD order: test (red) → feat (green) → refactor (optional).
                Write status report to {atom_dir}/implementer/backend-status.json on exit."

   Task 2 — Dev-Frontend persona  (if concerns.frontend.dispatch)
     prompt: contents of references/personas/dev-frontend-persona.md
             + "Atom dir: {atom_dir}. Allowlist subset: {concerns.frontend.globs}.
                Backend API contract: {atom_dir}/architecture.md#API surface.
                UX spec: {atom_dir}/ux-spec.md.
                Same TDD + status-report rules."

   Task 3 — Dev-Tests persona  (if concerns.tests.dispatch)
     prompt: contents of references/personas/dev-tests-persona.md
             + "Atom dir: {atom_dir}. Allowlist subset: {concerns.tests.globs}.
                core_flows[] from intent/verdict.json MUST each be covered.
                Wait for backend+frontend RED commits before writing the GREEN test commit."
   ```

5. After all dispatched Tasks return, run `scripts/implementer/implementer-coverage-gate.sh --atom-dir {atom_dir} --project-root {project_root}`. This gate verifies:
   - Every dispatched persona wrote its `*-status.json` report.
   - Every concern in `concerns.*.dispatch == true` has actual `files_changed` in its report.
   - No persona's commits touched files outside its allowlist subset.
   - Each `verdict.json#core_flows[]` is in `tests-status.json#core_flows_covered`.
   - LAW-02 invariant: union of persona allowlists = atom allowlist; intersections are empty (no overlap).

6. On gate FAIL: identify which persona reported `PENDING_*` or which concern is missing coverage. Re-dispatch the single failing persona with the gate's `details.violations[]` as additional context. Max 2 retries per persona before HALT.

## Persona overlap rule (critical)

The three personas MUST own DISJOINT file sets. If two personas both have permission to edit `frontend/api-client.ts`, the second commit will conflict with the first.

`concern-split.sh` enforces:

- Each allowlist file appears in exactly one concern.
- If a file is ambiguous (e.g. shared `types/api.d.ts` that both backend and frontend reference), it is assigned to **backend** by default, with a `cross-concern` flag set. The frontend persona is told to consume it read-only.

Shared schema types are generated, not handwritten. If your project handwrites shared types, the architect persona MUST split them into separate per-concern files at Stage 1.B — re-dispatch Stage 1.B if missing.

## What this prevents

| Failure mode addressed | How |
|------------------------|-----|
| Single-author bias in implementation (same agent rationalises FE+BE+tests around its own first decision) | Fresh persona contexts |
| Sequential wall-time (B → F → T can be ≈ 30 min total) | Parallel dispatch ≈ max(10, 12, 8) = 12 min |
| Overlapping file edits causing merge conflicts | Disjoint allowlist subsets enforced by `concern-split.sh` |
| Tests written by the same agent that wrote the code (teaching-to-the-test) | Dev-tests persona is a separate context; only sees PRD + architecture, not the implementer's reasoning |
| Frontend invents endpoints the backend didn't expose | Frontend persona consumes `architecture.md#API surface` as a contract; raises `PENDING_ARCHITECT:` if wrong rather than forking |

## Fallback paths

- **Concern-split returns 1 concern** → single-persona mode, full fullstack-developer agent. The `implementer-coverage-gate.sh` still runs but expects exactly one `{concern}-status.json`.
- **A persona reports `PENDING_DISPATCHER`** → orchestrator pauses, surfaces the question to the user, and resumes after answer. The `PENDING_DISPATCHER` text MUST be the exact action needed (e.g. "expand allowlist to include `shared/types/`").
- **Persona Task returns no `*-status.json`** → gate emits `ERROR` (silent-drop guard, LAW-F6 at Stage 4 level). Re-dispatch the missing persona; if it fails twice → HALT.

## Output checklist (gate enforces)

`multi-persona`:
- `{atom_dir}/implementer/concern-split.json` exists with `mode: "multi-persona"`
- For each `concerns.<x>.dispatch == true`: `{atom_dir}/implementer/<x>-status.json` exists with `verdict ∈ { PASS, PENDING }`
- Union of all `files_changed[]` ⊆ original atom allowlist
- For each persona: `files_changed[]` ⊆ that persona's `allowlist_subset`
- `tests-status.json.core_flows_covered[]` ⊇ `intent/verdict.json.core_flows[]`

`single-persona`:
- `{atom_dir}/implementer/concern-split.json` exists with `mode: "single-persona"`
- `{atom_dir}/implementer/single-status.json` exists with `verdict ∈ { PASS, PENDING }`
- `files_changed[]` ⊆ atom allowlist
- Stage 5 (mechanical) still enforces TDD evidence + GATE-25-E2E core-flow coverage
