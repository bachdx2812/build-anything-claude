# Seeded Bugs — Toy Project for `/build-anything` Dry-Run

**Purpose:** seed 13 known defects across the toy app so each gate has a target to catch. If a gate misses its bug → gate logic must be fixed before shipping the skill.

**Atom under test:** `ATOM-001-orders-create` (POST `/api/orders` + LIST + GET by id).

| # | Bug ID | File:Line | Description | Expected Catcher | Severity if missed |
|---|--------|-----------|-------------|------------------|--------------------|
| 1 | BUG-01 | `tests/orders.test.js:7,13` | Assertions only check truthy / fixed sum; mutated branch logic still passes | GATE-11 (mutation) | CRITICAL — silent regression vector |
| 2 | BUG-02 | `tests/orders.test.js:13` | `Date.now() % 3` branch in route never exercised | GATE-10 (coverage) | HIGH |
| 3 | BUG-03 | `backend/server.js:10` | Hardcoded `sk-proj-...` in source | LAW-04 secret scan + security-bridge reviewer | CRITICAL — credential leak |
| 4 | BUG-04 | `backend/routes/orders.js:26` | SQL string-concat (`note`) — injection vector | security-bridge + property-test fuzz | CRITICAL |
| 5 | BUG-05 | `backend/routes/orders.js:35-39` | N+1 query loop on `?refresh=1` | GATE-14 perf budget (p95) + code-quality reviewer | HIGH |
| 6 | BUG-06 | `backend/server.js` (absence) | No logging middleware → no request_id/log_event | GATE-15 observability scan | MEDIUM |
| 7 | BUG-07 | `backend/routes/orders.js:21` | `total` sometimes != SUM(items.amount) → invariant violation | GATE-18a `db-invariant-check.sh` via `orders_sum_match` | CRITICAL |
| 8 | BUG-08 | `backend/routes/orders.js` (absence) | Mutation writes order/items but never inserts audit_log | GATE-18e `audit-log-assertion.sh` (silent 2xx) | CRITICAL — fraud blind spot |
| 9 | BUG-09 | `backend/routes/orders.js:18-31` | Idempotency-Key ignored → POST×2 same key = 2 rows | GATE-20 `idempotency-test.sh` + GATE-18b concurrency | HIGH |
| 10 | BUG-10 | `backend/routes/orders.js:13` | LIST omits `WHERE tenant_id=$t` → cross-tenant leak | GATE-21 `multi-tenant-isolation-test.sh` (leak_in_body) | CRITICAL — compliance breach |
| 11 | BUG-11 | `backend/routes/orders.js:46` | GET by id no tenant check → wrong tenant gets 200 | GATE-18f `authorization-test.sh` | CRITICAL |
| 12 | BUG-12 | `backend/routes/orders.js:33-34` | Job enqueued but no worker → never executed; side-effect file absent | GATE-18d `background-job-assertion.sh` | HIGH |
| 13 | BUG-13 | `frontend/app.js:3` | Frontend imports DB driver token — UI → DB layering violation | architecture-bridge reviewer (`everything-claude-code:architect`) | HIGH |

## Bonus (spec-attacker target)

The atom-brief sample for ATOM-001 deliberately omits: (a) what happens on partial item insert failure, (b) max order total, (c) authz for tenant-admin vs tenant-user. **Expected: spec-attacker reviewer flags ≥3 ambiguities → atom blocked at Stage 2.**

## Bonus (AL-4 oscillation)

If first 2 fix iterations swap BUG-09 and BUG-10 back and forth (i.e., fixing one breaks the other), AL-4 circuit breaker must demote to AL-0 after 3 oscillation cycles.

## Verification matrix

| Gate | Script / Reviewer | Bug(s) |
|------|-------------------|--------|
| LAW-04 | `_common.sh::require_test_db` + `security-bridge` regex | BUG-03 |
| GATE-10 | `coverage-check.sh` | BUG-02 |
| GATE-11 | `mutation-test.sh` | BUG-01 |
| GATE-14 | `load-test-smoke.sh` | BUG-05 |
| GATE-15 | `observability-check.sh` | BUG-06 |
| GATE-16 | `property-test-runner.sh` | BUG-04 (fuzzed note) |
| GATE-18a | `db-invariant-check.sh` | BUG-07 |
| GATE-18b | `concurrency-test.sh` | BUG-09 |
| GATE-18c | `transaction-atomicity-test.sh` | (no bug — should PASS to prove no false-positive) |
| GATE-18d | `background-job-assertion.sh` | BUG-12 |
| GATE-18e | `audit-log-assertion.sh` | BUG-08 |
| GATE-18f | `authorization-test.sh` | BUG-11 |
| GATE-19 | `api-contract-test.sh` | (no bug — should PASS) |
| GATE-20 | `idempotency-test.sh` | BUG-09 (duplicate target) |
| GATE-21 | `multi-tenant-isolation-test.sh` | BUG-10 |
| architecture-bridge | reviewer | BUG-13 |
| spec-attacker | reviewer | ambiguous spec |

## What this proves

If every row above turns red on a known-buggy toy → green on a clean toy, the skill demonstrably catches the things UI-screenshot evidence misses. **This is the boss-facing demo.**
