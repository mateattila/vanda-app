# 4. fázis — Panikgomb és backend: design

**Dátum:** 2026-07-07
**Státusz:** Jóváhagyva (Attila), implementációs terv készül
**Forrás:** `docs/spec/vanda-app-spec.md` 4.4, 5., 7. fejezet (4. fázis); `docs/design/design-tokens.md` (panik-képernyő)

## Eldöntött kérdések

- **Backend-stack:** Cloudflare Workers (TypeScript + Hono), D1 a strukturált adatnak, R2 az escrow-bloboknak. Zéró üzemeltetés, ingyenes tier, mindig ébren.
- **Párosítás:** 6 jegyű, rövid élettartamú kód (nem QR) — a legkevesebb mozgó alkatrész.
- **APNs setup:** a Push Notifications capability (Xcode) és a p8 auth kulcs (developer.apple.com) Attila kézi lépése, ahogy a CloudKit-nél; a p8 wrangler secretként kerül a Workerbe.
- **Push-besorolás:** time-sensitive (sima entitlementtel megy); critical alert (külön Apple-jóváhagyás) nem része a v1-nek.

## 1. Backend (`backend/`)

Cloudflare Worker, TypeScript + Hono. Deploy wrangler-rel `*.workers.dev` URL-re (HTTPS adott). A panik-események 30 nap után cron-triggerrel törlődnek (spec 6. fejezet, adatminimalizálás).

**Tárolás:**
- **D1:** családok, eszközök (token-hash, szerep, APNs device token), párosító kódok, panik-események, megosztási számok, escrow-metaadat, audit-események.
- **R2:** escrow-blobok (a titkosított fotók miatt MB-os méret is lehet).

**Hitelesítés:** párosításból származó, eszközönkénti bearer token (256 bit véletlen, D1-ben hashelve), szereppel (child/parent). Minden endpoint family-scoped — most egy család, de a modell nem zárja ki a többcsaládos jövőt (spec 8./nyitott kérdések).

**Endpointok:**

| Terület | Endpoint | Ki |
|---|---|---|
| Párosítás | `POST /families` (család létrehozása, child token vissza) | child |
| | `POST /pairing-codes` (6 jegyű kód, 10 perc TTL) | child |
| | `POST /pair` (kód beváltása → parent token) | parent |
| | `PUT /devices/me/apns-token` | mindkettő |
| Panik | `POST /panic-events` (szint + opcionális üzenet → APNs push minden szülő-eszközre; a válasz kézbesítési státuszt ad) | child |
| | `GET /panic-events` | parent |
| Megosztás | `POST /shares` (napi aksi% / zóna / progress%) | child |
| | `GET /shares/today` | parent |
| Escrow | `POST /escrow/entries` (append-only titkosított blob) | child |
| | `GET /escrow/entries` (recovery-letöltés → **visszavonhatatlan audit-esemény**) | parent |
| | `GET /audit-events` (Vanda appja innen szinkronizálja a felnyitás-bannert) | child |

**APNs:** közvetlen HTTP/2 hívás `api.push.apple.com` felé, p8 kulcsból generált ES256 JWT-vel. `apns-push-type: alert`, `apns-priority: 10`, `interruption-level: time-sensitive`. Az első backend-lépés tracer bullet: párosítás + egy teszt-push end-to-end, valódi eszközre — mielőtt bármi ráépül, bizonyítjuk a Workers→APNs utat.

**Adatminimalizálás (spec 1. és 5. fejezet):** olvasható naplótartalom soha nem megy át a backenden; nevek helyett szerepek/becenevek; a megosztási rekordok csak számokat tartalmaznak.

## 2. Panikgomb, 1. szint (backend nélkül)

A `PanicPlaceholderView` helyére az igazi panik-képernyő (design-tokens: saját, sötétebb környezet, lélegző kör ~3 mp-es lüktetéssel): érzés-chipek + szabad szöveg, alatta a helyzethez illő eszközök. Az eszközök **modul-protokoll** mögött (spec: „Az eszközkészlet modulrendszer, később bővítjük"):

- vezetett légzés (box breathing / 4-7-8, táguló-szűkülő kör),
- 5-4-3-2-1 grounding, lépésenként vezetve,
- nyugi-mappa: Vanda által válogatott képek (PhotosPicker, lokális tárolás),
- a tevékenység-katalógus NYUGI-címkés elemei,
- „Hívd anyát / apát": `facetime://` / `facetime-audio://` / `tel:` linkek; a szülők elérhetőségei kis, CloudKit-szinkronizált beállítás-modellben.

Ez a lépés backend nélkül teljes értékű és Vandával azonnal tesztelhető.

## 3. Panikgomb, 2. szint + szülő mód

- „📣 Szólok anyáéknak" gomb megerősítéssel + opcionális rövid üzenettel → `POST /panic-events`. Kísérőszöveg a design-tokens szerint: „Te döntöd el. Nem muszáj."
- **Kézbesítés-visszajelzés:** siker esetén kedves nyugtázás; bizonytalan/sikertelen küldésnél az app azonnal a hívás/FaceTime alternatívát ajánlja — a riasztás sosem vész el csendben (spec 5. fejezet, megbízhatóság).
- Nincs automatikus/rejtett riasztás; a hosszú nyomásos SOS nem része a v1-nek (spec: alapból kikapcsolva, később megbeszélendő).

**Szülő mód** (a mostani `ParentModeView` stub helyén): párosítás 6 jegyű kóddal, riasztás-lista, megosztott aksi%/progress% nézet, recovery-funkció (escrow-blobok letöltése + a recovery-kulccsal **helyi** visszafejtés, a 3. fázis kriptó-rétegének újrahasznosításával — a kulcs a szerverre nem kerül).

## 4. Megosztás és escrow élesítése

- A `MoodSettings` megosztás-kapcsolói élesednek: bekapcsolva a napi aksi%/zóna/progress% felkerül a backendre (app-nyitáskor / kitöltéskor, best-effort újrapróbálással). Szöveges válaszok soha.
- Escrow: minden napló-mentés után a titkosított blob append-only feltöltése, offline-tűrő újrapróbáló sorral. A recovery-letöltés szerver-oldali audit-eseménye visszaszinkronizál Vanda appjába → a 3. fázis felnyitás-bannere ezt is mutatja.

## 5. Lépéssorrend (minden lépés önállóan buildel)

1. **4.1** Panik 1. szint: eszközmodulok, backend nélkül.
2. **4.2** Backend tracer: Worker-váz + család/párosítás + APNs teszt-push valódi eszközre. *(Itt esedékesek Attila kézi lépései: push capability, p8 kulcs.)*
3. **4.3** Panik 2. szint riasztás + szülő-módú fogadás + kézbesítés-visszajelzés.
4. **4.4** Megosztási számok (küldés + szülő-nézet).
5. **4.5** Escrow-feltöltés + recovery + audit-banner.

## Tesztelés

- **Worker:** vitest — párosítás/token-logika, APNs JWT-generálás, escrow append-only és audit-invariánsok (a kriptóhoz kapcsolódó részek itt sem mennek „működik, jó lesz" alapon).
- **iOS:** unit teszt az API-kliensre és az escrow újrapróbáló sorra; a meglévő 22 kriptó-teszt marad a recovery-út fedezete.
- **Eszközön:** push-kézbesítés, párosítás, panik-folyamat end-to-end két eszközzel (Vanda + szülő).

## Nem célok (v1)

- QR-párosítás (később ráér, a 6 jegyű kód fölé építhető).
- Critical alert besorolás (Apple-jóváhagyást igényel).
- Hosszú nyomásos azonnali SOS.
- AI a panik-folyamatban (spec, explicit non-goal).
