# Phase 04 — Adversarial Reviewer Prompts

## Context Links

- Journal Section 9.4 (multi-agent adversarial review innovation)
- UBS v8.0 Section D (multi-agent review protocol)
- Phase 03 output (sub-skills/review/SKILL.md)

## Overview

- Priority: P0
- Status: pending
- Brief: write 6 adversarial reviewer prompt templates — all Opus 4.7, adversarial framing

## Key Insights

- "AI tự review cấp cao nhất" + "No human review" → adversarial framing CRITICAL
- Default LLM reviewer = sycophantic. Must explicitly instruct attack mode
- Consensus-bias risk → mitigate via mechanical gates as ground truth, not via more reviewers
- Each reviewer has ONE lens (don't mix concerns)

## Requirements

**Functional reviewer roster:**

| Role | Lens | Triggers FAIL |
|------|------|----------------|
| spec-attacker | Ambiguity, untestable criteria, missing edge case, scope creep | Any ambiguity found |
| spec-compliance-reviewer | Code matches spec line-by-line | Over/under-implementation |
| code-quality-reviewer | Dead code, naming, error handling, YAGNI/KISS/DRY | Any quality drift |
| backend-integrity-reviewer | 9 backend concerns from journal 4.7 | Missing any sub-check |
| architecture-bridge | Calls `/architecture-reviewer`, parses output | CRITICAL/HIGH from sub-agent |
| security-bridge | Calls `/ck:security`, parses output | Any CRITICAL/HIGH from sub-agent |

**Non-functional:**
- Each prompt ≤ 150 LOC
- All use Opus 4.7
- Adversarial framing explicit ("you are hired to find bugs, not approve work")
- Output format: structured (PASS/FAIL + findings list + severity)

## Architecture

Each prompt = `.md` file under `references/reviewer-prompts/`. Sub-skill `review` Skill.md loads + dispatches via Agent tool.

## Related Code Files

**Create (under `~/.claude/skills/build-anything/references/reviewer-prompts/`):**
- `spec-attacker.md`
- `spec-compliance-reviewer.md`
- `code-quality-reviewer.md`
- `backend-integrity-reviewer.md`
- `architecture-bridge.md`
- `security-bridge.md`

**Modify:**
- `sub-skills/review/SKILL.md` → dispatch logic referencing these prompts

## Implementation Steps

1. Write `spec-attacker.md`:
   - Frame: "your job is to break this spec, find every ambiguity"
   - Checklist: ambiguous verbs, missing edge cases, untestable criteria, hidden assumption, scope creep risk
   - Output: numbered findings + severity (BLOCKER/MAJOR/MINOR) + suggested fix
2. Write `spec-compliance-reviewer.md`:
   - Input: spec.md + diff
   - Task: line-by-line spec ↔ code comparison
   - FAIL if: missing requirement OR extra unrequested code
3. Write `code-quality-reviewer.md`:
   - Apply YAGNI/KISS/DRY explicitly
   - Detect: dead code, unclear naming, swallowed errors, premature abstraction, magic numbers
4. Write `backend-integrity-reviewer.md`:
   - 9 lenses from journal 4.7
   - For each: does code/test prove the property?
   - FAIL if any lens unverified
5. Write `architecture-bridge.md`:
   - Invoke `/architecture-reviewer` skill
   - Parse output
   - Translate CRITICAL/HIGH → FAIL
6. Write `security-bridge.md`:
   - Invoke `/ck:security` skill
   - Parse output
   - Translate CRITICAL/HIGH → FAIL
7. Validation: dry-run each prompt against sample diff, verify output structured

## Todo List

- [ ] spec-attacker.md
- [ ] spec-compliance-reviewer.md
- [ ] code-quality-reviewer.md
- [ ] backend-integrity-reviewer.md
- [ ] architecture-bridge.md
- [ ] security-bridge.md
- [ ] Update sub-skills/review/SKILL.md dispatch

## Success Criteria

- 6 prompt files exist, each ≤ 150 LOC
- Each prompt has explicit adversarial framing
- Each has structured output spec
- Sub-skill `review` invokes all 6 in parallel via Agent tool
- Consensus rule: ANY reviewer FAIL → atom HALT

## Risk Assessment

- Reviewer prompt drift to sycophancy (mitigation: explicit "find bugs not approve" line + reject-by-default framing)
- Output format inconsistency (mitigation: strict template at end of each prompt)
- Cost (6 × Opus call per atom ≈ $1-3) (mitigation: cache + skip on green mechanical)

## Security Considerations

- Reviewers see code — must not paste secrets
- security-bridge reviewer is gatekeeper for LAW-04/05/16

## Next Steps

- Phase 07 dry-run will validate reviewer prompts catch seeded bugs
