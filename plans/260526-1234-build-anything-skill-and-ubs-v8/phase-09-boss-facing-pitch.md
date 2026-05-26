# Phase 09 — Boss-Facing 1-Pager Pitch

## Context Links

- Phase 02 (UBS v8.0 full doc)
- Phase 07 dry-run results (evidence)
- Phase 08 red-team findings

## Overview

- Priority: P1
- Status: pending
- Brief: 1-pager pitch convincing boss to adopt UBS v8.0 hardening; links to full spec

## Key Insights

- User picked "Both pitch + full spec linked" — pitch ≠ full doc, pitch is sales tool
- Boss decision criterion: does this break my framework? Answer: NO (extension only)
- Boss likely objection: "slower, more cost" → counter with: catches bugs earlier (cost saved later)
- Pitch must use boss's vocabulary (Atom, Layer, Gate, Law, Evidence, Allowlist)
- Lead with concrete failure mode boss's current UBS misses (UI-bias finding)

## Requirements

**Functional pitch structure:**

1. **One-liner** — "UBS v8.0 = UBS v7.5 + 7 laws + 12 gates for technical correctness. Same atoms, same allowlist, same automation ladder."
2. **The Gap** — 1 paragraph: current UBS evidence model is UI-shaped (4/5 evidence types). UI cannot prove backend correctness. Cite 3 concrete failure modes (payment double-charge, tenant leak, aggregation drift).
3. **The Fix** — 1 paragraph: add LAW-14 BACKEND INTEGRITY + 4 new gates (GATE-18-21) for DB invariant / API contract / idempotency / multi-tenant. Plus LAW-11-13 + LAW-15-17 for mechanical/multi-agent/observability/perf/security/crypto-evidence.
4. **Boss Compatibility Proof** — table: v7.5 element → v8.0 status. All "PRESERVED".
5. **Evidence** — dry-run on toy project caught 12/12 seeded bugs across all gates. Cost $X, time Y min.
6. **Trade-offs** — explicit: +N% review time, +$M cost per atom. Justified by: zero post-prod incidents from caught-class bugs.
7. **Ask** — adopt v8.0 as extension; existing atoms continue under v7.5; new atoms under v8.0; migrate gradually.

**Non-functional:**
- Length ≤ 1 page (≈ 200 LOC markdown after rendering)
- Tone: business + engineering hybrid, not academic
- Link to full v8.0 spec at bottom
- Vietnamese or English version per user pick (default English)

## Architecture

Single markdown file. Optionally render to PDF for boss share.

## Related Code Files

**Create:**
- `docs/ubs-v8-pitch.md` (1-pager)

**Reference:**
- `docs/ubs-v8-technical-hardening.md` (Phase 02 output)
- `plans/260526-1234-build-anything-skill-and-ubs-v8/reports/phase-07-dry-run-results.md`

## Implementation Steps

1. Draft outline matching 7-section structure above
2. Write opening one-liner — must hook boss in 5 seconds
3. Write "The Gap" — use exact quote from boss's v7.5 LAW-03 ("pipeline ID, preview URL, prod URL, screenshot, or DB row") to show even boss's doc admits DB row is evidence, but UBS doesn't define how
4. Write "The Fix" — table of new laws + gates with one-line each
5. Write boss-compatibility table
6. Write "Evidence" — dry-run numbers
7. Write trade-offs — honest cost/time numbers
8. Write "Ask" — concrete adoption path
9. Review: length ≤ 1 page? Tone right? Boss vocab preserved?
10. Optional: PDF render via pandoc

## Todo List

- [ ] One-liner
- [ ] The Gap paragraph
- [ ] The Fix paragraph + table
- [ ] Boss-compat table
- [ ] Evidence section (numbers from Phase 07)
- [ ] Trade-offs honest
- [ ] Ask + adoption path
- [ ] Length + tone review
- [ ] Optional PDF render

## Success Criteria

- 1-pager ≤ 1 page
- Uses boss's vocabulary (Atom, Layer, Gate, Law, Evidence, Allowlist, Automation Ladder)
- Cites concrete failure modes (payment, tenant, aggregation)
- Includes dry-run evidence numbers
- Has clear adoption ask

## Risk Assessment

- Boss rejects ("too academic", "slower") (mitigation: lead with failure modes, not theory)
- Pitch too long (mitigation: 1-page hard cap)
- Pitch too short (skips evidence) (mitigation: must include dry-run numbers section)
- Boss objection: "v7.5 already works for us" (mitigation: counter with UI-bias finding — show what v7.5 CAN'T catch)

## Security Considerations

- Pitch may be shared externally — must not include skill internals or attack surface details
- No internal red-team findings in pitch

## Next Steps

- Deliver pitch to boss
- Schedule walkthrough of full v8.0 spec
- Pilot v8.0 on 1 real atom; measure outcome vs v7.5 baseline
