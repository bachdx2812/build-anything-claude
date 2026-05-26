# Evidence Collection — Reference

Canonical source: `docs/ubs-v8-technical-hardening.md` LAW-17 + stage 13 sub-skill SKILL.md. This file is the on-disk layout + verification command.

## Evidence dir layout per atom

```
{project_root}/.build-anything/atoms/{atom_code}/
├── spec.md
├── schema/
│   ├── openapi.yaml
│   ├── migration.sql
│   ├── invariants.sql
│   └── types.ts
├── diff.patch
├── gate-mechanical/
│   ├── coverage.json
│   ├── mutation.json
│   ├── property.json
│   ├── lint.json
│   ├── type.json
│   └── bundle.json (if FE)
├── gate-backend/                  (if applicable)
│   ├── db-invariant.json
│   ├── concurrency.json
│   ├── transaction-atomicity.json
│   ├── background-job.json
│   ├── audit-log.json
│   ├── authorization.json
│   ├── api-contract.json
│   ├── idempotency.json
│   └── multi-tenant-isolation.json
├── gate-security/
│   ├── sast.json
│   ├── dep-audit.json
│   ├── secret-scan.json
│   └── threat-model.json
├── gate-arch/
│   ├── cycle-report.json
│   ├── layer-report.json
│   └── reviewer.json
├── gate-pattern/
│   └── findings.json
├── review/
│   ├── spec-attacker.json
│   ├── spec-compliance.json
│   ├── code-quality.json
│   ├── backend-integrity.json     (if applicable)
│   ├── architecture-bridge.json   (if cross-module)
│   └── security-bridge.json
├── gate-perf/
│   ├── lighthouse.json (FE)
│   ├── bundle.json (FE)
│   ├── load.json (BE)
│   └── observability.json
├── evidence/                       (artifacts — screenshots, query results, contract reports)
│   ├── screenshot-{ts}.png
│   ├── db-query-{name}.txt
│   └── ...
├── verify/                         (stage 14 outputs)
│   ├── preflight.json
│   ├── deploy-log.json
│   ├── post-deploy-smoke.json
│   ├── db-invariant-prod.json
│   ├── rollback-drill.json
│   ├── error-rate.json
│   └── latency.json
├── verdicts.json                   (orchestrator-aggregated)
├── manifest.json                   (LAW-17)
└── manifest.sha256                 (LAW-17 single-line hash)
```

## Manifest schema (LAW-17)

```json
{
  "atom_code": "ATOM-260526-foo",
  "atom_layer": "L5_PRE_MERGE",
  "iter": 1,
  "git_sha": "abc123...",
  "al_level": 3,
  "timestamp": "2026-05-26T12:34:56Z",
  "artifacts": [
    {
      "path": "gate-mechanical/coverage.json",
      "sha256": "...",
      "size_bytes": 1234,
      "produced_by": "scripts/mechanical/coverage-check.sh",
      "gate": "GATE-10"
    }
  ],
  "verdict_summary": {
    "stages": [
      { "stage": 1, "verdict": "PASS" }
    ]
  },
  "manifest_version": "1.0"
}
```

The manifest itself is SHA-256-hashed and the hash recorded in `manifest.sha256` and appended to BUILD ARCHIVE (LAW-08 append-only).

## Verification command

```sh
~/.claude/skills/build-anything/scripts/mechanical/verify-manifest.sh \
  /path/to/.build-anything/atoms/{atom_code}/
```

Output:
```
verify-manifest: {atom_code}
  manifest_sha256: PASS (matches manifest.sha256)
  artifact verification:
    gate-mechanical/coverage.json: PASS
    gate-mechanical/mutation.json: PASS
    ...
  RESULT: PASS — manifest is intact
```

Any mismatch → manifest INVALID → atom retroactively HALT → AL demote to 0.

## Append to BUILD ARCHIVE

Project-level append-only log at `{project_root}/.build-anything/BUILD-ARCHIVE.md`:

```
2026-05-26T12:34:56Z | ATOM-260526-foo | iter 1 | L6 | PASS
  manifest: sha256:abcdef...
  deploy: sha:abc123 | smoke: ok | invariant: ok | rollback_drill: 47s
  evidence: 27 artifacts, total 384 KB
```

File is opened in append mode + chmod +i where supported. Editing past entries → LAW-08 violation → AL demote 0.

## Screenshot capture (frontend)

Headless via `/ck:chrome-devtools` (Phase 01 Discovery):
```sh
~/.claude/skills/build-anything/scripts/mechanical/screenshot.sh {prod_url} {atom_dir}/evidence/screenshot.png
```
SHA-256 of PNG is recorded in manifest. PNG re-render would change SHA — tampering caught.

## DB query result capture (backend)

`scripts/backend/db-invariant-check.sh` writes results to `evidence/db-query-{name}.txt` with timestamp, query, and result rows. Format is plain text for human auditability; SHA-256 binds in manifest.

## Why this matters for boss compatibility

Boss accepts "DB row" as evidence per LAW-03. v8.0 defines what that means rigorously: a specific query, a specific result, a specific hash. Boss's loophole closes; boss's framework is honoured.
