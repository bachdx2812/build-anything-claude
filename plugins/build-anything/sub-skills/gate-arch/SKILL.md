---
name: build-anything-gate-arch
description: Stage 8 — architecture review for layer violations, dependency cycles, coupling drift; thin wrapper around `architecture-reviewer` skill + `system-design-advisor` Q&A
---

# gate-arch — Stage 8 Architecture Gate

**Maps to:** stage 8 of `/build-anything`. Implements GATE-13. Addresses journal §4.8 (architecture review absent in v7.5).

## Inputs

- Atom diff
- Project architecture baseline (if `docs/system-architecture.md` exists, read for layer rules)
- Module dependency graph snapshot pre-atom

## Outputs

- `{atom_dir}/gate-arch/cycle-report.json`
- `{atom_dir}/gate-arch/layer-report.json`
- `{atom_dir}/gate-arch/coupling-report.json`
- `{atom_dir}/gate-arch/reviewer.json` (architecture-bridge reviewer output)
- Verdict `{ "stage": 8, "verdict": "PASS|FAIL", "findings": [...] }`

## Checks

| Check | Tool | Pass criteria |
|-------|------|---------------|
| Dependency cycles | `madge` (JS/TS) / `dependency-cruiser` / `pydeps` / `gomvarcheck` | 0 new cycles |
| Layer violations | reviewer + rule engine | UI does not call DB directly; business logic not in route handler |
| Coupling delta | `madge --orphans --circular` + diff | ≤ +5 % on changed module |
| Cumulative complexity | `lizard` or language-equivalent | no function exceeding 30 cyclomatic in diff |
| Reviewer pass | `architecture-bridge.md` (Opus 4.7) | PASS verdict |

## Tool Delegation

- `architecture-reviewer` skill (catalogued Phase 01) — primary review engine
- `system-design-advisor` for Q&A when ambiguity arises
- `code-pattern-reviewer` referenced for any anti-pattern overlap; results dedup'd against stage 9

## Layer Rule Examples

Default rules (overridable per project in `.build-anything.json`):

```yaml
layers:
  - name: ui
    may_import: [shared, presentation]
    may_not_import: [db, infra]
  - name: business
    may_import: [shared]
    may_not_import: [ui]
  - name: db
    may_import: [shared]
    may_not_import: [ui, business]
```

Project may override or extend. Missing config → reviewer attests "no formal layer rules; soft check only."

## HALT Conditions

- Any new dependency cycle
- Any layer violation
- Coupling delta > threshold
- Reviewer FAIL

## Cumulative Atom Impact

This stage queries the BUILD ARCHIVE for the last 10 atoms and checks the trajectory:
- Average coupling rising over 10 atoms → emit WARNING (not FAIL) and require architecture-bridge reviewer attestation that drift is intentional
- Cycle count rising over 10 atoms → FAIL the current atom even if it does not itself add a cycle (the trend is unsustainable)

This catches the "100 atoms compose into spaghetti" failure mode (journal §4.8).

## Retry Policy

- AL ≤ 2: HALT
- AL ≥ 3: emit refactor-note atom suggestion; do NOT auto-refactor (architecture changes need human assent)

## References

- v8.0 GATE-13: `docs/ubs-v8-technical-hardening.md`
- `architecture-reviewer` skill (Phase 01 catalogue)
- Reviewer prompt: `references/reviewer-prompts/architecture-bridge.md`
- Journal §4.8: architectural decay rationale
