# Phase 08 — Red-Team Review of `/build-anything` Skill

## Context Links

- Phase 03 skill design
- Phase 07 dry-run results
- Journal Section 13 (unresolved questions / risks)

## Overview

- Priority: P1
- Status: pending
- Brief: adversarial agent attacks `/build-anything` design itself — find gaps we missed

## Key Insights

- We applied adversarial review to USER code in Phase 04 — must apply to OURSELVES too (eat own dog food)
- Red team must NOT be primary author (separate fresh context agent)
- Red team has multiple angles: gate evasion, prompt injection, cost exhaustion, false-confidence
- Output feeds back to Phase 03/04/05/06 if blockers found

## Requirements

**Functional adversarial questions:**

1. **Gate evasion** — Can an adversarial Devin pass all gates while introducing a real bug?
2. **Reviewer collusion** — All Opus → same model → same blind spot. How to detect?
3. **Cost runaway** — Can self-heal loop drain budget?
4. **Prompt injection** — Can crafted code/spec hijack reviewer?
5. **Evidence forgery** — Can crypto bundle be faked?
6. **Multi-tenant test gaming** — Fixture too narrow to catch real leak?
7. **Mutation testing scope** — Changed-file-only scope → can attacker hide bug outside scope?
8. **Coverage gaming** — Can 80% cov be achieved without meaningful tests?
9. **Backend integrity false-pass** — Can invariant queries be too narrow?
10. **Boss compatibility** — Does v8.0 actually preserve all v7.5 semantics?

**Non-functional:**
- Red-team agent: fresh subagent, no Phase 03-07 author context
- Output report ≤ 300 LOC
- Each finding has severity (BLOCKER/HIGH/MEDIUM/LOW) + concrete fix

## Architecture

Single red-team agent invocation via Agent tool with specific prompt. Read-only (analyzes Phase 03-07 outputs).

## Related Code Files

**Create:**
- `reports/phase-08-red-team-findings.md`

**Modify (based on findings):**
- Phase 03/04/05/06 outputs if BLOCKER

## Implementation Steps

1. Prepare red-team brief: list 10 adversarial questions + reference to Phase 03-07 outputs
2. Spawn red-team Agent (subagent_type: `brainstormer` or `code-reviewer` with adversarial prompt)
3. Agent reads:
   - `/Users/macos/.claude/skills/build-anything/` (full skill)
   - Phase 07 dry-run results
   - Journal Section 13 risks
4. Agent attacks each angle, produces findings
5. Classify findings by severity
6. Triage: BLOCKER → fix before Phase 09; HIGH → fix; MEDIUM → backlog; LOW → note
7. Re-run dry-run if BLOCKER fixed

## Todo List

- [ ] Draft red-team brief
- [ ] Spawn red-team agent
- [ ] Collect findings
- [ ] Triage by severity
- [ ] Fix BLOCKER + HIGH
- [ ] Re-run Phase 07 if needed
- [ ] Write phase-08-red-team-findings.md

## Success Criteria

- Red-team produced findings (zero findings = suspicious, suggests weak red-team)
- All BLOCKER fixed
- All HIGH addressed or explicitly accepted with rationale
- Report includes "5 things I would attack as a malicious operator" section

## Risk Assessment

- Red-team consensus-bias with primary author (mitigation: different model if possible, different prompt framing)
- Findings explosion paralyzes (mitigation: severity triage + acceptance rationale OK)
- Red-team misses real issues (mitigation: this risk IS unresolvable — Phase 09 deploys conservatively to real project)

## Security Considerations

- Red-team is sandboxed (read-only, no skill modification authority)
- Red-team findings may reveal attack surface — keep report internal, not boss-facing

## Next Steps

- Phase 09 pitch incorporates "validated by adversarial review" claim ONLY if no BLOCKER remained
