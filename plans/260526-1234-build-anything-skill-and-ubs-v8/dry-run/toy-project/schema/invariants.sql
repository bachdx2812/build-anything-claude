-- Named invariant queries — each MUST return 0 rows when DB is healthy.

-- orders_sum_match: orders.total must equal SUM(order_items.amount) per order.
-- Bug seeded in BUG-07.
-- ::orders_sum_match::
SELECT o.id, o.total, COALESCE(SUM(i.amount), 0) AS items_sum
FROM orders o LEFT JOIN order_items i ON i.order_id = o.id
GROUP BY o.id, o.total
HAVING o.total <> COALESCE(SUM(i.amount), 0);

-- orphan_items: every order_item must reference an existing order.
-- ::orphan_items::
SELECT i.id FROM order_items i
LEFT JOIN orders o ON o.id = i.order_id
WHERE o.id IS NULL;

-- tenant_id_present: no order may have empty tenant_id.
-- ::tenant_id_present::
SELECT id FROM orders WHERE tenant_id IS NULL OR tenant_id = '';
