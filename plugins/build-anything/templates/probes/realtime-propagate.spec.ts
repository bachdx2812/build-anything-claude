// realtime-propagate.spec.ts — SKILL-AUTHORED probe for GATE-RT-PROPAGATE (UBS v8.9).
//
// The build does NOT write this test — the gate renders + runs it. That is the
// anti-gaming property: a build cannot tautology-pass a realtime claim it never
// implemented. The probe opens TWO independent browser contexts, has client A
// emit a unique marker, and asserts client B observes it WITHOUT a reload, within
// budget. HTTP-poll-only / no-push backends never deliver the marker → FAIL.
//
// All parameters arrive as one JSON blob in env RT_PROBE_CONFIG:
//   { app_url, login{url,email_selector,password_selector,submit_selector,ready_selector?},
//     users{a{email,password}, b{email,password}},
//     journey{ nav_url?, nav_selector?, send_selector, send_submit("enter"|<click-selector>),
//              observe_selector, budget_ms, isolation_nav_url?, isolation_nav_selector? },
//     marker }
import { test, expect, Page } from '@playwright/test';

const CFG = JSON.parse(process.env.RT_PROBE_CONFIG || '{}');
const APP: string = CFG.app_url;
const L = CFG.login || {};
const U = CFG.users || {};
const J = CFG.journey || {};
const MARKER: string = CFG.marker;
const BUDGET: number = J.budget_ms || 3000;

async function login(page: Page, creds: { email: string; password: string }) {
  await page.goto(APP + (L.url || '/login'));
  await page.fill(L.email_selector, creds.email);
  await page.fill(L.password_selector, creds.password);
  await page.click(L.submit_selector);
  if (L.ready_selector) await page.waitForSelector(L.ready_selector, { timeout: 15000 });
}

async function gotoChannel(page: Page, navUrl?: string, navSel?: string) {
  if (navUrl) await page.goto(APP + navUrl);
  else if (navSel) await page.click(navSel);
}

async function sendFrom(page: Page) {
  await page.fill(J.send_selector, MARKER);
  if ((J.send_submit || 'enter') === 'enter') await page.press(J.send_selector, 'Enter');
  else await page.click(J.send_submit);
}

test('realtime propagation A->B without reload', async ({ browser }) => {
  const ctxA = await browser.newContext();
  const ctxB = await browser.newContext();
  const a = await ctxA.newPage();
  const b = await ctxB.newPage();

  await login(a, U.a);
  await login(b, U.b);
  await gotoChannel(a, J.nav_url, J.nav_selector);
  await gotoChannel(b, J.nav_url, J.nav_selector);

  // B sits idle on the same channel. A emits the unique marker.
  await sendFrom(a);

  // CORE PROOF: B's DOM reflects A's marker live (no b.reload()), within budget.
  await expect(b.locator(J.observe_selector)).toContainText(MARKER, { timeout: BUDGET });

  await ctxA.close();
  await ctxB.close();
});

// Negative isolation: a client in a DIFFERENT channel must NOT receive the marker.
// Runs only when the build declares an isolation channel — proves push is scoped,
// not a global broadcast (cross-tenant/channel leak).
test('realtime isolation — other channel does NOT receive', async ({ browser }) => {
  test.skip(!(J.isolation_nav_url || J.isolation_nav_selector), 'no isolation channel declared');
  const ctxA = await browser.newContext();
  const ctxC = await browser.newContext();
  const a = await ctxA.newPage();
  const c = await ctxC.newPage();

  await login(a, U.a);
  await login(c, U.b);
  await gotoChannel(a, J.nav_url, J.nav_selector);
  await gotoChannel(c, J.isolation_nav_url, J.isolation_nav_selector);

  await sendFrom(a);

  // C must NOT see A's marker (scoped delivery). Wait the budget, then assert absent.
  await c.waitForTimeout(BUDGET);
  await expect(c.locator(J.observe_selector)).not.toContainText(MARKER);

  await ctxA.close();
  await ctxC.close();
});
