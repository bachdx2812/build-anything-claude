# Phase 01 — Skill Catalog Deep-Dive

## Context Links

- Journal: `../reports/journal-260526-1156-ubs-discovery-and-skill-design.md` (Section 8)
- Existing partial map: ~55% coverage already identified

## Overview

- Priority: P0 (blocks 02-03)
- Status: pending
- Brief: read remaining skills not yet examined, finalize coverage gap map

## Key Insights

- ~55% coverage from skills already mapped (`/ck:security`, `/code-pattern-reviewer`, `/architecture-reviewer`, `/ck:loop`, superpowers:*)
- 45% gap: backend integrity (9 sub-gates), observability, perf-backend, cost, mutation, property-based, API contract, idempotency, multi-tenant isolation
- Need verify: `/ck:cook`, `/ck:autoresearch`, TDD-related skills, `superpowers:dispatching-parallel-agents`, `deploy/ship/devops` skills

## Requirements

**Functional:**
- Read each unexamined skill's SKILL.md
- Map skill capability → UBS gap addressed
- Identify orchestration patterns reusable in `/build-anything`

**Non-functional:**
- Read-only phase (no skill modification)
- Output ≤ 300 lines markdown

## Architecture

Read-only investigation. Output single report file consumed by Phase 02 + 03.

## Related Code Files

**Read:**
- `~/.claude/skills/ck-cook/SKILL.md`
- `~/.claude/skills/ck-autoresearch/SKILL.md`
- `~/.claude/skills/superpowers/SKILL.md` and any TDD-named sub-skills
- `~/.claude/skills/superpowers/dispatching-parallel-agents/SKILL.md` if exists
- `~/.claude/skills/deploy/SKILL.md`
- `~/.claude/skills/ship/SKILL.md`
- `~/.claude/skills/devops/SKILL.md`
- `~/.claude/skills/databases/SKILL.md`
- `~/.claude/skills/chrome-devtools/SKILL.md`

**Create:**
- `reports/phase-01-skill-coverage-final.md`

**Modify:** none

## Implementation Steps

1. List all skills under `~/.claude/skills/` via Bash `ls -la ~/.claude/skills/`
2. For each skill not yet read, read SKILL.md (top of file, frontmatter + description sufficient)
3. Map to UBS gap table (extend Section 8 of journal)
4. Identify reusable orchestration patterns (parallel dispatch, subagent isolation, evidence collection)
5. Output `reports/phase-01-skill-coverage-final.md` with:
   - Skill inventory table
   - Coverage % final (target: have clear delta from 55%)
   - Per-gap recommendation (use existing skill | invoke external tool | build new)

## Todo List

- [ ] List all skills directory
- [ ] Read ck-cook SKILL.md
- [ ] Read ck-autoresearch SKILL.md
- [ ] Read superpowers TDD sub-skill (if exists)
- [ ] Read dispatching-parallel-agents
- [ ] Read deploy/ship/devops
- [ ] Read databases
- [ ] Read chrome-devtools
- [ ] Build coverage table
- [ ] Write phase-01-skill-coverage-final.md

## Success Criteria

- All skills referenced in journal Section 8 have been read
- Coverage final % documented (≥55%)
- Each of 21 gaps has recommendation: existing skill name OR external tool OR "build new"
- Report file < 300 lines

## Risk Assessment

- Skill content may have changed since last session (mitigation: re-read, don't trust memory)
- Some skills may not exist (mitigation: note absence in report)

## Security Considerations

- Read-only; no secrets handled

## Next Steps

- Output feeds Phase 02 (which gaps need new LAW/GATE entries)
- Output feeds Phase 03 (which existing skills to invoke from `/build-anything`)
