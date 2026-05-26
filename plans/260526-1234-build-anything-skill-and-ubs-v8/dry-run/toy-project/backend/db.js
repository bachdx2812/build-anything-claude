// SQLite — embedded for zero-setup dry-run. Real prod = Postgres.
const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

const DB_PATH = process.env.DB_URL || path.join(__dirname, '../.toy-test.db');
const db = new Database(DB_PATH);

function initDb() {
  const schema = fs.readFileSync(path.join(__dirname, '../schema/init.sql'), 'utf8');
  db.exec(schema);
}

module.exports = { db, initDb };
