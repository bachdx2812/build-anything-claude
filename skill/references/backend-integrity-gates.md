# Backend Integrity Gates — Reference

Canonical source: `docs/ubs-v8-technical-hardening.md` Section B (GATE-18 a–f, 19, 20, 21). This file is the operator-facing detail.

## Why this exists

Journal §4.7: UBS v7.5 LAW-03 evidence types are 4-of-5 UI-shaped. UI cannot prove payment correctness, tenant isolation, idempotency, audit, multi-tenant safety, or aggregation correctness.

This reference is the playbook for the 9 sub-gates that close that gap. Each emits machine-readable JSON evidence (not screenshots).

## Sub-gate catalogue

| ID | Sub-gate | Script | Proves |
|----|----------|--------|--------|
| GATE-18a | DB invariant | `db-invariant-check.sh` | named invariants hold (SUM match, FK valid, no orphan, NOT NULL) |
| GATE-18b | Concurrency | `concurrency-test.sh` | parallel POST × N → no duplicate rows, consistent codes |
| GATE-18c | Tx atomicity | `transaction-atomicity-test.sh` | chaos-inject mid-tx → invariants still hold |
| GATE-18d | Background job | `background-job-assertion.sh` | job enqueued AND executed AND side-effect probed |
| GATE-18e | Audit log | `audit-log-assertion.sh` | audit delta == mutation count |
| GATE-18f | Authorization | `authorization-test.sh` | anon→401, wrong-user→403, owner→200 |
| GATE-19 | API contract | `api-contract-test.sh` | Schemathesis / Dredd vs OpenAPI clean |
| GATE-20 | Idempotency | `idempotency-test.sh` | call×2 → single side-effect |
| GATE-21 | Multi-tenant | `multi-tenant-isolation-test.sh` | tenant-A ⊥ tenant-B |

## Config-driven via `.build-anything.json`

Each script reads its config from a `backend` block:

```json
{
  "backend": {
    "db": {
      "url_env": "TEST_DB_URL",
      "driver": "postgres"
    },
    "openapi_path": "openapi.yaml",
    "endpoints_to_test": [
      { "method": "POST", "path": "/orders" },
      { "method": "GET",  "path": "/orders/{id}" }
    ],
    "tenant_fixtures": {
      "tenant_a": { "id": "uuid-a", "user_jwt_env": "TEST_JWT_A" },
      "tenant_b": { "id": "uuid-b", "user_jwt_env": "TEST_JWT_B" }
    },
    "audit_table": "audit_log",
    "background_queues": ["email", "reports"],
    "invariants": [
      {
        "name": "orders_sum_match",
        "query_path": "schema/invariants.sql:orders_sum_match",
        "expect_zero_rows": true
      }
    ]
  }
}
```

## N/A claims require reviewer signoff

A sub-gate marked N/A is a security statement. The backend-integrity reviewer at stage 11 verifies. False N/A → review FAIL.

## Evidence captured per sub-gate

| Sub-gate | Evidence |
|----------|----------|
| 18a | pre-state row counts, query result snapshots, count of violations (must be 0) |
| 18b | request timeline, response codes, post-state row counts, no-duplicate proof |
| 18c | injected failure point, post-state invariant re-run result |
| 18d | queue depth before/after, side-effect probe transcript (e.g. mock email body sha) |
| 18e | audit_log row count before/after, delta == mutation count proof |
| 18f | curl transcripts: anon→401, wrong-user→403, owner→200 |
| GATE-19 | Schemathesis/Dredd report; passing/failing endpoints |
| GATE-20 | curl × 2 with Idempotency-Key; DB row count == 1 |
| GATE-21 | tenant-A login → fetch tenant-B → 403/404; tenant-A query → 0 tenant-B rows |

All evidence emitted as JSON, hashed in LAW-17 manifest.

## Test database hygiene

- Use `TEST_DB_URL` only — never prod
- Transaction-rollback fixture where supported (Postgres, MySQL)
- For mutations that cannot rollback (queue push, external API call), pre-state snapshot + post-state diff
- Idempotency-Key convention follows OASIS standard; project may override

## Common failure modes caught

| Failure mode | Caught by |
|--------------|-----------|
| Payment double-charge | 18b + 20 |
| Tenant data leak | 21 + 18f |
| Aggregation drift | 18a invariant query |
| Stale cache shown as fresh | 18a + 18e (no audit on cache invalidation) |
| Silent worker drop | 18d |
| Optimistic UI hides server fail | 18e (audit not present) + 19 (contract violation) |
| DB constraint violation handled silently | 18a (invariant) + 18c (atomicity) |

## When a sub-gate is hard to implement

If a project's tech stack does not support a sub-gate (e.g. no audit table, no queue), the project owner explicitly marks N/A in `.build-anything.json` with reasoning. The architecture-bridge reviewer at stage 11 reads these and may FAIL the atom if the N/A is dishonest.

## Per-language adapters

`scripts/backend/_common.sh` detects DB driver (postgres / mysql / sqlite / mongo) and provides connection helpers + cleanup hooks. Per-language adapters wrap test runners (Python: Schemathesis; Node: Dredd; etc.).
