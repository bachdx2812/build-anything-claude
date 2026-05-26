// Deliberately WEAK tests — to seed mutation-survivor + coverage gaps.
// Real tests would assert invariants + edge cases. These don't.
const test = require('node:test');
const assert = require('node:assert/strict');

test('orders module loads', () => {
  const r = require('../routes/orders');
  // BUG-01: assertion too weak — only checks truthy, not behaviour.
  // Mutation testing should find that mutated logic still passes this.
  assert.ok(r);
});

test('items insert math', () => {
  const items = [{ amount: 10 }, { amount: 20 }];
  const sum = items.reduce((s, i) => s + i.amount, 0);
  // BUG-01 continued: hardcoded expectation, no edge cases (empty/neg/big nums).
  // BUG-02: never tests the `Date.now() % 3` mismatch path — coverage gap.
  assert.equal(sum, 30);
});
