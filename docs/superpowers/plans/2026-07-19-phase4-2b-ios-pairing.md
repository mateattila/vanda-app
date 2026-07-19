# 4.2b — iOS párosítás, push-regisztráció, teszt-push: implementációs terv

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A 4.2a-ban elkészült backend bekötése az iOS-appba: család-párosítás 6 jegyű kóddal (szülő és második gyerek-eszköz), APNs device-token feltöltés, és eszközönként visszajelző teszt-push.

**Architecture:** Öt új típus a `Services/Backend/` alatt, egy-egy tiszta felelősséggel: `BackendConfig` (hoszt az xcconfigból), `DeviceCredentialStore` (Keychain, eszköz-lokális), `BackendClient` (async HTTP, injektálható `URLSession`), `PushRegistrar` (+ app delegate, várakozó-token logikával), `FamilyLinkModel` (`@Observable` állapotgép, amit a gyerek- és a szülő-felület egyaránt fogyaszt). A backend két apró bővítést kap: szerep-hordozó párosító kód és eszköz-leválasztás.

**Tech Stack:** Swift 5 / SwiftUI / Swift Testing (`VandaAppTests`), Keychain (Security framework), `URLProtocol`-alapú teszt-stub; backend oldalon TypeScript + Hono + D1 + vitest (`@cloudflare/vitest-pool-workers`).

**Spec:** `docs/superpowers/specs/2026-07-19-phase4-2b-ios-pairing-design.md`

## Global Constraints

- **Fázis-fegyelem:** kizárólag párosítás + push-regisztráció + teszt-push. Panik-riasztás (4.3), megosztási számok (4.4), escrow (4.5) nem kerül bele — még „ha már itt vagyunk" alapon sem.
- **iOS build minden lépés végén hibátlanul fusson:**
  ```sh
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  xcodebuild -project VandaApp/VandaApp.xcodeproj -scheme VandaApp \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
  ```
- **iOS tesztek futtatása** (ugyanez `test` alparanccsal):
  ```sh
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  xcodebuild -project VandaApp/VandaApp.xcodeproj -scheme VandaApp \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
  ```
- **Backend ellenőrzés:** `cd backend && npm test && npm run check && npm run check:test` — mind zöld.
- **UI kizárólag `Theme` tokenekből** (színek, fontok, radiusok): nyers hex/pt érték nem szóródhat szét a view-kban.
- **Hangnem:** kedves, játékos, tegező magyar. Nincs streak, nincs bűntudat-mechanika.
- **Nincs új third-party függőség** sem iOS-, sem backend-oldalon.
- **Commit-üzenet stílus:** `phase 4.2b: <rövid angol összefoglaló>`.
- **Az Xcode-projekt fájl-szinkronizált** (`PBXFileSystemSynchronizedRootGroup`): új Swift fájlok a `VandaApp/VandaApp/` illetve `VandaApp/VandaAppTests/` mappában **automatikusan** a targetbe kerülnek, nem kell `project.pbxproj`-t szerkeszteni. Egyetlen kivétel a 2. feladat xcconfig-bekötése.
- **Bundle ID, signing, iCloud/CloudKit capability változatlan** — ezekhez nem nyúlunk.

---

## Áttekintés

| # | Feladat | Deliverable |
|---|---|---|
| 1 | Backend: szerep-hordozó kód + eszköz-törlés | Migráció, 2 endpoint-változás, 1 új endpoint, vitest zöld |
| 2 | xcconfig + `BackendConfig` + `DeviceCredentialStore` | Konfigurált hoszt + Keychain-tároló, tesztekkel |
| 3 | `BackendClient` | Teljes API-kliens típusos hibákkal, `URLProtocol`-tesztekkel |
| 4 | App delegate + `PushRegistrar` | APNs-token átvétel és feltöltés, várakozó-token logikával |
| 5 | `FamilyLinkModel` | Párosítási állapotgép, tesztekkel |
| 6 | Vanda Család képernyője | Létrehozás, csatlakozás, kód-lap, eszköznév |
| 7 | Szülő mód párosítás + engedélykérés | Kódbevitel, notification-engedély két úton, leválasztás |
| 8 | Teszt-push gomb | Eszközönkénti visszajelzés |

---

### Task 1: Backend — szerep-hordozó párosító kód és eszköz-leválasztás

**Files:**
- Create: `backend/migrations/0002_pairing_code_roles.sql`
- Modify: `backend/src/pairing.ts`
- Modify: `backend/src/index.ts` (`/pairing-codes`, `/pair` handler; új `DELETE /devices/me`)
- Modify: `backend/test/pairing.test.ts`
- Create: `backend/test/devices.test.ts`
- Modify: `backend/README.md` (endpoint-tábla)

**Interfaces:**
- Consumes: a meglévő `requireDevice`, `requireRole`, `newBearerToken`, `sha256Hex`, `isCodeUsable`, `PAIRING_CODE_TTL_MS`.
- Produces: `POST /pairing-codes` opcionális `{ role: "parent" | "child" }` kéréstestet fogad; `POST /pair` válasza kiegészül `role` mezővel (`{ familyId, deviceId, token, role }`); új `DELETE /devices/me` → 204. A 3. feladat iOS-kliense ezekre az alakokra épül.

- [ ] **Step 1: Írd meg a bukó teszteket**

`backend/test/pairing.test.ts` — a fájl tetején lévő `createCode` segédfüggvényt cseréld le erre (szerep-paramétert kap), majd told hozzá az új `describe` blokkot a fájl végére:

```ts
async function createCode(childToken: string, role?: 'parent' | 'child'): Promise<string> {
  const res = await SELF.fetch('https://vanda.test/pairing-codes', {
    method: 'POST',
    headers: { authorization: `Bearer ${childToken}`, 'content-type': 'application/json' },
    body: JSON.stringify(role ? { role } : {}),
  });
  const { code } = await res.json<{ code: string }>();
  return code;
}
```

```ts
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
```

`backend/test/devices.test.ts` (új fájl):

```ts
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

    await SELF.fetch('https://vanda.test/devices/me', {
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
```

Figyelem: a harmadik teszt APNs-tokent tölt fel, majd törli az eszközt — így a `/test-pushes` nulla címzettet talál, és **nem hív APNs-t**, tehát nem kell mockolni.

Az APNs-token feltöltés útvonala `PUT /devices/me/apns-token`; a fenti tesztben szándékosan a teljes útvonalat írd ki:

```ts
    await SELF.fetch('https://vanda.test/devices/me/apns-token', {
```

(A `PUT /devices/me` sor elgépelés lenne — az `apns-token` szegmens kötelező.)

- [ ] **Step 2: Futtasd a teszteket, győződj meg róla, hogy buknak**

Run: `cd backend && npm test`
Expected: FAIL — a `pairing code roles` blokk `role: undefined`-ot lát a `/pair` válaszában, a `devices.test.ts` pedig 404-et kap a `DELETE /devices/me`-re.

- [ ] **Step 3: Migráció**

Create `backend/migrations/0002_pairing_code_roles.sql`:

```sql
-- A párosító kód hordozza, milyen szerepű eszközt hoz létre a beváltása.
-- A DEFAULT 'parent' miatt a meglévő sorok viselkedése változatlan.
ALTER TABLE pairing_codes ADD COLUMN role TEXT NOT NULL DEFAULT 'parent';
```

- [ ] **Step 4: `pairing.ts` — sor-típus és szerep-ellenőrzés**

Modify `backend/src/pairing.ts`:

```ts
export type PairingRole = 'parent' | 'child';

export type PairingCodeRow = {
  code: string;
  family_id: string;
  expires_at: number;
  used_at: number | null;
  role: PairingRole;
};

export const PAIRING_CODE_TTL_MS = 10 * 60 * 1000;

export function isCodeUsable(row: PairingCodeRow, now: number): boolean {
  return row.used_at === null && now <= row.expires_at;
}

export function isPairingRole(value: unknown): value is PairingRole {
  return value === 'parent' || value === 'child';
}
```

A meglévő `isCodeUsable` unit tesztek `base` objektuma bővítendő `role: 'parent'` mezővel, különben a TypeScript hibát jelez — `backend/test/pairing.test.ts`:

```ts
  const base = { code: '123456', family_id: 'f', expires_at: 1000, used_at: null, role: 'parent' as const };
```

- [ ] **Step 5: `/pairing-codes` — szerep fogadása**

Modify `backend/src/index.ts` — az importot egészítsd ki, majd cseréld a handlert:

```ts
import { isCodeUsable, isPairingRole, PAIRING_CODE_TTL_MS, type PairingCodeRow } from './pairing';
```

```ts
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
```

- [ ] **Step 6: `/pair` — a kód szerepe szerinti eszköz**

Modify `backend/src/index.ts` — a `/pair` handlerben az `INSERT` `'parent'` literálját cseréld `row.role`-ra, és a válasz kapjon `role` mezőt:

```ts
  await c.env.DB
    .prepare(
      'INSERT INTO devices (id, family_id, role, name, token_hash, created_at) VALUES (?, ?, ?, ?, ?, ?)'
    )
    .bind(deviceId, row.family_id, row.role, (body as { deviceName?: string }).deviceName ?? '', await sha256Hex(token), now)
    .run();

  return c.json({ familyId: row.family_id, deviceId, token, role: row.role }, 201);
```

- [ ] **Step 7: `DELETE /devices/me`**

Modify `backend/src/index.ts` — a `PUT /devices/me/apns-token` handler alá:

```ts
/// Eszköz-leválasztás. Csak helyi (Keychain-) törlés esetén árva sor maradna
/// élő APNs-tokennel, és a teszt-push (4.3-ban a riasztás) egy nem létező
/// készüléknek próbálna küldeni — a szellem-címzett a kézbesítési
/// megbízhatóság ellen dolgozna.
app.delete('/devices/me', requireDevice, async (c) => {
  await c.env.DB.prepare('DELETE FROM devices WHERE id = ?').bind(c.get('device').id).run();
  return c.body(null, 204);
});
```

- [ ] **Step 8: Futtasd a teszteket és a típus-ellenőrzést**

Run: `cd backend && npm test && npm run check && npm run check:test`
Expected: PASS — a korábbi 26 teszt plusz az új 7 (4 szerep + 3 leválasztás) zöld, tsc mindkét configgal tiszta.

- [ ] **Step 9: README endpoint-tábla frissítése**

Modify `backend/README.md` — az endpoint-táblázatba két sor:

```markdown
| `/devices/me` | DELETE | Bármelyik eszköz | 204 No Content — leválasztás a családról |
```

és a `/pairing-codes` sor leírását egészítsd ki: `— 6 jegyű, 10 perc TTL; opcionális `role` (`parent` alapértelmezés | `child` a második gyerek-eszközhöz)`.

- [ ] **Step 10: Commit**

```bash
git add backend/migrations/0002_pairing_code_roles.sql backend/src/pairing.ts backend/src/index.ts backend/test/pairing.test.ts backend/test/devices.test.ts backend/README.md
git commit -m "phase 4.2b: role-carrying pairing codes and device unlink endpoint"
```

---

### Task 2: xcconfig, `BackendConfig`, `DeviceCredentialStore`

**Files:**
- Create: `VandaApp/Config/Backend.xcconfig`
- Modify: `VandaApp/VandaApp.xcodeproj/project.pbxproj` (fájl-referencia + `baseConfigurationReference` a projekt-szintű Debug/Release configokon)
- Modify: `VandaApp/VandaApp/Info.plist`
- Create: `VandaApp/VandaApp/Services/Backend/BackendConfig.swift`
- Create: `VandaApp/VandaApp/Services/Backend/DeviceCredentials.swift`
- Create: `VandaApp/VandaApp/Services/Backend/DeviceCredentialStore.swift`
- Modify: `VandaApp/VandaApp/App/RootView.swift` (`AppRole` legyen `Codable`)
- Test: `VandaApp/VandaAppTests/BackendCredentialTests.swift`

**Interfaces:**
- Consumes: `AppRole` (`RootView.swift`, `String` rawValue `child`/`parent`).
- Produces: `BackendConfig.baseURL: URL?`, `BackendConfig.isConfigured: Bool`; `DeviceCredentials` (`familyId`, `deviceId`, `token`, `role: AppRole`, `deviceName`); `DeviceCredentialStoring` protokoll `load()` / `save(_:)` / `clear()` metódusokkal, `KeychainDeviceCredentialStore` és `InMemoryDeviceCredentialStore` implementációkkal. A 3–8. feladat ezekre épül.

- [ ] **Step 1: Írd meg a bukó tesztet**

Create `VandaApp/VandaAppTests/BackendCredentialTests.swift`:

```swift
//
//  BackendCredentialTests.swift
//  VandaAppTests
//
//  A backend-hitelesítés tárolójának és a hoszt-konfigurációnak a tesztjei (4.2b).
//

import Foundation
import Testing
@testable import VandaApp

struct DeviceCredentialStoreTests {

    private func sample(role: AppRole = .child) -> DeviceCredentials {
        DeviceCredentials(
            familyId: "fam-1",
            deviceId: "dev-1",
            token: "titkos-token",
            role: role,
            deviceName: "Vanda telefonja"
        )
    }

    @Test func emptyStoreLoadsNothing() {
        let store = InMemoryDeviceCredentialStore()
        #expect(store.load() == nil)
    }

    @Test func savedCredentialsComeBackUnchanged() {
        let store = InMemoryDeviceCredentialStore()
        store.save(sample())
        #expect(store.load() == sample())
    }

    @Test func savingTwiceKeepsTheNewerValue() {
        let store = InMemoryDeviceCredentialStore()
        store.save(sample())
        store.save(sample(role: .parent))
        #expect(store.load()?.role == .parent)
    }

    @Test func clearRemovesEverything() {
        let store = InMemoryDeviceCredentialStore()
        store.save(sample())
        store.clear()
        #expect(store.load() == nil)
    }

    @Test func credentialsSurviveJSONRoundTrip() throws {
        let data = try JSONEncoder().encode(sample())
        let decoded = try JSONDecoder().decode(DeviceCredentials.self, from: data)
        #expect(decoded == sample())
    }
}

struct BackendConfigTests {

    @Test func placeholderHostCountsAsUnconfigured() {
        #expect(BackendConfig.isConfigured(host: BackendConfig.placeholderHost) == false)
    }

    @Test func emptyHostCountsAsUnconfigured() {
        #expect(BackendConfig.isConfigured(host: "") == false)
    }

    @Test func realHostCountsAsConfigured() {
        #expect(BackendConfig.isConfigured(host: "vanda.attis.workers.dev"))
    }

    @Test func hostBecomesHTTPSURL() {
        #expect(BackendConfig.url(forHost: "vanda.attis.workers.dev")
                == URL(string: "https://vanda.attis.workers.dev"))
    }

    @Test func unconfiguredHostGivesNoURL() {
        #expect(BackendConfig.url(forHost: BackendConfig.placeholderHost) == nil)
    }
}
```

- [ ] **Step 2: Futtasd, győződj meg róla, hogy nem fordul**

Run:
```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project VandaApp/VandaApp.xcodeproj -scheme VandaApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```
Expected: FAIL — `cannot find 'DeviceCredentials' in scope`, `cannot find 'BackendConfig' in scope`.

- [ ] **Step 3: xcconfig fájl**

Create `VandaApp/Config/Backend.xcconfig`:

```
// A Vanda-backend (Cloudflare Worker) hosztja — SÉMA NÉLKÜL.
// Az xcconfig a "//"-t kommentkezdetnek tekinti, ezért teljes URL-t nem lehet
// itt épen tárolni; a "https://" előtagot a BackendConfig teszi hozzá.
//
// A deploy után (backend/README.md ellenőrzőlista) írd ide a workers.dev hosztot,
// pl.: BACKEND_HOST = vanda.attis.workers.dev
BACKEND_HOST = vanda-backend.example.workers.dev
```

- [ ] **Step 4: Info.plist kulcs**

Modify `VandaApp/VandaApp/Info.plist` — a `<dict>` elejére, az `NSAlarmKitUsageDescription` elé:

```xml
	<key>BackendHost</key>
	<string>$(BACKEND_HOST)</string>
```

- [ ] **Step 5: xcconfig bekötése a projektbe**

Modify `VandaApp/VandaApp.xcodeproj/project.pbxproj` — három pontosan körülhatárolt szerkesztés.

(a) A `PBXFileReference` szekcióba, a `CloudKit.framework` sora **elé**:

```
		EB4B2B0130000001000000A1 /* Backend.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Config/Backend.xcconfig; sourceTree = "<group>"; };
```

(b) A gyökér `PBXGroup` (`EBC2D2FD2FFC27DA00A60AB5`) `children` listájába, a `VandaApp` sora **elé**:

```
				EB4B2B0130000001000000A1 /* Backend.xcconfig */,
```

(c) A **projekt-szintű** Debug (`EBC2D30F2FFC27DB00A60AB5`) és Release (`EBC2D3102FFC27DB00A60AB5`) `XCBuildConfiguration` objektumokban az `isa = XCBuildConfiguration;` sor **után** told be:

```
			baseConfigurationReference = EB4B2B0130000001000000A1 /* Backend.xcconfig */;
```

Projekt-szinten (nem target-szinten) azért, mert így az app- és a teszt-target egyaránt látja a `BACKEND_HOST`-ot.

- [ ] **Step 6: `AppRole` legyen `Codable`**

Modify `VandaApp/VandaApp/App/RootView.swift:13`:

```swift
enum AppRole: String, Codable {
```

- [ ] **Step 7: `BackendConfig`**

Create `VandaApp/VandaApp/Services/Backend/BackendConfig.swift`:

```swift
//
//  BackendConfig.swift
//  VandaApp
//
//  A backend hosztja a Config/Backend.xcconfig-ból jön, az Info.plist
//  BackendHost kulcsán keresztül. Séma nélkül tároljuk (az xcconfig a "//"-t
//  kommentnek veszi), a https:// előtagot itt tesszük hozzá.
//

import Foundation

enum BackendConfig {

    /// Amíg nincs deploy, ez az érték áll az xcconfig-ban. Nem tekintjük
    /// konfigurációnak — így a hiba nem néma 404-ek formájában jelentkezik.
    static let placeholderHost = "vanda-backend.example.workers.dev"

    static var host: String {
        (Bundle.main.object(forInfoDictionaryKey: "BackendHost") as? String) ?? ""
    }

    static func isConfigured(host: String) -> Bool {
        !host.isEmpty && host != placeholderHost
    }

    static func url(forHost host: String) -> URL? {
        guard isConfigured(host: host) else { return nil }
        return URL(string: "https://\(host)")
    }

    /// `nil`, ha a hoszt hiányzik vagy még a placeholder — a BackendClient
    /// ilyenkor `BackendError.notConfigured`-del hasal el, beszédesen.
    static var baseURL: URL? { url(forHost: host) }

    static var isConfigured: Bool { isConfigured(host: host) }
}
```

- [ ] **Step 8: `DeviceCredentials`**

Create `VandaApp/VandaApp/Services/Backend/DeviceCredentials.swift`:

```swift
//
//  DeviceCredentials.swift
//  VandaApp
//
//  Egy eszköz backend-identitása: melyik családhoz tartozik, milyen szerepben,
//  és milyen bearer tokennel hitelesíti magát.
//

import Foundation

struct DeviceCredentials: Codable, Equatable {
    var familyId: String
    var deviceId: String
    var token: String
    var role: AppRole
    var deviceName: String
}
```

- [ ] **Step 9: `DeviceCredentialStore`**

Create `VandaApp/VandaApp/Services/Backend/DeviceCredentialStore.swift`:

```swift
//
//  DeviceCredentialStore.swift
//  VandaApp
//
//  A backend-hitelesítés tárolója. Keychain, de a napló KeyStore-jával
//  ellentétben SZÁNDÉKOSAN NEM iCloud-szinkronizált: a modellben minden eszköz
//  önálló identitás, saját APNs-tokennel — közös tokennel a két eszköz
//  felülírná egymás APNs-tokenjét, és a szerver nem tudná megkülönböztetni őket.
//

import Foundation
import Security

protocol DeviceCredentialStoring: AnyObject {
    func load() -> DeviceCredentials?
    func save(_ credentials: DeviceCredentials)
    func clear()
}

final class KeychainDeviceCredentialStore: DeviceCredentialStoring {
    static let shared = KeychainDeviceCredentialStore()

    private let service = "hu.attis.VandaApp.backend"
    private let account = "deviceCredentials"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    func load() -> DeviceCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(DeviceCredentials.self, from: data)
    }

    func save(_ credentials: DeviceCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        clear()
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        // A push-kezelés háttérben is futhat, ezért AfterFirstUnlock.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// Tesztekhez és previewhoz.
final class InMemoryDeviceCredentialStore: DeviceCredentialStoring {
    private var stored: DeviceCredentials?

    init(_ initial: DeviceCredentials? = nil) { stored = initial }

    func load() -> DeviceCredentials? { stored }
    func save(_ credentials: DeviceCredentials) { stored = credentials }
    func clear() { stored = nil }
}
```

- [ ] **Step 10: Futtasd a teszteket**

Run:
```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project VandaApp/VandaApp.xcodeproj -scheme VandaApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```
Expected: PASS — a 10 új teszt zöld, a meglévők változatlanul futnak.

- [ ] **Step 11: Ellenőrizd, hogy az xcconfig tényleg átér az Info.plistbe**

Run:
```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project VandaApp/VandaApp.xcodeproj -scheme VandaApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -showBuildSettings 2>/dev/null | grep BACKEND_HOST
```
Expected: `BACKEND_HOST = vanda-backend.example.workers.dev`. Ha üres, a Step 5 (c) pontja nem talált célba.

- [ ] **Step 12: Commit**

```bash
git add VandaApp/Config/Backend.xcconfig VandaApp/VandaApp.xcodeproj/project.pbxproj VandaApp/VandaApp/Info.plist VandaApp/VandaApp/Services/Backend VandaApp/VandaApp/App/RootView.swift VandaApp/VandaAppTests/BackendCredentialTests.swift
git commit -m "phase 4.2b: backend host config via xcconfig and Keychain credential store"
```

---

### Task 3: `BackendClient`

**Files:**
- Create: `VandaApp/VandaApp/Services/Backend/BackendError.swift`
- Create: `VandaApp/VandaApp/Services/Backend/BackendClient.swift`
- Test: `VandaApp/VandaAppTests/BackendClientTests.swift`

**Interfaces:**
- Consumes: `BackendConfig.baseURL`, `DeviceCredentials`, `AppRole`.
- Produces: `BackendError` (`notConfigured`, `unknownCode`, `codeExpiredOrUsed`, `unauthorized`, `forbidden`, `server(Int)`, `transport(String)`, `decoding`); `BackendClient` a következő metódusokkal:
  - `createFamily(deviceName: String) async throws -> DeviceCredentials`
  - `createPairingCode(role: AppRole, token: String) async throws -> PairingCode`
  - `redeemPairingCode(_ code: String, deviceName: String) async throws -> DeviceCredentials`
  - `uploadAPNsToken(_ apnsToken: String, token: String) async throws`
  - `sendTestPush(token: String) async throws -> [TestPushResult]`
  - `deleteDevice(token: String) async throws`
  - `PairingCode` (`code: String`, `expiresAt: Date`, `role: AppRole`), `TestPushResult` (`deviceId: String`, `status: Int`, `delivered: Bool`).

- [ ] **Step 1: Írd meg a bukó tesztet**

Create `VandaApp/VandaAppTests/BackendClientTests.swift`:

```swift
//
//  BackendClientTests.swift
//  VandaAppTests
//
//  A backend-kliens tesztjei URLProtocol-stubbal — élő backend nélkül.
//

import Foundation
import Testing
@testable import VandaApp

/// Minden kérést elkap, és a `handler`-rel válaszol. A `VandaAppTests`
/// soros futása miatt a statikus handler biztonságos.
final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    static var lastRequest: URLRequest?
    static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lastRequest = request
        StubURLProtocol.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.drain)

        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

private func makeClient(
    handler: @escaping (URLRequest) throws -> (Int, Data)
) -> BackendClient {
    StubURLProtocol.handler = handler
    StubURLProtocol.lastRequest = nil
    StubURLProtocol.lastBody = nil
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return BackendClient(
        baseURL: URL(string: "https://vanda.test")!,
        session: URLSession(configuration: config)
    )
}

private func json(_ raw: String) -> Data { Data(raw.utf8) }

struct BackendClientStatusMappingTests {

    @Test func unknownCodeMapsTo404() async {
        let client = makeClient { _ in (404, json(#"{"error":"unknown code"}"#)) }
        await #expect(throws: BackendError.unknownCode) {
            _ = try await client.redeemPairingCode("123456", deviceName: "Anya")
        }
    }

    @Test func expiredCodeMapsTo410() async {
        let client = makeClient { _ in (410, json(#"{"error":"code expired or used"}"#)) }
        await #expect(throws: BackendError.codeExpiredOrUsed) {
            _ = try await client.redeemPairingCode("123456", deviceName: "Anya")
        }
    }

    @Test func staleTokenMapsTo401() async {
        let client = makeClient { _ in (401, json(#"{"error":"unauthorized"}"#)) }
        await #expect(throws: BackendError.unauthorized) {
            try await client.uploadAPNsToken("abc", token: "regi-token")
        }
    }

    @Test func serverErrorKeepsItsStatus() async {
        let client = makeClient { _ in (503, json("{}")) }
        await #expect(throws: BackendError.server(503)) {
            try await client.uploadAPNsToken("abc", token: "t")
        }
    }

    @Test func transportFailureIsReported() async {
        let client = makeClient { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: BackendError.self) {
            try await client.uploadAPNsToken("abc", token: "t")
        }
    }

    @Test func missingHostGivesNotConfigured() async {
        let client = BackendClient(baseURL: nil, session: .shared)
        await #expect(throws: BackendError.notConfigured) {
            _ = try await client.createFamily(deviceName: "Vanda telefonja")
        }
    }
}

struct BackendClientRequestTests {

    @Test func createFamilyReturnsChildCredentials() async throws {
        let client = makeClient { _ in
            (201, json(#"{"familyId":"f1","deviceId":"d1","token":"tok"}"#))
        }
        let credentials = try await client.createFamily(deviceName: "Vanda telefonja")
        #expect(credentials.familyId == "f1")
        #expect(credentials.deviceId == "d1")
        #expect(credentials.token == "tok")
        #expect(credentials.role == .child)
        #expect(credentials.deviceName == "Vanda telefonja")
    }

    @Test func redeemUsesTheRoleFromTheResponse() async throws {
        let client = makeClient { _ in
            (201, json(#"{"familyId":"f1","deviceId":"d2","token":"tok2","role":"child"}"#))
        }
        let credentials = try await client.redeemPairingCode("654321", deviceName: "Vanda iPadje")
        #expect(credentials.role == .child)
        #expect(credentials.deviceId == "d2")
    }

    @Test func pairingCodeRequestCarriesTheRole() async throws {
        let client = makeClient { _ in
            (201, json(#"{"code":"123456","expiresAt":1000,"role":"child"}"#))
        }
        let code = try await client.createPairingCode(role: .child, token: "tok")
        #expect(code.code == "123456")
        #expect(code.role == .child)
        #expect(code.expiresAt == Date(timeIntervalSince1970: 1))

        let body = try #require(StubURLProtocol.lastBody)
        let sent = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(sent?["role"] as? String == "child")
    }

    @Test func authenticatedCallsSendBearerToken() async throws {
        let client = makeClient { _ in (204, Data()) }
        try await client.uploadAPNsToken("apns-token", token: "titkos")
        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer titkos")
        #expect(request.httpMethod == "PUT")
    }

    @Test func deleteDeviceUsesDeleteMethod() async throws {
        let client = makeClient { _ in (204, Data()) }
        try await client.deleteDevice(token: "titkos")
        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/devices/me")
    }

    @Test func codeIsGroupedForReading() {
        let code = PairingCode(code: "123456", expiresAt: .now, role: .parent)
        #expect(code.grouped == "123 456")
    }

    @Test func countdownCountsDownInMinutesAndSeconds() {
        let start = Date(timeIntervalSince1970: 0)
        let code = PairingCode(
            code: "123456", expiresAt: Date(timeIntervalSince1970: 600), role: .parent
        )
        #expect(code.remainingText(at: start) == "10:00")
        #expect(code.remainingText(at: Date(timeIntervalSince1970: 540)) == "1:00")
        #expect(code.remainingText(at: Date(timeIntervalSince1970: 591)) == "0:09")
    }

    @Test func expiredCodeNeverShowsNegativeTime() {
        let code = PairingCode(
            code: "123456", expiresAt: Date(timeIntervalSince1970: 600), role: .parent
        )
        #expect(code.isExpired(at: Date(timeIntervalSince1970: 700)))
        #expect(code.remainingText(at: Date(timeIntervalSince1970: 700)) == "0:00")
    }

    @Test func testPushResultsSeparateDeliveredFromFailed() async throws {
        let client = makeClient { _ in
            (200, json(#"{"results":[{"deviceId":"a","status":200},{"deviceId":"b","status":0}]}"#))
        }
        let results = try await client.sendTestPush(token: "tok")
        #expect(results.count == 2)
        #expect(results[0].delivered)
        #expect(results[1].delivered == false)
    }
}
```

- [ ] **Step 2: Futtasd, győződj meg róla, hogy nem fordul**

Run: az iOS teszt-parancs (lásd Global Constraints).
Expected: FAIL — `cannot find 'BackendClient' in scope`.

- [ ] **Step 3: `BackendError`**

Create `VandaApp/VandaApp/Services/Backend/BackendError.swift`:

```swift
//
//  BackendError.swift
//  VandaApp
//
//  A backend-hívások típusos hibái. A nyers Error helyett azért kell, hogy a
//  felület kedves, konkrét magyar mondatot tudjon mondani — és hogy a
//  hibakezelés tesztelhető legyen.
//

import Foundation

enum BackendError: Error, Equatable {
    /// Nincs beállítva a BACKEND_HOST (Config/Backend.xcconfig) — deploy előtti állapot.
    case notConfigured
    case unknownCode
    case codeExpiredOrUsed
    case unauthorized
    case forbidden
    case server(Int)
    case transport(String)
    case decoding

    /// Kedves, tegező magyar mondat a felületnek.
    var friendlyMessage: String {
        switch self {
        case .notConfigured:
            return "A backend címe még nincs beállítva ebben a buildben."
        case .unknownCode:
            return "Ilyen kódot nem találunk — lehet, hogy elgépeltük?"
        case .codeExpiredOrUsed:
            return "Ez a kód lejárt vagy már felhasználták. Kérj egy újat!"
        case .unauthorized:
            return "Megszakadt az összeköttetés a családdal — párosítsd újra az eszközt."
        case .forbidden:
            return "Ehhez ennek az eszköznek nincs jogosultsága."
        case .server:
            return "A szerver most nem tudott válaszolni. Próbáljuk újra?"
        case .transport:
            return "Úgy tűnik, most nincs net. Próbáljuk újra?"
        case .decoding:
            return "Furcsa választ kaptunk a szervertől. Próbáljuk újra?"
        }
    }

    /// A HTTP-státusz → hiba leképezés egy helyen, hogy tesztelhető legyen.
    static func forStatus(_ status: Int) -> BackendError? {
        switch status {
        case 200..<300: return nil
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .unknownCode
        case 410: return .codeExpiredOrUsed
        default: return .server(status)
        }
    }
}
```

- [ ] **Step 4: `BackendClient`**

Create `VandaApp/VandaApp/Services/Backend/BackendClient.swift`:

```swift
//
//  BackendClient.swift
//  VandaApp
//
//  Vékony async kliens a Vanda-backendhez. Az URLSession injektálható, hogy a
//  tesztek URLProtocol-stubbal, élő backend nélkül futhassanak.
//

import Foundation

struct PairingCode: Equatable {
    var code: String
    var expiresAt: Date
    var role: AppRole

    /// Formázott, hat számjegyű alak: „123 456".
    var grouped: String {
        guard code.count == 6 else { return code }
        let middle = code.index(code.startIndex, offsetBy: 3)
        return "\(code[code.startIndex..<middle]) \(code[middle...])"
    }

    func isExpired(at now: Date) -> Bool { expiresAt <= now }

    /// Visszaszámláló „m:ss" alakban. A lejárat utáni negatív időt 0:00-ra
    /// vágjuk, hogy a felület sose mutasson mínuszt.
    func remainingText(at now: Date) -> String {
        let seconds = Int(max(0, expiresAt.timeIntervalSince(now)).rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct TestPushResult: Equatable {
    var deviceId: String
    var status: Int

    /// A backend 0-t ad, ha HTTP-státusz sem született (transzport-hiba).
    var delivered: Bool { (200..<300).contains(status) }
}

final class BackendClient {
    static let shared = BackendClient()

    private let baseURL: URL?
    private let session: URLSession

    init(baseURL: URL? = BackendConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Endpointok

    func createFamily(deviceName: String) async throws -> DeviceCredentials {
        let response: PairingResponse = try await send(
            "/families", method: "POST", body: ["deviceName": deviceName], token: nil
        )
        return DeviceCredentials(
            familyId: response.familyId,
            deviceId: response.deviceId,
            token: response.token,
            role: .child,
            deviceName: deviceName
        )
    }

    func createPairingCode(role: AppRole, token: String) async throws -> PairingCode {
        let response: PairingCodeResponse = try await send(
            "/pairing-codes", method: "POST", body: ["role": role.rawValue], token: token
        )
        return PairingCode(
            code: response.code,
            expiresAt: Date(timeIntervalSince1970: response.expiresAt / 1000),
            role: AppRole(rawValue: response.role ?? role.rawValue) ?? role
        )
    }

    func redeemPairingCode(_ code: String, deviceName: String) async throws -> DeviceCredentials {
        let response: PairingResponse = try await send(
            "/pair", method: "POST", body: ["code": code, "deviceName": deviceName], token: nil
        )
        return DeviceCredentials(
            familyId: response.familyId,
            deviceId: response.deviceId,
            token: response.token,
            role: AppRole(rawValue: response.role ?? "parent") ?? .parent,
            deviceName: deviceName
        )
    }

    func uploadAPNsToken(_ apnsToken: String, token: String) async throws {
        try await sendIgnoringBody(
            "/devices/me/apns-token", method: "PUT", body: ["token": apnsToken], token: token
        )
    }

    func sendTestPush(token: String) async throws -> [TestPushResult] {
        let response: TestPushResponse = try await send(
            "/test-pushes", method: "POST", body: nil, token: token
        )
        return response.results.map { TestPushResult(deviceId: $0.deviceId, status: $0.status) }
    }

    func deleteDevice(token: String) async throws {
        try await sendIgnoringBody("/devices/me", method: "DELETE", body: nil, token: token)
    }

    // MARK: - Belső HTTP-réteg

    private struct PairingResponse: Decodable {
        var familyId: String
        var deviceId: String
        var token: String
        var role: String?
    }

    private struct PairingCodeResponse: Decodable {
        var code: String
        var expiresAt: Double
        var role: String?
    }

    private struct TestPushResponse: Decodable {
        struct Row: Decodable {
            var deviceId: String
            var status: Int
        }
        var results: [Row]
    }

    private func makeRequest(
        _ path: String, method: String, body: [String: String]?, token: String?
    ) throws -> URLRequest {
        guard let baseURL else { throw BackendError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 20
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw BackendError.decoding }
        if let error = BackendError.forStatus(http.statusCode) { throw error }
        return data
    }

    private func send<T: Decodable>(
        _ path: String, method: String, body: [String: String]?, token: String?
    ) async throws -> T {
        let data = try await perform(try makeRequest(path, method: method, body: body, token: token))
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw BackendError.decoding
        }
    }

    private func sendIgnoringBody(
        _ path: String, method: String, body: [String: String]?, token: String?
    ) async throws {
        _ = try await perform(try makeRequest(path, method: method, body: body, token: token))
    }
}
```

- [ ] **Step 5: Futtasd a teszteket**

Run: az iOS teszt-parancs.
Expected: PASS — a 16 új teszt zöld.

- [ ] **Step 6: Commit**

```bash
git add VandaApp/VandaApp/Services/Backend/BackendError.swift VandaApp/VandaApp/Services/Backend/BackendClient.swift VandaApp/VandaAppTests/BackendClientTests.swift
git commit -m "phase 4.2b: typed backend HTTP client with URLProtocol-tested error mapping"
```

---

### Task 4: App delegate és `PushRegistrar`

**Files:**
- Create: `VandaApp/VandaApp/Services/Backend/PushRegistrar.swift`
- Create: `VandaApp/VandaApp/App/AppDelegate.swift`
- Modify: `VandaApp/VandaApp/VandaAppApp.swift`
- Test: `VandaApp/VandaAppTests/PushRegistrarTests.swift`

**Interfaces:**
- Consumes: `DeviceCredentialStoring`, `BackendClient`, `BackendError`.
- Produces: `PushRegistrar` osztály `init(client:store:defaults:)`, `didReceive(deviceToken: Data)`, `didReceive(deviceTokenHex: String)`, `func flush() async`, valamint `PushUploader` protokoll (a `BackendClient` erre konformál) — a 6–8. feladat a `PushRegistrar.shared.flush()`-t hívja párosítás után.

- [ ] **Step 1: Írd meg a bukó tesztet**

Create `VandaApp/VandaAppTests/PushRegistrarTests.swift`:

```swift
//
//  PushRegistrarTests.swift
//  VandaAppTests
//
//  Az APNs-token feltöltésének tesztjei: a token és a párosítás bármilyen
//  sorrendben érkezhet, és változatlan token nem generál felesleges hívást.
//

import Foundation
import Testing
@testable import VandaApp

private final class SpyUploader: PushUploader {
    var uploaded: [(apnsToken: String, token: String)] = []
    var nextError: BackendError?

    func uploadAPNsToken(_ apnsToken: String, token: String) async throws {
        if let nextError { throw nextError }
        uploaded.append((apnsToken, token))
    }
}

private func makeDefaults() -> UserDefaults {
    let suite = "PushRegistrarTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private let credentials = DeviceCredentials(
    familyId: "f1", deviceId: "d1", token: "titkos", role: .parent, deviceName: "Anya telefonja"
)

struct PushRegistrarTests {

    @Test func hexEncodingMatchesAPNsFormat() {
        let data = Data([0x0A, 0xFF, 0x10])
        #expect(PushRegistrar.hexString(from: data) == "0aff10")
    }

    @Test func tokenArrivingAfterPairingIsUploaded() async {
        let uploader = SpyUploader()
        let registrar = PushRegistrar(
            uploader: uploader,
            store: InMemoryDeviceCredentialStore(credentials),
            defaults: makeDefaults()
        )
        registrar.didReceive(deviceTokenHex: "abcd")
        await registrar.flush()
        #expect(uploader.uploaded.count == 1)
        #expect(uploader.uploaded.first?.apnsToken == "abcd")
        #expect(uploader.uploaded.first?.token == "titkos")
    }

    @Test func tokenArrivingBeforePairingWaitsThenUploads() async {
        let uploader = SpyUploader()
        let store = InMemoryDeviceCredentialStore()
        let registrar = PushRegistrar(uploader: uploader, store: store, defaults: makeDefaults())

        registrar.didReceive(deviceTokenHex: "abcd")
        await registrar.flush()
        #expect(uploader.uploaded.isEmpty)

        store.save(credentials)
        await registrar.flush()
        #expect(uploader.uploaded.count == 1)
    }

    @Test func unchangedTokenIsNotUploadedTwice() async {
        let uploader = SpyUploader()
        let registrar = PushRegistrar(
            uploader: uploader,
            store: InMemoryDeviceCredentialStore(credentials),
            defaults: makeDefaults()
        )
        registrar.didReceive(deviceTokenHex: "abcd")
        await registrar.flush()
        await registrar.flush()
        #expect(uploader.uploaded.count == 1)
    }

    @Test func changedTokenIsUploadedAgain() async {
        let uploader = SpyUploader()
        let registrar = PushRegistrar(
            uploader: uploader,
            store: InMemoryDeviceCredentialStore(credentials),
            defaults: makeDefaults()
        )
        registrar.didReceive(deviceTokenHex: "abcd")
        await registrar.flush()
        registrar.didReceive(deviceTokenHex: "ef01")
        await registrar.flush()
        #expect(uploader.uploaded.map(\.apnsToken) == ["abcd", "ef01"])
    }

    @Test func failedUploadIsRetriedOnTheNextFlush() async {
        let uploader = SpyUploader()
        uploader.nextError = .transport("nincs net")
        let registrar = PushRegistrar(
            uploader: uploader,
            store: InMemoryDeviceCredentialStore(credentials),
            defaults: makeDefaults()
        )
        registrar.didReceive(deviceTokenHex: "abcd")
        await registrar.flush()
        #expect(uploader.uploaded.isEmpty)

        uploader.nextError = nil
        await registrar.flush()
        #expect(uploader.uploaded.count == 1)
    }

    @Test func unlinkingForgetsTheUploadedToken() async {
        let uploader = SpyUploader()
        let store = InMemoryDeviceCredentialStore(credentials)
        let registrar = PushRegistrar(uploader: uploader, store: store, defaults: makeDefaults())
        registrar.didReceive(deviceTokenHex: "abcd")
        await registrar.flush()

        registrar.forgetUploadState()
        store.save(credentials)
        await registrar.flush()
        #expect(uploader.uploaded.count == 2)
    }
}
```

- [ ] **Step 2: Futtasd, győződj meg róla, hogy nem fordul**

Run: az iOS teszt-parancs.
Expected: FAIL — `cannot find 'PushRegistrar' in scope`.

- [ ] **Step 3: `PushRegistrar`**

Create `VandaApp/VandaApp/Services/Backend/PushRegistrar.swift`:

```swift
//
//  PushRegistrar.swift
//  VandaApp
//
//  Az APNs device-token és a párosítás bármilyen sorrendben érkezhet: a token
//  jöhet a párosítás előtt (indításkor regisztrálunk) és utána is. A registrar
//  ezért mindig eltárolja a legutóbb kapott tokent, és csak akkor tölti fel,
//  ha van hitelesítés ÉS a token eltér a legutóbb feltöltöttől.
//

import Foundation

protocol PushUploader {
    func uploadAPNsToken(_ apnsToken: String, token: String) async throws
}

extension BackendClient: PushUploader {}

final class PushRegistrar {
    static let shared = PushRegistrar()

    private let uploader: PushUploader
    private let store: DeviceCredentialStoring
    private let defaults: UserDefaults

    private let pendingKey = "backend.apnsToken.pending"
    private let uploadedKey = "backend.apnsToken.uploaded"

    init(
        uploader: PushUploader = BackendClient.shared,
        store: DeviceCredentialStoring = KeychainDeviceCredentialStore.shared,
        defaults: UserDefaults = .standard
    ) {
        self.uploader = uploader
        self.store = store
        self.defaults = defaults
    }

    static func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    func didReceive(deviceToken: Data) {
        didReceive(deviceTokenHex: Self.hexString(from: deviceToken))
    }

    func didReceive(deviceTokenHex: String) {
        defaults.set(deviceTokenHex, forKey: pendingKey)
    }

    /// Leválasztáskor hívandó: a következő párosítás után a token újra felmegy.
    func forgetUploadState() {
        defaults.removeObject(forKey: uploadedKey)
    }

    func flush() async {
        guard let pending = defaults.string(forKey: pendingKey),
              let credentials = store.load(),
              defaults.string(forKey: uploadedKey) != pending else { return }

        do {
            try await uploader.uploadAPNsToken(pending, token: credentials.token)
            defaults.set(pending, forKey: uploadedKey)
        } catch {
            // Nem végzetes: a következő indítás vagy párosítás újrapróbálja.
            // A 4.3 riasztás-ciklusa nem ettől függ, de a szülőnek jobb, ha
            // a token minél előbb felér — ezért nincs elnyelt, néma hiba.
            print("VandaApp: az APNs-token feltöltése nem sikerült — \(error)")
        }
    }
}
```

- [ ] **Step 4: App delegate**

Create `VandaApp/VandaApp/App/AppDelegate.swift`:

```swift
//
//  AppDelegate.swift
//  VandaApp
//
//  Az APNs device-token átvételéhez kell (SwiftUI-ból csak app delegate-en át
//  érhető el). A helyi notificationök továbbra is UNUserNotificationCenterrel
//  mennek — ez a delegate kizárólag a távoli push regisztrációjáért felel.
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // A regisztráció NEM igényel notification-engedélyt (az csak a
        // megjelenítést szabályozza), ezért minden indításkor lefuttatjuk —
        // a token változhat, és a PushRegistrar úgyis csak eltérés esetén tölt fel.
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushRegistrar.shared.didReceive(deviceToken: deviceToken)
        Task { await PushRegistrar.shared.flush() }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Szimulátoron ez normális; eszközön hálózat- vagy provisioning-hiba.
        print("VandaApp: APNs-regisztráció nem sikerült — \(error.localizedDescription)")
    }
}
```

- [ ] **Step 5: A delegate bekötése**

Modify `VandaApp/VandaApp/VandaAppApp.swift` — a `@main struct VandaAppApp: App {` sor után, az `init()` elé:

```swift
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
```

- [ ] **Step 6: Futtasd a teszteket**

Run: az iOS teszt-parancs.
Expected: PASS — a 7 új teszt zöld.

- [ ] **Step 7: Commit**

```bash
git add VandaApp/VandaApp/Services/Backend/PushRegistrar.swift VandaApp/VandaApp/App/AppDelegate.swift VandaApp/VandaApp/VandaAppApp.swift VandaApp/VandaAppTests/PushRegistrarTests.swift
git commit -m "phase 4.2b: APNs token registration with pending-token upload logic"
```

---

### Task 5: `FamilyLinkModel` — a párosítási állapotgép

**Files:**
- Create: `VandaApp/VandaApp/Services/Backend/FamilyLinkModel.swift`
- Test: `VandaApp/VandaAppTests/FamilyLinkModelTests.swift`

**Interfaces:**
- Consumes: `BackendClient`, `DeviceCredentialStoring`, `PushRegistrar`, `BackendError`, `PairingCode`, `TestPushResult`.
- Produces: `FamilyLinkModel` (`@Observable`), `init(client:store:registrar:)`, publikus felület:
  - `var link: FamilyLink` — `.unlinked` / `.linked(DeviceCredentials)`
  - `var isBusy: Bool`, `var errorMessage: String?`, `var activeCode: PairingCode?`, `var testPushResults: [TestPushResult]?`
  - `func createFamily(deviceName: String) async`
  - `func joinWithCode(_ code: String, deviceName: String) async`
  - `func issueCode(role: AppRole) async`
  - `func rename(to newName: String) async`
  - `func sendTestPush() async`
  - `func unlink() async`
  A 6–8. feladat kizárólag ezt a felületet használja.

- [ ] **Step 1: Írd meg a bukó tesztet**

Create `VandaApp/VandaAppTests/FamilyLinkModelTests.swift`:

```swift
//
//  FamilyLinkModelTests.swift
//  VandaAppTests
//
//  A párosítási állapotgép tesztjei — hálózat és felület nélkül.
//

import Foundation
import Testing
@testable import VandaApp

private final class FakeBackend: FamilyLinking {
    var createFamilyResult: Result<DeviceCredentials, BackendError> = .failure(.notConfigured)
    var redeemResult: Result<DeviceCredentials, BackendError> = .failure(.unknownCode)
    var codeResult: Result<PairingCode, BackendError> = .failure(.notConfigured)
    var testPushResult: Result<[TestPushResult], BackendError> = .success([])
    var deleteResult: Result<Void, BackendError> = .success(())
    var deleteCalls = 0

    func createFamily(deviceName: String) async throws -> DeviceCredentials {
        try createFamilyResult.get()
    }
    func redeemPairingCode(_ code: String, deviceName: String) async throws -> DeviceCredentials {
        try redeemResult.get()
    }
    func createPairingCode(role: AppRole, token: String) async throws -> PairingCode {
        try codeResult.get()
    }
    func sendTestPush(token: String) async throws -> [TestPushResult] {
        try testPushResult.get()
    }
    func deleteDevice(token: String) async throws {
        deleteCalls += 1
        try deleteResult.get()
    }
}

private let childCredentials = DeviceCredentials(
    familyId: "f1", deviceId: "d1", token: "tok", role: .child, deviceName: "Vanda telefonja"
)

private func makeModel(
    backend: FakeBackend, store: InMemoryDeviceCredentialStore = InMemoryDeviceCredentialStore()
) -> FamilyLinkModel {
    FamilyLinkModel(
        client: backend,
        store: store,
        registrar: PushRegistrar(
            uploader: NoopUploader(),
            store: store,
            defaults: UserDefaults(suiteName: "FamilyLinkModelTests-\(UUID().uuidString)")!
        )
    )
}

private final class NoopUploader: PushUploader {
    func uploadAPNsToken(_ apnsToken: String, token: String) async throws {}
}

struct FamilyLinkModelTests {

    @Test func startsUnlinkedWithAnEmptyStore() {
        let model = makeModel(backend: FakeBackend())
        #expect(model.link == .unlinked)
        #expect(model.isLinked == false)
    }

    @Test func picksUpCredentialsAlreadyInTheStore() {
        let store = InMemoryDeviceCredentialStore(childCredentials)
        let model = makeModel(backend: FakeBackend(), store: store)
        #expect(model.link == .linked(childCredentials))
        #expect(model.credentials?.role == .child)
    }

    @Test func creatingAFamilyStoresTheCredentials() async {
        let backend = FakeBackend()
        backend.createFamilyResult = .success(childCredentials)
        let store = InMemoryDeviceCredentialStore()
        let model = makeModel(backend: backend, store: store)

        await model.createFamily(deviceName: "Vanda telefonja")

        #expect(model.link == .linked(childCredentials))
        #expect(store.load() == childCredentials)
        #expect(model.errorMessage == nil)
        #expect(model.isBusy == false)
    }

    @Test func creatingAFamilyTwiceIsRefused() async {
        let backend = FakeBackend()
        backend.createFamilyResult = .success(childCredentials)
        let store = InMemoryDeviceCredentialStore(childCredentials)
        let model = makeModel(backend: backend, store: store)

        await model.createFamily(deviceName: "Másik név")

        #expect(store.load()?.deviceName == "Vanda telefonja")
    }

    @Test func joiningWithABadCodeSurfacesAKindMessage() async {
        let backend = FakeBackend()
        backend.redeemResult = .failure(.unknownCode)
        let model = makeModel(backend: backend)

        await model.joinWithCode("000000", deviceName: "Vanda iPadje")

        #expect(model.link == .unlinked)
        #expect(model.errorMessage == BackendError.unknownCode.friendlyMessage)
    }

    @Test func joiningWithAnExpiredCodeSurfacesTheExpiryMessage() async {
        let backend = FakeBackend()
        backend.redeemResult = .failure(.codeExpiredOrUsed)
        let model = makeModel(backend: backend)

        await model.joinWithCode("123456", deviceName: "Anya telefonja")

        #expect(model.errorMessage == BackendError.codeExpiredOrUsed.friendlyMessage)
    }

    @Test func issuingACodeRequiresBeingLinked() async {
        let backend = FakeBackend()
        backend.codeResult = .success(PairingCode(
            code: "123456", expiresAt: Date(timeIntervalSince1970: 1), role: .parent
        ))
        let model = makeModel(backend: backend)

        await model.issueCode(role: .parent)

        #expect(model.activeCode == nil)
    }

    @Test func issuingACodeWhenLinkedPublishesIt() async {
        let backend = FakeBackend()
        backend.codeResult = .success(PairingCode(
            code: "123456", expiresAt: Date(timeIntervalSince1970: 1), role: .child
        ))
        let model = makeModel(backend: backend, store: InMemoryDeviceCredentialStore(childCredentials))

        await model.issueCode(role: .child)

        #expect(model.activeCode?.code == "123456")
        #expect(model.activeCode?.role == .child)
    }

    @Test func renamingKeepsTheRestOfTheCredentials() async {
        let store = InMemoryDeviceCredentialStore(childCredentials)
        let model = makeModel(backend: FakeBackend(), store: store)

        await model.rename(to: "Vanda új telefonja")

        #expect(store.load()?.deviceName == "Vanda új telefonja")
        #expect(store.load()?.token == "tok")
    }

    @Test func unlinkingClearsTheStoreEvenIfTheServerCallFails() async {
        let backend = FakeBackend()
        backend.deleteResult = .failure(.transport("nincs net"))
        let store = InMemoryDeviceCredentialStore(childCredentials)
        let model = makeModel(backend: backend, store: store)

        await model.unlink()

        #expect(backend.deleteCalls == 1)
        #expect(store.load() == nil)
        #expect(model.link == .unlinked)
    }

    @Test func testPushResultsAreKept() async {
        let backend = FakeBackend()
        backend.testPushResult = .success([
            TestPushResult(deviceId: "a", status: 200),
            TestPushResult(deviceId: "b", status: 0),
        ])
        let model = makeModel(backend: backend, store: InMemoryDeviceCredentialStore(childCredentials))

        await model.sendTestPush()

        #expect(model.testPushResults?.count == 2)
        #expect(model.deliveredCount == 1)
        #expect(model.failedCount == 1)
    }
}
```

- [ ] **Step 2: Futtasd, győződj meg róla, hogy nem fordul**

Run: az iOS teszt-parancs.
Expected: FAIL — `cannot find 'FamilyLinkModel' in scope`, `cannot find type 'FamilyLinking' in scope`.

- [ ] **Step 3: A modell**

Create `VandaApp/VandaApp/Services/Backend/FamilyLinkModel.swift`:

```swift
//
//  FamilyLinkModel.swift
//  VandaApp
//
//  A párosítás állapotgépe: ezt fogyasztja Vanda Család képernyője és a szülő
//  mód egyaránt. A hálózati réteg protokoll mögött van, hogy a tesztek
//  hálózat nélkül futhassanak.
//

import Foundation
import Observation

/// A BackendClient azon szelete, amire a párosítás támaszkodik.
protocol FamilyLinking {
    func createFamily(deviceName: String) async throws -> DeviceCredentials
    func redeemPairingCode(_ code: String, deviceName: String) async throws -> DeviceCredentials
    func createPairingCode(role: AppRole, token: String) async throws -> PairingCode
    func sendTestPush(token: String) async throws -> [TestPushResult]
    func deleteDevice(token: String) async throws
}

extension BackendClient: FamilyLinking {}

enum FamilyLink: Equatable {
    case unlinked
    case linked(DeviceCredentials)
}

@Observable
final class FamilyLinkModel {

    private(set) var link: FamilyLink
    private(set) var isBusy = false
    var errorMessage: String?
    private(set) var activeCode: PairingCode?
    private(set) var testPushResults: [TestPushResult]?

    private let client: FamilyLinking
    private let store: DeviceCredentialStoring
    private let registrar: PushRegistrar

    init(
        client: FamilyLinking = BackendClient.shared,
        store: DeviceCredentialStoring = KeychainDeviceCredentialStore.shared,
        registrar: PushRegistrar = .shared
    ) {
        self.client = client
        self.store = store
        self.registrar = registrar
        self.link = store.load().map(FamilyLink.linked) ?? .unlinked
    }

    var credentials: DeviceCredentials? {
        if case .linked(let credentials) = link { return credentials }
        return nil
    }

    var isLinked: Bool { credentials != nil }
    var deliveredCount: Int { (testPushResults ?? []).filter(\.delivered).count }
    var failedCount: Int { (testPushResults ?? []).filter { !$0.delivered }.count }

    // MARK: - Műveletek

    func createFamily(deviceName: String) async {
        // Idempotencia-őr: mentett hitelesítés mellett soha ne keletkezzen
        // második, árva család (dupla koppintás, timeout utáni újrapróbálás).
        guard !isLinked else { return }
        await run {
            let credentials = try await self.client.createFamily(deviceName: deviceName)
            self.persist(credentials)
        }
    }

    func joinWithCode(_ code: String, deviceName: String) async {
        guard !isLinked else { return }
        await run {
            let credentials = try await self.client.redeemPairingCode(code, deviceName: deviceName)
            self.persist(credentials)
        }
    }

    func issueCode(role: AppRole) async {
        guard let credentials else { return }
        activeCode = nil
        await run {
            self.activeCode = try await self.client.createPairingCode(
                role: role, token: credentials.token
            )
        }
    }

    func rename(to newName: String) async {
        guard var credentials else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        credentials.deviceName = trimmed
        persist(credentials)
    }

    func sendTestPush() async {
        guard let credentials else { return }
        testPushResults = nil
        await run {
            self.testPushResults = try await self.client.sendTestPush(token: credentials.token)
        }
    }

    func unlink() async {
        guard let credentials else { return }
        isBusy = true
        errorMessage = nil
        // A szerver-hívás hibája sem ragaszthatja ide az eszközt: a helyi
        // törlés akkor is megtörténik, hogy újra lehessen párosítani.
        do {
            try await client.deleteDevice(token: credentials.token)
        } catch {
            errorMessage = (error as? BackendError)?.friendlyMessage
        }
        self.store.clear()
        registrar.forgetUploadState()
        link = .unlinked
        activeCode = nil
        testPushResults = nil
        isBusy = false
    }

    // MARK: - Belső

    /// Nem `store(_:)` a neve, hogy ne ütközzön a `store` property-vel.
    private func persist(_ credentials: DeviceCredentials) {
        store.save(credentials)
        link = .linked(credentials)
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        do {
            try await work()
        } catch let error as BackendError {
            errorMessage = error.friendlyMessage
        } catch {
            errorMessage = BackendError.transport(error.localizedDescription).friendlyMessage
        }
        isBusy = false
        await registrar.flush()
    }
}
```

- [ ] **Step 4: Futtasd a teszteket**

Run: az iOS teszt-parancs.
Expected: PASS — a 11 új teszt zöld.

- [ ] **Step 5: Commit**

```bash
git add VandaApp/VandaApp/Services/Backend/FamilyLinkModel.swift VandaApp/VandaAppTests/FamilyLinkModelTests.swift
git commit -m "phase 4.2b: family pairing state machine with idempotency guard"
```

---

### Task 6: Vanda Család képernyője

**Files:**
- Create: `VandaApp/VandaApp/Screens/Settings/FamilySettingsView.swift`
- Create: `VandaApp/VandaApp/Screens/Settings/PairingCodeSheet.swift`
- Modify: `VandaApp/VandaApp/Screens/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `FamilyLinkModel`, `PairingCode`, `AppRole`, `Theme` tokenek, `vandaCard()` modifier.
- Produces: `FamilySettingsView` (paraméter nélküli `init`), `PairingCodeSheet(code:onRefresh:)`. A 8. feladat a `FamilySettingsView`-ba tesz gombot.

- [ ] **Step 1: Kód-lap**

Create `VandaApp/VandaApp/Screens/Settings/PairingCodeSheet.swift`:

```swift
//
//  PairingCodeSheet.swift
//  VandaApp
//
//  A 6 jegyű párosító kód megjelenítése visszaszámlálóval. Nagy, jól olvasható
//  számjegyek — a másik eszközön valakinek be kell gépelnie.
//

import SwiftUI

struct PairingCodeSheet: View {
    let code: PairingCode
    let onRefresh: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // A visszaszámlálás logikája a PairingCode-ban van (tesztelt), itt csak megjelenik.
    private var isExpired: Bool { code.isExpired(at: now) }
    private var countdownText: String { code.remainingText(at: now) }

    private var title: String {
        code.role == .child ? "Vanda másik eszközéhez" : "Szülő meghívása"
    }

    private var hint: String {
        code.role == .child
            ? "Írd be ezt a kódot a másik eszközödön, a Beállítások → Család képernyőn."
            : "Írd be ezt a kódot anya vagy apa telefonján, a szülő módban."
    }

    var body: some View {
        ZStack {
            Theme.BackgroundGradient.default.gradient
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.cardGap) {
                Text(title)
                    .font(.vandaDisplay())
                    .foregroundStyle(Color.ink)

                VStack(spacing: 12) {
                    Text(code.grouped)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isExpired ? Color.inkFaint : Color.ink)

                    if isExpired {
                        Text("Ez a kód lejárt.")
                            .font(.vandaBody())
                            .foregroundStyle(Color.inkMuted)
                    } else {
                        Text("Még \(countdownText) percig érvényes")
                            .font(.vandaCaption())
                            .foregroundStyle(Color.inkMuted)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity)
                .vandaCard()

                Text(hint)
                    .font(.vandaBody())
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)

                Button(isExpired ? "Kérek újat" : "Új kódot kérek", action: onRefresh)
                    .font(.vandaBodyStrong())

                Button("Kész") { dismiss() }
                    .font(.vandaBodyStrong(13))
                    .foregroundStyle(Color.inkMuted)
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
        }
        .onReceive(tick) { now = $0 }
    }
}
```

- [ ] **Step 2: Család képernyő**

Create `VandaApp/VandaApp/Screens/Settings/FamilySettingsView.swift`:

```swift
//
//  FamilySettingsView.swift
//  VandaApp
//
//  Vanda oldalán a család-párosítás. Lusta: az első indításkor nincs hálózati
//  hívás, a döntés (család létrehozása vs. kód beváltása) itt születik — így
//  nem keletkezhet árva vagy második család.
//

import SwiftUI
import SwiftData

struct FamilySettingsView: View {
    @Query private var themeSettings: [ThemeSettings]
    @State private var model = FamilyLinkModel()
    @State private var enteredCode = ""
    @State private var editedName = ""
    @State private var showCodeSheet = false
    @State private var showUnlinkConfirm = false

    private var theme: ThemeSettings? { themeSettings.first }
    private var cardSurface: Color { theme?.cardSurface ?? .surface }

    private var defaultDeviceName: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "Vanda iPadje" : "Vanda telefonja"
    }

    var body: some View {
        ZStack {
            ThemedBackground(settings: theme)

            ScrollView {
                VStack(spacing: Theme.Spacing.cardGap) {
                    if let credentials = model.credentials {
                        linkedSection(credentials)
                    } else {
                        unlinkedSection
                    }

                    if let message = model.errorMessage {
                        Text(message)
                            .font(.vandaBody())
                            .foregroundStyle(Color.zoneRedStrong)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .vandaCard(surface: cardSurface)
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.cardGap)
            }
        }
        .navigationTitle("Család")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showCodeSheet) {
            if let code = model.activeCode {
                PairingCodeSheet(code: code) {
                    Task { await model.issueCode(role: code.role) }
                }
            }
        }
        .confirmationDialog(
            "Biztosan lekötöd ezt az eszközt a családról?",
            isPresented: $showUnlinkConfirm,
            titleVisibility: .visible
        ) {
            Button("Igen, leválasztom", role: .destructive) {
                Task { await model.unlink() }
            }
            Button("Mégsem", role: .cancel) {}
        } message: {
            Text("Utána újra kell párosítani, hogy a jelzések működjenek.")
        }
        .onAppear { editedName = model.credentials?.deviceName ?? defaultDeviceName }
    }

    // MARK: - Nincs összekötve

    private var unlinkedSection: some View {
        VStack(spacing: Theme.Spacing.cardGap) {
            VStack(spacing: 8) {
                Text("🫂")
                    .font(.system(size: 40))
                Text("Még nincs összekötve")
                    .font(.vandaBodyStrong())
                    .foregroundStyle(Color.ink)
                Text("Ha ez az első eszközöd, hozz létre családot. Ha kaptál egy hat jegyű kódot, azt írd be.")
                    .font(.vandaCaption())
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .vandaCard(surface: cardSurface)

            Button {
                Task { await model.createFamily(deviceName: editedName) }
            } label: {
                Text("Család létrehozása")
                    .font(.vandaBodyStrong())
                    .frame(maxWidth: .infinity)
                    .vandaCard(surface: cardSurface)
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)

            VStack(alignment: .leading, spacing: 10) {
                Text("Kódot kaptam")
                    .font(.vandaBodyStrong())
                    .foregroundStyle(Color.ink)
                TextField("123456", text: $enteredCode)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                Button("Csatlakozás") {
                    Task { await model.joinWithCode(enteredCode, deviceName: editedName) }
                }
                .font(.vandaBodyStrong())
                .disabled(enteredCode.count != 6 || model.isBusy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vandaCard(surface: cardSurface)
        }
    }

    // MARK: - Össze van kötve

    private func linkedSection(_ credentials: DeviceCredentials) -> some View {
        VStack(spacing: Theme.Spacing.cardGap) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Össze van kötve 💛")
                    .font(.vandaBodyStrong())
                    .foregroundStyle(Color.ink)
                Text(credentials.role == .child ? "Ez az eszköz a tiéd." : "Ez az eszköz szülő módban van.")
                    .font(.vandaCaption())
                    .foregroundStyle(Color.inkMuted)

                TextField("Eszköz neve", text: $editedName)
                    .font(.vandaBody())
                    .onSubmit { Task { await model.rename(to: editedName) } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vandaCard(surface: cardSurface)

            actionRow(symbol: "person.badge.plus", title: "Szülő meghívása") {
                Task {
                    await model.issueCode(role: .parent)
                    showCodeSheet = model.activeCode != nil
                }
            }

            actionRow(symbol: "ipad.and.iphone", title: "Másik eszközöm hozzáadása") {
                Task {
                    await model.issueCode(role: .child)
                    showCodeSheet = model.activeCode != nil
                }
            }

            Button("Összeköttetés bontása") { showUnlinkConfirm = true }
                .font(.vandaBodyStrong(13))
                .foregroundStyle(Color.inkMuted)
        }
    }

    private func actionRow(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.cardPadding) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme?.accentColor ?? Theme.Accent.default)
                    .frame(width: 34, height: 34)
                    .background(
                        Color.surfaceTint,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.iconContainer, style: .continuous)
                    )
                Text(title)
                    .font(.vandaBodyStrong())
                    .foregroundStyle(Color.ink)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vandaCard(surface: cardSurface)
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
    }
}

#Preview {
    NavigationStack {
        FamilySettingsView()
    }
    .modelContainer(VandaStore.makeContainer())
}
```

A használt tokenek mind léteznek: `Color.zoneRedStrong` (`Theme+Colors.swift:50`), `Theme.Accent.default`, `Theme.Spacing.*`, `Theme.Radius.iconContainer`, `Color.surfaceTint`, `vandaCard(surface:)` (alapértéke `.surface`).

- [ ] **Step 3: Bekötés a Beállításokba**

Modify `VandaApp/VandaApp/Screens/Settings/SettingsView.swift` — a „Megosztás a szülőkkel" placeholder sor **elé**:

```swift
                    NavigationLink {
                        FamilySettingsView()
                    } label: {
                        settingsRow(
                            symbol: "person.2.badge.key.fill",
                            title: "Család",
                            subtitle: "Párosítás anyáékkal és a másik eszközöddel"
                        )
                    }
                    .buttonStyle(.plain)
```

- [ ] **Step 4: Buildelj**

Run: az iOS build-parancs (lásd Global Constraints).
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Futtasd a teszteket**

Run: az iOS teszt-parancs.
Expected: PASS — minden korábbi teszt zöld marad.

- [ ] **Step 6: Commit**

```bash
git add VandaApp/VandaApp/Screens/Settings/FamilySettingsView.swift VandaApp/VandaApp/Screens/Settings/PairingCodeSheet.swift VandaApp/VandaApp/Screens/Settings/SettingsView.swift
git commit -m "phase 4.2b: family pairing screen for Vanda's devices"
```

---

### Task 7: Szülő mód párosítás és notification-engedély

**Files:**
- Create: `VandaApp/VandaApp/Services/Backend/NotificationPermission.swift`
- Modify: `VandaApp/VandaApp/App/ParentModeView.swift`
- Test: `VandaApp/VandaAppTests/NotificationPermissionTests.swift`

**Interfaces:**
- Consumes: `FamilyLinkModel`, `PushRegistrar`.
- Produces: `NotificationPermission` (`@Observable`), `var status: UNAuthorizationStatus`, `func refresh() async`, `func request() async`, `var needsAttention: Bool`, `static func settingsURL() -> URL?`.

- [ ] **Step 1: Írd meg a bukó tesztet**

Create `VandaApp/VandaAppTests/NotificationPermissionTests.swift`:

```swift
//
//  NotificationPermissionTests.swift
//  VandaAppTests
//
//  Az engedély-állapot értelmezésének tesztjei. Magát a rendszer-dialógust nem
//  teszteljük (az eszközös kör dolga) — csak azt, hogy mikor kell szólni.
//

import Foundation
import Testing
import UserNotifications
@testable import VandaApp

struct NotificationPermissionTests {

    @Test func authorizedNeedsNoAttention() {
        #expect(NotificationPermission.needsAttention(for: .authorized) == false)
    }

    @Test func provisionalNeedsNoAttention() {
        #expect(NotificationPermission.needsAttention(for: .provisional) == false)
    }

    @Test func notDeterminedNeedsAttention() {
        #expect(NotificationPermission.needsAttention(for: .notDetermined))
    }

    @Test func deniedNeedsAttention() {
        #expect(NotificationPermission.needsAttention(for: .denied))
    }

    @Test func onlyDeniedSendsYouToSettings() {
        #expect(NotificationPermission.requiresSettingsTrip(for: .denied))
        #expect(NotificationPermission.requiresSettingsTrip(for: .notDetermined) == false)
    }
}
```

- [ ] **Step 2: Futtasd, győződj meg róla, hogy nem fordul**

Run: az iOS teszt-parancs.
Expected: FAIL — `cannot find 'NotificationPermission' in scope`.

- [ ] **Step 3: `NotificationPermission`**

Create `VandaApp/VandaApp/Services/Backend/NotificationPermission.swift`:

```swift
//
//  NotificationPermission.swift
//  VandaApp
//
//  A szülő módban a push-engedély két úton kérhető: párosítás után azonnal,
//  és — ha hiányzik — egy tartósan látható gombbal. A rendszer csak egyszer
//  kérdez; ha már megtagadták, a Beállításokba kell vinni.
//

import Foundation
import Observation
import UIKit
import UserNotifications

@Observable
final class NotificationPermission {

    private(set) var status: UNAuthorizationStatus = .notDetermined

    static func needsAttention(for status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: return false
        default: return true
        }
    }

    /// A rendszer-dialógus csak `notDetermined` állapotban jelenik meg; utána
    /// már csak a Beállításokban lehet visszakapcsolni.
    static func requiresSettingsTrip(for status: UNAuthorizationStatus) -> Bool {
        status == .denied
    }

    var needsAttention: Bool { Self.needsAttention(for: status) }
    var requiresSettingsTrip: Bool { Self.requiresSettingsTrip(for: status) }

    static func settingsURL() -> URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
    }

    func request() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        await refresh()
    }
}
```

- [ ] **Step 4: Szülő mód képernyő**

Modify `VandaApp/VandaApp/App/ParentModeView.swift` — teljes csere:

```swift
//
//  ParentModeView.swift
//  VandaApp
//
//  Szülő mód: párosítás 6 jegyű kóddal, push-engedély, eszköznév.
//  A riasztások fogadása a 4.3-ban érkezik ide.
//

import SwiftUI
import UIKit

struct ParentModeView: View {
    @AppStorage("appRole") private var appRoleRaw: String = ""
    @State private var model = FamilyLinkModel()
    @State private var permission = NotificationPermission()
    @State private var enteredCode = ""
    @State private var deviceName = "Szülő telefonja"
    @State private var showUnlinkConfirm = false

    var body: some View {
        ZStack {
            Theme.BackgroundGradient.default.gradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.cardGap) {
                    if model.isLinked {
                        linkedSection
                    } else {
                        pairingSection
                    }

                    if let message = model.errorMessage {
                        Text(message)
                            .font(.vandaBody())
                            .foregroundStyle(Color.zoneRedStrong)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .vandaCard()
                    }

                    Button("Másik szerepet választok") { appRoleRaw = "" }
                        .font(.vandaBodyStrong(13))
                        .foregroundStyle(Color.inkMuted)
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.cardGap)
            }
        }
        .task { await permission.refresh() }
        .confirmationDialog(
            "Biztosan leválasztod ezt az eszközt?",
            isPresented: $showUnlinkConfirm,
            titleVisibility: .visible
        ) {
            Button("Igen, leválasztom", role: .destructive) {
                Task { await model.unlink() }
            }
            Button("Mégsem", role: .cancel) {}
        } message: {
            Text("Utána Vanda jelzései nem érkeznek meg ide.")
        }
    }

    // MARK: - Párosítás

    private var pairingSection: some View {
        VStack(spacing: Theme.Spacing.cardGap) {
            VStack(spacing: 8) {
                Text("🫶")
                    .font(.system(size: 48))
                Text("Párosítás Vandával")
                    .font(.vandaDisplay())
                    .foregroundStyle(Color.ink)
                Text("Kérj Vandától egy hat jegyű kódot a telefonján: Beállítások → Család → Szülő meghívása.")
                    .font(.vandaBody())
                    .foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .vandaCard()

            VStack(alignment: .leading, spacing: 10) {
                TextField("123456", text: $enteredCode)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)

                TextField("Eszköz neve", text: $deviceName)
                    .font(.vandaBody())

                Button("Csatlakozás") {
                    Task {
                        await model.joinWithCode(enteredCode, deviceName: deviceName)
                        // Párosítás után azonnal kérjük az engedélyt — ez a
                        // legjobb pillanat, mert itt derül ki, mire kell.
                        if model.isLinked, permission.status == .notDetermined {
                            await permission.request()
                        }
                        await PushRegistrar.shared.flush()
                    }
                }
                .font(.vandaBodyStrong())
                .disabled(enteredCode.count != 6 || model.isBusy)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vandaCard()
        }
    }

    // MARK: - Össze van kötve

    private var linkedSection: some View {
        VStack(spacing: Theme.Spacing.cardGap) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Össze vagytok kötve 💛")
                    .font(.vandaBodyStrong())
                    .foregroundStyle(Color.ink)
                Text("Vanda jelzései ide fognak érkezni.")
                    .font(.vandaCaption())
                    .foregroundStyle(Color.inkMuted)
                TextField("Eszköz neve", text: $deviceName)
                    .font(.vandaBody())
                    .onSubmit { Task { await model.rename(to: deviceName) } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vandaCard()

            if permission.needsAttention {
                permissionCard
            }

            Button("Összeköttetés bontása") { showUnlinkConfirm = true }
                .font(.vandaBodyStrong(13))
                .foregroundStyle(Color.inkMuted)
        }
        .onAppear { deviceName = model.credentials?.deviceName ?? deviceName }
    }

    private var permissionCard: some View {
        VStack(spacing: 10) {
            Text("Az értesítések ki vannak kapcsolva")
                .font(.vandaBodyStrong())
                .foregroundStyle(Color.ink)
            Text("Enélkül nem jelenik meg Vanda jelzése ezen a telefonon.")
                .font(.vandaCaption())
                .foregroundStyle(Color.inkMuted)
                .multilineTextAlignment(.center)

            Button(permission.requiresSettingsTrip ? "Beállítások megnyitása" : "Értesítések bekapcsolása") {
                Task {
                    if permission.requiresSettingsTrip {
                        if let url = NotificationPermission.settingsURL() {
                            await UIApplication.shared.open(url)
                        }
                    } else {
                        await permission.request()
                    }
                }
            }
            .font(.vandaBodyStrong())
        }
        .frame(maxWidth: .infinity)
        .vandaCard()
    }
}

#Preview {
    ParentModeView()
}
```

- [ ] **Step 5: Futtasd a teszteket és buildelj**

Run: az iOS teszt-parancs, majd a build-parancs.
Expected: PASS és BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add VandaApp/VandaApp/Services/Backend/NotificationPermission.swift VandaApp/VandaApp/App/ParentModeView.swift VandaApp/VandaAppTests/NotificationPermissionTests.swift
git commit -m "phase 4.2b: parent mode pairing with push permission prompt and fallback"
```

---

### Task 8: Teszt-push gomb eszközönkénti visszajelzéssel

**Files:**
- Modify: `VandaApp/VandaApp/Screens/Settings/FamilySettingsView.swift`
- Test: `VandaApp/VandaAppTests/TestPushSummaryTests.swift`
- Create: `VandaApp/VandaApp/Services/Backend/TestPushSummary.swift`
- Modify: `docs/decisions.md` (ha az implementáció közben eltértél a tervtől)

**Interfaces:**
- Consumes: `FamilyLinkModel.sendTestPush()`, `TestPushResult`.
- Produces: `TestPushSummary.text(for:)` — a `[TestPushResult]`-ból kedves magyar összefoglaló.

- [ ] **Step 1: Írd meg a bukó tesztet**

Create `VandaApp/VandaAppTests/TestPushSummaryTests.swift`:

```swift
//
//  TestPushSummaryTests.swift
//  VandaAppTests
//
//  A teszt-push összefoglalója. Elv (spec 5.): a riasztás soha ne vesszen el
//  csendben — a részleges kudarcot is ki kell mondani.
//

import Foundation
import Testing
@testable import VandaApp

struct TestPushSummaryTests {

    @Test func noParentsIsExplained() {
        #expect(TestPushSummary.text(for: []) ==
                "Még nincs párosított szülői készülék, ezért nem volt kinek szólni.")
    }

    @Test func allDeliveredIsCheerful() {
        let results = [
            TestPushResult(deviceId: "a", status: 200),
            TestPushResult(deviceId: "b", status: 200),
        ]
        #expect(TestPushSummary.text(for: results) == "Elment 2 készülékre 💛")
    }

    @Test func singleDeliveryUsesSingularWording() {
        #expect(TestPushSummary.text(for: [TestPushResult(deviceId: "a", status: 200)])
                == "Elment 1 készülékre 💛")
    }

    @Test func partialFailureIsNamedOutLoud() {
        let results = [
            TestPushResult(deviceId: "a", status: 200),
            TestPushResult(deviceId: "b", status: 0),
        ]
        #expect(TestPushSummary.text(for: results) ==
                "Elment 1 készülékre, 1 készüléknél viszont nem sikerült.")
    }

    @Test func totalFailureIsNamedOutLoud() {
        let results = [
            TestPushResult(deviceId: "a", status: 410),
            TestPushResult(deviceId: "b", status: 0),
        ]
        #expect(TestPushSummary.text(for: results) ==
                "Egyik készülékre sem sikerült elküldeni (2 próbálkozás).")
    }
}
```

- [ ] **Step 2: Futtasd, győződj meg róla, hogy nem fordul**

Run: az iOS teszt-parancs.
Expected: FAIL — `cannot find 'TestPushSummary' in scope`.

- [ ] **Step 3: Az összefoglaló**

Create `VandaApp/VandaApp/Services/Backend/TestPushSummary.swift`:

```swift
//
//  TestPushSummary.swift
//  VandaApp
//
//  A teszt-push eredményének kimondása. Részleges kudarcot is néven nevezünk:
//  a „riasztás soha ne vesszen el csendben" elvet (spec 5.) itt szoktatjuk a
//  felületbe, még a 4.3 éles riasztás előtt.
//

import Foundation

enum TestPushSummary {

    static func text(for results: [TestPushResult]) -> String {
        guard !results.isEmpty else {
            return "Még nincs párosított szülői készülék, ezért nem volt kinek szólni."
        }

        let delivered = results.filter(\.delivered).count
        let failed = results.count - delivered

        if failed == 0 {
            return "Elment \(delivered) készülékre 💛"
        }
        if delivered == 0 {
            return "Egyik készülékre sem sikerült elküldeni (\(results.count) próbálkozás)."
        }
        return "Elment \(delivered) készülékre, \(failed) készüléknél viszont nem sikerült."
    }
}
```

- [ ] **Step 4: A gomb a Család képernyőn**

Modify `VandaApp/VandaApp/Screens/Settings/FamilySettingsView.swift` — a `linkedSection` `actionRow(symbol: "ipad.and.iphone", ...)` blokkja **után**, az „Összeköttetés bontása" gomb **elé**:

```swift
            actionRow(symbol: "bell.badge", title: "Teszt-üzenet küldése") {
                Task { await model.sendTestPush() }
            }

            if let results = model.testPushResults {
                VStack(spacing: 6) {
                    Text(TestPushSummary.text(for: results))
                        .font(.vandaBody())
                        .foregroundStyle(results.contains(where: { !$0.delivered })
                                         ? Color.zoneOrangeStrong : Color.ink)
                        .multilineTextAlignment(.center)
                    if results.contains(where: { !$0.delivered }) {
                        Text("Ha nem jött meg, ellenőrizzétek, hogy a szülő telefonján be van-e kapcsolva az értesítés.")
                            .font(.vandaCaption())
                            .foregroundStyle(Color.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .vandaCard(surface: cardSurface)
            }
```

`Color.zoneOrangeStrong` a `Theme+Colors.swift:46` tokenje — a halványabb `zoneOrange` szövegként rosszul olvasható.

- [ ] **Step 5: Futtasd a teszteket és buildelj**

Run: az iOS teszt-parancs, majd a build-parancs.
Expected: PASS és BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add VandaApp/VandaApp/Services/Backend/TestPushSummary.swift VandaApp/VandaApp/Screens/Settings/FamilySettingsView.swift VandaApp/VandaAppTests/TestPushSummaryTests.swift
git commit -m "phase 4.2b: test push button with per-device delivery reporting"
```

- [ ] **Step 7: Döntési napló, ha eltértél**

Ha az implementáció közben bármiben eltértél ettől a tervtől (könyvtár, API-alak, elnevezés), írd be a `docs/decisions.md` tetejére egy `## 2026-07-19 — 4.2b implementáció: …` bejegyzésben, dátummal és rövid indoklással. Ha nem volt eltérés, ezt a lépést hagyd ki.

---

## Amikor a deploy megvan (Attila kézi köre után)

Ez a plan a deploy nélkül is végigvihető. Utána két lépés zárja a 4.2b-t:

1. `VandaApp/Config/Backend.xcconfig` → `BACKEND_HOST` a valódi workers.dev hosztra (séma nélkül).
2. Eszközös kör: párosítás iPhone ↔ szülői készülék; iPad mint második gyerek-eszköz; teszt-push megérkezése a szülő telefonjára; leválasztás és újrapárosítás.

Az APNs-hívás **csak deployolt Workerrel** működik (workerd HTTP/2-korlát, `backend/README.md`), tehát a teszt-push a szimulátorban a lokális `wrangler dev` ellen sem fog átmenni — ez várt viselkedés, nem hiba.
