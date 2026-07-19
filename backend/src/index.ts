import { Hono } from 'hono';
import { requireDevice, requireRole, type AuthEnv } from './auth';
import { newBearerToken, newPairingCode, sha256Hex } from './tokens';
import { isCodeUsable, isPairingRole, PAIRING_CODE_TTL_MS, type PairingCodeRow } from './pairing';
import { sendPush } from './apns';

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
  const body = await c.req.json<{ role?: unknown }>().catch(() => ({}) as { role?: unknown });
  // Alapértelmezés a szülő-párosítás; a 'child' szerep Vanda második eszközét
  // (iPad) engedi be ugyanabba a családba, saját tokennel és APNs-tokennel.
  const role = body.role === undefined ? 'parent' : body.role;
  if (!isPairingRole(role)) return c.json({ error: 'invalid role' }, 400);

  const code = newPairingCode();
  const expiresAt = Date.now() + PAIRING_CODE_TTL_MS;

  // Kód-ütközésnél (PRIMARY KEY) egyszerűen 500 — 10 perces ablakban egy
  // családnál gyakorlatilag kizárt; a kliens újrapróbálhat.
  await c.env.DB
    .prepare('INSERT INTO pairing_codes (code, family_id, expires_at, role) VALUES (?, ?, ?, ?)')
    .bind(code, device.family_id, expiresAt, role)
    .run();

  return c.json({ code, expiresAt, role }, 201);
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
    .bind(deviceId, row.family_id, row.role, (body as { deviceName?: string }).deviceName ?? '', await sha256Hex(token), now)
    .run();

  return c.json({ familyId: row.family_id, deviceId, token, role: row.role }, 201);
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

/// Eszköz-leválasztás. Csak helyi (Keychain-) törlés esetén árva sor maradna
/// élő APNs-tokennel, és a teszt-push (4.3-ban a riasztás) egy nem létező
/// készüléknek próbálna küldeni — a szellem-címzett a kézbesítési
/// megbízhatóság ellen dolgozna.
app.delete('/devices/me', requireDevice, async (c) => {
  await c.env.DB.prepare('DELETE FROM devices WHERE id = ?').bind(c.get('device').id).run();
  return c.body(null, 204);
});

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
    // Transzport-hiba (DNS/timeout/reset) egy eszköznél nem szakíthatja meg a
    // ciklust — a többi szülőnek akkor is mennie kell a push. status: 0 jelzi,
    // hogy HTTP-státusz sem született. (4.3-ban ez lesz a pánik-push ciklusa.)
    let status: number;
    try {
      status = await sendPush(c.env, parent.apns_token, {
        aps: {
          alert: {
            title: 'Próba-jelzés 💛',
            body: `${device.name || 'Vanda készüléke'} össze van kötve veletek.`,
          },
          sound: 'default',
        },
      });
    } catch (error) {
      status = 0;
      console.log(
        JSON.stringify({
          event: 'apns_transport_error',
          deviceId: parent.id,
          message: error instanceof Error ? error.message : String(error),
        })
      );
    }
    results.push({ deviceId: parent.id, status });
  }

  console.log(JSON.stringify({ event: 'test_push', family: device.family_id, results }));
  return c.json({ results });
});

export default app;
