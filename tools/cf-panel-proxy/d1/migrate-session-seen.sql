ALTER TABLE phone_sessions ADD COLUMN last_seen_at INTEGER;

UPDATE phone_sessions SET last_seen_at = created_at WHERE last_seen_at IS NULL;
