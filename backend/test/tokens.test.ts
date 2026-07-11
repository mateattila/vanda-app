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
