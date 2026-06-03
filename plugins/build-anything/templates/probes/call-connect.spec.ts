// call-connect.spec.ts — SKILL-AUTHORED probe for GATE-CALL (UBS v8.9).
//
// slack+notion audit 2026-06-03: a call button shipped that never connected. A
// present button / route / handler proves nothing — WebRTC needs signaling + ICE +
// media negotiation to actually establish. This probe opens TWO contexts with FAKE
// media (deterministic on localhost), has A start a call and B answer, then asserts
// BOTH peers reach RTCPeerConnection.connectionState === 'connected' within budget
// AND B receives a live remote track. A dead call button never reaches 'connected'.
//
// Build contract: the app MUST expose its active RTCPeerConnection at the declared
// accessor (default window.__rtcPeer) when booted under the E2E flag. No accessor =>
// the gate emits N/A (cannot introspect) — never a silent PASS.
//
// Params arrive as JSON in env CALL_PROBE_CONFIG:
//   { app_url, login{...}, users{a,b},
//     call{ peer_accessor, nav_url?, start_selector, accept_selector?, auto_answer?, budget_ms } }
import { test, expect, Page } from '@playwright/test';

const CFG = JSON.parse(process.env.CALL_PROBE_CONFIG || '{}');
const APP: string = CFG.app_url;
const L = CFG.login || {};
const U = CFG.users || {};
const C = CFG.call || {};
const ACCESSOR: string = C.peer_accessor || 'window.__rtcPeer';
const BUDGET: number = C.budget_ms || 15000;

// Fake media makes a same-host peer connection deterministic in headless CI.
test.use({
  permissions: ['microphone', 'camera'],
  launchOptions: {
    args: [
      '--use-fake-device-for-media-stream',
      '--use-fake-ui-for-media-stream',
      '--autoplay-policy=no-user-gesture-required',
    ],
  },
});

async function login(page: Page, creds: { email: string; password: string }) {
  await page.goto(APP + (L.url || '/login'));
  await page.fill(L.email_selector, creds.email);
  await page.fill(L.password_selector, creds.password);
  await page.click(L.submit_selector);
  if (L.ready_selector) await page.waitForSelector(L.ready_selector, { timeout: 15000 });
}

async function waitConnected(page: Page) {
  await page.waitForFunction(
    (acc) => {
      try {
        // eslint-disable-next-line no-eval
        const pc: any = eval(acc as string);
        return !!pc && pc.connectionState === 'connected';
      } catch {
        return false;
      }
    },
    ACCESSOR,
    { timeout: BUDGET },
  );
}

test('webrtc call connects A<->B with live media', async ({ browser }) => {
  const ctxA = await browser.newContext({ permissions: ['microphone', 'camera'] });
  const ctxB = await browser.newContext({ permissions: ['microphone', 'camera'] });
  const a = await ctxA.newPage();
  const b = await ctxB.newPage();

  await login(a, U.a);
  await login(b, U.b);
  if (C.nav_url) {
    await a.goto(APP + C.nav_url);
    await b.goto(APP + C.nav_url);
  }

  await a.click(C.start_selector);
  if (!C.auto_answer && C.accept_selector) await b.click(C.accept_selector);

  // PROOF 1: both peers negotiate to 'connected' (signaling + ICE + DTLS done).
  await waitConnected(a);
  await waitConnected(b);

  // PROOF 2: B actually receives a live remote track (media flows, not just signaling).
  const hasRemote = await b.evaluate((acc) => {
    try {
      // eslint-disable-next-line no-eval
      const pc: any = eval(acc as string);
      return (pc.getReceivers() || []).some((r: any) => r.track && r.track.readyState === 'live');
    } catch {
      return false;
    }
  }, ACCESSOR);
  expect(hasRemote, 'B received a live remote media track').toBeTruthy();

  await ctxA.close();
  await ctxB.close();
});
