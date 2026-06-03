# Phase 02 — realtime_media capability + GATE-CALL (P1, full runtime)

**Gap:** B2 — WebRTC/call unmodeled + unverified. **Symptom:** "có phần call nhưng k chạy."
**Status:** ☐ PLANNED. Depends on phase-01 multi-client runner.

## Key insight (evidence)
- `grep -rniE "webrtc|getusermedia|rtcpeer|simple-peer|livekit|peerjs" scripts/ docs/ SKILL.md` = **empty**. WebRTC is modeled NOWHERE.
- `chat-app` catalog must_have (`:1896`) = accounts / messaging / channels / history / presence. **No calls.** Nothing requires or verifies a call feature.
- Result: build ships a call button, wires it to nothing (or to broken signaling), every gate green.

**Cure (full runtime, per decision):** model `realtime_media` capability → GATE-WIRE-STACK requires it when calls declared → GATE-CALL proves a peer connection actually reaches `connected` between 2 clients with media, using Chromium fake-media.

## Requirements
**Functional**
- F1 Catalog `realtime_media` capability (in `_stack_fitness_capabilities`):
  ```
  satisfies_keys: ["backend.realtime_media.kind","call.transport","stack.webrtc"]
  accept_values: ["webrtc","livekit","mediasoup","janus","simple-peer","peerjs","agora","twilio-video","daily","100ms"]
  disqualified_values: ["http-polling","ws-audio-base64"]
  wiring.dep_packages: ["simple-peer","livekit-client","livekit-server-sdk","mediasoup","mediasoup-client","peerjs","agora-rtc-sdk-ng","twilio-video","@daily-co/daily-js","@100mslive/react-sdk"]
  wiring.code_symbols: ["RTCPeerConnection","getUserMedia","createOffer","createAnswer","addIceCandidate","ontrack"]
  rationale: "slack+notion audit 2026-06-03: call UI shipped non-functional. WebRTC = signaling + ICE + media negotiation; a button proves nothing."
  ```
- F2 GATE-CALL trigger (3-way, any match ⇒ mandatory — DECIDED 2026-06-03):
  - (a) calls (`call|huddle|voice call|video call|meeting`) ∈ declared feature_surface/must_have → mandatory ALL tiers.
  - (b) archetype ∈ {chat-app, collab-docs} AND `scale_tier` ∈ {scale, hyperscale} → mandatory even if undeclared.
  - (c) UI-detection: built frontend exposes a call surface → mandatory ANY tier.
  - else → N/A_PENDING_REVIEWER.
  - Mandatory ⇒ GATE-WIRE-STACK **requires** `realtime_media` wired AND GATE-CALL PASS.
- F2b UI-detection rule (trigger c) `scripts/spec/call-surface-detect.sh` (or inline in capability-wiring):
  - Signals scanned in frontend source (exclude node_modules/.git/tests): **route** segment `/(call|huddle|meeting|video-?call|voice-?call)\b`; **symbol** `\b(Call|Huddle|VideoCall|VoiceCall|StartCall|JoinCall|Meeting)\w*` (component/handler); **label** in JSX/template `start call|join call|video call|voice call|huddle`.
  - Trigger requires **≥2 distinct signal kinds** (route+symbol, or symbol+label…) → single-word false positive (`recall`,`API call`,`callback`) cannot fire. Word-boundary anchored.
  - Escape hatch (LAW-F6): config `call.ui_autodetect:false` + mandatory `reason` → demote to N/A + reviewer note; never silent PASS.
  - Fired + no `realtime_media` wired ⇒ WIRE-STACK FAIL (dead button = exactly the slack case).
- F3 GATE-CALL runner `scripts/mechanical/e2e-call.sh` (reuses phase-01 multi-client harness):
  - Chromium flags: `--use-fake-device-for-media-stream --use-fake-ui-for-media-stream --autoplay-policy=no-user-gesture-required`; context `permissions:['microphone','camera']`.
  - 2 users; A initiates call to B; B accepts (or auto-answer in E2E mode).
  - **Proof:** `await a.waitForFunction(() => window.__rtcPeer?.connectionState === 'connected', {timeout: budget})`; AND remote track present on B: `(window.__rtcPeer.getReceivers()||[]).some(r => r.track && r.track.readyState==='live')`.
  - PASS iff both peers reach `connected` + ≥1 live remote track within budget.
- F4 Config:
  ```
  call.enabled, call.peer_accessor (default "window.__rtcPeer"),
  call.start_selector, call.accept_selector?, call.auto_answer (bool),
  call.budget_ms (default 15000)
  ```
**Non-functional**
- LAW-F6: env cannot fake media (flags rejected) OR `peer_accessor` undefined on page ⇒ N/A_PENDING_REVIEWER + reviewer note. NEVER silent PASS.
- LAW-CL-95 confidence/ambiguities. Retry-once on ICE flake. macOS bash 3.2.

## Build contract (state as MUST in doc)
App declaring `call` MUST expose the active `RTCPeerConnection` at `call.peer_accessor` (default `window.__rtcPeer`) when booted with E2E flag (`?e2e=1` / `NODE_ENV=test`). This is the introspection handle GATE-CALL reads. No handle ⇒ unverifiable ⇒ N/A (reviewer must manually verify the call).

## Related code files
**Create**
- `scripts/mechanical/e2e-call.sh` (GATE-CALL)
- `scripts/spec/call-surface-detect.sh` (trigger-c UI-detection, ≥2-signal)
- `templates/probes/call-connect.spec.ts`
- `scripts/meta/call-webrtc-test.sh` (inversion meta-test)
**Modify**
- `scripts/spec/feature-catalog.json` (add `realtime_media`; chat-app recommended += realtime_media)
- `scripts/spec/capability-wiring-check.sh` (3-way trigger: declared | tier scale+ | UI-detected → require realtime_media)
- `scripts/orchestrator/run-all-gates.sh` (register `mech-call`)
- `scripts/meta/run-all-meta-gates.sh` (bump count)
- `docs/ubs.md` (LAW-CALL + §B contract + build-contract MUST)

## Implementation steps
1. Add `realtime_media` to catalog `_stack_fitness_capabilities` w/ wiring block.
2. `call-surface-detect.sh`: ≥2-signal scan (route/symbol/label, word-boundary, exclude node_modules/tests); honor `call.ui_autodetect:false`+reason. capability-wiring: GATE-CALL mandatory if (a)declared OR (b)archetype@scale+ OR (c)UI-detected → inject `realtime_media` into required set; FAIL if unwired.
3. `e2e-call.sh`: extend multi-client harness w/ fake-media launch args + camera/mic perms; render `call-connect.spec.ts`; run; parse connectionState + remote-track assertions.
4. Inversion meta-test: A = simple-peer call connects → PASS; B = **call UI button, no RTCPeerConnection/no realtime_media → trigger-c fires → WIRE-STACK FAIL** (the slack case); C = call declared, dep absent → FAIL; D = "recall"/"API call" wording only (1 weak signal) → trigger-c does NOT fire (no false positive).
5. Register orchestrator + bump meta count. LAW-CALL + build-contract in ubs.md. Regen docx.

## Todo
- [ ] catalog `realtime_media` capability
- [ ] `call-surface-detect.sh` (≥2-signal UI-detection + escape hatch)
- [ ] 3-way trigger in capability-wiring (declared | tier scale+ | UI-detected) → require realtime_media
- [ ] `e2e-call.sh` + `call-connect.spec.ts` (fake-media, connectionState + remote-track)
- [ ] inversion meta-test (4 fixtures incl. dead-button-FAIL + false-positive-guard)
- [ ] orchestrator + meta count bump
- [ ] LAW-CALL + build-contract in ubs.md + docx regen

## Success criteria
Replay slack atom (declared OR chat-app@scale+ OR **call button detected**): WIRE-STACK FAILs (no realtime_media dep). GATE-CALL FAILs (connectionState never 'connected'). Dead call button at ANY tier → trigger-c FAIL. False-positive guard: lone "call" wording → no trigger. Honest simple-peer build: PASS. No-fake-media / no peer_accessor: N/A + note. meta-suite green.

## Risk
- **Headless WebRTC flake** — fake-media flags make host-candidate p2p deterministic on localhost; retry-once; budget 15s. TURN not needed for same-host loopback.
- **peer_accessor coupling** — documented MUST; absent ⇒ N/A not FAIL (don't punish a working call we just can't introspect — surface to reviewer).
- **SFU stacks** (livekit/mediasoup) route media through server, not p2p — connectionState still valid on client PeerConnection to SFU; assertion holds.

## Security
getUserMedia permission prompt auto-granted only under fake-media E2E flag — never in prod build. Doc states E2E flag MUST be off in production (no auto-grant).

## Next steps
phase-03 binds calls (when declared) into must_have behavioral requirement.
