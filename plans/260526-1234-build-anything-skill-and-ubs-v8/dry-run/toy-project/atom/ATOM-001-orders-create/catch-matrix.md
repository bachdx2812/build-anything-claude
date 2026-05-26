# ATOM-001 Catch Matrix — UBS v8.1 dry-run (refreshed 2026-05-26 15:45+07)

Demonstration: skill enforced by mechanical gates catches every seeded bug whose tool is installed; missing tools surface as `N/A_PENDING_REVIEWER` (LAW-F6) rather than silently passing — exact opposite of "Devin says done."

Tools installed for this run: gitleaks 8.30.1, k6 v2.0.0, stryker 9.6.1, madge 8.0.0, c8 (Node coverage), eslint missing (intentionally — surfaces F6), tsc missing (intentionally — surfaces F6), schemathesis missing (LAW-15).

## Gate verdicts

| Gate | Verdict | Score | Threshold |
|------|---------|-------|-----------|
| GATE-10-line (coverage) | **FAIL** | 36.14% line / 100% branch | 80% / 80% |
| GATE-lint | N/A_PENDING_REVIEWER | — | no eslint config |
| GATE-type | N/A_PENDING_REVIEWER | — | no .ts files |
| GATE-11 (mutation) | **FAIL** | 2.59% | 60% |
| GATE-15 (observability) | **FAIL** | 5 violations | 0 |
| GATE-14-load | **FAIL** | p95=109ms | ≤50ms |
| GATE-14-lighthouse | N/A_PENDING_REVIEWER | — | no FE URLs |
| GATE-18a-invariant | **FAIL** | 1/3 invariants violated | 0 |
| GATE-20-idempotency | **FAIL** | row_delta=3 (want 1) | — |
| GATE-18b-concurrency | **FAIL** | 1 duplicate + 10x 5xx | 0 |
| GATE-18c-tx | PASS | rollback ok | — |
| GATE-18d-bg-job | **FAIL** | job enqueued, never executed | — |
| GATE-18e-audit | **FAIL** | 2xx response, 0 audit rows | — |
| GATE-18f-authz | **FAIL** | wrong tenant got 200 (want 403) | — |
| GATE-21-tenant | **FAIL** | cross-tenant leak in body+DB | — |
| GATE-19-contract | N/A_PENDING_REVIEWER | — | schemathesis missing |
| LAW-04-secret | **FAIL** | sk-proj key in server.js | 0 |
| GATE-16-sqli | **FAIL** | 3 string-concat SQL sites | 0 |
| arch-bridge | **FAIL** | FE references DB | 0 |

## Per-bug expected vs actual

| Bug | Expected catcher | Actual verdict | Status |
|-----|------------------|----------------|--------|
| BUG-01 (mutation-blind tests) | GATE-11 mutation | FAIL 2.59% (3 killed / 113 survived / 116 total) | **CAUGHT** by real stryker |
| BUG-02 (uncovered branch `Date.now()%3`) | GATE-10 coverage | FAIL 36.14% line | **CAUGHT** by real c8 |
| BUG-03 (hardcoded `sk-proj-...`) | LAW-04 secret scan | FAIL — grep substitute matched | **CAUGHT** via grep substitute (note: default gitleaks rules rejected the low-entropy test pattern; production gitleaks config needs custom rule for org's key shape) |
| BUG-04 (SQL injection note) | GATE-16 property fuzz | FAIL — 3 sites flagged | **CAUGHT** via grep substitute (property fuzz coming) |
| BUG-05 (N+1 query on `refresh=1`) | GATE-14 load p95 | FAIL p95=109ms (≤50ms) | **CAUGHT** by real k6 against running server (1905 row N+1 amplification) |
| BUG-06 (no logging/metrics/trace) | GATE-15 observability | FAIL — 5 files missing instrumentation | **CAUGHT** |
| BUG-07 (orders.total mismatch) | GATE-18a invariant | FAIL — 6 violation rows | **CAUGHT** |
| BUG-08 (no audit_log insert) | GATE-18e audit | FAIL — expected delta 1, got 0 | **CAUGHT** |
| BUG-09 (Idempotency-Key ignored) | GATE-20 + GATE-18b | FAIL — duplicate insert detected | **CAUGHT** |
| BUG-10 (cross-tenant LIST leak) | GATE-21 isolation | FAIL — leak_in_body=true, leak_in_db=true | **CAUGHT** |
| BUG-11 (GET no tenant check) | GATE-18f authz | FAIL — wrong_fixture got 200 want 403 | **CAUGHT** |
| BUG-12 (job never executed) | GATE-18d bg job | FAIL — side_effect_probe failed | **CAUGHT** |
| BUG-13 (FE references DB) | arch-bridge | FAIL — FE imports DB ref | **CAUGHT** via grep substitute |

## Summary

- **Caught by mechanical evidence:** 13/13 seeded bugs — every single one has a numeric verdict on disk.
- **Vacuous PASS count:** 0 — every silent skip recorded as `N/A_PENDING_REVIEWER`.
- **Real tools used end-to-end:** stryker (mutation), c8 (coverage), k6 (load), gitleaks (run but rule mismatch — fell back to grep), property/SQLi grep substitute, observability regex, db-invariant SQL, idempotency/concurrency/tx/audit/authz/tenant via custom backend gates.
- **N/A surfaced (correctly refused vacuous PASS):** lint (no eslint config), type (no .ts), lighthouse (no FE URLs), contract (no schemathesis).

## Why this beats "Devin says done"

| Trait | Devin-style | UBS v8.1 |
|-------|-------------|----------|
| Pass criterion | "I said it works" | numeric score on disk + SHA-256 |
| Empty test surface | silent green | `N/A_PENDING_REVIEWER` |
| Missing tool | unstated | `LAW-15` line in evidence |
| Cross-tenant leak | undetected | mandatory probe + body inspection |
| Audit gap | undetected | row-delta gate |
| Idempotency | undetected | dup-row gate |
| Logging coverage | undetected | file-by-file regex scan |
| Mutation-blind tests | undetected | stryker kill-ratio gate |
| Uncovered branch | undetected | c8 line/branch % gate |
| N+1 query | undetected | k6 p95 budget gate |
| Tampered evidence | trust me bro | manifest SHA-256 + external witness |

## Manifest integrity

- `manifest.sha256`: `a52bfa46a4aec5a0238e80dfa00e3d1d5b34beea87f90eba3d026143cb08fe97`
- `witness.json`: dry-run placeholder; production requires off-process co-signer (eg Sigstore keyless OIDC, TUF notary, or human approver signing offline).

## Outstanding follow-ups (next iteration)

1. Replace `secret-scan.json` grep substitute with proper gitleaks custom rules matching org key prefixes (current default rules reject low-entropy test patterns — fine for prod but masks dry-run bug).
2. Replace `sql-injection.json` and `architecture.json` grep substitutes with semgrep + dependency-cruiser real runs.
3. Wire schemathesis install path into contract gate.
4. Implement true external LAW-17 witness via cosign keyless (currently shape-only placeholder).
