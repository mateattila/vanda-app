# Döntési napló

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

## 2026-07-07 — Tartomány-tokenek: egy konkrét érték

A design-tokens tartományokat ad (kártya radius 22–26, gap 13–16 stb.); a `Theme` egy-egy konkrét középértéket rögzít (24, 14, …), hogy a UI egységes legyen. Képernyőnkénti eltérés csak indokolt esetben, a tokenen keresztül.
