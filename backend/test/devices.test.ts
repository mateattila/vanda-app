import { SELF } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';

async function createFamily(): Promise<string> {
  const res = await SELF.fetch('https://vanda.test/families', { method: 'POST' });
  const { token } = await res.json<{ token: string }>();
  return token;
}

async function pairParent(childToken: string): Promise<string> {
  const codeRes = await SELF.fetch('https://vanda.test/pairing-codes', {
    method: 'POST',
    headers: { authorization: `Bearer ${childToken}`, 'content-type': 'application/json' },
    body: JSON.stringify({}),
  });
  const { code } = await codeRes.json<{ code: string }>();
  const pairRes = await SELF.fetch('https://vanda.test/pair', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ code, deviceName: 'Anya telefonja' }),
  });
  const { token } = await pairRes.json<{ token: string }>();
  return token;
}

describe('DELETE /devices/me', () => {
  it('requires authentication', async () => {
    const res = await SELF.fetch('https://vanda.test/devices/me', { method: 'DELETE' });
    expect(res.status).toBe(401);
  });

  it('removes the device and invalidates its token', async () => {
    const childToken = await createFamily();
    const parentToken = await pairParent(childToken);

    const del = await SELF.fetch('https://vanda.test/devices/me', {
      method: 'DELETE',
      headers: { authorization: `Bearer ${parentToken}` },
    });
    expect(del.status).toBe(204);

    const me = await SELF.fetch('https://vanda.test/me', {
      headers: { authorization: `Bearer ${parentToken}` },
    });
    expect(me.status).toBe(401);
  });

  it('drops the removed parent from the test-push recipients', async () => {
    const childToken = await createFamily();
    const parentToken = await pairParent(childToken);

    await SELF.fetch('https://vanda.test/devices/me/apns-token', {
      method: 'PUT',
      headers: { authorization: `Bearer ${parentToken}`, 'content-type': 'application/json' },
      body: JSON.stringify({ token: 'a'.repeat(64) }),
    });
    await SELF.fetch('https://vanda.test/devices/me', {
      method: 'DELETE',
      headers: { authorization: `Bearer ${parentToken}` },
    });

    const push = await SELF.fetch('https://vanda.test/test-pushes', {
      method: 'POST',
      headers: { authorization: `Bearer ${childToken}` },
    });
    expect(push.status).toBe(200);
    const body = await push.json<{ results: unknown[] }>();
    expect(body.results).toHaveLength(0);
  });
});
