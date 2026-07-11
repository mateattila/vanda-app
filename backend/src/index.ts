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
