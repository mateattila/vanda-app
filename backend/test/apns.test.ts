import { SELF, env } from 'cloudflare:test';
import { afterEach, describe, expect, it, vi } from 'vitest';
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
  // @cloudflare/vitest-pool-workers@0.18.x removed the undici-backed
  // `fetchMock` export from 'cloudflare:test' (see the Vitest 3→4 migration
  // guide: "Mock globalThis.fetch directly or use ecosystem libraries such
  // as MSW"). We follow the project's own request-mocking recipe
  // (workers-sdk fixtures/vitest-pool-workers-examples/request-mocking) and
  // spy on globalThis.fetch directly, throwing for any unmatched request so
  // no real network call can slip through.
  afterEach(() => {
    vi.restoreAllMocks();
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

    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init) => {
      const request = new Request(input as RequestInfo, init);
      const url = new URL(request.url);
      if (
        request.method === 'POST' &&
        url.origin === 'https://api.sandbox.push.apple.com' &&
        url.pathname === '/3/device/parentdevicetoken1'
      ) {
        return new Response('', { status: 200 });
      }
      throw new Error(`unexpected fetch in test: ${request.method} ${url.toString()}`);
    });

    const res = await SELF.fetch('https://vanda.test/test-pushes', {
      method: 'POST',
      headers: { authorization: `Bearer ${childToken}` },
    });
    expect(res.status).toBe(200);
    const body = await res.json<{ results: { status: number }[] }>();
    expect(body.results).toHaveLength(1);
    expect(body.results[0].status).toBe(200);
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });

  it('reports the APNs HTTP status when the push is rejected (non-200 response)', async () => {
    const { childToken, parentToken } = await pairedFamily();
    await SELF.fetch('https://vanda.test/devices/me/apns-token', {
      method: 'PUT',
      headers: { authorization: `Bearer ${parentToken}`, 'content-type': 'application/json' },
      body: JSON.stringify({ token: 'parentdevicetoken1' }),
    });

    vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init) => {
      const request = new Request(input as RequestInfo, init);
      const url = new URL(request.url);
      if (
        request.method === 'POST' &&
        url.origin === 'https://api.sandbox.push.apple.com' &&
        url.pathname === '/3/device/parentdevicetoken1'
      ) {
        return new Response(JSON.stringify({ reason: 'BadDeviceToken' }), { status: 400 });
      }
      throw new Error(`unexpected fetch in test: ${request.method} ${url.toString()}`);
    });

    const res = await SELF.fetch('https://vanda.test/test-pushes', {
      method: 'POST',
      headers: { authorization: `Bearer ${childToken}` },
    });
    expect(res.status).toBe(200);
    const body = await res.json<{ results: { deviceId: string; status: number }[] }>();
    expect(body.results).toHaveLength(1);
    expect(body.results[0].status).toBe(400);
  });

  it('keeps pushing to the remaining parents when one push fails at transport level', async () => {
    const { childToken, parentToken } = await pairedFamily();
    // Második szülő ugyanabba a családba (új kód kell — a régi már felhasznált).
    const codeRes = await SELF.fetch('https://vanda.test/pairing-codes', {
      method: 'POST',
      headers: { authorization: `Bearer ${childToken}` },
    });
    const { code } = await codeRes.json<{ code: string }>();
    const pair2 = await SELF.fetch('https://vanda.test/pair', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ code, deviceName: 'Apa telefonja' }),
    });
    const { token: parent2Token } = await pair2.json<{ token: string }>();

    await SELF.fetch('https://vanda.test/devices/me/apns-token', {
      method: 'PUT',
      headers: { authorization: `Bearer ${parentToken}`, 'content-type': 'application/json' },
      body: JSON.stringify({ token: 'parentdevicetoken1' }),
    });
    await SELF.fetch('https://vanda.test/devices/me/apns-token', {
      method: 'PUT',
      headers: { authorization: `Bearer ${parent2Token}`, 'content-type': 'application/json' },
      body: JSON.stringify({ token: 'parentdevicetoken2' }),
    });

    vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init) => {
      const request = new Request(input as RequestInfo, init);
      const url = new URL(request.url);
      if (url.pathname === '/3/device/parentdevicetoken1') {
        throw new TypeError('network connection lost'); // transzport-hiba, nincs HTTP-státusz
      }
      if (
        request.method === 'POST' &&
        url.origin === 'https://api.sandbox.push.apple.com' &&
        url.pathname === '/3/device/parentdevicetoken2'
      ) {
        return new Response('', { status: 200 });
      }
      throw new Error(`unexpected fetch in test: ${request.method} ${url.toString()}`);
    });

    const res = await SELF.fetch('https://vanda.test/test-pushes', {
      method: 'POST',
      headers: { authorization: `Bearer ${childToken}` },
    });
    expect(res.status).toBe(200);
    const body = await res.json<{ results: { deviceId: string; status: number }[] }>();
    expect(body.results.map((r) => r.status)).toEqual([0, 200]);
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
