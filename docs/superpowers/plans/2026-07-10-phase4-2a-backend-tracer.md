# 4.2a — Backend tracer (Worker-váz + párosítás + APNs-küldő) — implementációs terv

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `backend/` alatt egy deploy-kész Cloudflare Worker: család-létrehozás, 6 jegyű párosítás, eszköz-tokenek, APNs teszt-push küldő — lokálisan teljes egészében vitest-tel tesztelve.

**Architecture:** TypeScript + Hono, D1 (families/devices/pairing_codes), bearer-token auth (32 bájt véletlen, SHA-256 hash-elve tárolva), APNs közvetlen `fetch`-csel (ES256 JWT WebCryptóval, függőség nélkül). A deploy és az end-to-end push a 4.2b + Attila kézi lépései után él — ez a terv addig a pontig visz, hogy minden más igazoltan működik.

**Tech Stack:** Hono ^4, wrangler ^4 (`wrangler.jsonc`), `@cloudflare/vitest-pool-workers` + vitest (valódi D1-lel, Workers-runtime-ban futó tesztek), WebCrypto.

**Design-forrás:** `docs/superpowers/specs/2026-07-07-phase4-panic-backend-design.md` (1. szakasz); spec 5. fejezet.

## Global Constraints

- **Környezet:** node v22, npm 10, wrangler `npx`-szel (4.110+). Minden parancs a `backend/` könyvtárból fut, kivéve a git-műveleteket (repo-gyökér).
- **Minden task végén zöld:** `npx tsc --noEmit` és `npx vitest run` (gyors, nincs szimulátor). A vitest-kimenet pristine — warning is finding.
- **Workers best practices (2026-07-10-én ellenőrizve):** `compatibility_date: "2026-07-10"`, `nodejs_compat` flag, `observability.enabled: true`; tokenekhez `crypto.getRandomValues` (SOHA `Math.random`); secret csak `wrangler secret put`-tal (a repo-ba secret nem kerülhet); minden Promise await-elve (no floating promises); nincs modul-szintű request-állapot.
- **APNs-korlát (workerd #4841):** lokális `wrangler dev` macOS-en NEM tud HTTP/2-t az APNs felé — az APNs-hívás élesben csak deployolt Workerből tesztelhető. A unit tesztek `fetchMock`-kal fedik a küldőt; az end-to-end push a 4.2b eszközös körében történik.
- **YAGNI:** R2 (escrow, 4.5), cron (panik-retenció, 4.3), PanicEvent endpointok (4.3) ebben a tervben NEM készülnek el.
- **Adatminimalizálás (spec 5.):** nevek helyett becenevek/szerepek; a válaszok soha nem tartalmaznak más eszköz tokenjét.
- Commit-üzenet stílus: `phase 4.2a: <rövid angol összefoglaló>`.
- A `wrangler.jsonc`-ban a `database_id` placeholder marad (`"REPLACE-AFTER-wrangler-d1-create"`) — a lokális teszteknek nem kell valódi ID; a valódit Attila teszi be deploykor (README).

---

### Task 1: Scaffold — npm-projekt, wrangler.jsonc, D1-séma, vitest-váz, /health

**Files:**
- Create: `backend/package.json`, `backend/wrangler.jsonc`, `backend/tsconfig.json`, `backend/.gitignore`
- Create: `backend/migrations/0001_init.sql`
- Create: `backend/src/index.ts`, `backend/src/secrets.d.ts`
- Create: `backend/vitest.config.ts`, `backend/test/apply-migrations.ts`, `backend/test/env.d.ts`, `backend/test/health.test.ts`

**Interfaces:**
- Produces: futó Hono-app `GET /health` végponttal; D1-séma (`families`, `devices`, `pairing_codes`); vitest-infrastruktúra `SELF.fetch`-csel és automatikusan migrált teszt-D1-gyel — minden későbbi task erre épül.

- [ ] **Step 1: npm-projekt és függőségek**

```bash
mkdir -p backend && cd backend
npm init -y
npm install hono
npm install -D wrangler typescript vitest@~3.2.0 @cloudflare/vitest-pool-workers
```

- [ ] **Step 2: Konfigurációs fájlok**

`backend/wrangler.jsonc`:

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "vanda-backend",
  "main": "src/index.ts",
  "compatibility_date": "2026-07-10",
  "compatibility_flags": ["nodejs_compat"],
  "observability": {
    "enabled": true,
    "logs": { "head_sampling_rate": 1 }
  },
  "vars": {
    // Xcode-os (development) buildekhez a sandbox APNs kell; TestFlight/App Store
    // buildekhez váltandó a production hostra: https://api.push.apple.com
    "APNS_HOST": "https://api.sandbox.push.apple.com",
    "APNS_TOPIC": "hu.attis.VandaApp"
  },
  "d1_databases": [
    {
      "binding": "DB",
      "database_name": "vanda",
      "database_id": "REPLACE-AFTER-wrangler-d1-create",
      "migrations_dir": "migrations"
    }
  ]
}
```

`backend/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "lib": ["ES2022"],
    "types": [],
    "strict": true,
    "noEmit": true,
    "skipLibCheck": true,
    "isolatedModules": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*.ts", "src/**/*.d.ts", "worker-configuration.d.ts"]
}
```

(A tesztfájlokat a vitest-pool-workers saját tsconfig nélkül is futtatja; a `tsc --noEmit` a src-t ellenőrzi. A `worker-configuration.d.ts`-t a `wrangler types` generálja és COMMITOLJUK, hogy friss checkout is típusozzon.)

`backend/.gitignore`:

```
node_modules/
.wrangler/
.dev.vars
```

`backend/src/secrets.d.ts` — a secretek nem szerepelnek a wrangler-configban, ezért a generált `Env`-et deklaráció-összefésüléssel bővítjük:

```ts
// A wrangler types által generált Env kiegészítése a secretekkel
// (wrangler secret put APNS_TEAM_ID / APNS_KEY_ID / APNS_PRIVATE_KEY).
interface Env {
  APNS_TEAM_ID: string;
  APNS_KEY_ID: string;
  APNS_PRIVATE_KEY: string;
}
```

- [ ] **Step 3: D1-séma**

`backend/migrations/0001_init.sql`:

```sql
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
```

- [ ] **Step 4: Minimál app + vitest-infrastruktúra**

`backend/src/index.ts`:

```ts
import { Hono } from 'hono';

const app = new Hono<{ Bindings: Env }>();

app.get('/health', (c) => c.json({ ok: true }));

export default app;
```

`backend/vitest.config.ts`:

```ts
import { defineWorkersConfig, readD1Migrations } from '@cloudflare/vitest-pool-workers/config';

// Teszt-fixture P-256 kulcs — NEM titok, kizárólag a JWT-aláírás unit tesztjéhez
// generált eldobható kulcspár (a párja a tesztfájlban lévő publikus kulcs).
export const TEST_APNS_PRIVATE_KEY = `-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg9YkeBF9Ngqi9ui3x
0MuY+62eO5fJvD/tdudghHUGwIOhRANCAAS2QfeCuMMsIe8AIs9eOIdfoO8SM1Ff
V7u6xKHfYj9GYElHOyoBEnMNAHOnTZlzgfrLme6IHjOKMspMXaRRvFKm
-----END PRIVATE KEY-----`;

export default defineWorkersConfig(async () => {
  const migrations = await readD1Migrations('./migrations');
  return {
    test: {
      setupFiles: ['./test/apply-migrations.ts'],
      poolOptions: {
        workers: {
          wrangler: { configPath: './wrangler.jsonc' },
          miniflare: {
            bindings: {
              TEST_MIGRATIONS: migrations,
              APNS_TEAM_ID: 'TESTTEAM99X',
              APNS_KEY_ID: 'TESTKEY99XX',
              APNS_PRIVATE_KEY: TEST_APNS_PRIVATE_KEY,
            },
          },
        },
      },
    },
  };
});
```

`backend/test/apply-migrations.ts`:

```ts
import { applyD1Migrations, env } from 'cloudflare:test';

await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
```

`backend/test/env.d.ts`:

```ts
import type { D1Migration } from '@cloudflare/vitest-pool-workers/config';

declare module 'cloudflare:test' {
  interface ProvidedEnv extends Env {
    TEST_MIGRATIONS: D1Migration[];
  }
}
```

`backend/test/health.test.ts`:

```ts
import { SELF } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';

describe('health', () => {
  it('responds ok', async () => {
    const res = await SELF.fetch('https://vanda.test/health');
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
  });
});
```

`backend/package.json` — a `scripts` blokk cseréje:

```json
{
  "scripts": {
    "dev": "wrangler dev",
    "test": "vitest run",
    "check": "tsc --noEmit",
    "types": "wrangler types",
    "deploy": "wrangler deploy"
  }
}
```

- [ ] **Step 5: Típusgenerálás + ellenőrzés**

```bash
cd backend
npx wrangler types
npx tsc --noEmit
npx vitest run
```

Expected: `worker-configuration.d.ts` létrejön; tsc hibátlan; 1 teszt PASS.

- [ ] **Step 6: Commit** (repo-gyökérből)

```bash
git add backend
git commit -m "phase 4.2a: backend scaffold — Hono worker, D1 schema, vitest pool-workers"
```

---

### Task 2: Kripto-helperek (TDD)

**Files:**
- Create: `backend/src/tokens.ts`
- Test: `backend/test/tokens.test.ts`

**Interfaces:**
- Produces: `newBearerToken(): string` (32 bájt, base64url), `sha256Hex(input: string): Promise<string>`, `newPairingCode(): string` (6 számjegy, kriptó-véletlen) — a 3–4. task használja.

- [ ] **Step 1: Bukó tesztek**

`backend/test/tokens.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { newBearerToken, newPairingCode, sha256Hex } from '../src/tokens';

describe('bearer token', () => {
  it('is base64url and long enough for 32 bytes', () => {
    const token = newBearerToken();
    expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/); // 32 bájt base64url, padding nélkül
  });

  it('is unique across calls', () => {
    expect(newBearerToken()).not.toBe(newBearerToken());
  });
});

describe('sha256Hex', () => {
  it('matches a known vector', async () => {
    expect(await sha256Hex('abc')).toBe(
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    );
  });
});

describe('pairing code', () => {
  it('is exactly six digits', () => {
    for (let i = 0; i < 20; i++) {
      expect(newPairingCode()).toMatch(/^\d{6}$/);
    }
  });
});
```

- [ ] **Step 2: Futtasd — bukjon** (`npx vitest run` → cannot find module '../src/tokens')

- [ ] **Step 3: Implementáció**

`backend/src/tokens.ts`:

```ts
export function base64url(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

/// Eszköz-token: 32 bájt kriptó-véletlen. A szerver csak a hash-ét tárolja.
export function newBearerToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return base64url(bytes);
}

export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/// 6 jegyű párosító kód. (A 2^32 mod 10^6 torzítás ~0,02% — 10 perces,
/// egyszer használatos kódnál elfogadható.)
export function newPairingCode(): string {
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  return String(bytes[0] % 1_000_000).padStart(6, '0');
}
```

- [ ] **Step 4: Futtasd — menjen át**, majd `npx tsc --noEmit`

- [ ] **Step 5: Commit**

```bash
git add backend/src/tokens.ts backend/test/tokens.test.ts
git commit -m "phase 4.2a: crypto helpers — bearer tokens, sha256, pairing codes"
```

---

### Task 3: Család-létrehozás + auth-middleware (TDD)

**Files:**
- Create: `backend/src/auth.ts`
- Modify: `backend/src/index.ts`
- Test: `backend/test/families.test.ts`

**Interfaces:**
- Consumes: Task 2 helperek.
- Produces: `POST /families {deviceName?} → 201 {familyId, deviceId, token}`; `GET /me → {deviceId, familyId, role, name, hasApnsToken}`; `requireDevice` middleware (`c.get('device')` → `DeviceRow`), `requireRole('child'|'parent')` — a 4–5. task használja.

- [ ] **Step 1: Bukó tesztek**

`backend/test/families.test.ts`:

```ts
import { SELF } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';

async function createFamily(name = 'Vanda iPhone') {
  const res = await SELF.fetch('https://vanda.test/families', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceName: name }),
  });
  return res;
}

describe('POST /families', () => {
  it('creates a family and returns a child token', async () => {
    const res = await createFamily();
    expect(res.status).toBe(201);
    const body = await res.json<{ familyId: string; deviceId: string; token: string }>();
    expect(body.familyId).toBeTruthy();
    expect(body.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });
});

describe('GET /me', () => {
  it('returns the device identity for a valid token', async () => {
    const { token } = await (await createFamily()).json<{ token: string }>();
    const res = await SELF.fetch('https://vanda.test/me', {
      headers: { authorization: `Bearer ${token}` },
    });
    expect(res.status).toBe(200);
    const me = await res.json<{ role: string; name: string; hasApnsToken: boolean }>();
    expect(me.role).toBe('child');
    expect(me.name).toBe('Vanda iPhone');
    expect(me.hasApnsToken).toBe(false);
  });

  it('rejects a missing token', async () => {
    const res = await SELF.fetch('https://vanda.test/me');
    expect(res.status).toBe(401);
  });

  it('rejects an unknown token', async () => {
    const res = await SELF.fetch('https://vanda.test/me', {
      headers: { authorization: 'Bearer definitely-not-a-real-token-aaaaaaaaaaaaa' },
    });
    expect(res.status).toBe(401);
  });
});
```

- [ ] **Step 2: Futtasd — bukjon** (404-ek / hiányzó modul)

- [ ] **Step 3: Implementáció**

`backend/src/auth.ts`:

```ts
import { createMiddleware } from 'hono/factory';
import { sha256Hex } from './tokens';

export type DeviceRow = {
  id: string;
  family_id: string;
  role: 'child' | 'parent';
  name: string;
  token_hash: string;
  apns_token: string | null;
  created_at: number;
};

export type AuthEnv = { Bindings: Env; Variables: { device: DeviceRow } };

/// Bearer-token → eszköz. A tokennek csak a SHA-256 hash-e van az adatbázisban;
/// a keresés a hash-en történik, így a nyers token sosem ér el a D1-ig.
export const requireDevice = createMiddleware<AuthEnv>(async (c, next) => {
  const header = c.req.header('authorization') ?? '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!token) return c.json({ error: 'unauthorized' }, 401);

  const hash = await sha256Hex(token);
  const device = await c.env.DB
    .prepare('SELECT * FROM devices WHERE token_hash = ?')
    .bind(hash)
    .first<DeviceRow>();
  if (!device) return c.json({ error: 'unauthorized' }, 401);

  c.set('device', device);
  await next();
});

export const requireRole = (role: DeviceRow['role']) =>
  createMiddleware<AuthEnv>(async (c, next) => {
    if (c.get('device').role !== role) return c.json({ error: 'forbidden' }, 403);
    await next();
  });
```

`backend/src/index.ts` — teljes új tartalom:

```ts
import { Hono } from 'hono';
import { requireDevice, type AuthEnv } from './auth';
import { newBearerToken, sha256Hex } from './tokens';

const app = new Hono<AuthEnv>();

app.get('/health', (c) => c.json({ ok: true }));

/// Család + gyerek-eszköz létrehozása. Nyílt végpont (első eszköz-regisztráció);
/// családi appnál az URL nem publikus, abuse-védelem tudatosan nincs (spec 5.).
app.post('/families', async (c) => {
  const body = await c.req.json<{ deviceName?: string }>().catch(() => ({}) as { deviceName?: string });
  const familyId = crypto.randomUUID();
  const deviceId = crypto.randomUUID();
  const token = newBearerToken();
  const now = Date.now();

  await c.env.DB.batch([
    c.env.DB.prepare('INSERT INTO families (id, created_at) VALUES (?, ?)').bind(familyId, now),
    c.env.DB
      .prepare(
        'INSERT INTO devices (id, family_id, role, name, token_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)'
      )
      .bind(deviceId, familyId, 'child', body.deviceName ?? '', await sha256Hex(token), now),
  ]);

  return c.json({ familyId, deviceId, token }, 201);
});

app.get('/me', requireDevice, (c) => {
  const device = c.get('device');
  return c.json({
    deviceId: device.id,
    familyId: device.family_id,
    role: device.role,
    name: device.name,
    hasApnsToken: device.apns_token !== null,
  });
});

export default app;
```

- [ ] **Step 4: Futtasd — menjen át**, majd `npx tsc --noEmit`

- [ ] **Step 5: Commit**

```bash
git add backend/src backend/test/families.test.ts
git commit -m "phase 4.2a: family creation + bearer-token auth middleware"
```

---

### Task 4: Párosítás + APNs-token feltöltés (TDD)

**Files:**
- Create: `backend/src/pairing.ts`
- Modify: `backend/src/index.ts`
- Test: `backend/test/pairing.test.ts`

**Interfaces:**
- Consumes: Task 2–3.
- Produces: `POST /pairing-codes → 201 {code, expiresAt}` (child); `POST /pair {code, deviceName?} → 201 {familyId, deviceId, token}`; `PUT /devices/me/apns-token {token} → 204`; `isCodeUsable(row, now): boolean` tiszta függvény.

- [ ] **Step 1: Bukó tesztek**

`backend/test/pairing.test.ts`:

```ts
import { SELF, env } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { isCodeUsable } from '../src/pairing';

async function createFamily(): Promise<string> {
  const res = await SELF.fetch('https://vanda.test/families', { method: 'POST' });
  const { token } = await res.json<{ token: string }>();
  return token;
}

async function createCode(childToken: string): Promise<string> {
  const res = await SELF.fetch('https://vanda.test/pairing-codes', {
    method: 'POST',
    headers: { authorization: `Bearer ${childToken}` },
  });
  const { code } = await res.json<{ code: string }>();
  return code;
}

describe('isCodeUsable', () => {
  const base = { code: '123456', family_id: 'f', expires_at: 1000, used_at: null };

  it('is usable before expiry and unused', () => {
    expect(isCodeUsable(base, 999)).toBe(true);
  });

  it('is not usable after expiry', () => {
    expect(isCodeUsable(base, 1001)).toBe(false);
  });

  it('is not usable when already used', () => {
    expect(isCodeUsable({ ...base, used_at: 500 }, 999)).toBe(false);
  });
});

describe('pairing flow', () => {
  it('issues a six digit code to the child', async () => {
    const childToken = await createFamily();
    const res = await SELF.fetch('https://vanda.test/pairing-codes', {
      method: 'POST',
      headers: { authorization: `Bearer ${childToken}` },
    });
    expect(res.status).toBe(201);
    const body = await res.json<{ code: string; expiresAt: number }>();
    expect(body.code).toMatch(/^\d{6}$/);
    expect(body.expiresAt).toBeGreaterThan(Date.now());
  });

  it('pairs a parent with a valid code, exactly once', async () => {
    const childToken = await createFamily();
    const code = await createCode(childToken);

    const first = await SELF.fetch('https://vanda.test/pair', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ code, deviceName: 'Anya telefonja' }),
    });
    expect(first.status).toBe(201);
    const parent = await first.json<{ token: string }>();

    const me = await SELF.fetch('https://vanda.test/me', {
      headers: { authorization: `Bearer ${parent.token}` },
    });
    expect((await me.json<{ role: string }>()).role).toBe('parent');

    const second = await SELF.fetch('https://vanda.test/pair', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ code }),
    });
    expect(second.status).toBe(410); // már felhasznált
  });

  it('rejects an unknown code', async () => {
    const res = await SELF.fetch('https://vanda.test/pair', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ code: '000000' }),
    });
    expect(res.status).toBe(404);
  });

  it('rejects an expired code', async () => {
    const childToken = await createFamily();
    const code = await createCode(childToken);
    await env.DB.prepare('UPDATE pairing_codes SET expires_at = ? WHERE code = ?')
      .bind(Date.now() - 1000, code)
      .run();

    const res = await SELF.fetch('https://vanda.test/pair', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ code }),
    });
    expect(res.status).toBe(410);
  });

  it('only the child may create pairing codes', async () => {
    const childToken = await createFamily();
    const code = await createCode(childToken);
    const pair = await SELF.fetch('https://vanda.test/pair', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ code }),
    });
    const { token: parentToken } = await pair.json<{ token: string }>();

    const res = await SELF.fetch('https://vanda.test/pairing-codes', {
      method: 'POST',
      headers: { authorization: `Bearer ${parentToken}` },
    });
    expect(res.status).toBe(403);
  });

  it('stores the apns token for the calling device', async () => {
    const childToken = await createFamily();
    const put = await SELF.fetch('https://vanda.test/devices/me/apns-token', {
      method: 'PUT',
      headers: { authorization: `Bearer ${childToken}`, 'content-type': 'application/json' },
      body: JSON.stringify({ token: 'abc123hexdevicetoken' }),
    });
    expect(put.status).toBe(204);

    const me = await SELF.fetch('https://vanda.test/me', {
      headers: { authorization: `Bearer ${childToken}` },
    });
    expect((await me.json<{ hasApnsToken: boolean }>()).hasApnsToken).toBe(true);
  });
});
```

- [ ] **Step 2: Futtasd — bukjon**

- [ ] **Step 3: Implementáció**

`backend/src/pairing.ts`:

```ts
export type PairingCodeRow = {
  code: string;
  family_id: string;
  expires_at: number;
  used_at: number | null;
};

export const PAIRING_CODE_TTL_MS = 10 * 60 * 1000;

export function isCodeUsable(row: PairingCodeRow, now: number): boolean {
  return row.used_at === null && now <= row.expires_at;
}
```

`backend/src/index.ts` — a `GET /me` után, az `export default` elé:

```ts
app.post('/pairing-codes', requireDevice, requireRole('child'), async (c) => {
  const device = c.get('device');
  const code = newPairingCode();
  const expiresAt = Date.now() + PAIRING_CODE_TTL_MS;

  // Kód-ütközésnél (PRIMARY KEY) egyszerűen 500 — 10 perces ablakban egy
  // családnál gyakorlatilag kizárt; a kliens újrapróbálhat.
  await c.env.DB
    .prepare('INSERT INTO pairing_codes (code, family_id, expires_at) VALUES (?, ?, ?)')
    .bind(code, device.family_id, expiresAt)
    .run();

  return c.json({ code, expiresAt }, 201);
});

app.post('/pair', async (c) => {
  const body = await c.req.json<{ code?: string; deviceName?: string }>().catch(() => ({}) as { code?: string });
  if (!body.code) return c.json({ error: 'code required' }, 400);

  const row = await c.env.DB
    .prepare('SELECT * FROM pairing_codes WHERE code = ?')
    .bind(body.code)
    .first<PairingCodeRow>();
  if (!row) return c.json({ error: 'unknown code' }, 404);
  if (!isCodeUsable(row, Date.now())) return c.json({ error: 'code expired or used' }, 410);

  const deviceId = crypto.randomUUID();
  const token = newBearerToken();
  const now = Date.now();

  await c.env.DB.batch([
    c.env.DB.prepare('UPDATE pairing_codes SET used_at = ? WHERE code = ?').bind(now, row.code),
    c.env.DB
      .prepare(
        'INSERT INTO devices (id, family_id, role, name, token_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)'
      )
      .bind(deviceId, row.family_id, 'parent', (body as { deviceName?: string }).deviceName ?? '', await sha256Hex(token), now),
  ]);

  return c.json({ familyId: row.family_id, deviceId, token }, 201);
});

app.put('/devices/me/apns-token', requireDevice, async (c) => {
  const body = await c.req.json<{ token?: string }>().catch(() => ({}) as { token?: string });
  if (!body.token) return c.json({ error: 'token required' }, 400);

  await c.env.DB
    .prepare('UPDATE devices SET apns_token = ? WHERE id = ?')
    .bind(body.token, c.get('device').id)
    .run();

  return c.body(null, 204);
});
```

Az importok bővítése az `index.ts` tetején:

```ts
import { requireDevice, requireRole, type AuthEnv } from './auth';
import { newBearerToken, newPairingCode, sha256Hex } from './tokens';
import { isCodeUsable, PAIRING_CODE_TTL_MS, type PairingCodeRow } from './pairing';
```

- [ ] **Step 4: Futtasd — menjen át**, majd `npx tsc --noEmit`

- [ ] **Step 5: Commit**

```bash
git add backend/src backend/test/pairing.test.ts
git commit -m "phase 4.2a: pairing codes, parent pairing, apns token upload"
```

---

### Task 5: APNs — ES256 JWT + push-küldő + `POST /test-pushes` (TDD)

**Files:**
- Create: `backend/src/apns.ts`
- Modify: `backend/src/index.ts`
- Test: `backend/test/apns.test.ts`

**Interfaces:**
- Consumes: Task 3–4 (auth, devices).
- Produces: `signApnsJwt(privateKeyPem, keyId, teamId, issuedAtSeconds): Promise<string>`; `sendPush(env, apnsToken, payload): Promise<number>` (HTTP-státusz); `POST /test-pushes → {results: [{deviceId, status}]}` (child; minden APNs-tokenes szülő-eszközre).

- [ ] **Step 1: Bukó tesztek**

`backend/test/apns.test.ts`:

```ts
import { SELF, env, fetchMock } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';
import { signApnsJwt } from '../src/apns';

// A vitest.config.ts-beli teszt-privátkulcs párja — kizárólag aláírás-ellenőrzéshez.
const TEST_PUBLIC_KEY_SPKI_B64 =
  'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEtkH3grjDLCHvACLPXjiHX6DvEjNR' +
  'X1e7usSh32I/RmBJRzsqARJzDQBzp02Zc4H6y5nuiB4zijLKTF2kUbxSpg==';

function b64urlDecode(part: string): Uint8Array {
  const b64 = part.replaceAll('-', '+').replaceAll('_', '/');
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

describe('signApnsJwt', () => {
  it('produces a verifiable ES256 JWT with the right claims', async () => {
    const issuedAt = 1_800_000_000;
    const jwt = await signApnsJwt(env.APNS_PRIVATE_KEY, 'TESTKEY99XX', 'TESTTEAM99X', issuedAt);

    const [headerB64, payloadB64, sigB64] = jwt.split('.');
    const header = JSON.parse(new TextDecoder().decode(b64urlDecode(headerB64)));
    const payload = JSON.parse(new TextDecoder().decode(b64urlDecode(payloadB64)));
    expect(header).toEqual({ alg: 'ES256', kid: 'TESTKEY99XX' });
    expect(payload).toEqual({ iss: 'TESTTEAM99X', iat: issuedAt });

    const publicKey = await crypto.subtle.importKey(
      'spki',
      Uint8Array.from(atob(TEST_PUBLIC_KEY_SPKI_B64), (c) => c.charCodeAt(0)),
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['verify']
    );
    const valid = await crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' },
      publicKey,
      b64urlDecode(sigB64),
      new TextEncoder().encode(`${headerB64}.${payloadB64}`)
    );
    expect(valid).toBe(true);
  });
});

describe('POST /test-pushes', () => {
  beforeAll(() => {
    fetchMock.activate();
    fetchMock.disableNetConnect();
  });
  afterEach(() => {
    fetchMock.assertNoPendingInterceptors();
  });

  async function pairedFamily() {
    const fam = await SELF.fetch('https://vanda.test/families', { method: 'POST' });
    const { token: childToken } = await fam.json<{ token: string }>();
    const codeRes = await SELF.fetch('https://vanda.test/pairing-codes', {
      method: 'POST',
      headers: { authorization: `Bearer ${childToken}` },
    });
    const { code } = await codeRes.json<{ code: string }>();
    const pair = await SELF.fetch('https://vanda.test/pair', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ code, deviceName: 'Anya telefonja' }),
    });
    const { token: parentToken } = await pair.json<{ token: string }>();
    return { childToken, parentToken };
  }

  it('pushes to every parent device that has an apns token', async () => {
    const { childToken, parentToken } = await pairedFamily();
    await SELF.fetch('https://vanda.test/devices/me/apns-token', {
      method: 'PUT',
      headers: { authorization: `Bearer ${parentToken}`, 'content-type': 'application/json' },
      body: JSON.stringify({ token: 'parentdevicetoken1' }),
    });

    fetchMock
      .get('https://api.sandbox.push.apple.com')
      .intercept({ method: 'POST', path: '/3/device/parentdevicetoken1' })
      .reply(200, '');

    const res = await SELF.fetch('https://vanda.test/test-pushes', {
      method: 'POST',
      headers: { authorization: `Bearer ${childToken}` },
    });
    expect(res.status).toBe(200);
    const body = await res.json<{ results: { status: number }[] }>();
    expect(body.results).toHaveLength(1);
    expect(body.results[0].status).toBe(200);
  });

  it('reports when no parent device is ready', async () => {
    const { childToken } = await pairedFamily(); // szülő van, de APNs-token nincs
    const res = await SELF.fetch('https://vanda.test/test-pushes', {
      method: 'POST',
      headers: { authorization: `Bearer ${childToken}` },
    });
    expect(res.status).toBe(200);
    expect((await res.json<{ results: unknown[] }>()).results).toHaveLength(0);
  });

  it('is child-only', async () => {
    const { parentToken } = await pairedFamily();
    const res = await SELF.fetch('https://vanda.test/test-pushes', {
      method: 'POST',
      headers: { authorization: `Bearer ${parentToken}` },
    });
    expect(res.status).toBe(403);
  });
});
```

- [ ] **Step 2: Futtasd — bukjon**

- [ ] **Step 3: Implementáció**

`backend/src/apns.ts`:

```ts
/// APNs-küldés közvetlen fetch-csel: ES256 JWT (WebCrypto, zéró függőség) +
/// HTTP/2 POST. FONTOS: lokális `wrangler dev` macOS-en nem tud HTTP/2-t az
/// APNs felé (workerd #4841) — élesben csak deployolt Workerből megy.

function base64urlBytes(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

function base64urlJson(value: unknown): string {
  return base64urlBytes(new TextEncoder().encode(JSON.stringify(value)));
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const der = Uint8Array.from(
    atob(pem.replace(/-----[^-]+-----/g, '').replace(/\s/g, '')),
    (c) => c.charCodeAt(0)
  );
  return crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, [
    'sign',
  ]);
}

export async function signApnsJwt(
  privateKeyPem: string,
  keyId: string,
  teamId: string,
  issuedAtSeconds: number
): Promise<string> {
  const signingInput = `${base64urlJson({ alg: 'ES256', kid: keyId })}.${base64urlJson({
    iss: teamId,
    iat: issuedAtSeconds,
  })}`;
  const key = await importPrivateKey(privateKeyPem);
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput)
  );
  return `${signingInput}.${base64urlBytes(new Uint8Array(signature))}`;
}

export type ApnsAlertPayload = {
  aps: {
    alert: { title: string; body: string };
    sound?: string;
    'interruption-level'?: 'passive' | 'active' | 'time-sensitive' | 'critical';
  };
};

export async function sendPush(env: Env, apnsToken: string, payload: ApnsAlertPayload): Promise<number> {
  const jwt = await signApnsJwt(
    env.APNS_PRIVATE_KEY,
    env.APNS_KEY_ID,
    env.APNS_TEAM_ID,
    Math.floor(Date.now() / 1000)
  );
  const response = await fetch(`${env.APNS_HOST}/3/device/${apnsToken}`, {
    method: 'POST',
    headers: {
      authorization: `bearer ${jwt}`,
      'apns-topic': env.APNS_TOPIC,
      'apns-push-type': 'alert',
      'apns-priority': '10',
    },
    body: JSON.stringify(payload),
  });
  // A hibatörzs rövid JSON (pl. BadDeviceToken) — naplózzuk, nem streameljük.
  if (response.status !== 200) {
    console.log(
      JSON.stringify({ event: 'apns_error', status: response.status, body: await response.text() })
    );
  } else {
    await response.body?.cancel();
  }
  return response.status;
}
```

`backend/src/index.ts` — az `export default` elé:

```ts
app.post('/test-pushes', requireDevice, requireRole('child'), async (c) => {
  const device = c.get('device');
  const parents = await c.env.DB
    .prepare(
      "SELECT id, apns_token FROM devices WHERE family_id = ? AND role = 'parent' AND apns_token IS NOT NULL"
    )
    .bind(device.family_id)
    .all<{ id: string; apns_token: string }>();

  const results: { deviceId: string; status: number }[] = [];
  for (const parent of parents.results) {
    const status = await sendPush(c.env, parent.apns_token, {
      aps: {
        alert: {
          title: 'Próba-jelzés 💛',
          body: `${device.name || 'Vanda készüléke'} össze van kötve veletek.`,
        },
        sound: 'default',
      },
    });
    results.push({ deviceId: parent.id, status });
  }

  console.log(JSON.stringify({ event: 'test_push', family: device.family_id, results }));
  return c.json({ results });
});
```

Import bővítés: `import { sendPush } from './apns';`

- [ ] **Step 4: Futtasd — menjen át**, majd `npx tsc --noEmit`

- [ ] **Step 5: Commit**

```bash
git add backend/src backend/test/apns.test.ts
git commit -m "phase 4.2a: APNs ES256 JWT signer, push sender, test-push endpoint"
```

---

### Task 6: README + deploy-ellenőrzőlista + zárás

**Files:**
- Create: `backend/README.md`
- Modify: `docs/decisions.md` (csak ha implementáció közben tervtől eltérő döntés született)

- [ ] **Step 1: README**

`backend/README.md` tartalma — endpoint-tábla (health, families, me, pairing-codes, pair, apns-token, test-pushes; ki hívhatja, mit ad vissza), lokális fejlesztés (`npm install`, `npm test`, `npm run check`), és a **kézi deploy-lépések Attilának**:

```markdown
## Deploy (kézi lépések, egyszer)

1. `npx wrangler login` — Cloudflare-fiók összekötése (böngészős)
2. `npx wrangler d1 create vanda` — a kapott `database_id`-t írd be a `wrangler.jsonc`-ba
3. `npx wrangler d1 migrations apply vanda --remote`
4. Apple Developer portál → Keys → új kulcs APNs-szel → töltsd le a `.p8`-at,
   jegyezd fel a Key ID-t; a Team ID a Membership oldalon
5. Secretek:
   - `npx wrangler secret put APNS_TEAM_ID`
   - `npx wrangler secret put APNS_KEY_ID`
   - `npx wrangler secret put APNS_PRIVATE_KEY`  ← a .p8 fájl teljes PEM-tartalma
6. `npx wrangler deploy` — jegyezd fel a workers.dev URL-t (a 4.2b iOS-kliens ezt kapja)
7. Xcode: VandaApp target → Signing & Capabilities → + Push Notifications
   (a Time Sensitive a 4.3-ban jön)

**APNS_HOST:** Xcode-ról telepített (development) buildhez a sandbox host kell
(ez az alapértelmezés a wrangler.jsonc-ban). TestFlight/App Store buildhez:
`https://api.push.apple.com`.

**Fontos:** az APNs-hívás lokális `wrangler dev`-ből macOS-en nem működik
(HTTP/2-korlát, workerd #4841) — a push-próba csak deployolt Workerrel megy.
```

- [ ] **Step 2: Teljes ellenőrzés**

```bash
cd backend
npx tsc --noEmit
npx vitest run
```

Expected: minden teszt PASS, kimenet pristine. Az iOS-teszteket ez a terv nem érinti (a `VandaApp/` könyvtárhoz nem nyúlt).

- [ ] **Step 3: Commit**

```bash
git add backend/README.md
git commit -m "phase 4.2a: backend README with manual deploy checklist"
```

---

## Self-review jegyzet (a terv írásakor lefutott)

- **Design-lefedettség (1. szakasz, 4.2-re eső rész):** család-létrehozás, 6 jegyű kód (10 perc TTL, egyszer használatos), parent-token, APNs-token feltöltés, teszt-push a szülő-eszközökre, token-hash tárolás — mind fedve. PanicEvent/megosztás/escrow/cron szándékosan nincs (4.3–4.5).
- **Best-practice ellenőrzés (2026-07-10):** wrangler.jsonc + compatibility_date + nodejs_compat + observability; crypto.getRandomValues; secretek wrangler secret-tel; nincs floating promise (minden fetch/DB-hívás await-elt); nincs modul-szintű állapot (a JWT-t push-onként írjuk alá — egy családnál elhanyagolható költség, cache később).
- **Típus-konzisztencia:** `AuthEnv` a Hono-generikus mindenhol; `PairingCodeRow.used_at: number | null`; a fixture privát kulcs (vitest.config) és a tesztbeli publikus kulcs összetartozó pár (2026-07-10-én generált eldobható kulcs, nem titok).
- **Ismert kockázat:** a `cloudflare:test` `fetchMock` és `readD1Migrations` API-k pontos viselkedése a telepített pool-workers verziótól függhet — az 1. task smoke tesztje ezt azonnal kibuktatja; ha eltér, az implementáló a hivatalos docs szerint igazít (a tesztek szándéka a kötelező, nem a betűje).
