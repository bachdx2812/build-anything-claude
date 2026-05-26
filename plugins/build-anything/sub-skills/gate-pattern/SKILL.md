---
name: build-anything-gate-pattern
description: Stage 9 — code pattern review (anti-pattern detection, pattern compliance, YAGNI/KISS/DRY); thin wrapper around `code-pattern-reviewer` skill
---

# gate-pattern — Stage 9 Code Pattern Gate

**Maps to:** stage 9 of `/build-anything`. Advisory in default mode, blocking when severity is HIGH. Addresses code-quality drift below architecture level.

## Inputs

- Atom diff
- Project patterns hint from `.build-anything.json` `patterns.*` (optional)

## Outputs

- `{atom_dir}/gate-pattern/findings.json`
- Verdict `{ "stage": 9, "verdict": "PASS|FAIL|ADVISORY", "findings": [...] }`

## Tool Delegation

- `code-pattern-reviewer` skill (catalogued Phase 01) — AI-only pattern detection
- `design-patterns-advisor` for guidance when reviewer flags ambiguity
- `pattern-implementation-guide` for refactor suggestions

## Checks

| Category | Pattern detected | Severity routing |
|----------|------------------|------------------|
| Anti-patterns | god class, shotgun surgery, feature envy | HIGH → FAIL |
| YAGNI violation | speculative abstraction, unused parameter | MEDIUM → ADVISORY |
| KISS violation | premature optimisation, clever one-liner | MEDIUM → ADVISORY |
| DRY violation | copy-pasted block ≥ 5 lines | HIGH → FAIL |
| Naming | unclear identifier, inconsistent convention | LOW → ADVISORY |
| Dead code | unreachable branch, unused import | MEDIUM → ADVISORY |

## Severity Routing

- HIGH → atom FAIL; refactor required
- MEDIUM → atom PASS with findings; spawn follow-up atom if priority warrants
- LOW → atom PASS; logged for trend monitoring (per stage 8 cumulative impact)

## Why Advisory by Default

Not every pattern hit needs to block. Boss's UBS prioritises shipping atomic value; pattern hygiene is downstream of correctness. Threshold for FAIL is reserved for patterns that cause measurable harm (god class → testability collapse; DRY violation → bug propagation surface).

## HALT Conditions

- Any HIGH severity finding
- Reviewer cannot complete analysis (tool error)

## Retry Policy

- HIGH finding: atom must refactor and re-run from stage 4
- MEDIUM / LOW: optional follow-up atom

## Tool Notes

This is the lightest gate in the suite. If `code-pattern-reviewer` skill is unavailable on the host, this gate degrades to ADVISORY-only and emits a warning.

## References

- `code-pattern-reviewer` skill (Phase 01 catalogue)
- `design-patterns-advisor` skill (Phase 01 catalogue)
- v8.0: no dedicated LAW or GATE — covered by overall code-quality reviewer at stage 11
