# 14-Stage Flow — Reference

The detailed expansion of the orchestrator table. Each stage notes inputs, sub-skill, primary gate, HALT condition, time budget, cost budget.

```text
[ 0 ] PRE-FLIGHT
      In:  user feature description + .build-anything.json
      Sub: (orchestrator)
      Gate: config sanity
      HALT: missing config / unresolved active plan
      Budget: < 1 min, < $0.10
      Out: atom_dir/, project_type, AL level

[ 1 ] SPEC ATOM (L1)
      In:  feature description, project rules
      Sub: spec
      Gate: GATE-0 brief complete + testable
      HALT: non-testable criteria after 3 refinement loops
      Budget: 5 min, $0.30
      Out: spec.md, predict_failures

[ 2 ] SCHEMA / SERVICE (L2)
      In:  approved spec
      Sub: schema
      Gate: GATE-1 allowlist + schema lint
      HALT: allowlist violation
      Budget: 5 min, $0.30
      Out: openapi.yaml | migration.sql | types.* | invariants.sql

[ 3 ] RED-TEAM SPEC
      In:  spec + schema
      Sub: spec (adversarial mode)
      Gate: spec-attacker reviewer PASS
      HALT: ambiguity remains after 3 loops
      Budget: 5 min, $0.50
      Out: spec-attacker.json

[ 4 ] BUILD (L3)
      In:  spec + schema (frozen)
      Sub: implementer
      Gate: GATE-1 + GATE-2 + LAW-04 (secret)
      HALT: allowlist violation / secret leak / 3 compile failures
      Budget: 15 min, $1.50
      Out: diff.patch + RED/GREEN/REFACTOR commits

[ 5 ] MECHANICAL GATES
      In:  diff + thresholds
      Sub: gate-mechanical
      Gate: GATE-10 cov + GATE-11 mutation + GATE-16 property + lint + type
      HALT: any threshold breach
      Budget: 10 min, $0.50 (mutation drives most)
      Out: per-gate JSON

[ 6 ] BACKEND INTEGRITY  ⭐ differentiator
      In:  diff + .build-anything.json backend config + test DB
      Sub: gate-backend
      Gate: GATE-18 a–f + GATE-19 + GATE-20 + GATE-21 (as applicable)
      HALT: any sub-gate fail
      Budget: 10 min, $0.30 (mostly DB I/O, not LLM)
      Out: per-sub-gate JSON

[ 7 ] SECURITY
      In:  diff + endpoint list + dep manifest
      Sub: gate-security
      Gate: GATE-12 — 0 CRITICAL/HIGH
      HALT: any CRITICAL/HIGH finding
      Budget: 5 min, $0.50
      Out: sast.json, dep-audit.json, secret-scan.json, threat-model.json

[ 8 ] ARCHITECTURE
      In:  diff + module graph baseline
      Sub: gate-arch
      Gate: GATE-13 — no new cycle, no layer violation
      HALT: new cycle / layer violation / reviewer FAIL
      Budget: 5 min, $0.40
      Out: cycle-report.json, layer-report.json, reviewer.json

[ 9 ] CODE PATTERNS
      In:  diff
      Sub: gate-pattern
      Gate: no HIGH anti-pattern
      HALT: HIGH severity finding
      Budget: 3 min, $0.30
      Out: findings.json

[10 ] SPEC-COMPLIANCE + SPEC-ATTACKER L4 REVIEW
      In:  diff + spec
      Sub: review (roles 1 + 2)
      Gate: GATE-17 — both PASS
      HALT: any reviewer FAIL
      Budget: 5 min, $0.80
      Out: spec-attacker.json, spec-compliance.json

[11 ] CODE-QUALITY + (cond. backend-integrity + arch + security) L4 REVIEW
      In:  diff + stage 5–9 verdicts
      Sub: review (roles 3..6)
      Gate: GATE-17 — all PASS
      HALT: any reviewer FAIL
      Budget: 7 min, $1.50 (4 parallel reviewers)
      Out: code-quality.json, backend-integrity.json, architecture-bridge.json, security-bridge.json

[12 ] PERF + OBSERVABILITY
      In:  diff + project_type + baselines
      Sub: gate-perf
      Gate: GATE-14 + GATE-15
      HALT: budget breach / missing instrumentation
      Budget: 5 min, $0.30
      Out: lighthouse.json, bundle.json, load.json, observability.json

[13 ] EVIDENCE BUNDLE
      In:  all preceding stage outputs
      Sub: evidence
      Gate: LAW-17 manifest sealed
      HALT: missing artifact / hash mismatch
      Budget: 1 min, $0.05
      Out: manifest.json, manifest.sha256, BUILD ARCHIVE append

[14 ] PROD-VERIFY (L6)
      In:  manifest + rollback path + deploy auth
      Sub: verify
      Gate: GATE-6 (v7.5) + GATE-16 rollback drill + GATE-15 continuity
      HALT: user did not confirm / smoke fail / invariant violation on prod
      Budget: 10 min, $0.50
      Out: deploy-log.json, smoke.json, db-invariant-prod.json, rollback-drill.json
```

## Cumulative atom budget (default)

- Time: ~ 90 min worst case (most stages run in parallel where possible)
- Cost: ~ $7 USD worst case (under AL-4 breaker ceiling of $5 per single autonomous iter; cap is per iter, not per total)

## Per-stage status emission

After each stage, orchestrator emits one short line to user:
```
[ATOM-260526-foo] stage 5/14 mechanical PASS (cov 84%, mut 67%, prop 12 tests)
```

No verbose narration — boss reads quickly.
