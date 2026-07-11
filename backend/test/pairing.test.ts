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
