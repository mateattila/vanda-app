CREATE TABLE families (
  id TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL
);

CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL REFERENCES families(id),
  role TEXT NOT NULL CHECK (role IN ('child', 'parent')),
  name TEXT NOT NULL DEFAULT '',
  token_hash TEXT NOT NULL UNIQUE,
  apns_token TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_devices_family ON devices(family_id);

CREATE TABLE pairing_codes (
  code TEXT PRIMARY KEY,
  family_id TEXT NOT NULL REFERENCES families(id),
  expires_at INTEGER NOT NULL,
  used_at INTEGER
);
