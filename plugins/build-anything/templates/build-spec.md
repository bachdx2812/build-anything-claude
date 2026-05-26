# Build Spec Template

Per UBS v7.5 5-disciplined-documents (BUILD SPEC). Output of stage 1. Lives at `{project_root}/.build-anything/atoms/{atom_code}/spec.md`.

The spec is the contract. The spec-attacker reviewer at stage 10 will try to break it. Write defensively.

```markdown
# BUILD SPEC — {ATOM-CODE}

> **Atom:** {atom_code}
> **Layer:** {L1..L6}
> **Created:** {ISO}
> **AL at creation:** {0..4}
> **Spec author:** {actor}

## 1. Problem statement (WHY)

{3-5 sentences. WHO is blocked, WHAT outcome they need, WHY now. No solution-language allowed — pure problem.}

## 2. User-visible behaviour (WHAT)

### Golden path
{Step-by-step happy path from user POV. Concrete inputs, concrete outputs.}

### Edge cases (enumerated, not exhaustive)
- {edge 1 → expected behaviour}
- {edge 2 → expected behaviour}
- {edge 3 — adversarial input → expected behaviour}

### Out of scope
- {explicit non-behaviour 1}
- {explicit non-behaviour 2}

## 3. Functional requirements

| ID | Requirement | Source |
|----|-------------|--------|
| FR-01 | {testable statement} | {parent initiative / boss / PRD link} |
| FR-02 | {testable statement} | ... |

## 4. Non-functional requirements

| ID | Requirement | Threshold | Measured by |
|----|-------------|-----------|-------------|
| NFR-01 | p95 latency | ≤ 200 ms | `load-test-smoke.sh` |
| NFR-02 | line coverage | ≥ 80% | `coverage-check.sh` |
| NFR-03 | mutation score | ≥ 60% | `mutation-test.sh` |
| NFR-04 | bundle delta | ≤ 5 KB gz | `bundle-budget.sh` |

## 5. Invariants (v8.0 — promoted from "nice to have")

Named SQL queries that MUST return 0 rows at all times. Lives at `schema/invariants.sql`.

```sql
-- invariant: orders_sum_match
-- Every order_total equals SUM(items.qty * items.unit_price)
SELECT o.id
FROM orders o
LEFT JOIN (
  SELECT order_id, SUM(qty * unit_price) AS computed
  FROM order_items
  GROUP BY order_id
) i ON i.order_id = o.id
WHERE COALESCE(i.computed, 0) <> o.total;
```

## 6. Authorisation matrix

| Role | Endpoint/Op | Allowed |
|------|-------------|---------|
| anon | POST /orders | 401 |
| user(tenant=A) | POST /orders {tenant_id:A} | 201 |
| user(tenant=A) | POST /orders {tenant_id:B} | 403 |
| admin | * | per OPA policy |

## 7. Data model deltas

```sql
-- migration: schema/migrations/0042_orders.sql (v8.0 stage 2 output)
CREATE TABLE orders (...);
ALTER TABLE ...;
```

Reverse migration MUST exist at same path with `.down.sql` suffix.

## 8. Idempotency contract

| Operation | Idempotency-Key header | Behaviour |
|-----------|------------------------|-----------|
| POST /orders | required, max 64 chars | 201 first, then 200 + same id on retry |

## 9. Audit log requirements

Every mutation must emit one row to `audit_log` with:
- `actor_id`, `action`, `entity_id`, `before_state_hash`, `after_state_hash`, `at_timestamp`

Verified by GATE-18e (audit-log-assertion).

## 10. Observability requirements

Every code path must emit:
- structured log line (correlation_id, atom_code, action)
- one metric (counter or histogram)
- one trace span if request-bound

Verified by GATE-15 (observability-check).

## 11. Acceptance test list (≥ 1 per FR/NFR)

- [ ] {test 1 → maps to FR-01}
- [ ] {test 2 → maps to FR-02}
- [ ] {test for each edge in §2}
- [ ] {invariant check after each mutation}

## 12. Adversarial scenarios (spec-attacker reviewer feeds on these)

Author MUST enumerate at least 5 attempts to break the spec:
1. {what if user submits malformed payload}
2. {what if network drops mid-tx}
3. {what if two requests arrive simultaneously with same key}
4. {what if upstream tenant claim is spoofed}
5. {what if DB constraint fires}

Each → expected behaviour MUST be specified.

## 13. Rollback plan

- Migration: `0042_orders.down.sql` reverses all changes
- Code: previous git_sha at `{prev_sha}`
- Drill: `evidence/verify/rollback-drill.json` proves rollback time ≤ 60s

## 14. Open questions

- [ ] {anything unresolved — DO NOT proceed until ≤ 0 open}

---
> **Spec compliance reviewer (stage 11) PASSES only if § 1-13 all populated and acceptance criteria are testable.**
```

## How this template is filled

1. Spec sub-skill (stage 1) drafts §1-7 + §10-14
2. Schema sub-skill (stage 2) populates §5 invariant SQL + §7 migration
3. Implementer sub-skill (stage 4) cross-references §11 acceptance tests
4. Reviewers at stages 10-11 use §12 adversarial scenarios as starting fuel

## Length budget

Spec ≤ 400 lines. Longer = decompose into smaller atoms.
