// Toy backend for dry-run validation of /build-anything skill.
// Intentionally contains 12 seeded bugs — see ../seeded-bugs.md.
// NEVER deploy this. Local docker-compose only.
const express = require('express');
const { initDb, db } = require('./db');
const ordersRouter = require('./routes/orders');
const authRouter = require('./routes/auth');

const app = express();
app.use(express.json());

// BUG-03: hardcoded "API key" left in plain source — LAW-04 must catch.
const ADMIN_API_KEY = "sk-proj-aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789";

// BUG-06: no request logging middleware — GATE-15 must catch.
// (deliberately no morgan/pino — observability gap)

app.use('/api/orders', ordersRouter);
app.use('/api/auth', authRouter);

// admin queue depth endpoint for GATE-18d
app.get('/admin/queues/:name/depth', (req, res) => {
  const row = db.prepare("SELECT count(*) AS c FROM job_queue WHERE queue=? AND status='pending'").get(req.params.name);
  res.json(row.c);
});

// chaos middleware honoring X-Chaos-Inject for GATE-18c tests
app.locals.chaos = (point) => (req, _res, next) => {
  if (req.get('X-Chaos-Inject') === point) {
    const err = new Error('chaos: ' + point);
    err.chaos = true;
    return next(err);
  }
  next();
};

app.use((err, _req, res, _next) => {
  // BUG-13 partial: error message leaks key on certain paths (security smell)
  res.status(err.chaos ? 500 : 500).json({ error: err.message });
});

if (require.main === module) {
  initDb();
  const port = process.env.PORT || 3000;
  app.listen(port, () => console.log(`toy backend on ${port}`));
}

module.exports = { app, ADMIN_API_KEY };
