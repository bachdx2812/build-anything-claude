# Phase 07 — Dry-Run Validation on Toy Project

## Context Links

- Phase 03 (skill suite)
- Phase 04 (reviewer prompts)
- Phase 05 (mechanical scripts)
- Phase 06 (backend integrity scripts)

## Overview

- Priority: P0
- Status: pending
- Brief: end-to-end run `/build-anything` on toy project with seeded bugs, verify all 14 stages + 12 gates fire correctly

## Key Insights

- Without dry-run, skill claims "works" = unverified — exactly the boss/Devin pattern we critique
- Toy project must include: frontend, backend, DB, multi-tenant scaffold, background queue
- Seed N bugs across categories; expect each to be caught by correct gate
- Apply LAW-03 EVIDENCE to ourselves — produce real evidence skill works

## Requirements

**Functional:**
- Toy project: minimal full-stack app with intentional vulnerabilities
- Seed bugs covering each gate (12 categories minimum)
- Run `/build-anything` end-to-end, capture stage-by-stage results
- Each gate must catch its assigned bug
- Generate evidence bundle per atom

**Non-functional:**
- Dry-run cost ≤ $10 (per atom)
- Total dry-run time ≤ 30 min
- Output report ≤ 400 LOC

## Architecture

```
plans/260526-1234-build-anything-skill-and-ubs-v8/dry-run/
├── toy-project/                 # minimal full-stack
│   ├── frontend/                # Next.js or Vite
│   ├── backend/                 # Express or FastAPI
│   ├── db/                      # SQLite or Postgres docker
│   └── .build-anything.json
├── seeded-bugs.md               # bug catalog + expected gate
└── results.md                   # per-stage observation
```

## Related Code Files

**Create:**
- `dry-run/toy-project/` — full toy project
- `dry-run/seeded-bugs.md` — bug catalog
- `reports/phase-07-dry-run-results.md` — outcome

**Modify:** none (skill should not need modification if 03-06 done well)

## Implementation Steps

1. Scaffold toy project (minimal full-stack)
2. Define seeded bugs catalog:
   - Coverage gap (untested branch) → GATE-10
   - Surviving mutant (assertion too weak) → GATE-11
   - Hardcoded API key → LAW-04
   - SQL injection vector → LAW-16/GATE-12
   - N+1 query → GATE-14
   - Missing logging → GATE-15
   - DB invariant violation (orphan row producer) → GATE-18
   - API contract drift (response field renamed) → GATE-19
   - Non-idempotent endpoint → GATE-20
   - Multi-tenant leak (missing WHERE tenant_id) → GATE-21
   - Architecture violation (UI calls DB direct) → GATE-13
   - Ambiguous spec → spec-attacker reviewer
3. Run `/build-anything` on toy project per stage
4. Record per-stage:
   - Stage triggered? YES/NO
   - Bug caught? YES/NO/PARTIAL
   - Time + cost
   - False positives (gate fired on correct code)
5. Fix any gate that missed its seeded bug — return to Phase 05/06
6. Write results report

## Todo List

- [ ] Scaffold toy frontend
- [ ] Scaffold toy backend + DB
- [ ] Scaffold multi-tenant fixtures
- [ ] Scaffold background queue
- [ ] Write seeded-bugs.md catalog (12 bugs)
- [ ] Run skill end-to-end
- [ ] Record per-stage results
- [ ] Fix any gate misses
- [ ] Write phase-07-dry-run-results.md

## Success Criteria

- All 12 seeded bugs caught by correct gate
- Zero false positives (gates only fire on real issues)
- Cost ≤ $10 per atom
- Time ≤ 30 min total
- Evidence bundle generated automatically
- Results report < 400 LOC

## Risk Assessment

- Toy project too simple → misses real-world complexity (mitigation: include multi-tenant + bg queue + DB constraints)
- Cost overrun (mitigation: $10 ceiling, halt at 80%)
- Gate misses bug (mitigation: this IS the test — fix gate before proceeding)
- False positive (mitigation: tune threshold, document)

## Security Considerations

- Toy project must NOT be deployed (mitigation: docker-compose local only)
- Seeded vulnerabilities must NOT exist in real code (mitigation: separate dir)

## Next Steps

- Phase 08 adversarial review of skill design based on dry-run findings
