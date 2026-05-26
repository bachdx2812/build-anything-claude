# Build Log Template

Per UBS v7.5 5-disciplined-documents (BUILD LOG). One file per atom at `{project_root}/.build-anything/atoms/{atom_code}/build-log.md`. APPEND-ONLY (LAW-08).

```markdown
# BUILD LOG — {ATOM-CODE}

> Append-only. Editing past entries → LAW-08 violation → AL demote to 0.
> Each entry: ISO timestamp + actor + action + outcome + evidence pointer.

## {ISO-8601} — {actor} — STAGE-01-SPEC — START
- Spec drafted
- Iter: 1
- Output: `spec.md` (sha256: {hash})

## {ISO} — {actor} — STAGE-01-SPEC — PASS
- spec.md §1-14 populated
- Adversarial scenarios: 6 enumerated
- Verdict: PASS
- Cost: $0.12

## {ISO} — {actor} — STAGE-02-SCHEMA — START
- Iter: 1

## {ISO} — {actor} — STAGE-02-SCHEMA — PASS
- openapi.yaml emitted
- migration 0042_orders.sql + 0042_orders.down.sql emitted
- invariants.sql: 3 named invariants
- types.ts: 2 types exported
- Cost: $0.08

## {ISO} — {actor} — STAGE-03-SPEC-REDTEAM — START

## {ISO} — {actor} — STAGE-03-SPEC-REDTEAM — FAIL
- Finding (HIGH): "Idempotency contract underspecified — what if key reused after 24h?"
  Anchor: spec.md §8
- Action: return to STAGE-01, iter 2

## {ISO} — {actor} — STAGE-01-SPEC — START (iter 2)
- Addressing redteam finding: added §8 row "TTL of idempotency key = 24h"
- spec.md sha256: {new-hash}

## {ISO} — {actor} — STAGE-01-SPEC — PASS (iter 2)
...

## {ISO} — {actor} — STAGE-04-IMPLEMENT — START
- Files claimed (allowlist): {list}
- TDD order: RED first

## {ISO} — {actor} — STAGE-04-IMPLEMENT — RED PASS
- Tests written: 7
- All FAIL as expected (no implementation yet)

## {ISO} — {actor} — STAGE-04-IMPLEMENT — GREEN PASS
- Implementation written
- All 7 tests now PASS
- Diff: +127 / -3 lines across 4 files
- Cost: $1.43

## {ISO} — {actor} — STAGE-05-MECHANICAL — START
- Triggered scripts: coverage, mutation, property, lint, type

## {ISO} — {actor} — STAGE-05-MECHANICAL — PASS
- coverage: 87.2% (threshold 80, PASS)
- mutation: 64.1% (threshold 60, PASS)
- property: 3 pure fns tested (PASS)
- lint: 0 errors
- type: 0 errors
- Cost: $0.04

## {ISO} — {actor} — STAGE-06-BACKEND — START
- Sub-gates fired: 18a, 18b, 18c, 18d, 18e, 18f, 19, 20, 21

## {ISO} — {actor} — STAGE-06-BACKEND — FAIL
- 18e (audit log) FAIL: "audit row missing for endpoint POST /orders"
  Evidence: `evidence/gate-backend/audit-log.json` shows 0 audit rows for 5 mutations
- AL-3 → autoresearch self-heal loop iter 1 invoked
- ...

## {ISO} — {actor} — STAGE-06-BACKEND — PASS (iter 2)
- Audit hook added in commit {sha}
- Re-run: audit_log delta == 5, matches mutation count
- All 9 sub-gates PASS

## {ISO} — {actor} — STAGE-07-SECURITY — PASS
- SAST: 0 HIGH
- dep-audit: 0 known CVE in atom dependencies
- secret-scan: 0 matches
- threat-model: STRIDE checklist passed (5 of 5)

## {ISO} — {actor} — STAGE-08-ARCH — PASS
- Cycles: 0
- Layer violations: 0
- Coupling delta: +0.02 (threshold +0.05)

## {ISO} — {actor} — STAGE-09-PATTERN — ADVISORY
- 2 LOW findings (advisory, not gate)

## {ISO} — {actor} — STAGE-10-REVIEW-DESIGN — START
- Reviewers spawned: spec-attacker, spec-compliance, code-quality, backend-integrity, security-bridge

## {ISO} — {actor} — STAGE-10-REVIEW-DESIGN — PASS
- All 5 reviewers PASS
- attempts_to_fail count: 23 (avg 4.6/reviewer)
- Cost: $1.14

## {ISO} — {actor} — STAGE-11-REVIEW-COMPLIANCE — PASS
- (same 5 reviewers, compliance pass)

## {ISO} — {actor} — STAGE-12-PERF — PASS
- p95 latency: 142 ms (threshold 200)
- bundle delta: N/A (BE atom)
- a11y: N/A (BE atom)
- observability: structured log + metric + trace span present

## {ISO} — {actor} — STAGE-13-EVIDENCE — PASS
- manifest.json built; 27 artifacts
- manifest_sha256: {hash}
- Appended to BUILD-ARCHIVE.md

## {ISO} — {actor} — STAGE-14-VERIFY — PENDING HUMAN CONFIRM (LAW-10)
- Pre-flight: PASS
- Awaiting human deploy confirm

## {ISO} — bachdx@email — STAGE-14-VERIFY — DEPLOY CONFIRMED
- Deploy started

## {ISO} — {actor} — STAGE-14-VERIFY — PASS
- Deployed sha {sha}
- Post-deploy smoke: PASS
- DB invariant prod re-check: PASS
- Rollback drill: 47s (threshold 60s)
- Error rate +1h: baseline +0.001%
- p95 latency +1h: 138 ms (matches lab)

## {ISO} — {actor} — ATOM-COMPLETE
- Total wall time: 26 min
- Total cost: $2.81
- All gates PASS, all reviewers PASS
- AL ledger: actor:{name} now at AL-3 with 22 clean atoms
```

## Rules

- Each entry: 1 timestamp + 1 actor + 1 stage + 1 outcome + bullets for detail
- No editing past entries — fix mistakes with NEW entries that supersede
- Each PASS entry MUST reference evidence file under `evidence/`
- Cost line per stage — feeds the AL-4 cost circuit breaker
