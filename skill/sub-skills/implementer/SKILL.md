---
name: build-anything-implementer
description: Stage 4 — TDD-style L3 implementation inside the atom's allowlist; fresh subagent context; self-review before handoff to mechanical gates. Folder named `implementer` to avoid scout-block `build` pattern.
---

# implementer — L3 Build (the implementation stage)

**Maps to:** stage 4 of `/build-anything` flow. Implements LAW-02 (allowlist) and LAW-08 (append-only history). Despite the folder name `implementer`, this is the "build" stage of UBS terminology.

## Inputs

- Atom brief (stage 1 + 3 PASS)
- Schema artifacts (stage 2 PASS)
- `.build-anything.json` config (test runner, language version)

## Outputs

- Diff inside allowlist
- Failing-then-passing test commits (TDD evidence in git history)
- Verdict `{ "stage": 4, "verdict": "PASS|FAIL", "findings": [...] }`

## TDD Order (mandatory)

1. **RED** — write failing test for each success criterion; commit `test: {atom-code} red`
2. **GREEN** — minimal implementation; tests pass; commit `feat: {atom-code} green`
3. **REFACTOR** — clean per coding-style.md; tests still pass; commit `refactor: {atom-code}`

Each commit is checked at stage 5 by `gate-mechanical` for advance.

## Mechanical Pass Criteria

- Build / compile succeeds
- All RED tests now GREEN
- Diff stays inside allowlist (LAW-02)
- No new TODOs, `console.log`, `print` debug statements
- Each commit is atomic and contributes to the atom (GATE-2)

## GATE-1 Enforcement

Pre-commit hook checks `git diff --name-only` against allowlist. Out-of-allowlist path → STOP, do not commit. Failed enforcement → HALT atom and demote AL one rung.

## GATE-2 Enforcement

Every commit must reference the atom code in message AND modify only allowlisted paths AND not regress any previously-passing test. This sub-skill rejects non-conforming commit messages and reverts.

## HALT Conditions

- Allowlist violation (LAW-02)
- Test suite regression in non-atom areas
- Compile failure after 3 fix-and-retry iterations
- Implementer agent tries to bypass spec (e.g. removes a criterion to make tests pass)
- Secret detected in diff (LAW-04)

## Self-Review Before Handoff

Before reporting PASS to orchestrator, the implementer subagent MUST:
1. Run full test suite locally; zero regression
2. Verify each success criterion has at least one assertion in the test suite
3. Allowlist clean
4. Run `gitleaks` or equivalent on diff (LAW-04)
5. No debug leftovers (`console.log`, `print(...)`, `debugger`, `pdb.set_trace()`)

Self-review is NOT a substitute for stages 5–11 — it is a precondition.

## Retry Policy

- Compile failure: 3 attempts with error-driven fix
- Test failure: 3 attempts
- Allowlist violation: 0 retries (immediate HALT)
- Secret leak: 0 retries (immediate HALT)

## Subagent Spawn Contract

This sub-skill spawns a fresh implementer subagent (subagent_type `fullstack-developer` or `claude` with detailed brief). The implementer receives:

- Atom brief
- Schema artifacts
- Allowlist (file glob list)
- Test runner command from `.build-anything.json`
- Forbidden patterns list (no mock data, no commented-out code, no skipped tests, no hardcoded creds)

The implementer DOES NOT receive: stages 5–11 reviewer prompts. Avoids teaching-to-the-test bias.

## Tools Used

- Skill tool to spawn implementer subagent
- Native test runner from project (`pnpm test`, `pytest`, `go test`, etc.)
- `gitleaks` for secret scan
- Git for commit-by-commit TDD evidence

## References

- TDD discipline: `superpowers:test-driven-development` skill (Phase 01 catalogue)
- Coding style: `coding-style.md` per global rules
- LAW-02 allowlist: v7.5 (preserved)
- LAW-04 secret law: v7.5 (preserved, never weakened)
