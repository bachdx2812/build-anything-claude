# Phase 06 — Backend Integrity Gate Scripts (9 sub-gates)

## Context Links

- Journal Section 4.7 (P0 NEW finding — UI-bias + backend verification absent)
- UBS v8.0 GATE-18/19/20/21 + LAW-14 (Phase 02 output)
- Phase 03 sub-skills/gate-backend/SKILL.md

## Overview

- Priority: P0 (addresses core gap user identified)
- Status: pending
- Brief: 9 scripts proving backend correctness UI cannot — DB invariant + idempotency + concurrency + tx-atom + contract + bg-job + multi-tenant + audit + authz

## Key Insights

- This phase IS the differentiator from boss's UBS — UI-screenshot evidence model fundamentally cannot prove these
- Each script must produce machine-readable proof artifact (not screenshot)
- Multi-tenant + authz are app-architecture-dependent → scripts need config hooks
- Idempotency + concurrency are testable on staging with seed data

## Requirements

**Functional script list:**

| Script | Sub-gate | What it proves | Tool/approach |
|--------|----------|----------------|---------------|
| `db-invariant-check.sh` | GATE-18a | SUM matches, no orphan, FK valid, NOT NULL satisfied | psql/mysql query templates from `.build-anything.json` |
| `idempotency-test.sh` | GATE-20 | call×2 → single side effect | curl/httpie + DB row count |
| `concurrency-test.sh` | GATE-18b | parallel call → no race | xargs -P N + DB row uniqueness check |
| `transaction-atomicity-test.sh` | GATE-18c | inject failure mid-tx → rollback complete | error injection middleware + invariant re-check |
| `api-contract-test.sh` | GATE-19 | request/response match schema | Schemathesis/Dredd against OpenAPI |
| `background-job-assertion.sh` | GATE-18d | job enqueued AND executed AND side-effect landed | queue inspect + DB/external state probe |
| `multi-tenant-isolation-test.sh` | GATE-21 | tenant A cannot read/write tenant B | dual-tenant test fixture + cross-fetch probe |
| `audit-log-assertion.sh` | GATE-18e | every mutation produces audit entry | DB audit table count delta == mutation count |
| `authorization-test.sh` | GATE-18f | each endpoint enforces ownership | unauth + cross-user fetch attempts |

**Non-functional:**
- Each script ≤ 150 LOC (more complex than mechanical)
- Config-driven via `.build-anything.json` (DB conn, OpenAPI path, tenant fixtures)
- JSON output to stderr (exit code reflects pass/fail)
- Idempotent runs (don't pollute test data)

## Architecture

```
~/.claude/skills/build-anything/scripts/backend/
├── _common.sh                              # DB conn, fixture loader, cleanup
├── db-invariant-check.sh
├── idempotency-test.sh
├── concurrency-test.sh
├── transaction-atomicity-test.sh
├── api-contract-test.sh
├── background-job-assertion.sh
├── multi-tenant-isolation-test.sh
├── audit-log-assertion.sh
└── authorization-test.sh
```

`.build-anything.json` schema fragment:
```json
{
  "backend": {
    "db": { "url": "ENV:TEST_DB_URL", "driver": "postgres" },
    "openapi_path": "openapi.yaml",
    "tenant_fixtures": { "tenant_a": {...}, "tenant_b": {...} },
    "invariants": [
      { "name": "orders_sum_match", "query": "SELECT ..." }
    ],
    "endpoints_to_test": ["GET /users/{id}", "POST /orders"],
    "audit_table": "audit_log",
    "background_queues": ["email", "reports"]
  }
}
```

## Related Code Files

**Create:** 9 scripts + `_common.sh`

**Modify:**
- `sub-skills/gate-backend/SKILL.md` → reference these scripts
- Template `.build-anything.json` schema

## Implementation Steps

1. Write `_common.sh` — DB conn helper, fixture loader, cleanup hooks
2. Write `db-invariant-check.sh` — iterate user-defined invariant queries, expect 0 rows for violation queries
3. Write `idempotency-test.sh` — POST endpoint twice with same Idempotency-Key header, assert single DB row inserted
4. Write `concurrency-test.sh` — `xargs -P 10` parallel POST, assert no duplicate rows AND no DB constraint violation AND response codes consistent
5. Write `transaction-atomicity-test.sh` — invoke endpoint with chaos-monkey middleware that kills connection at 50% of operations, verify DB invariants hold after each
6. Write `api-contract-test.sh` — Schemathesis-driven against OpenAPI, fail on any contract drift
7. Write `background-job-assertion.sh` — trigger mutation, poll queue, assert job processed, probe external side-effect (email mock, S3 object, etc.)
8. Write `multi-tenant-isolation-test.sh` — login as tenant-A, fetch tenant-B resources, expect 403/404; attempt write to tenant-B, expect 403
9. Write `audit-log-assertion.sh` — pre-count audit_log rows, execute mutations, post-count, assert delta == expected
10. Write `authorization-test.sh` — for each endpoint: anon→401, wrong-user→403, owner→200
11. Test each on toy project staging (Phase 07)

## Todo List

- [ ] _common.sh
- [ ] db-invariant-check.sh
- [ ] idempotency-test.sh
- [ ] concurrency-test.sh
- [ ] transaction-atomicity-test.sh
- [ ] api-contract-test.sh
- [ ] background-job-assertion.sh
- [ ] multi-tenant-isolation-test.sh
- [ ] audit-log-assertion.sh
- [ ] authorization-test.sh

## Success Criteria

- All 9 scripts executable
- Each emits JSON evidence (not screenshot)
- Cumulative evidence bundle generated per atom
- Toy project passes all 9 gates after fix; fails on seeded bug
- Config-driven (no hardcoded URLs/DB)

## Risk Assessment

- Schema-specific scripts (mitigation: parameterize via config)
- Test data pollution (mitigation: transaction-rollback wrappers, isolated test DB)
- Background job timing flake (mitigation: exponential backoff poll up to N seconds)
- Multi-tenant fixtures complexity (mitigation: minimal fixture template, document scaling)
- Chaos engineering depth (mitigation: stop at single-failure injection; chaos full = future phase)

## Security Considerations

- Test scripts use TEST DB credentials only (LAW-04 enforce)
- Cross-tenant probes use isolated fixtures
- Authorization test does not exploit found vulns — only reports

## Next Steps

- Phase 07 dry-run validates on toy project
- Phase 08 red-team challenges these gates
