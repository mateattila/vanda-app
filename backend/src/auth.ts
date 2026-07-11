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
