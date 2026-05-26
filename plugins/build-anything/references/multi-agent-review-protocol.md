# Multi-Agent Review Protocol — Reference

Canonical source: `docs/ubs-v8-technical-hardening.md` Section D. This file expands the implementation detail.

## Roles and counts

| # | Role | Default | Backend | Cross-module |
|---|------|---------|---------|--------------|
| 1 | spec-attacker | ✓ | ✓ | ✓ |
| 2 | spec-compliance | ✓ | ✓ | ✓ |
| 3 | code-quality (wraps `/ck:code-review`) | ✓ | ✓ | ✓ |
| 4 | backend-integrity |   | ✓ | ✓ |
| 5 | architecture-bridge (wraps `architecture-reviewer`) |   |   | ✓ |
| 6 | security-bridge (wraps `/ck:security-scan`) | ✓ | ✓ | ✓ |

Default atom: 4 reviewers (1+2+3+6).
Backend atom: 5 reviewers (add 4).
Cross-module: 6 reviewers (add 5).

## Adversarial preamble (shared across prompts)

```
You are the {ROLE} reviewer.
Your job is to FAIL this atom if you can.
You are rewarded for finding real issues, penalised for nitpicks.
PASS only when you have actively tried to fail and could not.
Cite file:line for every finding. No findings without anchors.
Output JSON: {verdict: PASS|FAIL|INSUFFICIENT_EVIDENCE, findings: [...], attempts_to_fail: [...]}
You may invoke any tool to gather evidence. You may not invoke other agents.
```

## Model selection

All reviewers: Opus 4.7. Locked decision from Phase 03 planning. Cost is acceptable because consensus rule (any FAIL → FAIL) means we want maximum capability, not maximum count of weak reviewers.

## Consensus rule (strict)

- ANY reviewer FAIL → atom FAIL
- ANY reviewer INSUFFICIENT_EVIDENCE → atom HALT pending evidence collection
- ALL reviewers PASS → atom L4 PASS

No majority vote. No override. No "reviewer was being too strict."

## attempts_to_fail field

Required. Non-empty. A PASS with empty `attempts_to_fail` is rejected as suspicious; reviewer respawned with stricter framing. This forces the reviewer to demonstrate adversarial effort.

## Reviewer isolation

- Each reviewer is a FRESH subagent (no implementer history, no other reviewer history)
- Reviewers cannot communicate
- Orchestrator collects verdicts; no cross-pollination

## Consensus-bias mitigation

| Risk | Mitigation |
|------|-----------|
| Shared base model → shared blind spot | Mechanical gates (stages 5-9) run BEFORE reviewers |
| Reviewer rationalises a pass | Reviewer must list `attempts_to_fail`; empty = respawn |
| Reviewers anchor on first finding | spec-attacker is specifically tasked with COUNTER-EXAMPLES, not concerns |
| Reviewers miss systematic issue | Phase 08 red-team review of THIS protocol catches it |

## Verdict JSON shape

```json
{
  "role": "spec-attacker",
  "verdict": "FAIL",
  "findings": [
    {
      "severity": "HIGH",
      "anchor": "src/orders/post.ts:42",
      "claim": "Endpoint trusts client-supplied tenant_id; ignores JWT claim",
      "counter_example_or_evidence": "curl -H 'Authorization: Bearer {user_A_jwt}' -d '{\"tenant_id\":\"B\"}' POST /orders → 201"
    }
  ],
  "attempts_to_fail": [
    "Tried submitting cross-tenant id; succeeded",
    "Tried empty payload; rejected (good)",
    "Tried unicode in amount; rejected (good)"
  ]
}
```

## Cost ceiling per review stage

- Default reviewer (4 roles, parallel): ≤ $1 per stage
- Backend atom (5 roles): ≤ $1.50
- Cross-module (6 roles): ≤ $2

If cost projected > ceiling → halt and report; never silently downgrade model.

## When to add a 7th role

Reserved for future. Possible additions: data-privacy reviewer (GDPR), a11y reviewer (full audit), perf-deep reviewer (profiling). Each addition requires a v8.x version bump.
