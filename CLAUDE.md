# Vanda App — munkaszabályok

Személyes iOS-app Vandának (iPhone + iPad). Swift + SwiftUI, SwiftData + CloudKit, iOS 26+.

## Kötelező olvasmányok

- **`docs/spec/vanda-app-spec.md`** — a projekt alkotmánya: fázisbeosztás (7. fejezet), alapelvek (1. fejezet), non-goalok (8. fejezet). Minden funkcionális kérdésben ez az irányadó.
- **`docs/design/design-tokens.md`** — a véglegesített vizuális irány („Soft Dusk"): színek, tipográfia, formák, komponens-jegyzék. **Vizuális és navigációs kérdésben ez nyer a spec felett** (pl. tab bar: 4 fül — Ma · Ébresztő · Napló · Unatkozom —, a Panik gomb a Ma képernyő fejlécében van, nem külön fül).

## Munkamódszer

- **Fázisonként haladunk** a spec 7. fejezete szerint. **Jelenlegi fázis: 4 (Panikgomb és backend); ezen belül a 4.1 (panik 1. szint), a 4.2a (backend: párosítás + APNs) és a 4.2b (iOS: párosítás, push-regisztráció, teszt-push) kész — következik a 4.3 (panik 2. szint: riasztás + szülő-módú fogadás).** A 0–3. fázis kész. Ne implementálj későbbi fázisokhoz tartozó funkciót, még „ha már itt vagyunk" alapon sem.
- **Attilára váró, még el nem végzett lépések** (ezek hiánya nem hiba, ne próbáld kikerülni őket): a backend deploy + APNs p8 kulcs a `backend/README.md` ellenőrzőlistája szerint, utána a `VandaApp/Config/Backend.xcconfig`-ban a `BACKEND_HOST` átírása a valódi hosztra és a 4.2b eszközös záró tesztje; továbbá a 0. fázis iPhone↔iPad CloudKit-szinkron tesztje. A 4.3 két ismert, tudatosan örökölt korlátot visz tovább — lásd `docs/decisions.md`, 2026-07-20.
- Egy fázison belül **kis, önállóan buildelhető lépésekben** dolgozz. Minden lépés végén az alábbi buildnek hibátlanul le kell futnia:

  ```sh
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  xcodebuild -project VandaApp/VandaApp.xcodeproj -scheme VandaApp \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
  ```

  (A `DEVELOPER_DIR` azért kell, mert a gépen a `xcode-select` a CommandLineTools-ra mutat.)
- **Jelentős döntéseket** (architektúra, könyvtárválasztás, spec-értelmezés, eltérés a tervtől) a `docs/decisions.md`-be írj, dátummal és rövid indoklással.
- **Ha a spec és a kód (vagy két dokumentum) ellentmond egymásnak, kérdezz — ne dönts egyedül.** Kivétel: a fent rögzített szabály, hogy vizuális/navigációs kérdésben a design-tokens.md nyer.
- Az ébresztő (AlarmKit) viselkedését **valódi eszközön** kell tesztelni; a szimulátor ott nem megbízható.

## Amihez ne nyúlj

- **Bundle ID** (`hu.attis.VandaApp`), signing, **iCloud/CloudKit capability** — ezek Xcode-ban kézzel beállítva/kezelve. Projekt-beállítást csak kifejezett kérésre módosíts.

## Kódolási irányelvek

- A UI a `Theme` névtér tokenjeiből építkezzen (színek, fontok, radiusok, árnyék) — nyers hex/pt érték ne szóródjon szét a view-kban.
- Az **accent** szín user-választható (`ThemeSettings`), a **zóna-színek** (zöld/narancs/piros) fixek — ezt a téma-réteg tükrözi.
- SwiftData-modellek CloudKit-kompatibilisen: minden mező opcionális vagy alapértékes, nincs `@Attribute(.unique)`.
- Hangnem: kedves, játékos, tegező magyar szövegek („Nyugis nap, ez is oké 🫶"). Nincs streak, nincs bűntudat-mechanika (spec 8. fejezet).

## Repo-struktúra

- `docs/` — spec, design, döntési napló
- `VandaApp/` — az iOS app (Xcode-projekt)
- `VandaWidgets/`, `backend/` — későbbi fázisokban jönnek létre
