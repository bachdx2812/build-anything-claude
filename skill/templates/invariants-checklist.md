# Invariants Checklist — F4 fix for "narrow taxonomy" red-team finding

Every atom touching persistent data MUST acknowledge each invariant below in its
`atom-brief.md` with one of: `applies` (with named query in `.build-anything.json#backend.invariants`),
`n/a` (with one-sentence reason), or `pending` (deferred to a follow-up atom).

A `pending` count >0 promotes the atom to AL-3 max (no AL-4 self-heal).

| # | Invariant family | Canonical violation query shape | Typical domain |
|---|------------------|----------------------------------|----------------|
| 1 | Sum/aggregate match | `SUM(line_items.amount) <> parent.total` | invoicing, orders, payments |
| 2 | Orphan child | `child WHERE parent_id NOT IN (SELECT id FROM parent)` | any FK |
| 3 | Required field present | `WHERE col IS NULL OR col = ''` | tenant_id, owner_id |
| 4 | Idempotency-key uniqueness | `count(*) > 1 GROUP BY idempotency_key, endpoint` | every mutation endpoint |
| 5 | Monotonic counter | `MAX(seq) < seq_to_be_used AND prior_max_seq > new_seq` | invoice number, order number |
| 6 | No-future-timestamp | `WHERE created_at > NOW()` | every timestamp column |
| 7 | Currency precision | `amount * 100 <> ROUND(amount * 100)` (integer minor units) | money columns |
| 8 | State-machine validity | `transition NOT IN allowed_transitions[from_state]` | order.status, ticket.state |
| 9 | FK cascade integrity | `child WHERE parent.deleted_at IS NOT NULL` | soft-delete + FK |
| 10 | Soft-delete consistency | `active query returns row WHERE deleted_at IS NOT NULL` | any soft-deleted table |
| 11 | Quota / limit enforcement | `count GROUP BY tenant HAVING count > tenant.quota` | rate-limits, plan caps |
| 12 | Time-window validity | `start_at > end_at OR (end_at - start_at) > max_duration` | bookings, schedules |
| 13 | Permission-role coherence | `user has role X AND lacks prerequisite role Y` | RBAC |
| 14 | Append-only history | `history table row UPDATE/DELETE detected` | audit, ledger, event-store |
| 15 | Cross-table conservation | `SUM(transfers.in) <> SUM(transfers.out) per ledger` | double-entry, balances, inventory |

## How the reviewer enforces this

`backend-integrity-reviewer.md` MUST FAIL the atom if `atom-brief.md` is missing
this checklist or any row is left blank. Reviewer marks the atom CRITICAL when:
- An `n/a` justification is implausible given the atom's scope
- A `pending` row covers a class likely to be violated by the atom's code

## How the orchestrator enforces this

`/build-anything` Stage 6 (atom-brief lint) MUST parse the checklist rows; any
missing or empty row blocks Stage 7. No grandfathering.

## Domain extensions

Specific verticals MUST add invariants on top of the 15 above:
- **Payments:** chargeback double-spend window, refund_amount ≤ original_amount
- **Inventory:** never negative on-hand, allocated ≤ on-hand
- **Scheduling:** no double-booking same resource, recurrence rules consistent
- **Auth:** session.expires_at > issued_at, MFA enabled where required
- **Healthcare:** all PHI columns column-encrypted, no PHI in logs
- **Multi-tenant SaaS:** every row has tenant_id; cross-tenant FK forbidden

Atoms in these verticals MUST extend the checklist with vertical-specific rows
before authoring code.
