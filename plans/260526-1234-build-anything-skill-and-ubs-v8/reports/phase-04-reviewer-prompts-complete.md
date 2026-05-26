# Phase 04 — Reviewer Prompts — Completion Report

**Date:** 2026-05-26
**Phase:** 04 of 09
**Status:** COMPLETE
**Output dir:** `/Users/macos/.claude/skills/build-anything/references/reviewer-prompts/`

## Files written (7)

| File | LOC | Role | Key innovation |
|------|----:|------|----------------|
| `preamble.md` | 64 | shared | "Your job is to FAIL this atom if you can" — highest-leverage line in entire skill |
| `spec-attacker.md` | 70 | spec-attacker | Hunts ambiguity, untestable criteria, missing edge cases; required 5 attack attempts |
| `spec-compliance-reviewer.md` | 76 | spec-compliance | Mode A (under-impl) + Mode B (over-impl/YAGNI); allowlist boundary check |
| `code-quality-reviewer.md` | 78 | code-quality | YAGNI/KISS/DRY + 16-item smell catalogue; wraps `/ck:code-review` |
| `backend-integrity-reviewer.md` | 75 | backend-integrity | THE differentiator — 9 sub-gates + N/A dishonesty detection |
| `architecture-bridge.md` | 70 | architecture-bridge | Delegates to `architecture-reviewer` subagent + independent cycle check |
| `security-bridge.md` | 88 | security-bridge | Delegates to `/ck:security-scan` + LAW-04 secret regex + dep CVE |

**Total: 521 LOC across 7 files. All under 150-LOC budget per file.**

## SKILL.md dispatch updated

`sub-skills/review/SKILL.md` table updated: rows 2-4 filenames now match the `-reviewer` suffix used by the actual files (was `spec-compliance.md` → now `spec-compliance-reviewer.md`; same for code-quality and backend-integrity).

## Architectural decisions locked

| Decision | Locked | Why |
|----------|--------|-----|
| Adversarial framing language | "You are graded on findings, not agreement" | Phase 01 Discovery 4: default LLMs are sycophantic |
| Verdict JSON shape | `role / verdict / findings[] / attempts_to_fail[] / elapsed_ms / tools_used[]` | Machine-parseable for orchestrator + audit-friendly |
| Required `attempts_to_fail` | non-empty, else respawn | Forces real attack work, not rubber-stamp |
| Tool delegation strategy | wrap existing skills where they cover the lens (`/ck:code-review`, `/ck:security-scan`, `architecture-reviewer`); bespoke prompts only where no skill exists (spec-attacker, spec-compliance, backend-integrity) | Phase 01 Discovery 1 — avoid duplication |
| Cost target per reviewer | $0.25-$0.40 (backend-integrity highest) | Allows ≤ $1.50 ceiling for default 4-reviewer atom |
| LAW-04 secret detection | independent regex + dep audit; CRITICAL = demote to AL-0 | Boss requirement non-negotiable |

## v8.0 LAW-12 coverage

| LAW-12 requirement | Where implemented |
|---------------------|-------------------|
| ≥ 3 reviewers per atom | review SKILL.md sets default 4, configurable 5/6 |
| All reviewers Opus 4.7 | preamble + multi-agent-review-protocol.md |
| Adversarial framing | preamble.md |
| Cite file:line | all 6 role prompts |
| Strict consensus (ANY FAIL → FAIL) | review SKILL.md + preamble.md |
| Reviewer isolation | review SKILL.md spawn-as-fresh-subagent |
| INSUFFICIENT_EVIDENCE handling | review SKILL.md HALT condition |

100% coverage.

## What changed vs Phase 04 plan

| Plan said | Built | Reason |
|-----------|-------|--------|
| files `spec-compliance-reviewer.md`, `code-quality-reviewer.md`, `backend-integrity-reviewer.md` | same names | preserved |
| `architecture-bridge.md`, `security-bridge.md`, `spec-attacker.md` | same | preserved |
| Update review SKILL.md dispatch | done (Edit) | filename consistency fix |
| Validation: dry-run each prompt against sample diff | DEFERRED to Phase 07 | dry-run validation is Phase 07's mandate |

No silent scope expansion. No silent scope cut.

## Pending for Phase 05

10 bash scripts under `scripts/mechanical/`:
- coverage-check.sh
- mutation-test.sh
- property-test-runner.sh
- lint-check.sh
- type-check.sh
- bundle-budget.sh
- lighthouse-check.sh
- load-test-smoke.sh
- observability-check.sh
- verify-manifest.sh
- (+ `_common.sh` for stack detection)

## Pending for Phase 06

9 bash scripts under `scripts/backend/` (the differentiator) + `_common.sh`.

## Open questions

1. **`/ck:code-review` model forcing.** Does it accept `--model opus`? If not, code-quality reviewer needs to spawn Opus directly. Verify in Phase 07.
2. **`architecture-reviewer` subagent type.** Verified `everything-claude-code:architect` exists. The bridge prompt names this explicitly.
3. **`/ck:security-scan` skill registration.** Verify exists at dry-run time; fallback to `everything-claude-code:security-reviewer` subagent.

## Status

**Status:** DONE
**Summary:** 7 reviewer prompt files written; review/SKILL.md dispatch table corrected; LAW-12 fully covered. Ready for Phase 05 mechanical gate scripts.
**Concerns:** none material — 3 dry-run-time verifications scheduled in Phase 07.
