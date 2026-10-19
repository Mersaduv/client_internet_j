CREATE TABLE IF NOT EXISTS access_codes (
  code_hash TEXT PRIMARY KEY,
  username TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at INTEGER,
  reusable INTEGER NOT NULL DEFAULT 0,
  router_secret TEXT,
  code_sealed TEXT
);

CREATE TABLE IF NOT EXISTS redeem_attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ip TEXT NOT NULL,
  at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS phone_sessions (
  token_hash TEXT PRIMARY KEY,
  username TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS access_codes_user ON access_codes (username, created_at);
