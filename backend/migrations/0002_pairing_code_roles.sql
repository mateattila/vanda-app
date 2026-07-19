-- A párosító kód hordozza, milyen szerepű eszközt hoz létre a beváltása.
-- A DEFAULT 'parent' miatt a meglévő sorok viselkedése változatlan.
ALTER TABLE pairing_codes ADD COLUMN role TEXT NOT NULL DEFAULT 'parent';
