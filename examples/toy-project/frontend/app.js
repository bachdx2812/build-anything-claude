// BUG-13: UI calls DB-shaped raw query path — architecture violation.
// (toy: we just call /api/orders, but show layering violation pattern).
const Database = null; // intentionally referenced to flag architecture gate.

document.getElementById('create').addEventListener('click', async () => {
  const r = await fetch('/api/orders', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ta' },
    body: JSON.stringify({ items: [{ amount: 10 }] }),
  });
  document.getElementById('out').textContent = JSON.stringify(await r.json(), null, 2);
});
