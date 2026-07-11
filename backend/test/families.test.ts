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
