// auth.js — minimal stub for toy. Real prod = JWT verify.
const express = require('express');
const router = express.Router();

router.post('/login', (req, res) => {
  // Toy: trust username param. Real prod = bcrypt + JWT issue.
  const { user } = req.body;
  if (!user) return res.status(400).json({ error: 'missing user' });
  res.json({ token: `Bearer t${user[0] || 'a'}` });
});

module.exports = router;
