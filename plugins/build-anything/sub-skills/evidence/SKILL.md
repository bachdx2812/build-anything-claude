---
name: build-anything-evidence
description: Stage 13 — assemble crypto-hashed evidence bundle binding every artifact (screenshot, JSON, query result, log) to atom code + iter + git SHA; precondition of every gate pass
---

# evidence — Stage 13 Evidence Bundle

**Maps to:** stage 13 of `/build-anything`. Implements LAW-17 (cryptographic evidence bundle). Addresses journal §4.9 (verifiable artifact forgeable in v7.5).

## When This Runs

Every gate that emits artifacts (5, 6, 7, 8, 9, 10, 11, 12) writes outputs to its own folder. This sub-skill ASSEMBLES + HASHES them into the canonical manifest before L5 merge.

## Inputs

All output folders under `{atom_dir}/`:
- `gate-mechanical/*.json`
- `gate-backend/*.json`
- `gate-security/*.json`
- `gate-arch/*.json`
- `gate-pattern/*.json`
- `review/*.json`
- `gate-perf/*.json`
- `spec.md`, `schema/`, `diff.patch`

Plus:
- Headless prod-like screenshot from `/ck:chrome-devtools` (frontend atoms)
- DB invariant query result snapshots (backend atoms)
- Git SHA of current HEAD
- AL level at time of pass

## Outputs

- `{atom_dir}/manifest.json` — full manifest
- `{atom_dir}/manifest.sha256` — single-line hash file
- Append entry to project-level `BUILD ARCHIVE` (v7.5 LAW-08 append-only history)

## Manifest Structure

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
    /* ... one entry per artifact ... */
  ],
  "verdict_summary": {
    "stages": [
      {"stage": 1, "verdict": "PASS"},
      /* ... */
      {"stage": 12, "verdict": "PASS"}
    ]
  },
  "manifest_version": "1.0"
}
```

The whole manifest is then SHA-256-hashed; the hash is written to `manifest.sha256` AND appended to BUILD ARCHIVE.

## Mechanical Pass Criteria

- Every gate output present (a missing output = INSUFFICIENT_EVIDENCE; atom HALT, return to the missing stage)
- Each artifact SHA-256 computed and stored
- Manifest itself SHA-256-hashed
- Manifest written to `manifest.json` AND hash to `manifest.sha256`
- BUILD ARCHIVE entry appended

## HALT Conditions

- Missing required artifact
- Hash collision (vanishingly rare — but if happens, HALT and escalate; cosmic ray or attack)
- Cannot write to BUILD ARCHIVE (file permission issue)
- AL level decreased mid-atom (suspicious — investigate)

## Tampering Detection

Re-verification command:
```sh
scripts/mechanical/verify-manifest.sh {atom_dir}
```
Walks every artifact in manifest, recomputes SHA-256, compares to stored hash. Any mismatch → manifest INVALID → atom retroactively HALT → AL demotes to 0 (per Section E.2 of v8.0 doc).

## Why This Precondition Matters

Without LAW-17 binding, a reviewer could (in theory) accept a PASS verdict based on a screenshot that was photoshopped or a JSON report that was hand-edited. Hash binding closes that. The verify-manifest script lets boss / auditor recompute trust independently.

## Tools Used

- `sha256sum` (Linux) / `shasum -a 256` (macOS)
- `jq` for manifest construction
- Native `git rev-parse HEAD` for SHA
- File system walk for artifact discovery

## Retry Policy

- 0 retries on hash mismatch (manifest is supposed to be deterministic)
- 1 retry on transient I/O error
- Missing artifact: redirect to the missing-stage's sub-skill

## Append-Only Discipline

The BUILD ARCHIVE entry is **append-only**. Editing a past entry → LAW-08 violation → AL demote 0. This sub-skill enforces by using append-mode file open + chmod (+i where supported).

## References

- v8.0 LAW-17: `docs/ubs-v8-technical-hardening.md`
- v7.5 LAW-08 append-only: preserved verbatim
- Crypto bundle rationale: journal §4.9
- BUILD ARCHIVE convention: v7.5 doc structure (5 disciplined documents)
