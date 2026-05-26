# Phase 01 — Skill Coverage Final Report

**Date:** 2026-05-26 12:43 (Asia/Saigon)
**Phase:** 01 of 09 (skill catalog deep-dive)
**Status:** complete

## Summary

- Read 15 additional skills not covered in journal Section 8
- Coverage delta: 55% → ~78% (significant lift, mainly from `/ck:code-review` adversarial features already built)
- 15 truly new builds still required (mostly backend integrity sub-gates)
- 2 major discoveries reduce scope of Phase 04 + Phase 07

## Major Discoveries

### Discovery 1: `/ck:code-review` already does adversarial review

Frontmatter quote: "Review code quality with adversarial rigor... Always-on red-team analysis finds security holes, false assumptions, and failure modes."

Features built-in:
- Spec compliance review
- Adversarial review (always-on Stage 3)
- Verification before completion
- Edge case scouting
- Checklist review
- Task-managed reviews (3+ files, parallel reviewers)
- Parallel codebase audit mode (`codebase parallel`)

**Impact on Phase 04:** Reviewer prompts can be THIN wrappers over `/ck:code-review` invocations with specific focus context. Don't rewrite from scratch.

**Impact on `/build-anything`:** `sub-skills/review/` can primarily orchestrate `/ck:code-review` invocations rather than implement multi-agent review itself.

### Discovery 2: `/ck:autoresearch` IS the autonomous loop for AL-3/AL-4

Frontmatter quote: "Autonomous iterative optimization loop — run N iterations against a mechanical metric, learn from git history, auto-keep/discard changes."

Features:
- Config: Goal + Scope + Verify (single-number command) + Guard + Iterations + Min-Delta
- Git-tracked experiments with rollback
- Direction (higher/lower better)

**Impact on UBS v8.0:** Maps directly to AL-3 AGENT-AUTONOMOUS self-heal pattern. AL-4 MAX-AUTO = `/ck:autoresearch` with circuit breaker.

**Impact on `/build-anything`:** Phase 05 mechanical gate scripts must each emit single-number output → directly usable as `Verify` command.

### Discovery 3: `/ck:cook` = orchestrator template

Already has: Smart Intent Detection, Anti-Rationalization table, Mode selection (interactive/fast/parallel/auto), HARD-GATE before code.

**Impact on Phase 03:** `/build-anything` orchestrator should INHERIT cook's pattern (smart detection + anti-rationalization + mode flags) rather than reinvent.

### Discovery 4: `/ck:ship` = full ship pipeline already exists

Already does: merge main, test, review, commit, push, PR.

**Impact:** `/build-anything:verify` (Stage 14) can DELEGATE to `/ck:ship` for the L5→L6 transition.

## Final Coverage Table

| UBS Gap | Status | Skill | Notes |
|---------|--------|-------|-------|
| Security gate (P0) | ✅ Full | `/ck:security` + `/ck:security-scan` | STRIDE + OWASP + secret + dep audit |
| Code pattern review (P0) | ✅ Full | `/code-pattern-reviewer` | AI-only pattern detection |
| Architecture review (P1) | ✅ Full | `/architecture-reviewer` + `system-design-advisor` | Scalability + reliability + comm + observability |
| Adversarial code review (P0 — was gap) | ✅ Full | `/ck:code-review` (NEW DISCOVERY) | Always-on adversarial; spec compliance built-in |
| Autonomous loop (AL-3/AL-4) | ✅ Full | `/ck:autoresearch` + `/ck:loop` | Metric-driven, git-tracked, rollback |
| Verification before complete | ✅ Full | `superpowers:verification-before-completion` + `/ck:code-review` | Evidence-before-claims |
| Multi-agent orchestration | ✅ Full | `superpowers:subagent-driven-development` | Implementer + reviewers |
| Parallel scout | ✅ Full | `/ck:scout` | File discovery |
| Planning | ✅ Full | `/ck:plan` + `ck-cook` smart-detect pattern | Template + orchestrator inspiration |
| Debugging | ✅ Full | `/ck:debug` | Root cause |
| Predict failure | ✅ Partial | `/ck:predict` | Scenario forecast |
| Scenario test | ✅ Partial | `/ck:scenario` | Edge case |
| Backend dev patterns | ✅ Reference | `/ck:backend-development` | OAuth, OWASP, ACID, microservices — reference for v8.0 doc |
| Database design + queries | ✅ Reference | `/ck:databases` | psql + invariant queries + migrations |
| Frontend perf (Lighthouse/CWV) | ✅ Full | `/ck:chrome-devtools` (Puppeteer) | Headless screenshot + perf + a11y |
| Test execution (cov/integration/e2e) | ✅ Full | `/ck:test` | Coverage analysis built-in |
| Deploy automation | ✅ Full | `/ck:deploy` + `/ck:devops` + `/ck:ship` | Auto-detect platform; Cloudflare/GCP/K8s |
| Skill creation infra | ✅ Reference | `/ck:skill-creator` | Use for Phase 03 itself |
| Pattern advisory | ✅ Reference | `/design-patterns-advisor` + `/pattern-implementation-guide` | Bridges to spec stage |

### Still Missing — MUST BUILD (15 items)

| Gap | Phase to build | Tool wrapper or custom |
|-----|----------------|------------------------|
| DB invariant query gate | Phase 06 | Custom (psql + config-driven queries) |
| Idempotency test | Phase 06 | Custom (curl + DB count) |
| Concurrency test | Phase 06 | Custom (xargs -P + uniqueness check) |
| Transaction atomicity test | Phase 06 | Custom (chaos injection middleware) |
| API contract test | Phase 06 | Wrapper around Schemathesis/Dredd |
| Background job assertion | Phase 06 | Custom (queue inspect + side-effect probe) |
| Multi-tenant isolation test | Phase 06 | Custom (dual-tenant fixture) |
| Audit log assertion | Phase 06 | Custom (DB delta count) |
| Authorization test (per endpoint) | Phase 06 | Custom (anon + cross-user probes) |
| Mutation testing wrapper | Phase 05 | Wrapper around stryker/mutmut/gremlins |
| Property-based test wrapper | Phase 05 | Wrapper around fast-check/hypothesis/proptest |
| Observability assertion (log/metric/alert presence) | Phase 05 | Custom (grep diff for instrumentation patterns) |
| Rollback drill verification (feature-flag flip) | Phase 03 + custom script | Custom |
| Evidence crypto bundle | Phase 03 + custom script | Custom (sha256 + manifest) |
| Cost ceiling circuit breaker (AL-4) | Phase 03 (skill logic) | Custom |

## Skill Inventory (read this phase)

```
~/.claude/skills/
├── cook                          ✅ orchestrator pattern source
├── ck-autoresearch               ✅ autonomous loop = AL-3/AL-4
├── test                          ✅ /ck:test for GATE-10
├── code-review                   ✅ /ck:code-review adversarial built-in
├── security-scan                 ✅ /ck:security-scan for LAW-04 + part GATE-12
├── backend-development           ✅ reference for v8.0 doc
├── deploy                        ✅ auto-detect platform
├── ship                          ✅ ship pipeline
├── devops                        ✅ Cloudflare/Docker/GCP/K8s prod-verify
├── databases                     ✅ schema + queries for GATE-18
├── system-design-advisor         ✅ Q&A reference for v8.0
├── design-patterns-advisor       ✅ pattern advice
├── pattern-implementation-guide  ✅ pattern → code plan
├── chrome-devtools               ✅ Puppeteer for screenshot + Lighthouse
└── skill-creator                 ✅ use for /build-anything Phase 03
```

## Adjustments to Subsequent Phases

### Phase 02 — UBS v8.0 doc
- ARCHITECTURE-GATE (GATE-13) can cite `/architecture-reviewer` + `/system-design-advisor` as ground-truth
- Reference `/ck:backend-development` OWASP 2025 list for LAW-16
- Reference `/ck:databases` for GATE-18 invariant query patterns
- AL-3/AL-4 self-heal explicitly = `/ck:autoresearch` with circuit breaker

### Phase 03 — `/build-anything` skill design
- Orchestrator INHERITS `/ck:cook` smart-detection + anti-rationalization
- `sub-skills/build/` delegates to existing build patterns
- `sub-skills/review/` orchestrates `/ck:code-review` rather than reimplement
- `sub-skills/verify/` delegates to `/ck:ship` for L5→L6
- `sub-skills/gate-perf/` delegates to `/ck:chrome-devtools` for Lighthouse
- `sub-skills/gate-mechanical/` delegates to `/ck:test` for coverage; wraps mutation/property tools

### Phase 04 — Reviewer prompts
- DRASTICALLY simplified: become thin wrappers + context briefs over `/ck:code-review` invocations
- Only need NEW: `backend-integrity-reviewer.md` (no existing skill covers 9 backend sub-checks)
- Spec-attacker = `/ck:code-review` with spec-only focus context
- Code-quality, spec-compliance = `/ck:code-review` modes already exist

### Phase 05 — Mechanical scripts
- Coverage script can wrap `/ck:test` (one less custom impl)
- Lighthouse script delegates to `/ck:chrome-devtools` (existing script there)
- Property + mutation wrappers still custom (no existing skill)

### Phase 06 — Backend integrity scripts
- NO existing skill covers — full custom (matches estimate)
- Reference `/ck:databases` for psql conn patterns

### Phase 07 — Dry-run
- Toy project can leverage `/ck:cook --fast` to bootstrap
- `/ck:ship --dry-run` for L5 simulation

## Open Questions (unresolved)

1. `/ck:code-review` model selection — does it allow forcing Opus 4.7 explicitly, or inherits parent context? Need verify before Phase 04.
2. `superpowers` skill location — searched `~/.claude/skills/`, didn't find dedicated `superpowers/` dir. May be aliased or under different name. Search before Phase 03.
3. `/ck:autoresearch` cost tracking — does it have built-in $ ceiling, or must we add wrapper? Affects Phase 03 circuit breaker design.
4. Some skills marked "Reference" — confirm they're invocable via Skill tool or are just docs.
5. `team/` skill at top of dir listing — multi-agent coord? Worth a read in Phase 03 before designing sub-skill dispatch.
