import { SELF, env } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { isCodeUsable } from '../src/pairing';

async function createFamily(): Promise<string> {
  const res = await SELF.fetch('https://vanda.test/families', { method: 'POST' });
  const { token } = await res.json<{ token: string }>();
  return token;
}

async function createCode(childToken: string, role?: 'parent' | 'child'): Promise<string> {
  const res = await SELF.fetch('https://vanda.test/pairing-codes', {
    method: 'POST',
    headers: { authorization: `Bearer ${childToken}`, 'content-type': 'application/json' },
    body: JSON.stringify(role ? { role } : {}),
  });
  const { code } = await res.json<{ code: string }>();
  return code;
}

describe('isCodeUsable', () => {
  const base = { code: '123456', family_id: 'f', expires_at: 1000, used_at: null, role: 'parent' as const };

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

  it('rejects a code already claimed by a concurrent redemption and creates no device', async () => {
    const childToken = await createFamily();
    const code = await createCode(childToken);
    const me = await SELF.fetch('https://vanda.test/me', {
      headers: { authorization: `Bearer ${childToken}` },
    });
    const { familyId } = await me.json<{ familyId: string }>();

    // Egy "versenytárs" kérés már lefoglalta a kódot — közvetlen D1-frissítéssel
    // szimuláljuk, mert vitest-pool-workers alatt valódi párhuzamos futás nincs.
    await env.DB.prepare('UPDATE pairing_codes SET used_at = ? WHERE code = ?')
      .bind(Date.now(), code)
      .run();

    const res = await SELF.fetch('https://vanda.test/pair', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ code }),
    });
    expect(res.status).toBe(410);

    const parents = await env.DB
      .prepare("SELECT COUNT(*) AS n FROM devices WHERE family_id = ? AND role = 'parent'")
      .bind(familyId)
      .first<{ n: number }>();
    expect(parents?.n).toBe(0);
  });

  it('burns the code atomically on pairing: the conditional claim finds nothing to re-claim', async () => {
    const childToken = await createFamily();
    const code = await createCode(childToken);

    const pair = await SELF.fetch('https://vanda.test/pair', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ code }),
    });
    expect(pair.status).toBe(201);

    // Sikeres /pair után a used_at ki van töltve, így a handlerben használt
    // feltételes claim (azonos WHERE) 0 sort érint — a guard zár.
    const now = Date.now();
    const claim = await env.DB
      .prepare(
        'UPDATE pairing_codes SET used_at = ? WHERE code = ? AND used_at IS NULL AND expires_at >= ?'
      )
      .bind(now, code, now)
      .run();
    expect(claim.meta.changes).toBe(0);

    const row = await env.DB
      .prepare('SELECT used_at FROM pairing_codes WHERE code = ?')
      .bind(code)
      .first<{ used_at: number | null }>();
    expect(row?.used_at).not.toBeNull();
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

describe('pairing code roles', () => {
  async function redeem(code: string, deviceName: string) {
    return SELF.fetch('https://vanda.test/pair', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ code, deviceName }),
    });
  }

  async function roleOf(token: string): Promise<string> {
    const res = await SELF.fetch('https://vanda.test/me', {
      headers: { authorization: `Bearer ${token}` },
    });
    return (await res.json<{ role: string }>()).role;
  }

  it('defaults to a parent device when no role is given', async () => {
    const childToken = await createFamily();
    const code = await createCode(childToken);
    const res = await redeem(code, 'Anya telefonja');
    expect(res.status).toBe(201);
    const body = await res.json<{ token: string; role: string }>();
    expect(body.role).toBe('parent');
    expect(await roleOf(body.token)).toBe('parent');
  });

  it('mints a child device from a child-role code', async () => {
    const childToken = await createFamily();
    const code = await createCode(childToken, 'child');
    const res = await redeem(code, 'Vanda iPadje');
    expect(res.status).toBe(201);
    const body = await res.json<{ token: string; role: string }>();
    expect(body.role).toBe('child');
    expect(await roleOf(body.token)).toBe('child');
  });

  it('lets a paired child device issue codes of its own', async () => {
    const childToken = await createFamily();
    const iPadToken = await redeem(await createCode(childToken, 'child'), 'Vanda iPadje')
      .then((r) => r.json<{ token: string }>())
      .then((b) => b.token);

    const res = await SELF.fetch('https://vanda.test/pairing-codes', {
      method: 'POST',
      headers: { authorization: `Bearer ${iPadToken}`, 'content-type': 'application/json' },
      body: JSON.stringify({ role: 'parent' }),
    });
    expect(res.status).toBe(201);
  });

  it('rejects an unknown role with 400', async () => {
    const childToken = await createFamily();
    const res = await SELF.fetch('https://vanda.test/pairing-codes', {
      method: 'POST',
      headers: { authorization: `Bearer ${childToken}`, 'content-type': 'application/json' },
      body: JSON.stringify({ role: 'admin' }),
    });
    expect(res.status).toBe(400);
  });
});
