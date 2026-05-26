# Build Archive Template

Per UBS v7.5 5-disciplined-documents (BUILD ARCHIVE) + v8.0 LAW-17 evidence cryptography. One per project at `{project_root}/.build-anything/BUILD-ARCHIVE.md`. **APPEND-ONLY (LAW-08). chmod +i where supported.**

```markdown
# BUILD ARCHIVE — {project name}

> APPEND-ONLY. Each line is a sealed verdict on an atom passing all 14 stages.
> Editing past entries → LAW-08 violation → AL demote to 0 + boss escalation.
> Verify with: `verify-manifest.sh {project_root}/.build-anything/atoms/{atom_code}/`

# Format (one entry per line block, separated by blank line)

{ISO-8601} | {ATOM-CODE} | iter {N} | {LAYER} | {VERDICT}
  manifest: sha256:{full-hash}
  git_sha: {commit-hash}
  deploy: sha:{deploy-hash} | smoke:ok | invariant:ok | rollback_drill:{N}s
  evidence: {M} artifacts, total {K} KB
  cost: $X.YZ | wall: {N} min | al: {0..4}

---

# Example entries (real format below)

2026-05-26T14:23:51Z | ATOM-260526-orders-create | iter 2 | L6 | PASS
  manifest: sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
  git_sha: 9a1b2c3d4e5f
  deploy: sha:9a1b2c3d4e5f | smoke:ok | invariant:ok | rollback_drill:47s
  evidence: 27 artifacts, total 384 KB
  cost: $2.81 | wall: 26 min | al: 3

2026-05-26T11:08:14Z | ATOM-260526-orders-get | iter 1 | L5 | PASS-PRE-MERGE
  manifest: sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
  git_sha: 8b0a1c2d3e4f
  (no deploy line — L5 atoms not yet pushed to prod)
  evidence: 19 artifacts, total 241 KB
  cost: $1.40 | wall: 14 min | al: 3

2026-05-25T17:42:03Z | ATOM-260525-billing-double-charge-fix | iter 1 | L6 | PASS
  manifest: sha256:fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321
  git_sha: 7c8d9e0f1a2b
  deploy: sha:7c8d9e0f1a2b | smoke:ok | invariant:ok | rollback_drill:38s
  evidence: 31 artifacts, total 412 KB
  cost: $3.14 | wall: 32 min | al: 3
  note: "Fixed CRITICAL bug — GATE-20 idempotency caught duplicate billing on retry"

---

# Failed atoms (HALT with no PASS)

Format: same as PASS but verdict = HALT-{stage} or DEMOTE-{from→to}

2026-05-23T09:11:25Z | ATOM-260523-tenant-merge | iter 3 | HALT-STAGE-6
  manifest: sha256:{hash}
  git_sha: 6d7e8f9a0b1c
  reason: "GATE-21 multi-tenant FAIL after 3 iterations; AL-4 circuit breaker fired"
  effect: actor:claude-opus-4-7 demoted AL-4 → AL-3
  evidence: 14 artifacts (partial)
  cost: $4.92 (capped at budget) | wall: 47 min

---

# Append rules

1. **Never** modify past entries. New facts → new entry.
2. **One block per atom transition** (PASS, HALT, DEMOTE).
3. **Manifest sha256 is the seal** — if file is tampered, manifest verifies stale.
4. **chmod +i where supported** (Linux ext4: `chattr +i`). On macOS APFS: `chflags uchg`.
5. **Compaction** is the ONLY mutation — periodic re-emission of identical content with index refresh. Compaction event itself logged at top.

---

# Compaction events (when this file is recompacted by orchestrator)

2026-05-26T00:00:00Z — compaction event, 247 entries summarised, manifest.sha256 chain re-verified PASS
```

## Why this format

| Constraint | How met |
|------------|---------|
| Boss W2 GATE-9 PROOF | Every entry references a manifest with cryptographic seal |
| LAW-08 append-only | OS-level immutability flag + this file's first line is the contract |
| Auditability | Plain text + grep-friendly; no JSON-only blob |
| Boss compat | "DB row" → "manifest artifact" — both prove same thing, this is more rigorous |

## Verification command

```sh
~/.claude/skills/build-anything/scripts/mechanical/verify-archive-chain.sh {project_root}
```

Walks every entry, runs `verify-manifest.sh` for each `manifest:` hash, reports chain integrity.

Any mismatch → LAW-17 violation → all actors AL-demoted to 0 + boss escalation event.

## What goes in BUILD ARCHIVE vs PROJECT TRACKER

| Type | BUILD ARCHIVE | PROJECT TRACKER |
|------|---------------|-----------------|
| Mutability | append-only | mutable (recompiled) |
| Granularity | per-atom-transition | per-project rollup |
| Retention | forever | current state only |
| Purpose | audit trail | dashboard |

PROJECT TRACKER is a view over BUILD ARCHIVE + live atom states. If TRACKER is lost, recompile from ARCHIVE. If ARCHIVE is lost, project loses audit history → boss escalation.
