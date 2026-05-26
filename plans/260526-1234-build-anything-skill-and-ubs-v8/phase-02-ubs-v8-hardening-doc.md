# Phase 02 — UBS v8.0 Technical Hardening Doc

## Context Links

- Journal Section 10 (intent)
- Journal Section 4 (21 gaps to address)
- Phase 01 output (coverage final)

## Overview

- Priority: P0
- Status: pending
- Brief: write full UBS v8.0 extension doc with 7 new laws + 12 new gates + multi-agent review protocol

## Key Insights

- Extension, not replacement — preserve boss's W1/W2/L1-L6/Atom/Allowlist/AutomationLadder
- Each new LAW/GATE must have rationale tied to original v7.5 gap (cite journal Section 4.X)
- Boss decision criterion: "does it break my framework?" — answer must be NO
- Backend integrity is the dominant new theme (was P0 NEW finding)

## Requirements

**Functional:**
- LAW-11 through LAW-17 defined with: name, statement, rationale, enforcement mechanism
- GATE-10 through GATE-21 defined with: name, when-runs, pass-criteria (mechanical), fail-action
- Multi-agent review protocol: roles, prompts (reference Phase 04 outputs), consensus rule, adversarial framing
- Mechanical threshold table per project type (frontend/backend/library/infra)
- Automation Ladder hardening: AL promotion requires PASS all technical gates; AL-4 circuit breaker spec
- Reverse-mapping table: original v7.5 gap → v8.0 fix

**Non-functional:**
- Length ≤ 800 LOC (per docs.maxLoc)
- Tone matches boss's v7.5 (terse, numbered, allcaps for laws)
- Vietnamese OR English (user picks — default English for boss universality)

## Architecture

Single doc + 1-pager pitch separate file (pitch in Phase 09, not here).

## Related Code Files

**Create:**
- `docs/ubs-v8-technical-hardening.md` (main extension doc)

**Modify:** none

**Reference (read):**
- Boss's v7.5 Google Doc structure (already extracted in journal)
- Journal Section 4 (21 gaps with quotes)

## Implementation Steps

1. Skeleton: Section A (laws) + B (gates) + C (thresholds) + D (review protocol) + E (AL hardening) + F (reverse-mapping)
2. Write Section A — 7 new laws:
   - LAW-11 MECHANICAL GATES — replace "tests green" with quantified thresholds
   - LAW-12 MULTI-AGENT REVIEW — define L4 substance
   - LAW-13 OBSERVABILITY — log/metric/alert required per atom
   - LAW-14 BACKEND INTEGRITY — 9 sub-checks (DB invariant, idempotency, concurrency, tx-atom, contract, bg-job, multi-tenant, audit, authz)
   - LAW-15 PERFORMANCE BUDGET — Lighthouse/CWV/bundle/latency per project type
   - LAW-16 SECURITY GATE — STRIDE + OWASP A01-A10 not just secrets
   - LAW-17 EVIDENCE CRYPTOGRAPHY — hash bundle linking artifact ↔ binary
3. Write Section B — 12 new gates with mechanical pass criteria:
   - GATE-10 COVERAGE-GATE (≥80%)
   - GATE-11 MUTATION-GATE (≥60%)
   - GATE-12 SECURITY-GATE (zero CRITICAL/HIGH findings)
   - GATE-13 ARCHITECTURE-GATE (no new cycles, layer violations)
   - GATE-14 PERFORMANCE-GATE (tight budget per project type)
   - GATE-15 OBSERVABILITY-GATE (log statement + metric + alert present)
   - GATE-16 ROLLBACK-DRILL-GATE (prod feature-flag flip verified)
   - GATE-17 ADVERSARIAL-REVIEW-GATE (≥3 reviewers PASS)
   - GATE-18 DB-INVARIANT-GATE (queries SUM-match, no orphan, FK valid)
   - GATE-19 API-CONTRACT-GATE (schema match request/response)
   - GATE-20 IDEMPOTENCY-GATE (call×2 → single effect)
   - GATE-21 MULTI-TENANT-ISOLATION-GATE (tenant A ⊥ tenant B)
4. Write Section C — threshold table (5 columns: project-type × gate × threshold × measurement-tool × fail-action)
5. Write Section D — multi-agent review protocol:
   - 5 reviewer roles (spec-attacker, spec-compliance, code-quality, backend-integrity, architecture-bridge)
   - All Opus 4.7
   - Consensus rule: any reviewer FAIL → atom HALT
   - Adversarial framing template
6. Write Section E — AL hardening:
   - AL promotion atom requires PASS all GATE-10→21
   - AL-4 requires circuit breaker: max-iter 5, max-cost $5/atom, halt-detector after 3 oscillation
7. Write Section F — reverse-mapping: gap 4.1 → LAW-12+GATE-17; gap 4.2 → LAW-11+GATE-10/11; ...; gap 4.7 → LAW-14+GATE-18/19/20/21
8. Final review: tone match boss's v7.5? Length ≤ 800?

## Todo List

- [ ] Skeleton 6 sections
- [ ] Section A (7 laws)
- [ ] Section B (12 gates)
- [ ] Section C (threshold table)
- [ ] Section D (review protocol)
- [ ] Section E (AL hardening)
- [ ] Section F (reverse-mapping)
- [ ] Tone + length review

## Success Criteria

- 7 laws + 12 gates defined with mechanical criteria
- Each gap from journal Section 4 mapped to ≥1 new law/gate
- Doc ≤ 800 LOC
- Boss-readable (terse, numbered, mechanical)

## Risk Assessment

- Doc length explosion (mitigation: ruthless cutting, mv detail to references)
- Mechanical criteria too strict for some projects (mitigation: per-type threshold table)
- Vocabulary drift from v7.5 (mitigation: re-read v7.5 quotes verbatim)

## Security Considerations

- No secrets in doc
- LAW-16 covers OWASP top 10

## Next Steps

- Phase 03 references LAW/GATE numbers from this doc
- Phase 09 pitch summarizes this doc
