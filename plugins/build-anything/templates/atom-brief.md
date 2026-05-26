# Atom Brief Template

Per UBS v7.5 Atom Shape (W3.2) + v8.0 hardening additions. Copy this YAML to `{project_root}/.build-anything/atoms/{atom_code}/atom-brief.yaml` at stage 1.

```yaml
# ─── Identity ────────────────────────────────────────────────
atom_code: "ATOM-{YYMMDD}-{slug}"          # e.g. ATOM-260526-orders-create
atom_layer: "L1_REQUIREMENTS"              # L1..L6 per UBS v7.5 6-layer chain
parent_initiative: "{init-code}"            # the larger initiative this rolls up to
created_at: "{ISO-8601}"
created_by: "actor:{name}"                  # human email or agent id
al_level: 3                                  # AL-0..AL-4 at time of creation

# ─── Scope (NARROW) ──────────────────────────────────────────
title: "{one sentence, ≤ 80 chars}"
goal: |
  {3-5 sentences: WHY this exists, WHAT the user gains, WHAT measurable change}
non_goals: |
  - {explicit list of things this atom does NOT do}
  - {prevents scope creep at review time}
files_in_scope:                              # ALLOWLIST LAW (v7.5 W1 LAW-05)
  - "src/orders/post.ts"
  - "src/orders/post.test.ts"
  - "schema/migrations/0042_orders.sql"
files_out_of_scope:                          # explicit deny — touching these = HALT
  - "src/auth/**"
  - "infra/**"

# ─── Specification anchors ───────────────────────────────────
requirements:
  functional:
    - "POST /orders accepts { tenant_id, items[], idempotency_key }"
    - "Returns 201 with order_id; persists row in orders table"
  non_functional:
    - p95_latency_ms: 200
    - availability: "99.9%"
acceptance_criteria:
  - "Given valid payload → 201 + DB row"
  - "Given duplicate idempotency_key → 201 + same order_id (no new row)"
  - "Given missing tenant claim → 401"
  - "Given foreign tenant_id → 403"

# ─── Schema first (v8.0 stage 2) ─────────────────────────────
schema:
  openapi_path: "schema/openapi.yaml#/paths/~1orders/post"
  migration_path: "schema/migrations/0042_orders.sql"
  invariants_sql: "schema/invariants.sql"   # named queries returning 0 rows
  types_ts: "schema/types.ts"               # for FE consumption

# ─── Gates that fire ─────────────────────────────────────────
gates_required:
  - GATE-10            # coverage
  - GATE-11            # mutation
  - GATE-16            # property
  - GATE-17            # security
  - GATE-18a-f         # backend integrity (this atom touches DB + tenant)
  - GATE-19            # API contract
  - GATE-20            # idempotency
  - GATE-21            # multi-tenant
gates_na:                                    # explicit N/A claims (reviewer verifies)
  - id: GATE-14-fe
    reason: "BE-only atom, no frontend page touched"

# ─── Reviewer set (v8.0 stage 10-11) ─────────────────────────
review_roles:
  - spec-attacker
  - spec-compliance
  - code-quality
  - backend-integrity                       # required: atom touches DB
  - security-bridge

# ─── Budget ──────────────────────────────────────────────────
budget:
  max_cost_usd: 5
  max_iterations: 5
  expected_time_min: 25

# ─── Evidence destinations (v8.0 LAW-17) ─────────────────────
evidence_dir: "{project_root}/.build-anything/atoms/{atom_code}/"

# ─── Stage 14 deployment ─────────────────────────────────────
deploy:
  target_env: "prod"
  human_confirm_required: true              # LAW-10 — NEVER false
  rollback_drill_required: true
  post_deploy_smoke: "scripts/smoke/orders-create.sh"
```

## Field discipline

| Field | Hard rule |
|-------|-----------|
| `files_in_scope` | Allowlist. Build agent CANNOT touch files outside this list. Violation → atom HALT |
| `gates_na` | Each N/A requires reason. Architecture-bridge reviewer at stage 11 may reject |
| `human_confirm_required` | `false` is a LAW-10 violation. Never set false even at AL-4 |
| `max_cost_usd` | AL-4 circuit breaker triggers at this value. Default $5, cap $20/hr/project |

## How agents fill this

- Spec sub-skill (stage 1) drafts fields: title, goal, non_goals, requirements, acceptance_criteria
- Schema sub-skill (stage 2) fills `schema:` block
- Orchestrator computes `gates_required` from atom type (FE/BE/cross-module)
- Reviewer set follows `multi-agent-review-protocol.md` table

## Validation

Before stage 4 (build), orchestrator runs:
```sh
~/.claude/skills/build-anything/scripts/mechanical/validate-atom-brief.sh atom-brief.yaml
```
Schema mismatch → HALT before any code written.
