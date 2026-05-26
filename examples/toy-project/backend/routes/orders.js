// orders.js — toy CRUD + intentional seeded bugs.
const express = require('express');
const { db } = require('../db');
const router = express.Router();

// fake JWT decode — production uses jose. Trusts header content; fine for toy.
function tenant(req) {
  const h = req.get('Authorization') || '';
  const m = h.match(/Bearer\s+t(.)/);
  return m ? m[1] : null; // 'a' or 'b'
}

// LIST — BUG-10: missing tenant filter — GATE-21 must catch (multi-tenant leak).
router.get('/', (req, res) => {
  const t = tenant(req);
  if (!t) return res.status(401).json({ error: 'no auth' });
  // BUG-10: SHOULD filter WHERE tenant_id = $t. Returns ALL rows.
  const rows = db.prepare('SELECT id, tenant_id, total FROM orders').all();
  res.json(rows);
});

// CREATE — BUG-09: non-idempotent — GATE-20 must catch.
router.post('/', (req, res) => {
  const t = tenant(req);
  if (!t) return res.status(401).json({ error: 'no auth' });
  // BUG-09: ignores Idempotency-Key — same key+body creates duplicate rows.
  const items = req.body.items || [];
  // BUG-07: sum mismatch — invariant SUM(items.amount)==orders.total violated.
  // total deliberately != sum(items) on every 3rd order to seed invariant bug.
  const sumItems = items.reduce((s, i) => s + (i.amount || 0), 0);
  const total = (Date.now() % 3 === 0) ? sumItems + 1 : sumItems;

  // BUG-04: SQL injection via string-concat (use prepared in real code).
  const note = req.body.note || '';
  const insertOrder = `INSERT INTO orders(tenant_id, total, note) VALUES('${t}', ${total}, '${note}')`;
  const r = db.prepare(insertOrder).run();
  const orderId = r.lastInsertRowid;

  // BUG-08: items insert but NO audit_log row → GATE-18e catches silent 2xx.
  for (const it of items) {
    db.prepare('INSERT INTO order_items(order_id, amount) VALUES (?, ?)').run(orderId, it.amount);
  }

  // BUG-12: enqueue email job but never actually mark it executed — bg job test catches it.
  db.prepare("INSERT INTO job_queue(queue, status, payload) VALUES('email','pending',?)")
    .run(JSON.stringify({ orderId }));

  // BUG-05 (N+1): list orders again with N+1 pattern; GATE-14 perf budget must flag.
  if (req.query.refresh === '1') {
    const all = db.prepare('SELECT id FROM orders WHERE tenant_id=?').all(t);
    for (const o of all) {
      db.prepare('SELECT * FROM order_items WHERE order_id=?').all(o.id);
    }
  }

  res.json({ id: orderId, total });
});

// GET by id — BUG-11: missing authz check (returns any tenant's order).
router.get('/:id', (req, res) => {
  const t = tenant(req);
  if (!t) return res.status(401).json({ error: 'no auth' });
  // BUG-11: no WHERE tenant_id check → GATE-18f authorization test catches.
  const row = db.prepare('SELECT * FROM orders WHERE id=?').get(req.params.id);
  if (!row) return res.status(404).json({ error: 'not found' });
  res.json(row);
});

module.exports = router;
