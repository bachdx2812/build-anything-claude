# Phase 03 — `/build-anything` Sub-Skill Suite Design

## Context Links

- Journal Section 9 (design intent, 14-stage flow)
- Journal Section 9.3 (proposed skill structure)
- Phase 02 output (LAW/GATE numbers to reference)

## Overview

- Priority: P0
- Status: pending
- Brief: design + write sub-skills modular suite — `build-anything:*` family

## Key Insights

- User chose sub-skills modular (not monolithic) — easier maintain + compose + selective invoke
- All reviewer agents = Opus 4.7
- Each sub-skill ≤ 200 LOC SKILL.md (per modularization rule)
- 14-stage flow split into composable sub-skills

## Requirements

**Functional sub-skill list:**

| Sub-skill | Purpose | Stages from flow |
|-----------|---------|------------------|
| `build-anything` | Orchestrator entry point | 0 (preflight) + dispatches sub-skills |
| `build-anything:spec` | Spec atom + red-team spec | 1, 3 |
| `build-anything:schema` | Schema/service generation | 2 |
| `build-anything:build` | TDD-style build with allowlist | 4 |
| `build-anything:gate-mechanical` | Coverage, mutation, property, lint, type | 5 |
| `build-anything:gate-backend` | 9 backend integrity sub-checks | 6 |
| `build-anything:gate-security` | Bridges to `/ck:security` | 7 |
| `build-anything:gate-arch` | Bridges to `/architecture-reviewer` | 8 |
| `build-anything:gate-pattern` | Bridges to `/code-pattern-reviewer` | 9 |
| `build-anything:review` | Adversarial multi-agent review (≥3 reviewers) | 10, 11 |
| `build-anything:gate-perf` | Lighthouse/CWV/bundle/load + a11y + observability | 12 |
| `build-anything:evidence` | Crypto bundle + screenshot + DB query result | 13 |
| `build-anything:verify` | Prod feature-flag flip + rollback drill | 14 |

**Non-functional:**
- Each sub-skill SKILL.md ≤ 200 LOC
- references/ + templates/ + scripts/ shared at suite root
- Frontmatter `name`, `description` per skill

## Architecture

```
~/.claude/skills/build-anything/
├── SKILL.md                              # orchestrator entry
├── references/
│   ├── ubs-philosophy.md                 # link to v8.0 doc
│   ├── atom-template.md
│   ├── 14-stage-flow.md
│   ├── multi-agent-review-protocol.md    # link to v8.0 Section D
│   ├── mechanical-gates.md               # link to v8.0 Section B (GATE-10/11/14/15)
│   ├── backend-integrity-gates.md        # link to v8.0 Section B (GATE-18-21)
│   ├── evidence-collection.md
│   └── reviewer-prompts/                 # phase 04 output dir
├── templates/
│   ├── build-log.md
│   ├── build-spec.md
│   ├── project-tracker.md
│   ├── build-archive.md
│   └── atom-brief.md
├── scripts/                              # phase 05+06 output dirs
│   ├── mechanical/
│   └── backend/
└── sub-skills/                           # each invoked via Skill tool
    ├── spec/SKILL.md
    ├── schema/SKILL.md
    ├── build/SKILL.md
    ├── gate-mechanical/SKILL.md
    ├── gate-backend/SKILL.md
    ├── gate-security/SKILL.md
    ├── gate-arch/SKILL.md
    ├── gate-pattern/SKILL.md
    ├── review/SKILL.md
    ├── gate-perf/SKILL.md
    ├── evidence/SKILL.md
    └── verify/SKILL.md
```

## Related Code Files

**Create (all under `~/.claude/skills/build-anything/`):**
- `SKILL.md` (orchestrator)
- 12 × `sub-skills/{name}/SKILL.md`
- `references/{8 files}.md`
- `templates/{5 files}.md`

**Modify:** none

## Implementation Steps

1. Create skill directory tree
2. Write root SKILL.md (orchestrator) — describes 14-stage flow, lists sub-skills, decision tree for which to skip
3. Write 12 sub-skill SKILL.md files in parallel batches
4. Write 8 references/ files
5. Write 5 templates/ files
6. Each sub-skill MUST:
   - Reference v8.0 LAW/GATE by number
   - Specify model (all Opus 4.7 for reviewers)
   - Define mechanical pass criteria
   - Specify HALT condition
   - Specify retry policy (max 3 iter default)
7. Validation pass: invoke each sub-skill in isolation, verify SKILL.md frontmatter loads

## Todo List

- [ ] Create dir tree
- [ ] Root SKILL.md
- [ ] sub-skills/spec/SKILL.md
- [ ] sub-skills/schema/SKILL.md
- [ ] sub-skills/build/SKILL.md
- [ ] sub-skills/gate-mechanical/SKILL.md
- [ ] sub-skills/gate-backend/SKILL.md
- [ ] sub-skills/gate-security/SKILL.md
- [ ] sub-skills/gate-arch/SKILL.md
- [ ] sub-skills/gate-pattern/SKILL.md
- [ ] sub-skills/review/SKILL.md
- [ ] sub-skills/gate-perf/SKILL.md
- [ ] sub-skills/evidence/SKILL.md
- [ ] sub-skills/verify/SKILL.md
- [ ] references/ × 8
- [ ] templates/ × 5

## Success Criteria

- Skill suite invocable: `Skill(build-anything)` triggers orchestrator
- Each sub-skill independently invocable
- All 14 stages from flow mapped to a sub-skill
- Each SKILL.md ≤ 200 LOC
- All references cross-link to v8.0 LAW/GATE numbers

## Risk Assessment

- Sub-skill explosion (12 files) hard to maintain (mitigation: shared references avoid duplication)
- Orchestrator complexity (mitigation: decision tree as ASCII flowchart in root SKILL.md)
- Sub-skill context bloat per invocation (mitigation: SKILL.md ≤ 200 LOC, references read on-demand)

## Security Considerations

- Sub-skill `verify` invokes prod ops — must enforce LAW-10 (explicit user confirm)
- Sub-skill `build` must enforce LAW-02 allowlist
- All scripts must scan for secrets pre-commit

## Next Steps

- Phase 04 writes reviewer prompts under `references/reviewer-prompts/`
- Phase 05 writes mechanical scripts under `scripts/mechanical/`
- Phase 06 writes backend scripts under `scripts/backend/`
