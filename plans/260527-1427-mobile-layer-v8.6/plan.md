# Plan — UBS v8.6 mobile layer (phase 1)

**Date:** 2026-05-27
**Driver:** User said "bake mobile layer now" after audit found UBS v8.5.2 was web-only.
**Scope decision:** Cross-platform Maestro + perms gate today; build/sign + store-rules deferred to v8.7.

## Motivation

UBS v8.5.2 ships with strong web E2E (Playwright must boot real stack + click through journeys). For native mobile apps that surface is meaningless:

- Playwright cannot drive iOS Simulator or Android Emulator.
- `localhost:3000` is not where a mobile binary runs.
- No project_type covers mobile-rn / mobile-flutter / mobile-ios / mobile-android / mobile-expo.
- production-design SLO regex demands `p95` + `availability %` — mobile cares about cold-start, jank, crash-free sessions.
- No permission-manifest check (orphan camera permission, missing location usage description, etc.).

Net effect: if boss tells Devin "build me an iOS app", UBS silently falls through to `mixed` project_type, Playwright fails N/A or boots a phantom web server, no mobile-specific check fires, Devin can claim done.

## Today's deliverable (phase 1)

1. `project_type` enum extended with 5 mobile values.
2. `scripts/mechanical/e2e-maestro.sh` — Maestro runner (cross-platform: iOS native / Android native / RN / Flutter / Expo).
3. `scripts/mechanical/mobile-perms-check.sh` — Info.plist + AndroidManifest perms reconciled against code.
4. `feature-catalog.json` — minimal mobile product types + scale_tiers.
5. `production-design-gate.sh` — SLO regex accepts mobile metrics (cold-start / jank / crash-free) when `project_type ∈ mobile-*`.
6. `scripts/meta/mobile-e2e-test.sh` — 5-7 fixtures regression test.
7. `docs/ubs.md` Section Y + Section B GATE rows + Section O meta inventory (8 → 9).
8. `SKILL.md` Stage 5 dispatch + project_type enum.
9. `docs/ubs.docx` regenerated.

## Deferred to v8.7

- **GATE-MOBILE-BUILD** — verify .ipa / .apk / .aab artefact exists + basic signing reconciled with Apple Developer cert / Android keystore. Big surface (debug vs release, free vs paid Apple Dev, fastlane integration).
- **GATE-MOBILE-STORE-RULES** — App Store Review Guidelines + Play Console policies checklist (private-data declarations, content ratings, etc.).
- **Native UX persona extension** — iOS HIG + Material 3 audit (current ux-pro-max is DOM-bound).
- **Per-platform perf gates** — XCUITest performance metrics / Android benchmark.
- **Flutter / RN bridge audit** — JS thread vs UI thread fps.

## Phase-1 architectural choices

| Decision | Choice | Why |
|----------|--------|-----|
| E2E runner | Maestro | Single tool covers all 4 mobile stacks (iOS native, Android native, RN, Flutter). YAML-driven. Owns simulator/emulator boot. Open-source. |
| project_type values | `mobile-ios`, `mobile-android`, `mobile-rn`, `mobile-flutter`, `mobile-expo` | Granular enough for Stack-fitness later; coarse enough that dispatch logic stays simple. |
| Perms gate scope | iOS Info.plist + Android AndroidManifest | Catches the most common ship-blocker (App Store rejects on missing usage description). |
| Boot in CI | Skip on CI by default, log N/A | Simulator/emulator on CI is heavy + flaky. Phase-1 runs locally; CI integration is v8.7. |
| Skip rule | If `mobile/` dir absent AND project_type ≠ mobile-* → N/A | Don't penalise web projects. |

## File touch list

```
plugins/build-anything/
├── SKILL.md                                                  [edit]
├── scripts/
│   ├── mechanical/
│   │   ├── e2e-maestro.sh                                    [new]
│   │   └── mobile-perms-check.sh                             [new]
│   ├── spec/
│   │   ├── feature-catalog.json                              [edit — add mobile rows]
│   │   └── production-design-gate.sh                         [edit — SLO regex]
│   └── meta/
│       └── mobile-e2e-test.sh                                [new]
└── sub-skills/
    └── gate-mechanical/
        └── SKILL.md                                          [edit — Maestro dispatch]
docs/
├── ubs.md                                                    [edit — Section Y + Section B + Section O]
└── ubs.docx                                                  [regen]
```

## Acceptance criteria

- `bash scripts/meta/run-all-meta-gates.sh` → `pass=9 fail=0`.
- New `mobile-e2e-test.sh` covers ≥5 fixtures (web-passthrough N/A, mobile-rn PASS, missing maestro YAML FAIL, iOS orphan perm FAIL, Android missing perm FAIL).
- Charter Section Y has full GATE-25-E2E-MOBILE + GATE-MOBILE-PERMS contracts (mechanical checks table + FAIL conditions).
- docs/ubs.docx regenerated via `pandoc ubs.md -o ubs.docx --from gfm --toc --toc-depth=2 --standalone`.
- Commit pushed to `bachdx2812/build-anything-claude#main`.

## Risks

- **Maestro install** — if user/CI doesn't have Maestro installed, runner must emit a clear "install maestro" error, not silent FAIL.
- **Simulator boot time** — first run takes ~60s. Document expected latency.
- **macOS bash 3.2** — same trap as v8.5.2; avoid `local -A` and `${arr[-1]}`.
- **Info.plist key explosion** — there are ~30 `NS*UsageDescription` keys. Phase-1 covers the top 10 (camera, photo, location, contacts, microphone, calendar, motion, bluetooth, faceid, tracking). Comprehensive list in v8.7.

## Open questions (for follow-up)

- Should mobile builds get their own scale_tiers (free Apple dev vs paid, App Store fee modeling)? Currently inheriting web tier costs.
- Push-notification infra (APNs / FCM) — add as required capability per product type, or leave to architecture persona's judgement?
- Cross-platform stack (RN / Flutter) tier costs — different from native? Flutter ships bigger binaries; RN ships JS bundle. Worth modeling separately?
