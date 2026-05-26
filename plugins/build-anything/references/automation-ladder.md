# Automation Ladder — Reference

Canonical source: `docs/ubs-v8-technical-hardening.md` Section E. This file expands the per-AL behaviour and the AL-4 circuit breaker.

## Levels

| AL | Name | Agent authority | Required clean history (last N atoms) |
|----|------|------------------|---------------------------------------|
| 0  | MANUAL | none — human writes code | n/a |
| 1  | ASSISTED | agent suggests; human types | n/a |
| 2  | AGENT-WITH-CONFIRM | agent writes; human confirms each commit | n/a |
| 3  | AGENT-AUTONOMOUS | agent autonomous within allowlist; no LAW-10 actions | last 5 atoms PASS all gates |
| 4  | MAX-AUTO | AL-3 + self-heal loop via `/ck:autoresearch` | last 20 atoms PASS + zero rollbacks |

## Promotion (additive to v7.5)

Promotion is **earned**, not granted. The promotion check runs automatically:
- Last K atoms by the same actor (human or agent) all passed GATE-10..21 cleanly
- No GATE FAILs in rolling 7 days
- No LAW violations in rolling 30 days

Failure to meet any → promotion denied with reason.

## Demotion (additive to v7.5)

Automatic on:
- Any GATE-17 FAIL severity HIGH or CRITICAL → demote one rung
- Any GATE-18..21 FAIL → demote one rung (backend integrity is unforgiving)
- Three GATE FAILs of any kind in rolling 24h → demote one rung
- LAW-17 manifest mismatch → demote to AL-0 (evidence tampering is terminal)
- LAW-04 secret leak → demote to AL-0
- LAW-10 violation attempt (agent tried to auto-deploy) → demote to AL-0

## AL-4 Circuit Breaker

AL-4 self-heal loop runs `/ck:autoresearch` against failed gate scripts (per Phase 01 Discovery 2). The breaker has five layers of protection:

### Layer 1 — Per-atom iteration cap
Maximum 5 iterations per atom. Sixth iteration → HALT and demote to AL-3.

### Layer 2 — Per-atom cost cap
Maximum $5 USD per atom (configurable in `.build-anything.json` `al4.max_cost_usd`). Sixth $1 chunk → HALT.

### Layer 3 — Oscillation detector
If two iterations produce the same diff hash, the loop is going in circles. HALT and demote to AL-3.

### Layer 4 — Project-level cost rate limit
If hourly burn exceeds $20 USD project-wide, HALT all AL-4 atoms project-wide until next hour.

### Layer 5 — Manual kill switch
Environment variable `BUILD_ANYTHING_AL4_DISABLE=1` halts all AL-4 atoms immediately. Reserved for boss / oncall override.

## What AL-4 is NOT authorised to do

LAW-10 is PRESERVED VERBATIM from v7.5. AL-4 does NOT bypass LAW-10. AL-4 agent autonomous within mechanical gates ≠ autonomous to deploy. Stage 14 prod-verify still requires user confirmation.

## Per-stage AL behaviour

| Stage | AL ≤ 2 | AL 3 | AL 4 |
|-------|--------|------|------|
| 1 spec | agent drafts; human confirms | agent autonomous | agent autonomous |
| 4 build | agent writes; commit confirmed | agent autonomous | agent autonomous |
| 5-12 gates FAIL | report to human | self-heal loop (max 3 iter) | self-heal loop (max 5 iter, breaker armed) |
| 14 deploy | human confirms | human confirms | human confirms (LAW-10 unchanged) |

## Implementation note

The breaker lives in the orchestrator (`/build-anything` root SKILL.md), NOT in `/ck:autoresearch`. autoresearch is the metric engine; the breaker is the safety harness. This separation keeps `/ck:autoresearch` reusable for non-build use cases.

## Per-actor history tracking

The skill maintains a per-actor ledger at `{project_root}/.build-anything/al-ledger.json`:

```json
{
  "actor:claude-opus-4-7": {
    "current_al": 3,
    "atoms_completed": 23,
    "atoms_passed_all_gates": 21,
    "atoms_failed": 2,
    "last_promotion": "2026-05-20T...",
    "last_demotion": null,
    "halt_reasons_30d": []
  },
  "actor:bachdx@gmail.com": {
    "current_al": 2,
    ...
  }
}
```

Ledger update is append-only-events with periodic compaction. Compaction is the only mutation; events themselves are append-only (LAW-08 alignment).

## Auditor lookup

To answer "why is this actor at AL-X?" run:
```sh
~/.claude/skills/build-anything/scripts/mechanical/al-history.sh actor:{name}
```
Returns the last 50 atom outcomes and current AL with reasoning.
