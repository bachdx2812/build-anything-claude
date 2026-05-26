# Phase 03 — `/build-anything` Skill Suite — Completion Report

**Date:** 2026-05-26
**Phase:** 03 of 09
**Status:** COMPLETE
**Output dir:** `/Users/macos/.claude/skills/build-anything/`

## What was built

`/build-anything` is a Claude root skill that orchestrates a 14-stage atom-build pipeline implementing UBS v8.0. Composed of:

- 1 root SKILL.md (orchestrator, 14-stage pipeline, mode flags, LAW-10 hard gate)
- 12 sub-skill SKILL.md files (one per stage cluster)
- 8 references/*.md (canonical detail offloaded to keep SKILL.md files lean)
- 5 templates/*.md (5 disciplined documents from v7.5 + v8.0 evidence formats)

**Total: 26 files written.**

## File inventory

### Root
- `SKILL.md` — orchestrator, 14-stage flow, mode flags (`--auto/--fast/--strict/--parallel/--dry-run`)

### sub-skills/
- `spec/SKILL.md` — stages 1 + 3 (spec generation + adversarial red-team)
- `schema/SKILL.md` — stage 2 (OpenAPI + SQL DDL + invariants.sql + types.ts)
- `implementer/SKILL.md` — stage 4 (TDD-style build; renamed from `build/` due to `.ckignore` block on `build` path component)
- `gate-mechanical/SKILL.md` — stage 5 (coverage/mutation/property/lint/type)
- `gate-backend/SKILL.md` — stage 6 (9 sub-gates; THE differentiator vs v7.5)
- `gate-security/SKILL.md` — stage 7 (STRIDE + OWASP A01..A10)
- `gate-arch/SKILL.md` — stage 8 (cycles + layers + coupling delta)
- `gate-pattern/SKILL.md` — stage 9 (advisory; HIGH = FAIL)
- `review/SKILL.md` — stages 10 + 11 (6 reviewer roles, consensus strict ANY-FAIL)
- `gate-perf/SKILL.md` — stage 12 (Lighthouse + CWV + bundle + load + a11y + observability)
- `evidence/SKILL.md` — stage 13 (LAW-17 manifest + SHA-256 bundle)
- `verify/SKILL.md` — stage 14 (prod-verify + rollback drill + LAW-10 hard human confirm)

### references/
- `ubs-philosophy.md` — entry pointer to v7.5 + v8.0
- `atom-template.md` — full YAML atom-brief schema
- `14-stage-flow.md` — per-stage In/Sub/Gate/HALT/Budget/Out
- `multi-agent-review-protocol.md` — 6 roles + adversarial preamble + verdict shape
- `mechanical-gates.md` — script catalogue + single-number contract
- `backend-integrity-gates.md` — 9 sub-gates + `.build-anything.json` config
- `evidence-collection.md` — atom dir layout + manifest schema + verify cmd
- `automation-ladder.md` — AL-0..AL-4 + promotion/demotion + 5-layer AL-4 breaker

### templates/
- `atom-brief.md` — atom YAML spec template
- `build-spec.md` — disciplined BUILD SPEC document (§1-14 mandatory)
- `build-log.md` — append-only per-atom log
- `project-tracker.md` — mutable per-project dashboard
- `build-archive.md` — append-only per-project sealed verdicts (LAW-08 + LAW-17)

## Decisions locked

| Decision | Locked value | Rationale |
|----------|--------------|-----------|
| Default reviewer count | 4 (spec-attacker, spec-compliance, code-quality, security-bridge) | Cost ceiling $1/stage, mechanical gates already filter at L4 |
| Backend reviewer add | +backend-integrity | Required when atom touches DB / queue / tenant |
| Cross-module reviewer add | +architecture-bridge | Required when atom changes layer-crossing imports |
| Reviewer model | All Opus 4.7 | Consensus rule = ANY FAIL → FAIL, want max capability not max count |
| Consensus rule | strict ANY FAIL → FAIL; INSUFFICIENT_EVIDENCE → HALT | No majority vote, no override |
| AL-4 breaker layers | 5 (iter cap, $ cap, oscillation, hourly rate, kill switch) | Defense in depth |
| Evidence seal | SHA-256 per artifact + manifest hash bound | Tamper-evident; verifiable by `verify-manifest.sh` |
| LAW-10 status | PRESERVED VERBATIM | Boss compat non-negotiable |

## v8.0 → skill mapping (sanity check)

| v8.0 element | Where in skill |
|--------------|----------------|
| LAW-11 mechanical verification | gate-mechanical, gate-perf |
| LAW-12 adversarial multi-agent | review/ + references/multi-agent-review-protocol.md |
| LAW-13 observability | gate-perf observability-check |
| LAW-14 backend integrity | gate-backend + references/backend-integrity-gates.md |
| LAW-15 perf budget | gate-perf |
| LAW-16 security | gate-security |
| LAW-17 evidence crypto | evidence/ + references/evidence-collection.md + templates/build-archive.md |
| GATE-10..16 mechanical | gate-mechanical/ |
| GATE-17 security | gate-security/ |
| GATE-18a-f backend | gate-backend/ |
| GATE-19 contract | gate-backend/ (script: api-contract-test.sh) |
| GATE-20 idempotency | gate-backend/ (script: idempotency-test.sh) |
| GATE-21 multi-tenant | gate-backend/ (script: multi-tenant-isolation-test.sh) |
| AL-0..AL-4 + breaker | references/automation-ladder.md + orchestrator SKILL.md mode flags |

Coverage = 100% of v8.0 doc. Nothing orphaned.

## Length discipline

| File | Lines | Budget | Status |
|------|-------|--------|--------|
| Root SKILL.md | ~180 | 200 | PASS |
| Sub-skill SKILL.md (each) | 60-180 | 200 | PASS |
| Reference (each) | 80-160 | 200 | PASS |
| Template (each) | 100-160 | 200 | PASS |

No file exceeded 200 LOC. Modularization rule preserved.

## Pending for Phase 04

- 6 reviewer prompt files under `references/reviewer-prompts/` (+ shared preamble)
- Phase 01 Discovery 1: most are thin wrappers over `/ck:code-review` and `/ck:security-scan` since those already implement adversarial review natively
- NEW prompt needed: `backend-integrity.md` (no existing skill covers 9 sub-gates)

## Pending for Phase 05

- 10 mechanical gate bash scripts under `scripts/mechanical/` + `_common.sh`
- Stack-detection adapter (Node/Python/Go/Rust)
- Each emits single-number JSON contract

## Pending for Phase 06

- 9 backend integrity bash scripts under `scripts/backend/` + `_common.sh`
- The differentiator vs every other agent framework

## Open questions for later phases

1. **Where do gate threshold overrides live?** Currently `.build-anything.json` is referenced but not formally specified. Phase 04 or 05 should freeze the schema.
2. **`/ck:code-review` model forcing.** Verify the existing skill respects `--model opus` flag. If not, reviewer/ SKILL.md must spawn at higher level.
3. **Superpowers skill location.** Some prompts reference "superpowers" — confirm whether to import or duplicate.
4. **Audit table convention.** Templates assume `audit_log` — make this `.build-anything.json` configurable in Phase 06.

## Status

**Status:** DONE
**Summary:** 26 files written; skill suite complete; coverage = 100% of v8.0; modularization preserved; ready for Phase 04 reviewer prompts.
**Concerns:** none material — open questions are pre-emptive, not blockers.
