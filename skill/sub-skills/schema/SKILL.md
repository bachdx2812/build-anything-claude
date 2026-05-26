---
name: build-anything-schema
description: Stage 2 — generate machine-readable schema artifacts (OpenAPI, JSON Schema, SQL DDL, type definitions) and contract test stubs; enforces allowlist
---

# schema — L2 Schema / Service

**Maps to:** stage 2 of `/build-anything` flow. Output is the contract that downstream stages (build + gate-mechanical + gate-backend + GATE-19) verify against.

## Inputs

- Approved atom brief from `spec` sub-skill (stage 1 + 3 PASS)
- Project schema convention from `.build-anything.json` (`schema.tool`, `schema.dir`)

## Outputs

- `{atom_dir}/schema/openapi.yaml` (if API atom)
- `{atom_dir}/schema/migration.sql` (if DB atom)
- `{atom_dir}/schema/types.ts` or `.py` or `.go` (type definitions)
- `{atom_dir}/schema/contract-test.{ext}` — stub of GATE-19 contract test
- Verdict JSON `{ "stage": 2, "verdict": "PASS|FAIL", "findings": [...] }`

## Atom Type Classification

The sub-skill classifies the atom into one or more of:

| Type | Required outputs |
|------|------------------|
| API endpoint | OpenAPI fragment + contract test stub |
| DB mutation | SQL DDL (migration) + rollback DDL + invariant queries |
| Background job | Queue payload schema + side-effect probe spec |
| Pure UI | Component prop types + visual contract (optional Storybook) |
| Pure library | Public API type signatures + property-test scaffolds |

Multi-type atoms produce multiple artifacts.

## Mechanical Pass Criteria

- All atom criteria from spec map to ≥ 1 schema artifact (no "magic" success criterion without schema)
- Allowlist diff check: only files in allowlist are touched
- Schema lints clean (`spectral` for OpenAPI; `sqlfluff` for SQL; `tsc --noEmit` for TS types)

## GATE-1 Enforcement

Pre-write: read allowlist. Any file path outside the allowlist that this stage would write → HALT before write. No partial writes.

## HALT Conditions

- Allowlist violation
- Spec criterion has no corresponding schema artifact
- Schema lint fails after 2 auto-fix attempts

## Retry Policy

- Schema generation: 2 attempts (auto-fix lint between attempts)
- If still failing, escalate to user

## Tools Used

- `/ck:databases` for DB schema patterns (per Phase 01 Discovery — has psql + invariant query templates)
- `spectral` (OpenAPI lint)
- `sqlfluff` (SQL lint)
- Native type-check for chosen language

## Invariant Hooks for GATE-18a

Every DB mutation in this stage MUST emit one or more invariant queries written to `{atom_dir}/schema/invariants.sql`. These queries are picked up by `gate-backend` sub-skill at stage 6. Pattern:

```sql
-- inv: orders_sum_match
-- expect: 0 rows
SELECT o.id
FROM orders o
LEFT JOIN order_items i ON i.order_id = o.id
GROUP BY o.id, o.total
HAVING o.total <> COALESCE(SUM(i.subtotal), 0);
```

If no invariant query is supplied for a DB mutation atom, this stage FAILs.

## Contract Test Stub for GATE-19

For API atoms, emit:
- Schemathesis (Python) or Dredd (Node) config + a baseline schema fetch line
- Stub assertions for at least: 200 response shape, 4xx for missing required, 5xx not present on validated input

## References

- Schema patterns: `references/schema-conventions.md`
- Backend integrity gates: `references/backend-integrity-gates.md`
- v8.0 GATE-19 spec: `docs/ubs-v8-technical-hardening.md`
