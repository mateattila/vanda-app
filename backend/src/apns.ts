/// APNs-küldés közvetlen fetch-csel: ES256 JWT (WebCrypto, zéró függőség) +
/// HTTP/2 POST. FONTOS: lokális `wrangler dev` macOS-en nem tud HTTP/2-t az
/// APNs felé (workerd #4841) — élesben csak deployolt Workerből megy.

function base64urlBytes(bytes: Uint8Array): string {
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

function base64urlJson(value: unknown): string {
  return base64urlBytes(new TextEncoder().encode(JSON.stringify(value)));
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const der = Uint8Array.from(
    atob(pem.replace(/-----[^-]+-----/g, '').replace(/\s/g, '')),
    (c) => c.charCodeAt(0)
  );
  return crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, [
    'sign',
  ]);
}

export async function signApnsJwt(
  privateKeyPem: string,
  keyId: string,
  teamId: string,
  issuedAtSeconds: number
): Promise<string> {
  const signingInput = `${base64urlJson({ alg: 'ES256', kid: keyId })}.${base64urlJson({
    iss: teamId,
    iat: issuedAtSeconds,
  })}`;
  const key = await importPrivateKey(privateKeyPem);
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput)
  );
  return `${signingInput}.${base64urlBytes(new Uint8Array(signature))}`;
}

export type ApnsAlertPayload = {
  aps: {
    alert: { title: string; body: string };
    sound?: string;
    'interruption-level'?: 'passive' | 'active' | 'time-sensitive' | 'critical';
  };
};

export async function sendPush(env: Env, apnsToken: string, payload: ApnsAlertPayload): Promise<number> {
  const jwt = await signApnsJwt(
    env.APNS_PRIVATE_KEY,
    env.APNS_KEY_ID,
    env.APNS_TEAM_ID,
    Math.floor(Date.now() / 1000)
  );
  const response = await fetch(`${env.APNS_HOST}/3/device/${apnsToken}`, {
    method: 'POST',
    headers: {
      authorization: `bearer ${jwt}`,
      'apns-topic': env.APNS_TOPIC,
      'apns-push-type': 'alert',
      'apns-priority': '10',
    },
    body: JSON.stringify(payload),
  });
  // A hibatörzs rövid JSON (pl. BadDeviceToken) — naplózzuk, nem streameljük.
  if (response.status !== 200) {
    console.log(
      JSON.stringify({ event: 'apns_error', status: response.status, body: await response.text() })
    );
  } else {
    await response.body?.cancel();
  }
  return response.status;
}
