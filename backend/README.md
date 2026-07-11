# Vanda Backend

Minimál Cloudflare Workers backend (TypeScript + Hono, D1) az iOS Vanda apphoz.

## API-végpontok

| Végpont | HTTP | Ki hívhatja | Mit ad vissza |
|---------|------|-------------|---------------|
| `/health` | GET | Nyilvános | `{ ok: true }` |
| `/families` | POST | Nyilvános (első eszköz-regisztráció) | `{ familyId, deviceId, token }` |
| `/me` | GET | Bármelyik eszköz (Bearer token) | `{ deviceId, familyId, role, name, hasApnsToken }` |
| `/pairing-codes` | POST | Gyerek eszköz | `{ code, expiresAt }` — 6 jegyű, 10 perc TTL (`expiresAt`: ezredmásodperces epoch timestamp) |
| `/pair` | POST | Nyilvános (szülő párosítás) | `{ familyId, deviceId, token }` |
| `/devices/me/apns-token` | PUT | Bármelyik eszköz | 204 No Content |
| `/test-pushes` | POST | Gyerek eszköz | `{ results: [{ deviceId, status }] }` — APNs teszt szülőknek |

## Helyi fejlesztés

```bash
npm install          # Függőségek telepítése
npm run dev          # Wrangler dev szerver
npm test             # Vitest, 26 teszt
npm run check        # TypeScript statikus analízis (src)
npm run check:test   # TypeScript statikus analízis (src + test)
npm run deploy       # Cloudflare Workers deploy
```

## Deploy (kézi lépések, egyszer)

1. `npx wrangler login` — Cloudflare-fiók összekötése (böngészős)
2. `npx wrangler d1 create vanda` — a kapott `database_id`-t írd be a `wrangler.jsonc`-ba
3. `npx wrangler d1 migrations apply vanda --remote`
4. Apple Developer portál → Keys → új kulcs APNs-szel → töltsd le a `.p8`-at,
   jegyezd fel a Key ID-t; a Team ID a Membership oldalon
5. Secretek:
   - `npx wrangler secret put APNS_TEAM_ID`
   - `npx wrangler secret put APNS_KEY_ID`
   - `npx wrangler secret put APNS_PRIVATE_KEY < AuthKey_XXXXXX.p8`  ← a .p8 fájl teljes PEM-tartalma

   **Figyelem:** az `APNS_PRIVATE_KEY` több soros — az interaktív `wrangler secret put`
   (beillesztés a terminálba) csak az első sort kapja el, a kulcs csendben csonkul.
   A fájlt kötelező bemenetként átirányítani (`< AuthKey_XXXXXX.p8`), nem beilleszteni.
6. `npx wrangler deploy` — jegyezd fel a workers.dev URL-t (a 4.2b iOS-kliens ezt kapja)
7. Ellenőrzés: `curl https://<worker-url>/health` → várt válasz `{"ok":true}`.
   Ha ez megvan, a deploy jó, mehet a következő lépés eszközön.
8. Xcode: VandaApp target → Signing & Capabilities → + Push Notifications
   (a Time Sensitive a 4.3-ban jön)

**APNS_HOST:** Xcode-ról telepített (development) buildhez a sandbox host kell
(ez az alapértelmezés a wrangler.jsonc-ban). TestFlight/App Store buildhez:
`https://api.push.apple.com`.

**Fontos:** az APNs-hívás lokális `wrangler dev`-ből macOS-en nem működik
(HTTP/2-korlát, workerd #4841) — a push-próba csak deployolt Workerrel megy.

## Biztonsági megközelítés

Ez egy családi app, nem publikus szolgáltatás: a workers.dev URL nem hirdetett,
és szándékosan nincs rate limiting. A `POST /pair` végpont hitelesítés nélküli —
a 6 jegyű párosítási kód elméletileg brute-force-olható, de csak addig, amíg a
kód érvényes (10 perces TTL), utána a próbálkozás értelmetlenné válik. Ezt v1-re
elfogadott kockázatnak tekintjük. Ha az app több családhoz vagy publikus URL-hez
kerülne, a `/pair` és `/pairing-codes` végpontokra rate limitinget kell bevezetni.
