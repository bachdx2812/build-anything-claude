---
name: intent
description: Stage 0.1 INTENT DECLARATION sub-skill. Extracts user's true intent from the raw prompt and iterates a verify-with-user loop until confidence ≥ 95%. Required as the first executable stage of /build-anything (v8.3+). Implements LAW-CL-95 (confidence-loop law).
---

# Stage 0.1 — INTENT DECLARATION

The build cannot start without a high-confidence answer to: **what does the user actually want?** No mechanical gate downstream can recover from a misread of the brief. This sub-skill makes the read explicit, structured, and verified by the user before any spec, research, or build kicks off.

## Why this exists

The v8.1 yt-clone audit shipped a "YouTube clone" with no upload and no playback. Root cause: the spec author (LLM) inferred a narrower intent than the user implied and never verified back. Spec atom passed because it was internally consistent — but it was the wrong spec. Stages 1–14 cannot recover from that miss.

Stage 0.1 forces a structured intent declaration with explicit user verification. **Confidence < 95% blocks all downstream stages.**

## Contract

| Field | Meaning |
|-------|---------|
| `iter` | Loop iteration counter (max 5) |
| `confidence` | Agent's self-assessed score 0-100 |
| `declared.product_type` | Catalog match if possible (`youtube-clone`, `todo-app`, etc.); novel types accepted but logged |
| `declared.primary_user` | Role + expertise + context |
| `declared.core_flows[]` | 2-5 end-to-end user journeys, each 1 sentence |
| `declared.success_criteria[]` | 2-5 mechanically-checkable acceptance signals |
| `declared.out_of_scope[]` | Explicit non-goals so reviewers can spot scope creep |
| `declared.constraints[]` | Hard constraints (stack, budget, deadline, compliance) |
| `declared.scale_tier` *(v8.5)* | `mvp` (≤1K DAU) / `growth` (1K-100K) / `scale` (100K-10M) / `hyperscale` (>10M). Drives Stage 1.D GATE-STACK tier-row selection AND Stage 1.B Architect persona capacity model. |
| `declared.cost.monthly_usd_ceiling` *(v8.5)* | Integer USD. Stack-fitness gate refuses stacks whose estimated infra cost exceeds this. |
| `declared.team.size` *(v8.5)* | Integer. Team-fitness check refuses architectures whose ops surface exceeds team capacity (e.g. solo + 5 microservices = HALT). |
| `declared.team.ops_maturity` *(v8.5)* | `solo` / `small` / `medium` / `enterprise`. Drives observability + deployment topology requirements in production-design.md. |
| `declared.feature_surface[]` *(v8.7.2)* | Complete enumeration of functional capabilities the user expects. Each item: `{ "name": "string", "must": true\|false, "synonyms": [...], "rationale": "string" }`. Items with `must=true` MUST appear in spec.success_criteria + spec body. Required non-empty. When the prompt references a known product (e.g. "Notion clone", "Flappy Bird"), the agent first expands to the canonical feature set, THEN runs the [feature enumeration interview](#feature-enumeration-interview-v872) to let the user mark each REQUIRED/OPTIONAL/OUT-OF-SCOPE. |
| `ambiguities[]` | Open questions to ask the user. Cleared as user answers |
| `history[]` | Append-only log of {iter, change, source: "user" \| "agent" \| "user-confirm-feature-surface"} |

## Loop protocol (LAW-CL-95)

```
1. Read raw user prompt → save to {atom_dir}/intent/raw-prompt.md
2. iter = 0
3. while iter < 5:
     a. Agent extracts/refines `declared` block from prompt + accumulated answers
     b. Agent scores `confidence` honestly (see scoring rubric below)
     c. Agent lists `ambiguities` — anything that would change the build if answered differently
     d. Run `scripts/intent/declare-intent.sh` to write intent.json + verdict.json
     e. Switch on verdict.next_action:
          READY      → emit final verdict.json, return PASS, advance to Stage 0.5
          NEEDS_USER → present `ambiguities[]` to user via AskUserQuestion (Claude Code)
                       or harness-equivalent question primitive. Append answers to
                       raw-prompt.md (with `## iter-N answers:` header). iter++
          HALT       → emit verdict with passed=false + na_pending_reason. Stop.
4. After loop: if still NEEDS_USER → forced HALT (max_iter exhausted) with
   summary of unresolved ambiguities. Cannot vacuous-PASS.
```

## Scoring rubric (agent must apply, NOT user)

Start from 100 and subtract:

| Gap | Penalty |
|-----|---------|
| `product_type` empty | -25 |
| `primary_user` empty | -15 |
| `core_flows` < 2 | -20 |
| `core_flows` 2-3 but vague (no verb-object pairs) | -10 |
| `success_criteria` empty | -15 |
| `success_criteria` not mechanically checkable | -10 |
| Contradiction in stated facts | -25 per contradiction |
| Out-of-scope unspecified for a fuzzy product type | -10 |
| Constraints unspecified for time/cost/stack-sensitive builds | -10 |
| `scale_tier` empty *(v8.5)* | -20 |
| `cost.monthly_usd_ceiling` empty *(v8.5)* | -15 |
| `team.size` empty *(v8.5)* | -10 |
| `team.ops_maturity` empty *(v8.5)* | -10 |
| `feature_surface` empty *(v8.7.2)* | -30 |
| `feature_surface` < 3 items *(v8.7.2)* | -25 |
| `feature_surface` < 5 items AND prompt mentions `clone` / `like X` / `alternative to` (referenced-product detector) *(v8.7.2)* | -25 |
| `feature_surface` populated but `history[]` has no `user-confirm-feature-surface` entry *(v8.7.2)* | -20 |

Floor at 0. Result is what gets written to `confidence` field. **Do not inflate: a higher score does not get you to Stage 1 faster — it gets you a worse build.**

Adversarial check before declaring confidence ≥ 95: re-read the prompt and ask "if a malicious paraphraser rewrote my `declared` block to be 80% different but still satisfy all my parsed criteria, would the user be happy?" If the answer is "maybe" or "no", confidence is at most 90.

## Feature enumeration interview (v8.7.2)

Why this exists: the v8.7.1 colleague test shipped a "Flappy Bird" with no high-score/restart and a "Notion clone" missing comments/realtime/search/version-history/mentions. Both passed Stage 0.1 because the rubric checked `core_flows` count, not functional completeness. Delegating feature discovery to Stage 1.A (research) means the user's expectations are NEVER anchored in the intent verdict — every downstream stage builds whatever the agent picks. v8.7.2 fixes the source.

After the first extraction pass, the agent MUST run a feature interview before declaring confidence ≥ threshold:

1. **Draft `feature_surface[]`** from the raw prompt. Include items the user literally said.
2. **Expand for known-product references.** If the prompt contains `clone` / `like X` / `alternative to` / a famous product name (Notion, Figma, YouTube, Flappy Bird, Slack, …), the agent MUST expand the draft to the canonical feature set of that product, even if the user did not list those items. Better to over-enumerate then let the user trim than to under-enumerate and ship without comments/realtime/history.
3. **Present draft via `AskUserQuestion`** (Claude Code) or harness-equivalent in a tri-select format per item: `REQUIRED` / `OPTIONAL` / `OUT-OF-SCOPE`. Include an "add more" prompt at the bottom.
4. **Apply user answers.** Items marked REQUIRED → `must=true`. OPTIONAL → `must=false`. OUT-OF-SCOPE → moved to `declared.out_of_scope[]`. Added items → re-classified next round.
5. **Append `{ "iter": N, "source": "user-confirm-feature-surface", "added": [...], "removed": [...] }`** to `history[]`.
6. **Re-loop if the user added items** (max 3 rounds — enumeration must converge). On round 3 with still-open additions → HALT with `na_pending_reason: "feature enumeration did not converge in 3 rounds"`.

The interview is NOT optional. The vacuous-PASS guard refuses to mark intent READY without at least one `user-confirm-feature-surface` entry in `history[]`, regardless of confidence score.

## How the agent invokes this stage

First call (bootstrap):
```bash
bash scripts/intent/declare-intent.sh \
  --prompt /path/to/user-prompt.md \
  --atom-dir {atom_dir} \
  --project-root {project_root}
```

The script writes a starter `intent.json` with `confidence=0` and a probed `ambiguities[]`. **The agent then mutates `intent.json` directly** (jq or text edit) to fill in `declared.*` from its LLM-side extraction, recompute `confidence`, and prune resolved `ambiguities`.

Subsequent calls (re-score after each user answer):
```bash
bash scripts/intent/declare-intent.sh \
  --atom-dir {atom_dir} \
  --project-root {project_root}
```

(No `--prompt` needed; script re-reads existing intent.json + raw-prompt.md.)

The script handles iter counter, snapshot, verdict logic, and LAW-F6 vacuous-PASS guard. The agent handles the semantic intent extraction and the user-facing question loop.

## Outputs

- `{atom_dir}/intent/raw-prompt.md` — verbatim user prompt + appended Q&A
- `{atom_dir}/intent/intent.json` — current state (mutated each iter)
- `{atom_dir}/intent/iter-N.json` — frozen snapshots
- `{atom_dir}/intent/transcript.md` — append-only log
- `{atom_dir}/intent/verdict.json` — final gate verdict for orchestrator

## Vacuous-PASS guard

Even if confidence ≥ 95, the script HALTs if any of these vacuous conditions hold:

- `product_type`, `primary_user`, `core_flows[0]`, `success_criteria[0]` empty (v8.3).
- `scale_tier` or `cost.monthly_usd_ceiling` missing (v8.5).
- `feature_surface[]` has fewer than 3 items (v8.7.2).
- `feature_surface[]` non-empty but `history[]` has no `user-confirm-feature-surface` entry (v8.7.2) — agent inferred without user confirmation.
- Prompt mentions a referenced product (`clone` / `like X` / `alternative to`) and `feature_surface[]` has fewer than 5 items (v8.7.2) — known-product threshold.

Confidence is a self-report; these guards make the self-report falsifiable.

## Downstream contract

Stage 1.A (research) reads `intent.json.declared.product_type` AND `feature_surface[]` to seed research queries — research expands non-functional context around the anchored feature list, never contracts it.
Stage 1.B (PRD/BMAD) consumes the full `declared` block as the PM brief; PRD must-have section MUST include every `feature_surface[*]` with `must=true`.
Stage 1.C (GATE-PFC, v8.7.2) checks spec coverage **against `declared.feature_surface[]` items where `must=true`** (primary source of truth). Catalog (`feature-catalog.json`) is consulted only as a fallback hint when `feature_surface[]` is unexpectedly empty (which would itself be a Stage 0.1 LAW-INTENT-FS violation).
Stage 3 (red-team spec) is given `out_of_scope[]` as the adversary's allowed weapons.

If `declared` is wrong, every downstream stage is built on sand. That is the entire reason this stage is hard-gated.

## When the user disagrees with declared block

If user answers contradict prior LLM extraction, the agent MUST:
1. Append the contradiction to `history[]` with `source: "user-correction"`.
2. Re-extract from the corrected prompt + new answers — do NOT just patch the field.
3. Drop confidence by at least 20 — a contradiction means the prior extraction was wrong, so the next extraction needs evidence that it isn't.

## Mode flags

| Flag (passed to /build-anything) | Effect on Stage 0.1 |
|-----------------------------------|----------------------|
| `--auto` (default) | Full loop, max 5 iter, threshold 95 |
| `--strict` | Threshold 99, max iter 10 |
| `--fast` | Threshold 80, max iter 2 — for prototypes only |
| `--no-intent-loop` | DEPRECATED — must be paired with `--ack-no-discovery` flag and an explicit `intent.json` written by user. Documents intent-bypass for audit, does NOT skip the gate |

## What this does not do

- Does not write the spec — that is Stage 1.B (PRD/BMAD).
- Does not pick a stack — that is Stage 1.B (Architect agent).
- Does not finalize success criteria as test cases — that is Stage 1 (spec atom).
- Does not deep-research the product domain — that is Stage 1.A (ck:research). *(v8.7.2 note: this stage DOES enumerate `feature_surface[]` interactively with the user. Stage 1.A then expands non-functional context — competitive analysis, stack options, best practices — around that anchored feature list.)*

This stage answers one question: **does the agent understand what the user wants?** Everything else flows from a high-confidence yes.
