# Vanda App — Specifikáció

**Verzió:** 1.3 (2026-07-07)
**Státusz:** Fejlesztésre kész, fázisokra bontva
**Cél:** Ez a dokumentum a Claude Code-dal folytatott fejlesztés referenciája. Minden fázis önállóan leszállítható.

---

## 1. Áttekintés

Személyes segítő app Vandának (iPhone + iPad, szinkronban): ébresztő, emlékeztetők, hangulatkövetés, panikgomb, titkosított napló, napi visszajelzés és tevékenység-ötletek. Az appot a család közösen tervezte; hosszabb távon más családoknak is átadható lehet.

### Alapelvek (minden funkcióra kötelezőek)

1. **Bizalom mint feature.** A napló kizárólag Vandáé; a szülői hozzáférés csak vészhelyzeti, és technikailag garantáltan nyomot hagy ("pecsétes zár"). Nincs rejtett megfigyelés.
2. **Segítség, nem teljesítménykényszer.** Nincs streak, nincs pontverseny, nincs bűntudat-mechanika. A napi visszajelzés semleges hangvételű; minden nap tiszta lap.
3. **Vanda kontrollál.** Az eszkaláció (szülők riasztása) Vanda döntése. A tartalmak (emlékeztető-szövegek, tevékenységlisták, nyugi-mappa) az ő szavaival, az ő ízlésére szabhatók.
4. **Adatminimalizálás.** A szerverre csak az kerül, ami az adott funkcióhoz elengedhetetlen: panik-metaadat, titkosított napló-escrow, és — ha Vanda bekapcsolta — a megosztott számok (aksi%, progress%). **Olvasható naplótartalom soha nem hagyja el az eszközöket**; az eszközök közti szinkron (CloudKit) Vanda saját iCloudjában történik.
5. **Kedves, játékos hangnem.** "Touch grass!", "Go feed the sheep!" — az app Vanda humorát beszéli, nem egy komor felnőtt-appét.

---

## 2. Platform és technológia

| Terület | Döntés | Megjegyzés |
|---|---|---|
| Eszköz | iPhone 16 Pro (elsődleges), friss iPad (másodlagos) | iOS 26+ a minimum target |
| Nyelv / UI | Swift + SwiftUI | |
| Ébresztő | **AlarmKit** (iOS 26+) | Rendszerszintű alarmok, Lock Screen / Dynamic Island |
| Emlékeztetők | UserNotifications (lokális) | Notification actionökkel |
| Perzisztencia + szinkron | SwiftData + CloudKit (privát adatbázis) | iPhone ↔ iPad automatikus szinkron Vanda iCloudjában |
| Napló-titkosítás | CryptoKit (AES-GCM), kulcsderiválás PIN-ből, Keychain (iCloud Keychain szinkronnal) | Részletek: 4.5 és 6. fejezet |
| Backend | Minimális saját szerver + APNs push | Panik-riasztás, napló-escrow, megosztás; részletek: 5. fejezet |
| Fotók | Lokális tárolás az app konténerében, titkosítva | CloudKit/escrow felé is csak titkosítva |
| Megjelenés | Testreszabható témák + alsó tab bar | Részletek: 2.1 |
| AI (későbbi fázis) | Apple Foundation Models (on-device); felhő-API csak szűk, jóváhagyásos esetekben | Részletek: 9. fejezet, 5. fázis |

### Szerepek

Ugyanaz az app két módban fut, első indításkor választva:

- **Gyerek mód** (Vanda telefonja/iPadje): minden funkció.
- **Szülő mód** (anya/apa telefonja): panik-riasztások fogadása, család-párosítás kezelése. Nem lát naplót, barométert, progresst.

A párosítás egyszeri QR-kóddal vagy 6 jegyű kóddal történik, a backend köti össze a családot.

### 2.1 Megjelenés és navigáció

- **Alsó tab bar** a fő funkciókkal (Vanda kérése), a design-körben véglegesítve: **Ma** (napi progress + aksi-gyorskitöltés) · **Ébresztő** · **Napló** · **Unatkozom** — 4 fül. A **Panik nem fül**, hanem kiemelt, visszafogottan lüktető gomb a Ma képernyő fejlécében (vizuális részletek: `docs/design/design-tokens.md`). Mivel a Ma az induló fül, a panikgomb app-nyitásból 1 érintésre van.
- Az emlékeztetők kezelése a Ma fülről nyílik; a beállítások a Ma fejlécének fogaskerék-ikonjáról (Beállítások › Kinézet: háttér + kiemelőszín, megosztás-kapcsolók).
- **Testreszabás:** Vanda saját háttérképet (fotóból) és kiemelőszínt választhat — első körben globálisan, később akár képernyőnként (`ThemeSettings`). A gyári témák mellett a "sajátot csinálok" út az elsődleges. Fotó-háttérnél olvashatósági overlay + áttetsző kártyák (design-tokens 2. fejezet).

---

## 3. Adatmodell (magas szint)

```
Family (backend): id, tagok (device tokenek, szerep)
AlarmProfile: id, név, ütemezés, hangfájl, láncbeállítás, feladvány-típus/nehézség
Reminder: id, forrás (gyári/saját), szöveg, emoji/ikon, szín, ütemezés, visszajelzés-e
ReminderLog: reminderId, dátum, státusz (kész/kihagyva)
MoodEntry: dátumidő, aksiSzázalék, zóna, [opcionális kérdés-válasz párok]
Question: id, szöveg, szint (1=könnyű … 3=mély), aktív-e, forrás (gyári/saját/AI-jóváhagyott)
Activity: id, cím, kategóriacímkék (bent/kint, egyedül/tesóval, időigény, TÖLTŐ, NYUGI), forrás
JournalEntry: dátumidő, titkosított blob (szöveg + sablonválaszok + fotóhivatkozások), hash-lánc mező
JournalAuditEvent: dátumidő, esemény (recovery-nyitás), visszavonhatatlan
DailyTask: dátum, cím, forrás (előre beírt / Vanda aznapi), státusz
JournalTemplate: id, név, kérdések [szöveg + válaszopciók/skála], aktív-e
ThemeSettings: háttérkép, kiemelőszín, hatókör (globális / képernyőnkénti)
PanicEvent (backend, minimál): családId, dátumidő, szint, [opcionális rövid üzenet]
```

**Szinkron-hatókörök:** a modellek CloudKiten szinkronizálódnak Vanda eszközei (iPhone + iPad) közt, a privát iCloud adatbázisában. A `JournalEntry` mindenhol csak titkosított blobként létezik; a `PanicEvent` és a napló-escrow a saját backendre megy; a megosztási számok (aksi%, progress%) szintén a backenden át jutnak a szülő módba.

A **tevékenység-katalógus** (`Activity`) közös háttere három nézetnek: unatkozó fal, "töltő tevékenységek" (barométer ajánlja), "nyugi-eszközök" (panikgomb ajánlja). Egy elem több címkét is kaphat.

---

## 4. Funkciók részletesen

### 4.1 Ébresztőóra

**Cél:** bármilyen (lokálisan tárolt) zenével induló ébresztő, amit nehéz kikapcsolni.

**Működés:**
- AlarmKit-alapú, ismétlődő ütemezéssel (pl. hétköznap 6:45).
- **Lánc-ébresztő:** egy "ébresztés" valójában N darab alarm (alapértelmezés: 5 db, 2 percenként). A hátralévő alarmok csak akkor törlődnek, ha Vanda az appban teljesítette a kikapcsoló feladványt. Ha csak lecsapja a rendszer-alarmot, 2 perc múlva jön a következő.
- **Kikapcsoló feladvány (v1):** egyszerű matekpélda — szorzótábla-szintű (pl. 7 × 8), beállítható nehézséggel és darabszámmal (pl. 3 jó válasz kell). A feladvány-modul cserélhető interfész mögött legyen (protokoll), mert később iterálunk rajta (gépelés, rázás stb.).
- **Zenetár:** külön képernyő, ahová Files appból importálhatók hangfájlok, vagy az appban rögzíthető hangfelvétel (pl. családtag hangja). Az app a fájlt a szükséges formátumra konvertálja és a `Library/Sounds` mappába teszi.

**Ismert platform-korlátok (dokumentálva, nem bug):**
- Csak lokális hangfájl játszható le; Apple Music (DRM) stream nem.
- A rendszer alarm-UI-án mindig lesz stop-vezérlő (iOS 26.1+: slider), és az egyszerű elhúzás nem detektálható — ezt kompenzálja a lánc-ébresztő.
- Countdown-megjelenítéshez widget extension (Live Activity) szükséges.
- Az alarm-viselkedést **valódi eszközön** kell tesztelni, a szimulátor megbízhatatlan (hang, Dynamic Island).

### 4.2 Emlékeztetők (gyári + saját, egy rendszerben)

**Cél:** kedves, testreszabható emlékeztetők bármilyen témában.

**Működés:**
- **Gyári csomag** (ki-be kapcsolható, szövege átírható): vitamin, reggeli pohár víz, fogmosás, "ettél?", "ittál?", "kimentél már ma? touch grass!", "go feed the sheep!".
- **Saját emlékeztetők:** cím, saját szöveg, emoji/ikon (SF Symbols + emoji picker), szín, ütemezés (napi/heti/egyedi időpontok).
- Lokális notificationök, **nem** agresszívek (nem AlarmKit).
- **Visszajelzés-hurok:** a notificationön action gomb ("✓ kész"), aminek eredménye a Napi progress falba folyik (`ReminderLog`). Emlékeztetőnként kapcsolható, hogy kér-e visszajelzést.
- Vizuális elem: v1-ben szín + emoji/SF Symbol; későbbi fázisban Lottie-animációk.

### 4.3 Hangulatbarométer

**Cél:** könnyű, gyors önreflexió + azonnali "töltő" visszacsatolás, mielőtt Vanda lemerítené magát.

**Működés:**
- **Alap-interakció:** "Hány százalékos az aksid?" — csúszka aksi-ikonnal, 0–100%. 5 másodperc alatt megválaszolható.
- **Zónák:** zöld (pl. 60–100%), narancs (30–60%), piros (0–30%). A határok beállításban módosíthatók.
- **Biofeedback-hurok:** narancs vagy piros zóna esetén az app azonnal 2–3 **töltő tevékenységet** ajánl a tevékenység-katalógus TÖLTŐ címkéjű elemeiből ("Mit szólnál ehhez, mielőtt tovább merülnél?"). Nem kötelező elfogadni; ha elfogad egyet, az bekerül a napi falba.
- **Kérdésbank (opcionális réteg):** az aksi% után felajánlható 1 kérdés a forgó bankból. Többszintű: 1. szint könnyű ("mire gondoltál az elmúlt 5 percben?"), 3. szint mély ("mit szeretnél, úgy igazán?"). Mindig átugorható; a szint aránya beállítható.
- **Időzítés:** napi 1–2 rákérdezés, véletlenszerű időpontban egy beállított idősávon belül (pl. 15:00–19:00), plusz bármikor kézzel is kitölthető.
- **Adatkezelés és megosztás:** az adat Vanda eszközei közt CloudKittel szinkronizálódik, nem PIN-védett. Vanda eddigi jelzése szerint csak a naplót tartja magának — a hangulatot/haladást szívesen mutatja. Ezért van **kapcsolható szülői megosztás**: bekapcsolva a napi aksi% és a zóna (a kérdésekre adott válaszok NEM) megjelenik a szülő módban, a backenden át. Az alapértelmezés (be/ki) Vandával megbeszélendő; a kapcsoló az ő beállításai közt van. Trend-nézet (heti/havi grafikon) Vandának, saját képernyőn.

### 4.4 Panikgomb

**Cél:** rossz pillanatban azonnal elérhető segítség, két szinten; a szülők riasztása Vanda döntése.

**Működés:**
- A panikgomb kiemelt, visszafogottan lüktető gomb a Ma képernyő fejlécében (nem tab-fül — a design-körben eldöntve). A Ma az induló fül, így app-nyitásból 1 érintésre elérhető; a lüktetés a design-tokens 6. fejezete szerinti finom, ~3 mp-es ciklus.
- **1. szint — eszközök:** megnyomás után Vanda pár szóval/emoji-val jelezheti, mi van ("félek", "dühös vagyok", "nem tudok megnyugodni" — előre definiált chipek + szabad szöveg). Az app a helyzethez illő eszközöket ajánl:
  - vezetett légzés-animáció (box breathing / 4-7-8, táguló-szűkülő kör),
  - 5-4-3-2-1 grounding gyakorlat (lépésenként vezetve),
  - **nyugi-mappa:** Vanda által összeválogatott képek/zenék,
  - a tevékenység-katalógus NYUGI címkéjű elemei,
  - **"Hívd anyát / apát"** gomb: FaceTime deep link (`facetime://` / `facetime-audio://`) vagy telefonhívás.
  - Az eszközkészlet modulrendszer (protokoll mögött), később bővítjük.
- **2. szint — riasztás:** külön, egyértelmű gomb ("Szólok anyáéknak"), megerősítéssel. Push értesítést küld a szülő módú eszközökre a backenden át, opcionális rövid üzenettel. A push time-sensitive, hogy Fókusz módban is átjöjjön.
- Nincs automatikus/rejtett riasztás. (Opcionális, később megbeszélendő kapcsoló: hosszú nyomásos azonnali SOS — alapból kikapcsolva.)

### 4.5 Napló + fotó ("pecsétes zár")

**Cél:** Vanda privát naplója, valódi titkosítással; szülői vészhelyzeti hozzáférés, ami garantáltan látható nyomot hagy.

**Bejegyzés:** szabad szöveg és/vagy sablon és/vagy fotók. A **sablon** n darab egyszerű, választós kérdés (chipek, skálák, emoji-választók — nem kifejtős), pl. hangulatnapló: "Milyen volt a napod? 😞…😄", "Mi dobott fel? [család / barátok / állatok / alkotás / …]". A sablonok szerkeszthetők (`JournalTemplate`), egy kitöltés fél perc — nem kell mindig mindent újraírni. **Későbbi kiegészítés:** kifejtős válasz diktálással (on-device Speech framework, a hangfelvétel nem megy hálózatra). Fotó-prompt: az app időnként felajánlja ("tölts fel egy fotót a napodról"), de bármikor kézzel is mehet. Az aznapi aksi% opcionálisan hozzácsatolható.

**Zárás és titkosítás:**
- A napló megnyitása Vanda saját PIN-kódjával történik, amit a szülők sem ismernek.
- A tartalom (szöveg + fotók) AES-GCM titkosítással tárolódik. A tartalomkulcsot két "boríték" védi:
  1. **Vanda útja:** a PIN-ből deriválunk kulcsot, ez nyitja a tartalomkulcsot.
  2. **Recovery-út (a pecsét):** a beállításkor generált recovery-kulcs, amit az app **egyszer** jelenít meg. Ezt kinyomtatva/leírva **lezárt borítékba** teszitek — a fizikai boríték maga a pecsét.
- **Felnyitás-jelzés (tamper-evidence):** ha a naplót a recovery-kulccsal nyitja meg bárki, az app visszavonhatatlan `JournalAuditEvent`-et rögzít, és Vanda a következő megnyitáskor feltűnő bannert lát: "A naplódat [dátum]-kor recovery-kulccsal nyitották meg." A bejegyzések hash-láncoltak (minden bejegyzés tartalmazza az előző hash-ét), így egy korábbi állapot visszaállítása is észrevehető.
- **Elfelejtett PIN:** ugyanez a recovery-út oldja meg — Vanda tudja, hogy a zár kinyílt, nem történik semmi a háta mögött.
- **Eszköz nélküli hozzáférés (escrow):** a titkosított bejegyzések append-only másolata a saját backendre is feltöltődik. Vészhelyzetben (pl. az eszköz nem elérhető) a szülő mód recovery-funkciója letölti a blobokat, és a borítékból elővett recovery-kulccsal **helyben** visszafejti (a kulcs a szerverre nem kerül). A szerver a recovery-letöltésről visszavonhatatlan audit-eseményt rögzít, ami Vanda appjába is visszaszinkronizál (banner) — a pecsét eszköz nélkül is nyomot hagy.
- **Őszinte korlát (a specben is dokumentálandó, a családi megállapodás része):** digitálisan tökéletes pecsét nem létezik olyan féllel szemben, aki a teljes eszközt és rendszert birtokolja. A boríték + digitális felnyitási napló kombináció a *családi bizalmi megállapodás* technikai megerősítése — ez a fenyegetésmodell, nem több.
- Naplótartalom **olvasható formában** soha nem kerül hálózatra. Titkosított blobként két helyre szinkronizálódik: CloudKit (Vanda eszközei közti szinkron) és a backend-escrow. A kulcsok az iCloud Keychainben szinkronizálódnak Vanda eszközei közt; szerverre soha nem kerülnek.

### 4.6 Napi progress

**Cél:** kedves napi visszajelzés — segítség, nem teljesítménymérés.

**Működés:**
- "Mai nap" fal: az emlékeztetőkből érkező pipák (`ReminderLog`) + Vanda saját, aznapra felvett teendői (`DailyTask`).
- Vizuális visszajelzés: **töltődő aksi** — "a napod 70%-on van" (szándékosan rímel a barométerre).
- Éjfélkor tiszta lap. Nincs streak, nincs múltbeli "elrontott napok" nézet, nincs negatív üzenet — 30%-os napnál is semleges/kedves a hangnem.
- A befejezett töltő/nyugi tevékenységek is ide pipálódnak.
- **Megosztás (kapcsolható):** ha Vanda engedélyezi, a napi összesített % a szülő módban is látszik — csak a szám, nem a tételes lista. Alapértelmezés Vandával megbeszélendő, a barométer-megosztással együtt.

### 4.7 Unatkozó lista

**Cél:** "mit csináljak?" — kártyafal + véletlen dobás, mert unatkozva a választás maga is teher.

**Működés:**
- Kártyák a tevékenység-katalógusból: gyári kezdőcsomag + Vanda sajátjai (appon belül vehet fel, szerkeszthet, törölhet, címkézhet).
- Szűrés címkékre: bent/kint, egyedül/tesóval, 5 perc / fél óra / 1 óra+.
- **"Pörgess egyet!"** gomb: véletlenszerűen dob egy (szűrésnek megfelelő) kártyát, kis animációval. Újrapörgethető.
- Elfogadott ötlet felkerülhet a napi falra.

---

## 5. Backend (minimális)

**Három szűk feladata van; olvasható naplótartalom soha nem megy át rajta.**

- **Panik-riasztás:** család-párosítás (QR/6 jegyű kód), device tokenek nyilvántartása, `PanicEvent` fogadása és APNs push kiküldése a szülő-eszközökre.
- **Napló-escrow:** a titkosított bejegyzés-blobok append-only tárolása + a recovery-hozzáférések visszavonhatatlan audit-naplója. A szerver a tartalmat kulcs híján nem tudja olvasni.
- **Megosztás:** ha Vanda bekapcsolta, a napi aksi% / zóna / progress-% továbbítása a szülő módnak (kis JSON, szöveges válaszokat soha nem tartalmaz).
- **Tárolt adat:** család-azonosító, tokenek, szerepek, panik-események, titkosított blobok, megosztási számok. Adatminimalizálás: nevek helyett becenevek/szerepek is elegendők.
- **Technológia:** szabadon választható (pl. Swift Vapor, hogy egy nyelven maradjon a stack, vagy bármi más, amit szívesen üzemeltetsz); HTTPS, token-alapú hitelesítés a párosításból.
- **Megbízhatóság:** a panik-push time-sensitive/critical besorolású; ha a push kézbesítés bizonytalan, az app Vandának jelezze, és ajánlja fel azonnal a hívás/FaceTime alternatívát (a riasztás soha ne "vesszen el csendben").

---

## 6. Biztonság és adatvédelem — összefoglaló

- Napló: AES-GCM, kulcsderiválás PIN-ből (pl. PBKDF2/Argon2), tartalomkulcs kettős borítékban (PIN-út + recovery-út), Keychain-tárolás, hash-láncolt bejegyzések, visszavonhatatlan felnyitási napló.
- Barométer/progress: CloudKit-szinkron Vanda eszközei közt; a szülők felé csak a kapcsolható megosztás számai mennek (backenden át), szöveges válaszok soha.
- Backend: panik-metaadat + titkosított escrow-blobok + megosztási számok; TLS; panik-események minimális retencióval (pl. 30 nap után törlődnek).
- Ha az app később más családokhoz is eljut: GDPR-megfelelés gyerekadatokra, szülői hozzájárulás, App Store "Kids" kategória szabályai (harmadik feles adattovábbítás korlátai) — külön jogi kör szükséges, a jelenlegi architektúra (lokális adat, minimál backend) ezt eleve jól szolgálja.

---

## 7. Fejlesztési fázisok

Minden fázis önállóan használható appot ad. Claude Code-dal fázisonként érdemes haladni: fázis = milestone, azon belül kis, tesztelhető lépések.

### 0. fázis — Alapozás
- Xcode projekt, SwiftUI app váz, SwiftData modellek **CloudKit-szinkronnal** (iPhone + iPad-en tesztelve).
- **Navigáció:** 4 fülös alsó tab bar (Ma · Ébresztő · Napló · Unatkozom), a Ma fejlécében a kiemelt, lüktető Panik gombbal (2.1) — a panik-képernyő tartalma a 4. fázisban élesedik, de a gomb helye kezdettől ott van.
- **Téma-rendszer:** háttérkép- és színválasztás alapjai (`ThemeSettings`) — Vanda az első pillanattól a magáévá teheti a felületet.
- Design-alap: színpaletta, tipográfia, az app kedves/játékos hangneme (Vandával közösen választva).
- Gyerek/szülő mód váz (szülő mód még üres).

### 1. fázis — MVP (a végén a mágnessel)
Sorrend a fázison belül, a gyors örömöktől a fő attrakcióig:
1. **Unatkozó lista** (tevékenység-katalógus + kártyafal + pörgetés + szűrés).
2. **Emlékeztetők** (gyári csomag + saját, lokális notificationök, ✓ action).
3. **Napi progress fal** (emlékeztető-pipák + saját teendők + töltődő aksi vizuál).
4. **Ébresztőóra — a mágnes-feature** (kedvenc zenekar ébresztőnek): AlarmKit, lánc-ébresztő, matek-feladvány modul, zenetár (fájlimport + hangfelvétel), widget extension a countdown-hoz. Valódi eszközön tesztelendő.

Az 1–3. pont közbenső buildekként már mehet Vanda telefonjára (TestFlight), így az appot már használja, miközben az ébresztőt várja — az MVP akkor kész, amikor az ébresztő megszólal.

### 2. fázis — Hangulatbarométer
- Aksi-csúszka, zónák, töltő-tevékenység ajánlás, kérdésbank (gyári kérdésekkel), trend-nézet.
- A szülői megosztás kapcsolója itt még csak UI-elem; élesben a 4. fázisban, a backenddel együtt kapcsol be.

### 3. fázis — Napló
- Titkosítási réteg (PIN, kulcsderiválás, iCloud Keychain, recovery-kulcs generálás és egyszeri megjelenítés).
- Bejegyzések: szabad szöveg, **választós sablonok** (`JournalTemplate`, szerkeszthető), fotó-csatolás (titkosítva), aksi% csatolás.
- Hash-lánc + felnyitási napló + banner; a titkosított blobok CloudKit-szinkronja.
- Fotó-prompt emlékeztetőként.
- Az eszköz nélküli recovery a 4. fázis escrow-jával válik teljessé.

### 4. fázis — Panikgomb és backend
- Backend (párosítás, APNs, PanicEvent, **napló-escrow**, megosztási endpointok).
- Szülő mód: riasztások fogadása, párosítás-kezelés, **megosztott aksi%/progress nézet**, recovery-funkció (escrow-letöltés + recovery-kulcsos helyi visszafejtés, audit-eseménnyel).
- Panikgomb: 1. szint eszközmodulok (légzés, grounding, nyugi-mappa, hívás/FaceTime), 2. szint riasztás megerősítéssel.
- Kézbesítés-visszajelzés Vandának.

### 5. fázis — AI (opt-in, óvatosan)

Alapszabály mindenhol: **generál → ember jóváhagy → bekerül.** Elsődleges motor az Apple Foundation Models framework (on-device, az adat nem hagyja el a telefont, offline is működik, nincs API-költség). Felhő-API (pl. Claude API) csak ott, ahol az on-device modell kevés, és ott is csak nem-érzékeny adattal.

| Funkció | Leírás | Motor | Rizikó és mitigáció |
|---|---|---|---|
| Unatkozó ötletgenerátor | "Dobj valami újat!" — kategóriák/érdeklődés alapján új tevékenység-kártya, Vanda mentheti | On-device | Alacsony; legrosszabb esetben béna ötlet. Ideális első AI-funkció. |
| Emlékeztető-szöveg generátor | Vicces/kedves szövegvariációk Vanda stílusában | On-device | Alacsony; csak jóváhagyással kerül be. |
| Kérdésbank-bővítés | Új többszintű reflexiós kérdések a barométerhez | On-device vagy felhő | Közepes-alacsony: rossz kérdés érzékeny pillanatban rosszul eshet. Mitigáció: "jóváhagyásra vár" lista, szülői átnézés után kerül forgásba. Az AI itt offline tartalomgyár, nem élő beszélgetőpartner. |
| Napló-visszatekintő | Heti/havi összefoglaló Vandának a saját bejegyzéseiből | **Kizárólag on-device** | Közepes: a napló a bizalmi ígéret magja. Felhő-API kizárt, anonimizálva is. A specifikáció garantálja: naplószöveg soha nem megy hálózatra. |

**Explicit non-goal — AI a panikgombban:** szabadon generáló nyelvi modell nem kerül a panik-folyamatba. Indoklás: (1) a kimenet nem determinisztikus, rossz pillanatban rossz mondat születhet, felnőtt korrekció nélkül; (2) kötődési rizikó — a nehéz pillanat tanult válasza az legyen, hogy emberekhez és bevált eszközökhöz fordul, ne az apphoz. Ha valaha kerül ide AI, csak erősen szkriptelt, előre jóváhagyott folyamatok megfogalmazás-lágyítására.

---

## 8. Non-goals (szándékosan nincs)

- Streak, pontszám, rangsor, "elrontott napok" nézet.
- Rejtett szülői megfigyelés, automatikus hangulat-riport a szülőknek.
- Naplótartalom vagy barométer-adat bármilyen szerveren.
- Élő AI-chat a panikgombban (lásd 5. fázis indoklása).
- Social/megosztás funkciók.

---

## 9. Nyitott kérdések (fejlesztés közben döntendők)

1. Lánc-ébresztő paraméterei (darab, időköz) és a feladvány nehézségi skálája — Vandával iterálva.
2. Barométer-zónahatárok finomhangolása használat közben.
3. A hosszú nyomásos azonnali SOS bekapcsolása — családi megbeszélés után.
4. Panik-eszközmodulok bővítése (mik váljanak be a gyakorlatban).
5. iPad-elrendezés: v1-ben "megnő" a telefonos UI; dedikált iPad-layout később.
6. Ha más családok is kapnak az appból: onboarding, jogi kör, App Store publikálás vs. TestFlight-terjesztés.
7. Barométer- és progress-megosztás alapértelmezése (be/ki) és pontos tartalma — Vandával megbeszélendő.
8. Szinkron-architektúra megerősítése: a munkadöntés a **hibrid** (CloudKit szinkron + backend escrow/megosztás). Ha a CloudKit-korlátok gondot okoznának, az alternatíva a teljes saját backend-szinkron — de ez lényegesen több munka (konfliktuskezelés, offline sor).
9. Diktálós naplóválasz (on-device Speech) bevezetésének ideje.
10. Tab bar kiosztása — **eldőlt** a design-körben (v1.3): 4 fül + Panik gomb a Ma fejlécében, lásd 2.1 és `docs/design/design-tokens.md`.
11. **Visszatekintő statisztika / komplett history (roadmap-ötlet, 2026-07-10, Attila).** Az előző napok hangulata, elvégzett/tervezett teendők stb. statisztikában visszakövethetők legyenek, és összepontozhatók a napló/önreflexió bejegyzésekkel — egy teljes kép a történésekről. Szakaszolva: **(a)** első kör naplótartalom NÉLKÜLI statisztika, kizárólag a készüléken lévő adatokból (MoodEntry, DailyTask, ReminderLog), csak Vandának; **(b)** a napló-összekapcsolás csak PIN-nel feloldva, on-device számítással történhet (a 4.5 titkosítási garanciái nem sérülhetnek, statisztika naplótartalmat nem szivárogtathat); **(c)** szülői láthatóság csak Vanda kifejezett beleegyezésével — vele megbeszélve, ahogy a megosztás-kapcsolóknál. **Tervezési korlát:** a 8. fejezet non-goalja („nincs elrontott napok nézet") és a 4.6 („éjfélkor tiszta lap") érvényben marad — a visszatekintés hangneme kedves, tényrögzítő, mintázat-kereső segítség, nem teljesítmény-számonkérés; a keretezést a design-körben kell kitalálni, mielőtt fázisba kerül.

---

## 10. Munkamódszer Claude Code-dal (javaslat)

- Repo-struktúra a gyökérben: `docs/` (ezen belül `docs/spec/vanda-app-spec.md` — ez a fájl —, plusz döntési napló és `docs/design/`), `VandaApp/` (iOS app), `VandaWidgets/` (alarm Live Activity), `backend/` (panik + escrow + megosztás).
- **Design-kör a 0. fázis előtt (Claude Design):** a spec alapján kattintható, mobil nézetű prototípus készül a téma-rendszerről (paletta, tipográfia, hangulat), a tab bar kiosztásáról és 4-5 kulcsképernyőről (Ma fal, barométer, unatkozó kártyafal, napló-belépés, panik-képernyő). Vandával közösen iterálva, **időkorláttal** (2-3 iteráció) — a cél döntések meghozatala, nem pixelpontos teljes app. Nem tervezendő: az ébresztő rendszer-UI-ja és a notificationök (ezeket az iOS adja). A kimenet webes prototípus, tehát **vizuális specifikáció**, nem kód-alapanyag: az eredmény (képernyőképek + design-tokenek: színek, betűk, térközök) a `docs/design/` alá kerül markdownban, és a Claude Code a 0. fázisban a spec + design-doc párosból dolgozik.
- A gyökérben lévő `CLAUDE.md` hivatkozzon a `docs/spec/vanda-app-spec.md`-re; fázisonként dolgozz, egy fázison belül kis, buildelhető lépésekben.
- Minden fázis végén: valódi eszközön futtatás (az AlarmKit-nél kötelező), Vanda-teszt, visszajelzések rögzítése a `docs/` alá.
- A titkosítási réteghez (3. fázis) írass unit teszteket a kulcsderiválásra, a hash-láncra és a felnyitási naplóra — ez a rész ne "működik, jó lesz" alapon menjen.
