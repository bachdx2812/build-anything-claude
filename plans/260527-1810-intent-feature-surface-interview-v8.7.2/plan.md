# v8.7.2 — Intent Feature-Surface Interview (LAW-INTENT-FS)

## Why

Colleague test (2026-05-27) shipped two atoms with obvious must-have gaps yet PASSed the pipeline:

1. **Flappy Bird web** — one-shot play, no high score, no restart, no DB persistence, no leaderboard.
2. **Notion clone** — register/login/CRUD/workspace/share/nested-page/database/upload only. Missing comments, mentions, real-time collab, search, version history, database-view variety, granular sharing, slash commands, drag reorder.

Root cause IS NOT catalog blindness (rejected: catalog-per-product is unbounded). Root cause is **Stage 0.1 INTENT does not extract user's full functional surface**. Current contract (`sub-skills/intent/SKILL.md` line 144): *"Does not enumerate features — that is Stage 1.A (ck:research)"*. Feature enumeration delegated to research = research returns whatever it finds, not what user expects. User's expectations never anchored in intent verdict, so every downstream stage builds whatever the agent picks.

LAW-CL-95 forces confidence ≥ 95 on intent, but the rubric (`product_type`, `primary_user`, `core_flows`, `success_criteria`, `scale_tier`, `cost`) can hit 95 with shallow flows. "User can register, login, create page, share page" = 4 flows, passes flow-count check, but is hopelessly incomplete for a Notion clone.

v8.7.2 closes this by:
- Making `feature_surface[]` a first-class required field of `declared`.
- Adding heavy confidence penalty + vacuous-PASS guard.
- Adding a new ambiguity probe: when `feature_surface[]` is empty or shallow, the agent MUST present a draft list back to the user and ask "is this complete? what's missing?" until the user confirms.
- Making GATE-PFC (Stage 1.C) verify spec coverage against `declared.feature_surface[]` (user-confirmed truth), with catalog reduced to a hint-generator for the interview.

## Contract change (sub-skills/intent/SKILL.md)

Add row to the contract table:

| Field | Meaning |
|-------|---------|
| `declared.feature_surface[]` *(v8.7.2)* | Complete list of functional capabilities the user expects, enumerated explicitly. Each item: `{ "name": "string", "must": true|false, "rationale": "string" }`. Items with `must=true` MUST appear in success_criteria + spec. Required non-empty; floor depends on declared.product_type complexity (see scoring). |

New scoring rubric rows:

| Gap | Penalty |
|-----|---------|
| `feature_surface` empty | -30 |
| `feature_surface` < 3 items | -25 |
| `feature_surface` < 5 items AND prompt contains `clone`/`like X`/`alternative to` (referenced-product detector) | -25 |
| `feature_surface` not user-confirmed (`history[]` shows no `user-confirm-feature-surface` entry) | -20 |

Remove from "What this does not do":
- ~~Does not enumerate features — that is Stage 1.A (ck:research)~~

Add new section "Feature enumeration interview":

```
After first-pass extraction, agent MUST:

1. Draft a candidate feature_surface[] from the raw prompt.
2. If prompt references a known product ("Notion clone", "YouTube clone", "Flappy Bird"),
   agent MUST expand the draft to the agent's best guess of that product's canonical
   feature set — NOT to limit to what user literally said.
3. Present draft to user via AskUserQuestion (or harness eq.) in a MULTI-SELECT format:
     "I plan to build these features. Mark each: REQUIRED / OPTIONAL / OUT-OF-SCOPE.
      Add any missing features at the bottom."
4. Apply user answers. Append `{ "iter": N, "source": "user-confirm-feature-surface" }`
   to history[].
5. If user adds items, repeat step 3 with the augmented list (max 3 rounds — feature
   enumeration must converge).

This interview is NOT optional. Skipping it triggers the vacuous-PASS guard
because feature_surface lacks the user-confirm-feature-surface history entry.
```

## Vacuous-PASS guard extension (scripts/intent/declare-intent.sh)

After existing scale_tier/cost check, add:

```bash
FS_COUNT=$(jq -r '.declared.feature_surface | length // 0' "$STATE")
FS_CONFIRMED=$(jq -r '[.history[] | select(.source=="user-confirm-feature-surface")] | length' "$STATE")
if [[ "$NEXT_ACTION" == "READY" ]]; then
  if [[ "$FS_COUNT" -lt 3 ]]; then
    NEXT_ACTION="HALT"
    PASSED="false"
    NA_REASON="LAW-INTENT-FS GUARD: feature_surface has $FS_COUNT items — user functional expectations not captured"
  elif [[ "$FS_CONFIRMED" -lt 1 ]]; then
    NEXT_ACTION="HALT"
    PASSED="false"
    NA_REASON="LAW-INTENT-FS GUARD: feature_surface not confirmed by user (no user-confirm-feature-surface entry in history[])"
  fi
fi
```

## New ambiguity probe

In `declare-intent.sh`, after existing probes:

```bash
DECL_FS=$(jq -r '.declared.feature_surface | length // 0' "$STATE")
if [[ "$DECL_FS" -lt 3 ]]; then
  PROBE_AMBIG+=('{"field":"feature_surface","question":"List every functional capability the build must have. For a known-product prompt (e.g. \"Notion clone\"), enumerate the FULL canonical feature set, then mark each REQUIRED/OPTIONAL/OUT-OF-SCOPE. Aim for completeness — incomplete feature_surface = shipped product missing core features.","required":true}')
fi
```

Plus a referenced-product detector: when raw-prompt contains `\bclone\b`, `\blike [A-Z]`, `\balternative to`, prepend a stronger prompt asking the agent to first list canonical features of the referenced product before showing to user.

## GATE-PFC change (scripts/spec/product-feature-coverage.sh)

Priority change:
1. First read `{atom_dir}/intent/verdict.json` → `declared.feature_surface[]` (filtered to `must=true`).
2. If non-empty, treat THAT as the must_have set. Match spec text against each item's name + synonyms (if synonyms field present in feature_surface item — otherwise just name substring).
3. If feature_surface empty AND a catalog entry matches → use catalog must_have (legacy path, downgraded to fallback).
4. If both empty → emit_na (no source-of-truth).
5. If any must-item missing from spec → emit_fail (existing path).

Net effect: user-declared feature_surface[] becomes the authoritative source for PFC. Catalog becomes hint-only.

## Orchestrator + docs updates

- `plugins/build-anything/SKILL.md`: Stage 0.1 row — add `feature_surface` to confidence rubric mention + add the interview sub-step description.
- `docs/ubs.md`: Stage 0.1 / GATE-INTENT contract table — add feature_surface row. Update §B GATE-PFC description to reflect feature_surface priority.

## Meta-gate: scripts/meta/intent-feature-surface-test.sh

Five fixtures:

| # | Fixture | Expected |
|---|---------|----------|
| 1 | declared.feature_surface absent + verdict READY conf=97 → orchestrator preflight rejects (HALT) | rc≠0 |
| 2 | feature_surface = 2 items + READY → vacuous guard HALT | rc≠0 |
| 3 | feature_surface = 5 items + history has user-confirm entry + READY → preflight passes | rc=0 |
| 4 | feature_surface = 5 items + history MISSING user-confirm entry + READY → vacuous guard HALT | rc≠0 |
| 5 | prompt mentions "notion clone" + feature_surface has only 3 items + READY → must HALT (referenced-product threshold = 5) | rc≠0 |

Add row to meta-gate table in `SKILL.md` + `docs/ubs.md` §O. Total meta-gate count: 12.

## Out of scope (defer)

- Auto-feature-extraction from referenced-product web research (would auto-fill feature_surface from Wikipedia-style sources) — v8.8.
- Feature-surface semantic deduplication (e.g. "comments" vs "comment threads" as same item) — v8.8.
- Feature-surface negation tests (assert spec OUT-OF-SCOPE items don't accidentally implement) — v8.8.
- Cross-stage feature-surface trace (verify Stage 4 build covers every must=true item with at least one test) — v8.8.
