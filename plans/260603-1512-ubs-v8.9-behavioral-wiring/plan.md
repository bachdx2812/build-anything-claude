# UBS v8.9 — Behavioral-Wiring Layer (multi-client runtime proof)

**Source:** colleague feedback 2026-06-03 — slack+notion build: simple UI / missing features / **chat not realtime** / **call dead** / "told to fix, not fixed."
**Status:** PLANNED. **Owner:** us (skill) + boss-stack (doc). **Bump:** v8.8 → v8.9.

## One-line disease (live in v8.8)
v8.8 proves **WIRE static** (dep present, handler defined, test-file references journey) but never proves **BEHAVIOR at runtime** for the defining interactions. `realtime_transport` = WIRED if `socket.io` dep OR symbol present (`capability-wiring-check.sh:233`) → proves import, not that A's message reaches B. `e2e-playwright.sh` boots **one** frontend+backend, single browser context (`:200-205`), journey "covered" = test-file name match (`:132`) → optimistic-UI mockup PASSES. No multi-client proof anywhere (`grep newContext|two-client = empty`). Calls unmodeled — no `webrtc`/`realtime_media` capability in skill (grep empty); `chat-app` must_have has messaging/presence but **no calls** (catalog `:1896`).

## Already fixed in v8.8 (do NOT re-plan)
GATE-WIRE-STACK (dep/symbol footprint), GATE-PFC-WIRE (route/handler/test), GATE-STUB, GATE-SEED, GATE-AUTH-RT, GATE-E2E-SEM (static semantic floor), GATE-CLOUD-ART, GATE-REVERIFY, verify-manifest 0-byte. Those stay. v8.9 adds the **runtime/multi-client** layer on top.

## Gap → Phase map
| Gap | Symptom | Phase |
|-----|---------|-------|
| B1 realtime propagation unverified (single-client E2E) | chat k realtime | **P0** [phase-01](phase-01-realtime-propagation.md) |
| B2 WebRTC/call unmodeled + unverified | call k chạy | **P1** [phase-02](phase-02-call-webrtc.md) |
| B3 interactive must_have passes on static wire only | UI only k hoạt động | **P1** [phase-03](phase-03-musthave-behavioral-binding.md) |
| B4 collab-docs archetype absent (notion: comments/search/history/mentions) | thiếu tính năng | **P1** [phase-03](phase-03-musthave-behavioral-binding.md) |
| B5 fix-loop no signal (gates green on dead build) | bảo fix chưa fix | downstream of B1–B4 — no separate fix |

## Phases
- **P0 [phase-01]** GATE-RT-PROPAGATE — skill-authored 2-context probe: A sends → assert B's DOM updates < budget, no reload. Presence/typing variant. Ships shared multi-client runner. *Core cure.* Status: ☐ PLANNED.
- **P1 [phase-02]** `realtime_media` capability + GATE-CALL — full runtime: 2 contexts + Chromium fake-media flags; assert `RTCPeerConnection.connectionState='connected'` + remote track. Status: ☐ PLANNED.
- **P1 [phase-03]** must_have→behavioral binding + `collab-docs` archetype — interactive must_have requires passing behavioral gate (not route+handler+test-file). Adds notion archetype. Status: ☐ PLANNED.

## Anti-gaming principle (applies P0+P1)
**Skill authors the probe spec**, build does not. Gate renders `templates/probes/*.spec.ts` from config selectors, runs against booted stack. Build cannot tautology-pass a test it never wrote. Build's contract = expose stable selectors / `window.__rtcPeer` accessor under E2E flag. Missing accessor ⇒ `N/A_PENDING_REVIEWER` (LAW-F6), never silent PASS.

## Cross-cutting (every phase)
1. New gate ⇒ new **MUST law** in `docs/ubs.md` (stack-agnostic bash contract, boss-doc tone — no Claude-only phrasing): LAW-RT-PROPAGATE, LAW-CALL, LAW-BEHAVIORAL-MUSTHAVE.
2. New gate ⇒ new **inversion meta-test** in `scripts/meta/` (HTTP-poll-only app → RT FAIL; call-UI-no-peer → CALL FAIL; working build → PASS). Bump `run-all-meta-gates.sh` expected count (23 → ~27).
3. Register gate ids in `scripts/orchestrator/run-all-gates.sh`.
4. Change protocol: edit skill → edit ubs.md → `run-all-meta-gates.sh` (pass=N fail=0) → regen `ubs.docx` → commit+push. docx→Drive manual.

## Dependencies / order
P0 first — ships shared `e2e-multiclient` runner that P1 reuses. Phase-02 builds on P0 runner + fake-media. Phase-03 last — binds to the gates P0+P1 produce.

## Key risks
- **WebRTC E2E flake** headless → fake-media flags + retry-once + budget; env can't fake media ⇒ N/A (never silent PASS).
- **Build-exposed handles** (selectors, `window.__rtcPeer`) = a real contract Devin apps MUST honor under E2E flag; doc states MUST; absent ⇒ N/A_PENDING_REVIEWER w/ reviewer note.
- **2 distinct logged-in users** needed → reuse v8.8 seed + auth-roundtrip to provision.
- **Boss-stack must actually RUN gates** — doc expresses MUST law + bash contract so any runner (Comet/Devin) enforces. Pre-existing constraint.

## Replay success criteria
Replay slack atom: RT-PROPAGATE FAILs (B never sees A's msg w/o reload). WIRE-STACK FAILs (call declared, `realtime_media` absent). GATE-CALL FAILs (connectionState never 'connected'). behavioral-binding FAILs (real-time-messaging must_have has no passing RT gate). Replay notion atom: collab-edit propagation FAILs if not live; collab-docs must_have surfaces comments/search/history/mentions. Honest realtime build passes all. meta-suite green.

## Resolved decisions (locked 2026-06-03)
1. **RTC accessor = configurable, default `window.__rtcPeer`.** Build declares `call.peer_accessor` in config; unset ⇒ default. Absent on page ⇒ N/A_PENDING_REVIEWER.
2. **RT-PROPAGATE budget = fixed 3000ms** (not tier-scaled). Per-journey explicit override allowed but no tier matrix. KISS.
3. **GATE-CALL trigger (3-way, any match ⇒ mandatory):**
   - (a) `call|huddle|voice call|video call|meeting` ∈ declared feature_surface → mandatory at ALL tiers (declared = must work).
   - (b) archetype ∈ {chat-app, collab-docs} AND scale_tier ∈ {scale, hyperscale} → mandatory even if undeclared (boss pick).
   - (c) **UI-detection (adopted 2026-06-03):** built frontend exposes a call surface (**≥2 corroborating signals**: call-ish route + call-ish component/handler/label) → mandatory at ANY tier. Closes the dead-button case.
   - else → N/A_PENDING_REVIEWER.
   - Mandatory ⇒ GATE-WIRE-STACK requires `realtime_media` wired AND GATE-CALL must PASS.
   - Escape hatch (LAW-F6): `call.ui_autodetect:false` + mandatory `reason` → demote (c) to N/A + reviewer note; never silent.

## Residual gap — CLOSED
Dead/unrequested call button now caught by trigger (c) UI-detection at any tier. ≥2-signal rule + escape-hatch guards false positives (e.g. "recall"/"API call" wording). slack case = covered regardless of tier.
