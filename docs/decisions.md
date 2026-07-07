# Döntési napló

## 2026-07-07 — 4. fázis: backend Cloudflare Workersen, párosítás 6 jegyű kóddal

A minimál backend (spec 5. fejezet) Cloudflare Workers-re épül (TypeScript + Hono, D1 + R2), nem Vaporra: zéró üzemeltetés, ingyenes tier, mindig ébren — egy panik-funkciónál a „szerver életben tartása" ne legyen családi felelősség. Az APNs-t közvetlen HTTP/2 + p8 JWT hívással érjük el; az első backend-lépés tracer bullet, ami ezt end-to-end igazolja. Párosítás 6 jegyű, 10 perces kóddal (QR nélkül — kevesebb mozgó alkatrész). A panik-push time-sensitive besorolású; a critical alert (külön Apple-jóváhagyás) nem v1. A push capability és a p8 kulcs Attila kézi lépése, ahogy a CloudKit-nél. Részletes design: `docs/superpowers/specs/2026-07-07-phase4-panic-backend-design.md`.

## 2026-07-07 — Barométer: MoodSettings modell + véletlen rákérdezés 7 napra előre

A zónahatárok, a rákérdezés-idősáv, a kérdés-mélység és a megosztás-kapcsolók egy CloudKit-szinkronizált `MoodSettings` modellben élnek (a spec adatmodell-listáján felül — a „zónahatárok beállításban módosíthatók" követelmény igényli). A napi véletlen időzítésű aksi-rákérdezés úgy készül, hogy a következő 7 nap kérdezéseit fix időpontú lokális notificationökre sorsoljuk, és minden app-indulás újrasorsolja — így nem kell háttér-futás, és a „sosem kiszámítható időben jön" élmény megmarad. A kérdésekre adott válaszok a MoodEntry-ben maradnak (CloudKit, Vanda eszközei), a megosztás-kapcsolók a 4. fázisig csak rögzítik a szándékot.

Jelentős fejlesztési döntések, dátummal és indoklással. (Elv: ami a specből/design-tokensből nem következik egyértelműen, az ide kerül.)

## 2026-07-07 — Fontok: statikus TTF-példányok, nem variable fontok

A Quicksand (Medium/SemiBold/Bold) és Nunito (SemiBold/Bold/ExtraBold) **statikus** TTF-példányként került be (Google Fonts, SIL OFL licenc — az OFL-fájlok a fontok mellett, a bundle-ben is). Indoklás: iOS-en a variable font named instance-einek elérése kevésbé kiszámítható (`Font.custom` a default instance-t adhatja), a statikus súlyokkal a PostScript-név → súly megfeleltetés egyértelmű. A PostScript-nevek ellenőrizve: `Quicksand-Medium/SemiBold/Bold`, `Nunito-SemiBold/Bold/ExtraBold`. Debug buildben induláskor assert őrzi, hogy mind regisztrálódott.

## 2026-07-07 — Dynamic Type: `Font.custom(relativeTo:)` a szerepekhez, `@ScaledMetric` a metrikákhoz

A tipográfia-tokenek `relativeTo:` horgonnyal skálázódnak (display/title2, nagy szám/largeTitle, törzs/body, címke+segéd/caption), így a rendszer szövegméretével együtt nőnek-csökkennek. View-beli nem-szöveg méretekhez (ikonkonténer, mérő) `@ScaledMetric` használandó a képernyőkön.

## 2026-07-07 — CSS-gradiens fokok fordítása SwiftUI-ra

A design-tokens CSS-gradienseiből: 180deg → `.top → .bottom`, 160deg → `.topLeading → .bottomTrailing` közelítés. A vizuális eltérés elhanyagolható; ha a design-körben feltűnne, `UnitPoint`-tal pontosítható.

## 2026-07-07 — A szerep (gyerek/szülő) UserDefaults-ban él, nem a szinkronizált adatban

A gyerek/szülő mód eszköz-szintű tulajdonság: Vanda iPhone-ja és iPadje gyerek módú, a szülők telefonja szülő módú — ha CloudKiten szinkronizálnánk, az egyik eszköz beállítása felülírná a másikét. Ezért `@AppStorage("appRole")`, nem SwiftData-modell.

## 2026-07-07 — ReminderLog: UUID-referencia, nem SwiftData-relationship

A `ReminderLog.reminderID` sima UUID, nem `@Relationship`: a napi fal naplója akkor is maradjon meg, ha Vanda törli az emlékeztetőt; plusz CloudKitnél a relationshipek kötelezően opcionálisak és a törlés-kaszkádolás szinkron közben törékenyebb.

## 2026-07-07 — Háttérfotó ~2000 px-re kicsinyítve tárolódik

A Kinézet fotó-háttere JPEG-ként (0.85), max 2000 px élhosszal kerül a `ThemeSettings.photoData`-ba (`.externalStorage`): a többmegabájtos eredeti fölösleges lenne a CloudKit-szinkronnak és a memóriának.

## 2026-07-07 — Navigation bar címek: UINavigationBar appearance

A SwiftUI `navigationTitle` fontja képernyőnként nem állítható; hogy a nav-címek is Quicksandben legyenek, az app induláskor `UINavigationBar.appearance()` állítja a large/inline title fontot.

## 2026-07-07 — Ismert környezeti probléma: emoji tofu a szimulátorban

Az iOS 26.2 szimulátor-runtime ezen a gépen minden emojit ⍰-ként renderel — a Safariban is, tehát nem az app hibája (a forrásfájlok UTF-8-ban épek, a runtime-ban ott az AppleColorEmoji). Valódi eszközön nem jelentkezik; kódkerülőt nem építünk rá.

## 2026-07-07 — Activity: emoji-mező a spec adatmodellje fölött

A spec 3. fejezete az `Activity`-nél csak címet + címkéket ír, de a design-referencia (03-screen) kártyáin emoji van — a modell `emoji` mezőt kapott (alapérték `✨`, CloudKit-kompatibilis). A spec adatmodellje „magas szint", ez kiegészítés, nem eltérés.

## 2026-07-07 — Gyári csomag seedelése: üres katalógusnál, kliens-oldalon

Az unatkozó fal gyári kezdőcsomagja akkor seedelődik, amikor a katalógus üres (első fül-megnyitás). CloudKit-szinkronnal elméletben előfordulhat dupla seed (két friss eszköz egyszerre, a szinkron beérkezte előtt) — `@Attribute(.unique)` CloudKit mellett nem használható, ezért ezt elfogadjuk; családi appnál a kockázat minimális, duplikátum kézzel törölhető.

## 2026-07-07 — Emlékeztetők: gyári elem nem törölhető, csak kikapcsolható

A gyári emlékeztetők a spec szerint „ki-be kapcsolhatók, szövegük átírható" — a törlést csak a saját emlékeztetőkre engedjük, így a gyári csomag nem veszhet el véletlenül (kikapcsolva ugyanazt adja). Az ütemezés-szinkron stratégiája: minden változás után teljes újraütemezés (az összes saját függő notification törlése + aktívak újrafelvétele) — egyszerűbb és robusztusabb, mint a differenciális követés.

## 2026-07-07 — Napi progress kártya címkéje: „A napod", nem „Mai töltöttség"

A design-tokens eredetileg „Mai töltöttség"-nek hívta a Ma képernyő progress-kártyáját, de ez összekeverhető Vanda aksijával (hangulatbarométer, 2. fázis). Döntés (Attila): a kártya címkéje **„A napod"**, az üzenetek is a napról szólnak („A napod szép ívben töltődik 🐨") — a spec 4.6 szófordulatát követve. A rímelés a barométerrel szándékos marad, de a két fogalom feliratban nem keveredik. A design-tokens 5. fejezete frissítve.

## 2026-07-07 — Lánc-ébresztő: fix időpontú alarmok + app-oldali újraütemezés

A lánc tagjai nem ismétlődő AlarmKit-alarmok, hanem **fix időpontúak a következő előfordulásra** (N darab, M percenként), és az app minden indulás/előtérbe kerülés/szerkesztés/feladvány-megoldás után újraütemez. Indoklás: ismétlődő alarmoknál a „mai hátralévő tagok törlése a feladvány után" a jövő heti alarmokat is vinné; a fix+újraütemezés modell egyszerű és kiszámítható. **Ismert korlát:** egy megszólalás után a következő előfordulás beütemezéséhez app-futás kell — Vanda napi szinten használja az appot (emlékeztetők, fal), és minden előtérbe kerülés újraszinkronizál; eszközön tesztelve iterálunk.

## 2026-07-07 — Feladvány-kapu: időablak-alapú felismerés, nem AppIntents (v1)

Az élő lánc felismerése app-megnyitáskor időablak alapján történik (t0 … utolsó tag + 10 perc ráhagyás, eszköz-lokális UserDefaults-állapotból). A megoldottság az **aktuális előforduláshoz (t0)** kötődik, nem a naphoz — az első eszközös teszt kibuktatta, hogy a naphoz kötött változat ugyanaznap minden további ébresztésnél elnyelte a feladványt. Lánc-ébresztős profilnál a rendszer-alarm „Leállítom" gombjához `stopIntent` (LiveActivityIntent, `openAppWhenRun`) kötődik: a leállítás egyben az appba dob, ahol a kapu azonnal felteszi a feladványt — sima ébresztőnél a stop csak leállít (eszközös teszt visszajelzése alapján, 2026-07-07). A countdown Live Activity (widget extension, spec 4.1) továbbra is későbbi kör — a widget-target hozzáadása Xcode-ban esedékes. Az ébresztés-állapot (ütemezett ID-k, megoldás napja) szándékosan NEM CloudKit-szinkronizált: az alarm azon az eszközön él, ahol beütemezték.

## 2026-07-07 — Zenetár: formátum-konverzió elhalasztva

Az importált hangfájl változatlanul másolódik a Library/Sounds alá (mp3/m4a/wav közvetlenül működik AlarmKit-tel); a spec szerinti automatikus konverziót (bármilyen formátum → támogatott) akkor építjük meg, ha eszközön kiderül, hogy kell. A felvétel eleve AAC/m4a.

## 2026-07-07 — Tartomány-tokenek: egy konkrét érték

A design-tokens tartományokat ad (kártya radius 22–26, gap 13–16 stb.); a `Theme` egy-egy konkrét középértéket rögzít (24, 14, …), hogy a UI egységes legyen. Képernyőnkénti eltérés csak indokolt esetben, a tokenen keresztül.
