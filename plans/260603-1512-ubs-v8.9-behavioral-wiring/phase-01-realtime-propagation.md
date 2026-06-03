# Phase 01 — GATE-RT-PROPAGATE (P0, core cure)

**Gap:** B1 — realtime propagation unverified. **Symptom:** "chat k realtime."
**Status:** ☐ PLANNED.

## Key insight (evidence, line-quoted)
- `e2e-playwright.sh:200-205` boots ONE frontend + ONE backend, runs `npx playwright test` in a single browser context. One client can't observe another's pushed state.
- `e2e-playwright.sh:132` journey "covered" = test-file name/content grep. A spec that sends a message and asserts the **sender's own** optimistic-UI echo PASSES — never proves delivery to a second client.
- `capability-wiring-check.sh:233` marks `realtime_transport` WIRED on dep/symbol presence. socket.io imported but never `.emit`/broadcast wired = still PASS.
- `grep -rniE "newContext|two.?client|propagat" scripts/` = empty. No multi-client gate exists.

**Cure:** skill-authored 2-context probe. A acts in client A; assert client B's DOM reflects it within budget, **without reload**. Unique per-run marker ⇒ B must receive A's marker (cross-client), not echo its own (anti-tautology).

## Requirements
**Functional**
- F1 Shared runner `scripts/mechanical/e2e-multiclient.sh`: boot stack (reuse `e2e-playwright` boot helpers in `_common.sh`), provision 2 distinct users (reuse v8.8 seed/auth-roundtrip), render probe spec from template, run, parse, emit verdict JSON.
- F2 GATE-RT-PROPAGATE: for each declared realtime journey, run propagate probe. PASS iff client B's `observe_selector` contains the unique marker A emitted, within `budget_ms`, with **no page reload** between send and observe.
- F3 Presence/typing variant: if `presence` ∈ must_have/feature_surface → probe: A focuses input / logs in → assert B's presence|typing selector reaches expected state in budget.
- F4 Config schema in `.build-anything.json`:
  ```
  realtime.enabled: true
  realtime.journeys[]: [{
    name, login_a{steps|seeded_user}, login_b{...},
    nav_selector|nav_url, send_selector, send_submit ("enter"|click-selector),
    observe_selector, budget_ms (default 3000),
    presence_selector? , presence_expect?
  }]
  ```
**Non-functional**
- LAW-F6: `realtime.enabled=true` but no journeys ⇒ FAIL (not vacuous). project realtime-class (chat-app/collab-docs) with `realtime.enabled` unset ⇒ FAIL (declared-but-skipped, mirrors e2e enabled rule `:92`). Selectors missing ⇒ N/A_PENDING_REVIEWER + reviewer note.
- LAW-CL-95: confidence + ambiguities[] on verdict. macOS bash 3.2. Retry-once on flake before FAIL.

## Probe template (skill-authored, build cannot game)
`templates/probes/realtime-propagate.spec.ts` (parameterized via env from config):
```ts
test('rt propagate A->B', async ({ browser }) => {
  const a = await (await browser.newContext()).newPage();
  const b = await (await browser.newContext()).newPage();
  await loginA(a); await loginB(b);                 // distinct creds
  await navA(a); await navB(b);                      // same channel/room
  const marker = `rt-${process.env.RUN_ID}`;        // unique per run (passed in, not Date.now in-spec)
  await a.fill(SEND_SEL, marker); await submitA(a);
  // CORE PROOF: B observes A's marker without reload, within budget
  await expect(b.locator(OBSERVE_SEL)).toContainText(marker, { timeout: BUDGET_MS });
});
```
HTTP-poll-only or no-push backend ⇒ B never sees marker in budget ⇒ FAIL. Exactly catches "k realtime."

## Related code files
**Create**
- `scripts/mechanical/e2e-multiclient.sh` (GATE-RT-PROPAGATE runner)
- `templates/probes/realtime-propagate.spec.ts`, `templates/probes/presence-observe.spec.ts`
- `scripts/meta/realtime-propagation-test.sh` (inversion meta-test)
**Modify**
- `scripts/orchestrator/run-all-gates.sh` (register `mech-rt-propagate`)
- `scripts/meta/run-all-meta-gates.sh` (bump expected count)
- `docs/ubs.md` (LAW-RT-PROPAGATE + §B contract)

## Implementation steps
1. Extract boot/teardown + dep-install helpers from `e2e-playwright.sh` into `_common.sh` (DRY) so multiclient reuses them.
2. `e2e-multiclient.sh`: resolve realtime journeys; per journey render template with selectors + `RUN_ID`; `npx playwright test <tmpspec>`; parse pass/fail; verdict JSON (`gate-mechanical/rt-propagate.json`).
3. Provision 2 users via seed/auth-roundtrip (register 2 random creds, or seeded_user from config).
4. Presence variant when declared.
5. Inversion meta-test: fixture A = realtime app (ws broadcast) → PASS; fixture B = HTTP-poll-only chat → FAIL; fixture C = enabled+0-journeys → FAIL.
6. Register orchestrator + bump meta count. LAW-RT-PROPAGATE in ubs.md. Regen docx.

## Todo
- [ ] `_common.sh` boot/teardown extraction
- [ ] `e2e-multiclient.sh` + propagate template
- [ ] presence/typing variant
- [ ] 2-user provisioning (reuse seed/auth-RT)
- [ ] inversion meta-test (3 fixtures)
- [ ] orchestrator + meta count bump
- [ ] LAW-RT-PROPAGATE in ubs.md + docx regen

## Success criteria
Replay slack atom: RT-PROPAGATE FAILs (B never sees A's marker w/o reload). Honest ws build: PASS. enabled+0-journeys: FAIL. meta-suite green.

## Risk
- Flake on slow boot → budget + retry-once; boot wait reuses `wait_http_200`.
- Selector drift across builds → config-declared selectors; absent ⇒ N/A + reviewer note (never silent PASS).
- Login flow varies → support seeded_user (skip UI login) as fallback to UI-login steps.

## Security
2-user isolation probe doubles as cross-tenant leak check: assert B in a DIFFERENT channel does NOT receive A's marker (negative case).

## Next steps
Ships the multi-client runner phase-02 (GATE-CALL) reuses.
