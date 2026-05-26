---
name: build-anything-skill-and-ubs-v8
description: Build /build-anything sub-skills + UBS v8.0 hardening doc + boss pitch
status: in_progress
created: 2026-05-26
owner: bachdx.hut@gmail.com
blockedBy: []
blocks: []
---

# Plan — `/build-anything` Skill + UBS v8.0 Hardening

**Context journal:** `../reports/journal-260526-1156-ubs-discovery-and-skill-design.md` (VI) + `-en.md` (EN)

## Goals

1. UBS v8.0 hardening doc — extension to boss's framework (LAW-11→17, GATE-10→21) addressing 21 gaps incl. UI-bias/backend-integrity P0 finding
2. `/build-anything` sub-skill suite — modular Claude skills implementing 14-stage UBS-style flow with multi-agent adversarial review + mechanical gates + backend integrity gates
3. Boss-facing 1-pager pitch — sell hardening without breaking philosophy

## Locked Decisions (from user 2026-05-26)

| Decision | Choice |
|----------|--------|
| Direction | Full plan first then execute |
| Reviewer model | All Opus 4.7 |
| Thresholds | Strict: cov 80% / mut 60% / perf tight |
| Backend depth | Full 9 sub-gates (invariant + idempotency + concurrency + tx-atom + contract + bg-job + multi-tenant + audit + authz) |
| Rollback drill | Prod with feature flag |
| Boss doc | Both pitch + full spec |
| Skill format | Sub-skills modular |

## Constraints

- NO human code review (multi-agent adversarial only)
- Keep all UBS terms (Atom, Layer, Gate, Law, Evidence, Allowlist, Automation Ladder)
- Compatible with boss philosophy (extension not replacement)

## Phases

| # | Phase | Status | Effort |
|---|-------|--------|--------|
| 01 | Skill catalog deep-dive | ⏳ pending | S |
| 02 | UBS v8.0 hardening doc | ⏳ pending | L |
| 03 | `/build-anything` sub-skill design + SKILL.md | ⏳ pending | L |
| 04 | Adversarial reviewer prompts | ⏳ pending | M |
| 05 | Mechanical gate scripts | ⏳ pending | M |
| 06 | Backend integrity gate scripts (9 sub-gates) | ⏳ pending | L |
| 07 | Dry-run validation on toy project | ⏳ pending | M |
| 08 | Red-team review of skill design | ⏳ pending | S |
| 09 | Boss-facing 1-pager pitch | ⏳ pending | S |

## Dependencies

- 02 needs 01 (catalog gap map informs v8.0 content)
- 03 needs 01 + 02 (skill maps to gates from v8.0)
- 04 needs 03 (reviewer prompts plug into skill flow)
- 05 + 06 parallelizable after 03
- 07 needs 03 + 04 + 05 + 06
- 08 needs 07 findings
- 09 needs 02 (pitch summarizes v8.0)

## Success Criteria (overall)

- All 9 phases marked complete
- `/build-anything:*` invocable end-to-end on toy project
- All 21 gaps from journal covered by gates or documented exceptions
- Boss receives both 1-pager + full spec
- Skill passes red-team review

## Risks

- Adversarial reviewer consensus-bias (mitigation: model diversity layer if available, mechanical gates as ground truth)
- Cost runaway in dry-run (mitigation: hard $ ceiling per atom, $5 default)
- Boss rejects hardening as "too slow" (mitigation: pitch frames as quality multiplier not speed cost)
- Backend integrity scripts fragile per stack (mitigation: parameterize, document per-stack adapters)
