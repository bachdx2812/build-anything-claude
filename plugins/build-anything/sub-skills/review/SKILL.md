---
name: build-anything-review
description: Stages 10 + 11 — adversarial multi-agent L4 review (≥3 reviewers, any FAIL → FAIL); the substance of L4 left undefined in v7.5
---

# review — Stages 10 + 11 Adversarial L4 Review

**Maps to:** stages 10 and 11 of `/build-anything`. Implements LAW-12 + GATE-17. **This is the substance of L4** — boss's v7.5 named L4 but did not define it (journal §4.1).

## Inputs

- Atom diff
- Spec from stage 1 + 3
- Schema artifacts from stage 2
- Gate verdicts from stages 5–9 (mechanical, backend, security, arch, pattern)

## Outputs

- `{atom_dir}/review/{role}.json` per reviewer
- Aggregated verdict `{ "stage": 10-11, "verdict": "PASS|FAIL", "findings": [...] }`

## Reviewer Set (all Opus 4.7)

| # | Role | Folder + prompt | Mandate |
|---|------|----------------|---------|
| 1 | spec-attacker | `references/reviewer-prompts/spec-attacker.md` | break the spec — same attacker re-run at L4 with implementation in hand |
| 2 | spec-compliance | `references/reviewer-prompts/spec-compliance-reviewer.md` | every spec line ↔ code line; flag over- and under-implementation |
| 3 | code-quality | `references/reviewer-prompts/code-quality-reviewer.md` | wraps `/ck:code-review` adversarial mode; maintainability, error handling, dead code |
| 4 | backend-integrity | `references/reviewer-prompts/backend-integrity-reviewer.md` | verifies stage 6 sub-gates; verifies N/A claims |
| 5 | architecture-bridge | `references/reviewer-prompts/architecture-bridge.md` | wraps `architecture-reviewer` skill; scale + reliability impact |
| 6 | security-bridge | `references/reviewer-prompts/security-bridge.md` | STRIDE per entry point + OWASP A01..A10 |

**Default set (every atom):** 1 + 2 + 3 + 6 — four reviewers.
**Backend atom adds:** 4 → five reviewers.
**Cross-module atom adds:** 5 → six reviewers.

## Parallel Dispatch

All N reviewers spawn in parallel as fresh subagents (no implementer history). Each writes its JSON verdict; orchestrator collects all then applies consensus rule.

## Consensus Rule

ANY reviewer returns FAIL → atom FAIL. No majority vote, no override.
ANY reviewer returns INSUFFICIENT_EVIDENCE → atom HALT pending evidence (route back to stage 13 evidence sub-skill).
All PASS → L4 PASS, advance to stage 12.

## Adversarial Framing Preamble

Every reviewer prompt opens with the six-line preamble (shared in `references/reviewer-prompts/preamble.md`):

```
You are the {ROLE} reviewer. Your job is to FAIL this atom if you can.
You are rewarded for finding real issues, penalised for nitpicks.
Pass only when you have actively tried to fail and could not.
Cite file:line for every finding. No findings without anchors.
Output JSON: {verdict: PASS|FAIL|INSUFFICIENT_EVIDENCE, findings: [...]}
You may invoke any tool to gather evidence. You may not invoke other agents.
```

## Output Format Per Reviewer

```json
{
  "role": "spec-attacker",
  "verdict": "PASS|FAIL|INSUFFICIENT_EVIDENCE",
  "findings": [
    {
      "severity": "CRITICAL|HIGH|MEDIUM|LOW",
      "anchor": "src/foo.ts:42",
      "claim": "...",
      "counter_example_or_evidence": "..."
    }
  ],
  "attempts_to_fail": [
    "described what I tried to break and how"
  ]
}
```

`attempts_to_fail` is required and non-empty. A PASS with empty attempts is rejected — that reviewer is re-spawned with stricter framing.

## Consensus-Bias Mitigation

All reviewers share Opus 4.7 base model. Mitigations applied here:
1. Stages 5–9 (mechanical + backend + security + arch + pattern) run BEFORE reviewers — catches what reviewers might rationalise.
2. spec-attacker is specifically tasked with adversarial input — counterweights implementation-side reviewers.
3. Reviewer prompts emphasise CONCRETE counter-examples, not abstract concerns.
4. Phase 08 red-team review of the skill suite itself catches systematic blind spots.

## HALT Conditions

- Any reviewer FAIL
- Any reviewer INSUFFICIENT_EVIDENCE persists after stage 13 collection
- Reviewer subagent crash → respawn once; second crash → HALT and escalate

## Retry Policy

- Reviewer FAIL: atom returns to stage 4 (build) with findings as input; max 3 review-iter per atom
- INSUFFICIENT_EVIDENCE: orchestrator dispatches stage 13 evidence sub-skill, then re-runs the requesting reviewer only

## /ck:code-review Wrapping

Per Phase 01 Discovery 1: `/ck:code-review` already has adversarial Stage 3 always-on, spec compliance review built-in, codebase parallel audit mode. Role 3 (code-quality) is a **thin wrapper** that invokes `/ck:code-review` with focused context. Roles 1, 2, 4, 5, 6 use bespoke prompts because no existing skill covers their angle.

## References

- Reviewer prompts: `references/reviewer-prompts/*.md` (Phase 04 deliverable)
- Preamble: `references/reviewer-prompts/preamble.md`
- v8.0 LAW-12 + GATE-17: `docs/ubs-v8-technical-hardening.md`
- Multi-agent review protocol: `references/multi-agent-review-protocol.md`
