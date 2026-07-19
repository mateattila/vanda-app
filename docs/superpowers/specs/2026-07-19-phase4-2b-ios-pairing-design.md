# 4.2b — iOS-oldal: párosítás, push-regisztráció, teszt-push: design

**Dátum:** 2026-07-19
**Státusz:** Jóváhagyva (Attila), implementációs terv készül
**Forrás:** `docs/superpowers/specs/2026-07-07-phase4-panic-backend-design.md` (4. fázis design), `docs/superpowers/plans/2026-07-10-phase4-2a-backend-tracer.md` (kész backend), `docs/spec/vanda-app-spec.md` 4.4 és 7. fejezet, `docs/design/design-tokens.md`

## Hatókör

A 4.2b három dolgot old meg az iOS-oldalon: **párosítás**, **APNs-token regisztráció**, **teszt-push**. A 4.2a-ban elkészült backend eddig kliens nélkül állt; ez a lépés köti be.

**Nem tartozik bele:** panik-riasztás küldése és fogadása (4.3), megosztási számok (4.4), escrow és recovery (4.5). A szülő mód ezekhez csak a helyet készíti elő.

**Előfeltétel, ami Attilára vár:** a Cloudflare-deploy és az APNs p8 kulcs (`backend/README.md` deploy-ellenőrzőlista). Enélkül a 4.2b implementálható és unit-tesztekkel igazolható, de eszközön nem zárható le. A Push Notifications capability **már megvan** (`aps-environment: development` az entitlementsben, `UIBackgroundModes: remote-notification` az Info.plistben) — a README 8. lépése tárgytalan.

## Eldöntött kérdések

- **Több gyerek-eszköz (iPhone + iPad):** a párosító kód **szerepet hordoz**. A `/pairing-codes` opcionális `role` mezőt kap (`parent` | `child`), a `/pair` a kód szerepe szerint hoz létre eszközt. Így az iPad ugyanazzal a 6 jegyű folyamattal lép be a családba, saját tokennel és saját APNs-tokennel. Az elvetett alternatívák: iCloud Keychainen megosztott közös token (a két eszköz felülírná egymás APNs-tokenjét, és a szerver nem tudná megkülönböztetni őket — adósság 4.3-ra), illetve az iPad kihagyása 4.2b-ből (a kérdés visszajönne 4.3-ban, és addig iPadről nem menne riasztás).
- **Backend URL:** xcconfig → Info.plist → futásidejű kiolvasás. Az érték **séma nélküli hoszt** (`BACKEND_HOST`), mert az xcconfig a `//`-t kommentkezdetnek tekinti; a `https://` előtagot a Swift oldal teszi hozzá. Az xcconfig **bekerül a gitbe**: a biztonság a bearer tokeneken áll, nem az URL rejtettségén (lásd `backend/README.md` biztonsági szakasza).
- **Belépési pont:** lusta párosítás. Első indításkor nincs hálózati hívás; a döntés a Beállítások → Család képernyőn születik („Család létrehozása" vs. „Kódot kaptam"). Így nem keletkezik árva család, ha valaki csak nézelődik, és az iPad sem hozhat létre véletlenül második családot.
- **Leválasztás:** új `DELETE /devices/me` végpont + helyi Keychain-törlés. Csak helyi törlés esetén árva eszköz-sor maradna élő APNs-tokennel, és a teszt-push (4.3-ban a riasztás) egy nem létező készüléknek próbálna küldeni.
- **Engedélykérés a szülő oldalán:** párosítás után azonnal, **és** ha az engedély hiányzik, tartósan látható gomb is kínálja. (A rendszer-dialógus egyszer kérdez; a gomb a Beállítások-hoz vezet, ha már megtagadták.)
- **Eszköznév:** szerkeszthető már 4.2b-ben.
- **Tesztelés élő backend nélkül:** `URLProtocol`-alapú mock a meglévő `VandaAppTests` targetben.

## 1. Backend-kiegészítés

Két apró változás a kész Workerhez:

**Szerep-hordozó párosító kódok.** Migráció: `pairing_codes` kap egy `role TEXT NOT NULL DEFAULT 'parent'` oszlopot — a meglévő sorok viselkedése nem változik. A `POST /pairing-codes` opcionális `role` mezőt fogad; ismeretlen érték 400. A `POST /pair` a kód `role` mezőjével hozza létre az eszközt a fix `'parent'` helyett. A `/test-pushes` továbbra is csak `role = 'parent'` eszközöket céloz — egy próba-jelzésnek épp a szülőkhöz kell megérkeznie.

**Eszköz-leválasztás.** `DELETE /devices/me` (bármelyik hitelesített eszköz): törli a saját sorát, 204. A kliens ezután üríti a Keychaint.

**Tesztek:** gyerek-kód gyerek-eszközt hoz létre; ismeretlen szerep 400; a `role` nélküli kérés továbbra is szülőt csinál (visszafelé kompatibilitás); a leválasztott eszköz tokenje 401-et kap, és nem szerepel többé a teszt-push címzettjei közt.

## 2. iOS-komponensek

Öt új, egy-egy tiszta felelősségű darab a `Services/Backend/` alatt. A tagolás célja, hogy mindegyik önmagában érthető és tesztelhető legyen.

**`BackendConfig`** — kiolvassa a `BACKEND_HOST` értékét az Info.plistből és `https://` előtaggal URL-t képez. Ha az érték hiányzik vagy még a placeholder, DEBUG buildben hangosan elhasal — a csendes 404-eknél sokkal jobb hibaüzenet.

**`DeviceCredentialStore`** — Keychain-tároló a `familyId` / `deviceId` / `token` / `role` / `deviceName` együttesnek, a meglévő `Services/Journal/KeyStore.swift` mintájára, `kSecAttrAccessibleAfterFirstUnlock` védelmi szinttel (a push-kezelés háttérben is futhat). **Eszköz-lokális, nem iCloud-szinkronizált:** a modellben minden eszköz saját identitás saját APNs-tokennel, a szinkronizált hitelesítés pont ezt rontaná el.

**`BackendClient`** — vékony async kliens injektálható `URLSession`-nel (ez teszi mockolhatóvá). Metódusok: család létrehozása, párosító kód kérése szereppel, kód beváltása, APNs-token feltöltése, saját eszköz lekérdezése, teszt-push küldése, eszköz leválasztása. A HTTP-státuszokat típusos hibákra képezi:

| Státusz | Hiba | Felhasználói üzenet iránya |
|---|---|---|
| 404 | `unknownCode` | „Ilyen kódot nem találunk — elgépeltük?" |
| 410 | `codeExpiredOrUsed` | „Ez a kód lejárt vagy már felhasználták — kérj újat." |
| 401 | `unauthorized` | „Megszakadt az összeköttetés — párosíts újra." |
| egyéb 4xx/5xx | `server(status)` | általános, újrapróbálható hiba |
| hálózati | `transport(Error)` | „Most nincs net — próbáld újra." |

**`PushRegistrar` + `AppDelegate`** — `UIApplicationDelegateAdaptor`-ral bevezetett app delegate veszi át az APNs device-tokent (a projektben eddig nem volt delegate; a helyi notificationök `UNUserNotificationCenter`-rel mennek). A regisztráció minden indításkor lefut, a feltöltés viszont csak akkor, ha a token eltér a legutóbb feltöltöttől. Ha a token azelőtt érkezik meg, hogy párosítás lenne, a registrar elteszi, és a hitelesítés mentésekor küldi fel — a két esemény bármilyen sorrendben történhet.

**`FamilyLinkModel`** (`@Observable`) — a párosítási állapotgép (`unlinked` / `linking` / `linked(role:)` / `failed`), amit a gyerek- és a szülő-felület egyaránt fogyaszt.

**Idempotencia:** a család-létrehozás és a kód-beváltás folyamatban-jelzővel védett, és ha már van mentett hitelesítés, elutasítja magát — a dupla koppintás vagy a timeout utáni újrapróbálás így nem hoz létre árva családot.

## 3. Felületek

**Vanda oldalán** új `Screens/Settings/FamilySettingsView.swift`, a `SettingsView`-ból elérhetően.

- *Nincs összekötve:* két gomb — „Család létrehozása" és „Kódot kaptam".
- *Össze van kötve:* látszik a szerep és a szerkeszthető eszköznév; „Szülő meghívása" (szülő-kód) és „Másik eszközöm hozzáadása" (gyerek-kód) — mindkettő ugyanazt a kód-lapot nyitja, nagy, jól olvasható hat számjeggyel és visszaszámlálóval a 10 perces lejáratig, újrakérés gombbal. Legalul „Teszt-üzenet küldése" és „Összeköttetés bontása".

**Szülő oldalán** a mostani `ParentModeView` stub helyére kódbeviteli képernyő kerül. Sikeres párosítás után egy mondatos indoklás, majd a rendszer engedélykérése; ha az engedély hiányzik (megtagadták vagy elhalasztották), a képernyőn tartósan ott marad egy gomb, ami újrakéri vagy a Beállításokba visz. Alatta kártya, hogy Vanda jelzései ide fognak érkezni (4.3), és a szerkeszthető eszköznév + leválasztás.

Vanda oldalán nincs engedélykérés: a remote notification **regisztráció** nem igényel engedélyt, csak a megjelenítés — azt pedig az emlékeztetők miatt már megadta.

Minden szöveg a `Theme` tokenjeiből épül, a hangnem kedves és tegező (spec 1. fejezet).

## 4. Hibakezelés

A teszt-push az egyetlen hely, ahol elvi tétje van a hibakezelésnek: a backend eszközönkénti státuszt ad vissza, és a UI is eszközönként mutatja — „2 készülékre ment el", vagy ha valamelyik elbukott, azt külön, kedvesen kiírja. Ez ugyanaz az elv, amit a backendnél is érvényesítettünk (spec 5. fejezet: a riasztás soha ne vesszen el csendben), és itt szoktatjuk hozzá a felületet a 4.3-ra. Offline esetben nincs néma nyelés: látható hibaüzenet és újrapróba-gomb mindenütt.

## 5. Tesztelés

`VandaAppTests`-be `URLProtocol`-alapú stub kerül, ami élő backend nélkül fedi le:

- a státuszkód → típusos hiba leképezést (404 / 410 / 401 / 5xx / hálózati),
- a `DeviceCredentialStore` mentés–olvasás–törlés körét,
- az APNs-token „várakozik, majd párosításkor felmegy" viselkedését, és hogy változatlan token nem generál felesleges feltöltést,
- a párosító kód lejárat-visszaszámlálását,
- az idempotencia-őrt (mentett hitelesítés mellett nincs újabb család-létrehozás).

Backend oldalon a fenti négy-öt új vitest eset. Eszközön (a deploy után): párosítás iPhone ↔ szülői készülék, iPad mint második gyerek-eszköz, teszt-push megérkezése, leválasztás.

## 6. Lépéssorrend (minden lépés önállóan buildel)

1. Backend: szerep-hordozó párosító kódok + `DELETE /devices/me` + tesztek.
2. xcconfig + Info.plist kulcs + `BackendConfig` + `DeviceCredentialStore` + tesztek.
3. `BackendClient` + hiba-leképezés + tesztek.
4. App delegate + `PushRegistrar` + várakozó-token logika + tesztek.
5. Vanda Család képernyője (létrehozás, csatlakozás, kód-lap, eszköznév).
6. Szülő párosítás + engedélykérés (azonnali és gombos út) + leválasztás.
7. Teszt-push gomb eszközönkénti visszajelzéssel.

## Nem célok (4.2b)

- QR-párosítás (a 6 jegyű kód fölé később építhető).
- Panik-riasztás küldése/fogadása — 4.3.
- Megosztási számok és escrow — 4.4, 4.5.
- Rate limiting a backenden (tudatos hiány, lásd `backend/README.md`).
