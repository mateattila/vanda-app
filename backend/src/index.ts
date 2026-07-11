import { Hono } from 'hono';
import { requireDevice, requireRole, type AuthEnv } from './auth';
import { newBearerToken, newPairingCode, sha256Hex } from './tokens';
import { isCodeUsable, PAIRING_CODE_TTL_MS, type PairingCodeRow } from './pairing';

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

  // Gyors út: ismeretlen vs. lejárt/felhasznált kód megkülönböztetése (404/410).
  const row = await c.env.DB
    .prepare('SELECT * FROM pairing_codes WHERE code = ?')
    .bind(body.code)
    .first<PairingCodeRow>();
  if (!row) return c.json({ error: 'unknown code' }, 404);
  if (!isCodeUsable(row, Date.now())) return c.json({ error: 'code expired or used' }, 410);

  const deviceId = crypto.randomUUID();
  const token = newBearerToken();
  const now = Date.now();

  // Autoritatív kapu: feltételes claim — két egyidejű beváltásból csak az
  // egyik érinthet sort (TOCTOU-védelem a fenti SELECT + isCodeUsable után).
  const claim = await c.env.DB
    .prepare(
      'UPDATE pairing_codes SET used_at = ? WHERE code = ? AND used_at IS NULL AND expires_at >= ?'
    )
    .bind(now, row.code, now)
    .run();
  if (claim.meta.changes !== 1) return c.json({ error: 'code expired or used' }, 410);

  // Ha az INSERT itt elhasal, a kód "elég" — a gyerek a 10 perces TTL-en
  // belül egyszerűen új kódot kér. (Tudatos trade-off.)
  await c.env.DB
    .prepare(
      'INSERT INTO devices (id, family_id, role, name, token_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)'
    )
    .bind(deviceId, row.family_id, 'parent', (body as { deviceName?: string }).deviceName ?? '', await sha256Hex(token), now)
    .run();

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

export default app;
