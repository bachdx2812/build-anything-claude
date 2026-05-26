---
name: build-anything-spec
description: Stages 1 + 3 — generate spec atom and adversarial red-team review of spec; outputs a testable atom brief or HALTs with ambiguity findings
---

# spec — L1 Spec Atom + Red-Team

**Maps to:** stage 1 (spec atom generation) and stage 3 (red-team spec) of `/build-anything` flow. Implements LAW-12 (adversarial framing) at spec layer.

## Inputs

- 1–3 sentence feature description from user / orchestrator
- `.build-anything.json` project config
- (optional) parent plan reference from `## Plan Context`

## Outputs

- `{atom_dir}/spec.md` — atom brief
- `{atom_dir}/verdicts.json` entry `{ "stage": 1, "verdict": "PASS|FAIL", "findings": [...] }`
- Red-team verdict in `{atom_dir}/verdicts.json` stage 3

## Atom Brief Structure (required fields)

```yaml
code: ATOM-{yyyymmdd}-{slug}
layer: L1
iter: 1
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

## Mechanical Pass Criteria

- GATE-0 (atom brief complete) → all required fields present
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

## Tools Used

- `/ck:plan` template for atom brief
- `/ck:predict` for failure forecast
- Skill tool to spawn spec-attacker subagent (fresh context, no implementer history)

## References

- Reviewer prompt: `references/reviewer-prompts/spec-attacker.md`
- Atom template: `templates/atom-brief.md`
- LAW-12 multi-agent review: `docs/ubs-v8-technical-hardening.md` §Section A
