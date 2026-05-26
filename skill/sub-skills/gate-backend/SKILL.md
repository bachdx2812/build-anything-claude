---
name: build-anything-gate-backend
description: Stage 6 — backend integrity gates (DB invariants, idempotency, concurrency, tx atomicity, API contract, bg job, multi-tenant, audit, authz, rate-limit, cache); the differentiator from UI-shaped evidence
---

# gate-backend — Stage 6 Backend Integrity (v8.1)

**Maps to:** stage 6 of `/build-anything` flow. Implements LAW-14 + GATE-18 (a–f) + GATE-19 + GATE-20 + GATE-21 + GATE-23 + GATE-24. **This stage is THE differentiator vs v7.5 — UI screenshot cannot prove any of these.**

## When This Stage Runs

Applies when atom touches server, API, DB, or async work. Frontend-only atom → stage marked N/A (with reviewer signoff).

## Inputs

- Atom diff from stage 4
- Schema artifacts from stage 2 (especially `invariants.sql`)
- `.build-anything.json` `backend` block:
  - `db.url` (env reference; never plain text)
  - `openapi_path`
  - `tenant_fixtures.{tenant_a, tenant_b}`
  - `endpoints_to_test`
  - `audit_table`
  - `background_queues`
  - `invariants` (list of named queries)

## Sub-Gates Executed

| ID | Script | Pass criteria |
|----|--------|---------------|
| GATE-18a DB invariant | `scripts/backend/db-invariant-check.sh` | every invariant query returns 0 violation rows |
| GATE-18b Concurrency | `scripts/backend/concurrency-test.sh` | parallel POST × N → no duplicate rows, no constraint violation, consistent codes |
| GATE-18c Tx atomicity | `scripts/backend/transaction-atomicity-test.sh` | chaos-inject mid-tx → invariants still hold post-rollback |
| GATE-18d Background job | `scripts/backend/background-job-assertion.sh` | job enqueued AND executed AND side-effect probed |
| GATE-18e Audit log | `scripts/backend/audit-log-assertion.sh` | audit delta == mutation count |
| GATE-18f Authorization | `scripts/backend/authorization-test.sh` | anon→401, wrong-user→403, owner→200 per endpoint |
| GATE-19 API contract | `scripts/backend/api-contract-test.sh` | Schemathesis / Dredd vs OpenAPI clean |
| GATE-20 Idempotency | `scripts/backend/idempotency-test.sh` | call×2 → single side-effect |
| GATE-21 Multi-tenant | `scripts/backend/multi-tenant-isolation-test.sh` | tenant-A ⊥ tenant-B |
| GATE-23 Rate limit (v8.1) | `scripts/backend/rate-limit-test.sh` | burst → 429 + Retry-After present |
| GATE-24 Cache invariant (v8.1) | `scripts/backend/cache-invariant-test.sh` | Cache-Control/ETag/Vary present + write-through correct |

## Parallel Execution

All applicable sub-gates run in parallel against an isolated test DB (`TEST_DB_URL`). Test DB seeded fresh per atom. Cleanup wraps every run in a transaction-rollback fixture where possible.

## HALT Conditions

- Any sub-gate FAIL
- Test DB unreachable (config error)
- Tenant fixtures missing for multi-tenant project
- Audit table specified but does not exist in DB

## Why "N/A" Requires Reviewer Signoff

A sub-gate marked N/A is a claim: "this atom does not touch the surface this gate covers." That claim is itself a security statement. The backend-integrity reviewer (Phase 04 prompt) verifies the N/A claim is true. False N/A → review FAIL → atom HALT.

## Outputs

- `{atom_dir}/gate-backend/{gate-id}.json` per sub-gate
- Verdict `{ "stage": 6, "verdict": "PASS|FAIL", "findings": [...], "n_a": [...] }`

## Evidence Captured (feeds Stage 13)

- Pre-state DB row counts
- Post-state DB row counts
- Audit log diff
- Contract test report
- Concurrency call log with response codes
- Tenant-isolation probe transcript

All emitted as JSON, not screenshots — directly hashable into LAW-17 manifest.

## Retry Policy

- AL ≤ 2: HALT and return to user
- AL ≥ 3: `/ck:autoresearch` self-heal on the specific failing sub-gate; max 5 iter; respects AL-4 breaker

## Test Data Hygiene

- TEST_DB credentials only — never prod
- Transaction-rollback fixture where supported
- For mutation tests that cannot rollback (e.g. queue push), pre-state snapshot + post-state diff
- Idempotency test uses `Idempotency-Key` header convention; project may override

## References

- Scripts spec: Phase 06 deliverable
- v8.0 GATE-18..21 spec: `docs/ubs-v8-technical-hardening.md` Section B
- Failure modes addressed: journal §4.7 (payment double-charge, tenant leak, aggregation drift, etc.)
- Config schema: `references/build-anything-config.md`
