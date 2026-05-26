# Phase 02 — UBS v8.0 Doc Complete

**Date:** 2026-05-26 (Asia/Saigon)
**Phase:** 02 of 09
**Status:** complete
**Deliverable:** `docs/ubs-v8-technical-hardening.md` (355 LOC, budget 800)

## Decisions Locked

- 7 new laws: LAW-11 mechanical, LAW-12 adversarial multi-agent, LAW-13 observability, LAW-14 backend integrity (P0 NEW), LAW-15 perf budget, LAW-16 security, LAW-17 evidence crypto
- 12 new gates: GATE-10 cov, 11 mutation, 12 sec, 13 arch, 14 perf, 15 obs, 16 rollback drill, 17 adversarial review, 18(a–f) backend, 19 contract, 20 idempotency, 21 multi-tenant
- Consensus rule = ANY reviewer FAIL → FAIL (no majority)
- Default reviewer set = 4 (spec-attacker + spec-compliance + code-quality + security-bridge). Backend atom adds backend-integrity (5). Cross-module adds architecture-bridge (6)
- Threshold table per project type (frontend / backend / library / infra)
- AL-4 breaker: max 5 iter, $5 USD per atom, oscillation detect, $20/h project cap, env kill switch
- LAW-17 enforced inside evidence sub-skill (precondition of any gate pass, no separate gate number)

## Reverse-Mapping Coverage

- P0 gaps (7/7) fully resolved
- P1 gaps (4/5 fully, 1 partial)
- P2 gaps (1 unresolved, 1 unresolved, 7 partial) — intentionally out of v8.0 scope

## Inputs To Phase 03

- All LAW/GATE numbers stable — Phase 03 sub-skills reference these directly
- Reviewer prompt files map to Section D table (6 role files in `prompts/`)
- Mechanical scripts listed by name in Section B (Phase 05/06 implements)
- `.build-anything.json` schema fragments cited (project_type, gate_overrides, backend.* keys)

## Open Questions

1. Per-project gate_overrides storage — keep inline in `.build-anything.json` or separate file? (Phase 03 design call)
2. LAW-17 manifest format — JSON vs CBOR? Default JSON unless signing tooling argues otherwise (Phase 03)
3. Reviewer prompt sharing — same six-line preamble in every prompt or one shared `preamble.md`? (Phase 03 / Phase 04)
4. Test of GATE-16 rollback drill on backend atom — staging vs prod with feature flag? Locked decision said feature flag → staging or prod-with-flag both acceptable; pick per atom in Phase 03

## Next

Phase 03 — design `/build-anything` skill suite at `~/.claude/skills/build-anything/` (13 sub-skills) per phase-03 plan file.
