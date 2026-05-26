# YouTube build demo — UBS v8.3 from scratch

**Date:** 2026-05-26 21:57 ICT
**Prompt:** `build cho tôi youtube`
**Atom:** `/tmp/yt-build-from-scratch/atom/`
**Atom SHA:** `311f23ff2dd2ee41a337af9e235b8566c537ce00e80cd61e3caf8d24ba87cb1a`

---

## Purpose

Run the full v8.3 pipeline against a fresh atom whose only input is the literal Vietnamese sentence `build cho tôi youtube`. Demonstrate the loop end-to-end and surface what the orchestrator does (and refuses to do) when given an ultra-vague prompt and no code.

This run is BEFORE any code is written. It demonstrates that v8.3 cannot be tricked into claiming success on an empty atom.

---

## Stage 0.1 — INTENT DECLARATION

| Iter | Confidence | Action | Notes |
|------|------------|--------|-------|
| 1 | 0 | NEEDS_USER | 4 ambiguities (product_type, primary_user, core_flows, success_criteria) all unanswered |
| 2 | 97 | **READY** | Agent inferred MVP scope from `youtube-clone-mvp` pattern; surfaced 6 explicit `out_of_scope` items + 4 explicit `constraints` |

**Declared intent** (agent assumptions, user can override on review):

- **product_type**: `youtube-clone-mvp`
- **primary_user**: authenticated end-user (both creator + viewer; no admin/mod roles)
- **core_flows**: register/login → upload mp4 ≤100MB → list+watch → comment
- **success_criteria** (all mechanically checkable):
  - bcrypt password storage + duplicate-email rejection
  - JWT issued on login + 401 on bad/missing token
  - mp4 persisted + orphan-video invariant zero
  - HTML5 player streams the file
  - comment row inserts + orphan-comment invariant zero
- **out_of_scope**: transcoding/HLS, recommendations, monetization, live streaming, mobile apps, horizontal scaling
- **constraints**: node+express+sqlite single-tenant, local disk uploads, ship-bar = 5 success_criteria green + confidence ≥ 95

**LAW-CL-95 verdict:** READY at iter 2 (≤ 5 max). Confidence 97 ≥ 95. Vacuous-PASS guard passed (no core field empty).

`{atom_dir}/intent/verdict.json` now exists with `next_action: READY` — orchestrator preflight will green-light.

---

## Stages 1–14 — Orchestrator run

Command:

```bash
bash scripts/orchestrator/run-all-gates.sh \
  --atom-dir /tmp/yt-build-from-scratch/atom \
  --project-root /tmp/yt-build-from-scratch \
  --no-witness --confidence-floor 80
```

Exit code: **1** (one FAIL).

| Metric | Value |
|--------|-------|
| gates_total | 30 |
| PASS | 0 |
| FAIL | 1 |
| ERROR | 0 |
| N/A_PENDING_REVIEWER | 29 |
| min_confidence | 0 |
| mean_confidence | 3 |
| open_ambiguities | 29 |

### Why this is the correct output

- **0 PASS**: no source code exists yet, so nothing can honestly pass. LAW-F6 prevents the orchestrator from emitting any vacuous PASS on empty input.
- **1 FAIL**: GATE-UIUX correctly fails — `ui.enabled=true` but no `frontend/` dir. Confidence=100 on the FAIL (a concrete observation, not a guess).
- **0 ERROR**: silent-drop guard is live; no gate script crashed without producing JSON.
- **29 N/A_PENDING_REVIEWER**: every other gate emits N/A with a concrete reason (e.g. "no package.json at /tmp/yt-build-from-scratch/.", "no source files in scope", "no load_smoke.endpoints/target_url configured"). Each requires either reviewer override or actual code/config.
- **open_ambiguities=29**: surfaced at the top of the manifest. A reviewer reading the manifest sees 29 concrete things they must resolve before any PASS verdict is possible. None of them are hidden inside "passed: true" leaves.

### Sample ambiguities (first 5)

```
no package.json at /tmp/yt-build-from-scratch/.; set frontend.dir or stack.dir in config OR confirm atom has no FE bundle
no package.json at /tmp/yt-build-from-scratch/.; set stack.dir to the dir containing package.json OR confirm atom has no test runner
no frontend.test_urls configured; reviewer must add URLs OR confirm atom has no FE surface
no source files in scope; either add scope.paths/bootstrap_glob to .build-anything.json OR confirm atom is doc/config-only
no load_smoke.endpoints/target_url configured; reviewer must add OR confirm atom has no HTTP perf budget
```

---

## What this demonstrates

| Claim | Evidence |
|-------|----------|
| **Intent enforcement works** | Orchestrator refused to run gates until `intent/verdict.json` had `next_action=READY`. A bare `bash run-all-gates.sh ...` without intent setup exits 2 with `GATE-INTENT preflight: ...verdict.json missing`. |
| **No vacuous PASS** | 0 PASS verdicts on an empty atom. The skill emits N/A for every gate that lacks a real surface to scan. |
| **No silent drop** | 0 ERROR verdicts. Every gate script either produced its JSON or was synthesized into an explicit ERROR by the orchestrator (none required synthesis this run). |
| **Honest confidence** | min_confidence=0, mean=3 on this empty-code atom. A reader cannot mistake "0 PASS" for "all good — try again later". The min_confidence headline tells them the floor is bottom. |
| **Floor enforcement available** | `--confidence-floor 80` did not fire here because exit 1 (FAIL) takes precedence over exit 2 (floor breach). If the FAIL were resolved and 29 N/A remained, the floor would correctly exit 2. |
| **LAW-17 guard wired** | `--no-witness` was accepted because `.build-anything.json#env: "test"`. In prod (default env) the same flag would have exit-2'd with "LAW-17 mandates witness in prod". |

---

## What would happen if Devin claimed "YouTube done"

Suppose Devin pushed the same atom and ran `claim: deployed and tested`. Boss reads the manifest:

- `summary.pass = 0` — no green check anywhere
- `summary.min_confidence = 0` — the loudest signal that something is unaccounted for
- `ambiguities[]` lists 29 concrete unresolved questions
- Cosign witness step is intentionally skipped (env=test), so no production seal exists

A boss eyeballing only "Devin says done" would have to ignore literally every signal v8.3 produces. The doc is no longer doc-only; the manifest is the contract.

---

## What this run does NOT demonstrate

- **Actual YouTube code being written.** That requires Stage 4 (Build) which the orchestrator does not auto-execute — it verifies. To produce real PASS verdicts the agent would need to scaffold the routes/schema/UI based on the declared intent and re-run. That is a follow-up build, not a v8.3 invariant.
- **Cosign signing.** This run uses `--no-witness` because env=test. A boss-facing prod run would witness the manifest (PLACEHOLDER_NOT_FOR_PROD label visible to reviewer if no real key configured).
- **AskUserQuestion loop.** The skill's intent stage normally asks the user when ambiguities exist; this run used agent-assumed defaults instead (per harness constraint "KHÔNG dùng AskUserQuestion"). User reviewing the declared intent block is the equivalent step.

---

## Unresolved questions for boss / user

1. **Does the inferred MVP scope match what you want?** Specifically: is "single-tenant, sqlite, no transcoding, no live streaming" acceptable as the v1, or should those move into `success_criteria`?
2. **Confidence-floor policy.** Recommended tiers in v8.3 doc: fast=80 / default=95 / strict=99. Which should the boss-facing pipeline use as default?
3. **Cosign signing key.** Production runs need `cosign.signing.key_path` in `.build-anything.json` or `COSIGN_KEY` env. Where does the key live? Who owns it?
4. **UI/UX dep.** GATE-UIUX requires `ui-ux-pro-max` skill installed at `~/.claude/skills/ui-ux-pro-max/`. Is this expected to be present on Devin/Comet/Kimi's environment, or is the FAIL there expected pending install?
