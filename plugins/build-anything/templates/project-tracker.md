# Project Tracker Template

Per UBS v7.5 5-disciplined-documents (PROJECT TRACKER). One per project at `{project_root}/.build-anything/PROJECT-TRACKER.md`. Mutable (unlike BUILD ARCHIVE which is append-only).

```markdown
# PROJECT TRACKER — {project name}

> Mutable. Recompiled from atom states + BUILD ARCHIVE on every atom transition.
> Source of truth for "what's live, what's in flight, what's blocked."

## Project meta

- Project: {name}
- Repo: {git remote}
- Started: {ISO}
- v8.0 onboarded: {ISO}
- Primary tech: {Node/TS, Python, Go, Rust}
- DB: {postgres/mysql/sqlite/mongo/none}
- Boss-compat: TRUE (LAW-01..10 v7.5 preserved verbatim)

## Active automation ladder

| Actor | Current AL | Atoms completed | Clean streak | Last promotion | Halt reasons (30d) |
|-------|-----------|-----------------|--------------|----------------|---------------------|
| actor:claude-opus-4-7 | 3 | 23 | 5 | 2026-05-20 | — |
| actor:bachdx@email | 2 | 4 | n/a | n/a | — |

## Initiatives

### INIT-260520-orders-v2 (in flight)
> Owner: {team} | Goal: "stand up new orders microservice with multi-tenant safety"

| Atom | Layer | Status | AL | Iter | Cost | Verdict |
|------|-------|--------|----|----|------|---------|
| ATOM-260526-orders-create | L6 | DEPLOYED | 3 | 2 | $2.81 | PASS |
| ATOM-260526-orders-get | L5 | PRE-MERGE | 3 | 1 | $1.40 | PASS |
| ATOM-260526-orders-cancel | L4 | DESIGN | 3 | 1 | $0.90 | review |
| ATOM-260526-orders-export | L1 | SPEC | 3 | 1 | $0.10 | spec-attacker pending |

### INIT-260512-billing-fix (completed 2026-05-22)
> Owner: {team} | Goal: "patch double-charge bug found in QA"
> All atoms ARCHIVED. See `BUILD-ARCHIVE.md` for sealed entries.

## Atom layer summary

| Layer | Definition | Count active |
|-------|-----------|--------------|
| L1 REQUIREMENTS | spec drafted | 1 |
| L2 SCHEMA | openapi + migration + invariants emitted | 0 |
| L3 IMPLEMENT | code written, RED→GREEN | 0 |
| L4 DESIGN-REVIEW | reviewers approved design | 1 |
| L5 PRE-MERGE | all gates + reviewers PASS | 1 |
| L6 DEPLOYED | stage 14 verified prod | 1 |

## Halts (last 30 days)

| Atom | Stage | Reason | Resolved |
|------|-------|--------|----------|
| ATOM-260518-tenant-rename | 6 | GATE-21 FAIL (cross-tenant leak) | yes, iter 3 |
| ATOM-260514-export-csv | 7 | dep-audit HIGH cve | yes, bumped lib |

## Cost ledger (rolling 7d)

| Day | Atoms attempted | Atoms passed | Total spend | $/atom avg |
|-----|-----------------|--------------|-------------|------------|
| 2026-05-25 | 3 | 3 | $7.42 | $2.47 |
| 2026-05-24 | 4 | 3 | $9.10 | $2.27 |
| ... |

Project hourly burn rate cap: $20 (AL-4 circuit breaker Layer 4).

## Pending human confirmations (LAW-10)

- ATOM-260526-orders-get → stage 14 deploy queued, awaiting bachdx@email confirm

## Blockers (HALT or stuck)

| Atom | Stuck at | Reason | Owner | ETA |
|------|----------|--------|-------|-----|
| ATOM-260526-orders-export | spec | "boss undecided on tenant-share semantics" | bachdx | 2026-05-27 |

## v8.0 gate-level health (last 50 atoms)

| Gate | PASS | FAIL | FAIL rate |
|------|------|------|-----------|
| GATE-10 coverage | 48 | 2 | 4% |
| GATE-11 mutation | 47 | 3 | 6% |
| GATE-16 property | 50 | 0 | 0% |
| GATE-17 security | 49 | 1 | 2% |
| GATE-18a-f backend | 44 | 6 | 12% ← highest, expected |
| GATE-19 contract | 48 | 2 | 4% |
| GATE-20 idempotency | 49 | 1 | 2% |
| GATE-21 multi-tenant | 47 | 3 | 6% |

Trend: backend integrity gates are doing real work (high FAIL = catching real bugs).

## Recent decisions / waivers

| Date | Atom | Waiver | Approver | Expiry |
|------|------|--------|----------|--------|
| 2026-05-24 | ATOM-260524-* | N/A on GATE-15 observability (no metrics stack yet) | bachdx | 2026-06-24 |

## Open questions across project

- [ ] When do we onboard the metrics stack so GATE-15 stops being waived?
- [ ] Tenant-share semantics for cross-tenant orders — boss decision pending
```

## How this is updated

- Orchestrator recompiles this from atom states after every stage transition
- The tracker is a VIEW; truth lives in atom-level `manifest.json` files + `BUILD-ARCHIVE.md`
- Recompile is idempotent — safe to regenerate from scratch any time

## Recompile command

```sh
~/.claude/skills/build-anything/scripts/mechanical/recompile-tracker.sh {project_root}
```

Output: this file, overwritten. Past versions visible via git (project repo).
