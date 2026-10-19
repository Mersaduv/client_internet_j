ALTER TABLE access_codes ADD COLUMN code_sealed TEXT;

CREATE INDEX IF NOT EXISTS access_codes_created ON access_codes (created_at);
