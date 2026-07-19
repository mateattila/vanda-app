# Döntési napló

## 2026-07-20 — 4.2b lezárás: két ismert korlát, amit a 4.3 tudatosan örököl

A 4.2b záró code review-ja két olyan hiányosságot talált, amit nem javítunk ki most, hanem szándékosan, dokumentáltan tovább görgetünk a 4.3-ba — hogy ne balesetként derüljenek ki, amikor a pánik-riasztás már éles. **(1) Árva család egy gyerek-eszköz leválasztása után.** A `DELETE /devices/me` csak a hívó eszköz sorát törli. Ha Vanda telefonja — az az eszköz, ami a családot létrehozta — leválik, majd újra megnyomja a „Család létrehozása” gombot, egy vadonatúj `familyId`-t kap, miközben a szülők érvényesen hitelesített tagjai maradnak a réginek, immár gyerek-eszköz nélküli családnak. Az ő képernyőik örökre azt mutatják, „Vanda jelzései ide fognak érkezni”, és soha semmi nem fog megérkezni. Vanda oldalán van egy gyenge jelzés (a teszt-push jelzi, hogy nincs párosított szülő-eszköz), a szülők oldalán viszont semmi. A rendes javítás — szülő-oldali család-egészség-ellenőrzés, vagy a család lebontása, amikor az utolsó gyerek-eszköze is leválik — a 4.3 feladata. **(2) A `rename(to:)` sose jut el a backendig.** Az eszköznév-szerkesztés csak a helyi Keychain-hitelesítést írja át; szerver-oldali átnevezés endpoint nincs. Ma ennek nulla a költsége (a teszt-push törzse a gyerek saját nevét használja, a szerver-oldali nevet ma semmi nem olvassa), de két felületen (`ParentModeView`, `FamilySettingsView`) is kínálunk egy átnevezést, ami látszólag sikerül, és csendben soha nem szinkronizálódik — a 4.3 szülő-eszköz-listája pedig már láthatóvá teszi az elavult nevet. A 4.3 legelső lépéseként vagy megépítjük a szerver-oldali átnevezést, vagy elrejtjük a mezőt.

## 2026-07-19 — 4.2b design: szerep-hordozó párosító kód, xcconfig-alapú backend-URL

A 4.2b iOS-oldal tervezése három olyan döntést hozott, ami a 4. fázis eredeti designjához képest eltérés vagy kiegészítés. **(1) A párosító kód szerepet hordoz.** Az eredeti modellben a `POST /pair` mindig `role='parent'` eszközt hozott létre, a `POST /families` pedig gyereket — így Vanda második eszköze (iPad) csak úgy tudott volna backendre kerülni, ha külön, hibás családot hoz létre. A `pairing_codes` ezért kap egy `role` oszlopot (`DEFAULT 'parent'`, visszafelé kompatibilis), és az iPad ugyanazzal a 6 jegyű folyamattal lép be, saját tokennel és saját APNs-tokennel. Az elvetett alternatíva az iCloud Keychainen megosztott közös gyerek-token volt: a két eszköz felülírta volna egymás APNs-tokenjét, és a szerver nem tudta volna megkülönböztetni őket — közvetlen adósság a 4.3 riasztás-ciklusra. **(2) A backend URL xcconfig → Info.plist úton jön, nem Swift konstansként.** Attila kifejezett választása (ez egyben engedély a projekt-beállítások módosítására, amit a CLAUDE.md egyébként külön kéréshez köt). Az érték **séma nélküli hoszt** (`BACKEND_HOST`), mert az xcconfig a `//`-t kommentkezdetnek tekinti és a teljes URL csendben csonkulna; a `https://` előtagot a Swift oldal teszi hozzá. Az xcconfig bekerül a gitbe: a biztonság a bearer tokeneken áll, nem az URL rejtettségén. **(3) `DELETE /devices/me` a leválasztáshoz.** Csak helyi Keychain-törlés esetén árva eszköz-sor maradna élő APNs-tokennel, és a teszt-push (4.3-ban a riasztás) egy nem létező készüléknek próbálna küldeni — a „szellem-címzett" pont a kézbesítési megbízhatóság ellen dolgozna. Mellékes megállapítás a tervezés közben: a Push Notifications capability már be van állítva (`aps-environment: development`), tehát a `backend/README.md` 8. kézi lépése tárgytalan.

## 2026-07-11 — 4.2a backend: vitest 4 + D1 típus-fedettség + párosítás-óvás

Az 4.2a backend implementáció a tervhez képest négy lényegi eltérést hozott. **(1) Vitest verzió és plugin API:** a terv vitest 3-ra számított `defineWorkersConfig` konfigurációval, azonban az elérhető `@cloudflare/vitest-pool-workers 0.18.x` már vitest 4-et igényel és a Vite plugin API-t (`cloudflareTest()` export). Az integrációs logika ugyanaz maradt. **(2) Fetch mock:** a vitest 3→4 átmenet során a `cloudflare:test` modul `fetchMock` exportja eltűnt; helyettük a projekt saját minta-kódját követve (`workers-sdk/fixtures/vitest-pool-workers-examples/request-mocking`) a `globalThis.fetch`-re `vi.spyOn`-t használunk — az APNs HTTP/2-hívások így mockolt tesztkörnyezetben ellenőrizhetők, és az eltérés tisztán dokumentálva van a test/apns.test.ts-ben. **(3) Párosítás-verseny fix:** a szülő párosítási kód `POST /pair`-nél kettős beváltás-védelmet a **feltételes UPDATE** valósítja meg (`used_at IS NULL` + `expires_at >= now` + meta.changes === 1 ellenőrzés), nem a terv szerinti batch-művelet — az SQL-szintű atomicitás erősebb és egyszerűbb. **(4) Push-szállítás-hibák elszigetelése:** az apns.ts sendPush és az index.ts /test-pushes ciklusa egyes szülőnél bekövetkező transzport-hiba (DNS/timeout) nem szakítja meg a többi szülő push-ját — status 0 jelzi a HTTP-státusz nélküli hibát, strukturált JSON log rögzíti az err.message-t. Ez előkészít a 4.3 pánik-push ciklusához (több szülő, egy hiba sem blokkolhat).

## 2026-07-09 — Napi használati visszajelzések: négy javítás

Az első többnapos eszközös használat négy javítást hozott. (1) **Fantom ébresztés:** az alarm-resync mostantól kisöpri a rendszerből azokat az AlarmKit-alarmokat, amiket egyik profil nyilvántartása sem ismer — régi buildek maradványai árván csörögtek, feladvány és leállítás nélkül. (2) **Éjféli tiszta lap:** a Ma fal „ma" horgonya `NSCalendarDayChanged`-re és előtérbe kerülésre újraáll — a @Query csak adatváltozásra frissít, így az éjfélt háttérben átvészelő app reggel a tegnapi falat mutatta. (3) **Dupla aksi-rákérdezés:** az újrasorsolás kihagyja a mai napot, ha ma már szólt a prompt vagy van mai bejegyzés — korábban épp a promptra megnyitott app sorsolt aznapra másodikat („zaklatós" hatás, az 1. fejezet kedvesség-elve ellen). (4) **Emlékeztető-akciók (Attila kérése):** a „✓ Kész" mellé +10 perc / +30 perc / +1 óra szundi és „Ma kihagyom" került. Döntés: a notification-gomb **nem töröl véglegesen** — a „Ma kihagyom" csak a mai alkalmat veszi ki (`ReminderLog.skipped`), összhangban a „gyári emlékeztető nem törölhető" korábbi döntéssel és a bűntudat-mentes hangnemmel. A szundizott értesítés külön előtagot kap, hogy a resync ne söpörje ki.

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

## 2026-07-19 — FamilyLinkModel: explicit @MainActor az idempotencia-őr miatt

Code review kifogásolta, hogy a `createFamily`/`joinWithCode` `guard !isLinked` őre nem zár ki egy második, átfedő hívást (dupla koppintás, timeout utáni retry): `isLinked` csak a hálózati kör LEZÁRÁSA után válik igazzá, két, még folyamatban lévő hívás mindkettője átjutna az őrön. A javítás egy szinkron `claim(requireUnlinked:)`-re épül, ami az első `await` előtt, egyetlen lépésben ellenőrzi ÉS beállítja az `isBusy`-t — ez viszont csak akkor megbízható, ha a metódusokat egyszerre csak egy végrehajtási szál futtathatja. A `FamilyLinkModel` addig nem volt actor-izolált (a projekt `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` beállítása @Observable osztályokra empirikusan NEM öröklődik — ellenőrizve build-warningokkal: az `InMemoryDeviceCredentialStore` plain classként kapja az örökölt izolációt, a `FamilyLinkModel` nem). Ezért az osztály explicit `@MainActor`-t kapott. Ez most ingyen van, mert a két fogyasztó képernyő (Vanda Család, szülő mód) még nincs megírva; egy `@Observable`, SwiftUI-ból hajtott modellnél amúgy is ez a természetes hely. A tesztfájlban a `makeModel` helper és a `FamilyLinkModelTests` struct is `@MainActor` lett, hogy a szinkron property-elérések (pl. `model.link`) fordítási hiba nélkül maradjanak — ez a Swift 6 nyelvi módban amúgy is kötelező lenne.

## 2026-07-09 — Fázis 4.1 apró eltérések: FlowLayout-ütközés, Set-alapú duplikátumőr, tel: forma

Három apró eltérés a 4.1 tervhez képest, végleges review során derültek ki. (1) A terv `FlowLayout`-ja `PanicFlowLayout`-ra lett átnevezve — a modulban már létezik egy top-level `FlowLayout` (JournalTemplateFillView.swift), és a névütközés modul-szinten fennáll, `fileprivate`-től függetlenül. (2) A `CalmActivitiesView` tervezett skaláris `addedID` duplikátumőre helyett `Set<UUID>` került, mert a skaláris változat csak a legutóbb hozzáadott DailyTaskot tudta megjegyezni — több elem hozzáadásakor duplikátum DailyTask és félrevezető ✓ jelent meg. (3) A `PanicContact` hívás-linkjei közül a `tel:` séma a design-dokumentum szerinti RFC 3966 formára javítva (kettőspont, „//” nélkül: `tel:+36301234567`); a FaceTime linkek Apple dokumentált formájukban maradtak (`facetime://`, `facetime-audio://`).
