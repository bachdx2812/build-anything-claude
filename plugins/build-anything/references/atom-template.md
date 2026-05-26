# Atom Template — Reference

The atom is the unit of `/build-anything` work. Every atom MUST have these fields.

```yaml
# atom-brief.yaml — produced by spec sub-skill
code: ATOM-{YYYYMMDD}-{slug}            # unique, kebab-case slug
layer: L1                                # starts at L1; advances stage by stage
iter: 1                                  # incremented on retry
title: "human-readable headline"
description: "1-3 sentences"

allowlist:
  - "src/orders/**"
  - "tests/orders/**"
  - "db/migrations/2026_*.sql"

success_criteria:
  - id: SC-1
    type: behavioural
    statement: "POST /orders with {valid_payload} MUST return 201 and persist 1 row in orders"
    test_anchor: "tests/orders/post_orders.spec.ts"
  - id: SC-2
    type: invariant
    statement: "SUM(orders.total) == SUM(order_items.subtotal) for atom-touched rows"
    invariant_query: "schema/invariants.sql:orders_sum_match"
  - id: SC-3
    type: contract
    statement: "Response matches OpenAPI schema component PostOrderResponse"
    contract_anchor: "schema/openapi.yaml#components.schemas.PostOrderResponse"

rollback:
  - flag: "feature_orders_v2"
    action: "flip OFF"
    max_time_seconds: 60
  - migration: "2026_05_26_orders.sql"
    reverse: "2026_05_26_orders_rollback.sql"

declared_budget:
  cost_usd: 5
  iterations: 5
  p95_latency_ms: 200
  bundle_delta_kb: 5

automation_level: 2                       # AL-0..4

predict_failures:                         # filled by /ck:predict
  - "Race condition on parallel POST with same Idempotency-Key"
  - "Tenant-A could craft URL to fetch tenant-B order"
  - "Currency rounding could cause SUM mismatch"

stride_threats:                           # filled by security-bridge reviewer
  spoofing: { considered: true, mitigation: "JWT validated middleware" }
  tampering: { considered: true, mitigation: "Zod schema; signed cookies" }
  repudiation: { considered: true, mitigation: "audit_log table" }
  info_disclosure: { considered: true, mitigation: "owner-only fields in response" }
  dos: { considered: true, mitigation: "rate-limit middleware 100/min/user" }
  elev_priv: { considered: true, mitigation: "RBAC check on every path" }

backend_surfaces:                         # which GATE-18 sub-gates apply
  db_mutation: true
  api_endpoint: true
  background_job: false
  multi_tenant: true
  audit_log: true
  authorization: true

n_a_with_reason:                          # explicit N/A
  GATE-18d (bg-job): "atom has no async work — synchronous request only"
```

## Field rules

- `code` is immutable; rename = new atom
- `allowlist` may NOT be edited after stage 1; expansion = new atom
- `success_criteria` MUST contain at least 1 behavioural AND 1 invariant criterion (no UI-only)
- `rollback` MUST list at least 1 action per layer that mutates state
- `automation_level` decreases on FAIL (per Section E.2 of v8.0)
- `predict_failures` empty → spec-attacker auto-FAIL (suspicious)

## Validation by spec sub-skill

GATE-0 = all required fields present + every success_criterion is testable + rollback present.
