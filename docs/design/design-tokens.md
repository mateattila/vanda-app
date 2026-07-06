# Vanda App — Design tokens & vizuális spec

> Ez a dokumentum a Claude Design-körben véglegesített vizuális irány (**Soft Dusk**) kivonata.
> Kiindulás a SwiftUI implementációhoz. A prototípus web-kód volt; ez itt a **fordítási referencia** — nem konvertálandó, hanem újraimplementálandó natívban.
> Kapcsolódó: `docs/spec/vanda-app-spec.md` (funkcionális spec).

---

## 1. Választott irány

**Soft Dusk** — lágy, levegős, pasztell-levendula. Nyugtató, nem „felnőtt-appos", nem harsány.
A hangnem kedves és játékos; a szövegek tegeznek, bátorítanak, sosem nyomasztanak („Nyugis nap, ez is oké 🫶", „Te döntöd el. Nem muszáj.").

Két másik irányt is megnéztünk és elvetettünk: *Juicy Pop* (élénk korall) és *Midnight Arcade* (neon). Ha kell fallback dark-mode hangulat, a Midnight Arcade paletta a kiindulás.

---

## 2. Szín-tokenek

### Alap (fix, téma-szintű)
| Token | Hex | Használat |
|---|---|---|
| `ink` | `#3A3550` | Elsődleges szöveg, ikonok, sötét gombok |
| `ink-muted` | `#8A82A8` | Másodlagos szöveg, feliratok |
| `ink-faint` | `#A69FC0` | Címkék, placeholder, uppercase kis feliratok |
| `surface` | `#FFFFFF` | Kártyák |
| `surface-tint` | `#EEE9F6` | Inaktív chip/segment háttér |
| `hairline` | `rgba(58,53,80,0.10)` | Elválasztó vonalak |

### Háttér-gradiensek (a Kinézetben választható)
| Név | CSS | 
|---|---|
| `grad0` Levendula (alapértelmezett) | `linear-gradient(180deg,#F4F1FC,#ECE7F8)` |
| `grad1` Menta | `linear-gradient(160deg,#DCF0E8,#BFE3D4)` |
| `grad2` Rózsa | `linear-gradient(160deg,#FFE7EF,#FBC9DC)` |
| `grad3` Írisz | `linear-gradient(160deg,#E9E4FF,#C7BBF5)` |
| Fotó-háttér | user kép + olvashatósági overlay: `linear-gradient(180deg,rgba(58,53,80,.05),rgba(58,53,80,.35))` a kép fölött |

Fotó-háttér esetén a kártyák háttere `rgba(255,255,255,0.9)` (nem tömör fehér), hogy a kép átüssön, de a szöveg olvasható maradjon.

### Kiemelőszín (`accent`) — user-választható
- **Alapértelmezett:** `#8A7DE0` (periwinkle)
- **Preset sor:** `#8A7DE0`, `#5FB89C`, `#EC6F9E`, `#F2A65A`, `#6FA8E8`
- **Szabad választó:** teljes színkör (natív color picker) — bármilyen hex megengedett
- Az accent viszi: Panik gomb, töltés-csík kitöltése, aktív tab, elsődleges gombok, kiemelt kártya (pl. „Unatkozol?"), napló-progress.

### Zóna-színek (hangulatbarométer — fixek, nem témázhatók)
| Zóna | Hex | Jelentés |
|---|---|---|
| Zöld | `#5FB89C` (világos `#86CBB5`) | „bírom" |
| Narancs | `#F4CE96` / jelző `#F2A65A` | „fárad" |
| Piros | `#EDA6A0` / jelző `#E06A5E` | „kimerül" |

### Panik-képernyő (saját, sötétebb környezet)
Háttér `linear-gradient(180deg,#5E4F86,#3E355C)`, fehér szöveg, `rgba(255,255,255,.14–.16)` chip/eszköz-felületek. Elsődleges akció fehér kártyagomb ink-szöveggel.

---

## 3. Tipográfia

| Szerep | Család | Súly | Méret (pt, iOS) |
|---|---|---|---|
| Display / képernyőcím | **Quicksand** | 700 | 20–25 |
| Nagy szám (aksi %, óra) | Quicksand | 700 | 34–52 |
| Törzsszöveg | **Nunito** | 600–700 | 13–14 |
| Címke / uppercase felirat | Nunito | 800 | 11 (letter-spacing ~0.05em, UPPERCASE) |
| Segéd / halvány | Nunito | 600 | 11–12 |

SwiftUI: mindkettő behúzandó custom fontként (`Quicksand`, `Nunito`) — a rendszer San Francisco NEM adja vissza ezt a barátságos, kerek karaktert. Dynamic Type-hoz `@ScaledMetric` vagy relatív text style-ok.

---

## 4. Forma & tér

| Token | Érték |
|---|---|
| Kártya radius | 22–26 pt |
| Kis kártya / chip radius | 15–20 pt |
| Gomb radius | 16–20 pt |
| Ikon-konténer radius | 12–14 pt |
| Képernyő oldalmargó | 20 pt |
| Kártyák közti gap | 13–16 pt |
| Kártya belső padding | 15–18 pt |
| Chip padding | 8–9 × 14–15 pt |

**Árnyék (elevation):** lágy, lila-árnyalatú, alátett — `0 10px 26px -14px rgba(58,53,80,0.28)`. Kerülni a kemény fekete drop shadow-t. iOS: `.shadow(color: Color(hex:0x3A3550).opacity(0.28), radius: 13, y: 8)` nagyjából.

**Tab bar ikon (aktív):** accent szín; inaktív: `ink` 50% opacitáson.

---

## 5. Komponens-jegyzék (képernyőnként)

- **Ma:** üdvözlés + dátum · **Panik gomb jobb fent** (kiemelt, lüktető) · „Mai töltöttség" aksi-kártya (nagy %, kirajzolt elem-akku csík) · barométer mini · „Unatkozol?" accent-kártya · alsó tab bar (Ma · Ébresztő · Napló · Unatkozom) · fogaskerék → Beállítások.
- **Hangulatbarométer:** függőleges aksi-mérő (elem forma, terminál a tetején) zöld/narancs/piros zóna-chipekkel + „egy kis töltő" ajánló kártya.
- **Unatkozom:** kiemelt accent-kártya + 2×2 kártyafal · alul `🎲 Pörgess egyet!` ink-gomb.
- **Napló-belépés:** külön **sötét** környezet (`#48416A→#322C4C`), PIN-pöttyök + numpad + Face ID. Adatvédelmi jelzés: ez privát.
- **Hangulatnapló (sablon):** lépés-progress · emoji-skála (5 fok, kiválasztott felnagyítva accent-körben) · több-választós chipek · „diktálós kifejtés (később)" halvány sor · `Tovább →`.
- **Panik:** lélegző kör (lüktet) · érzés-chipek · eszközök (Légzés/Nyugi-hang/Kiírom) · `📣 Szólok anyáéknak` + „Te döntöd el. Nem muszáj."
- **Ébresztő-beállító:** idő + napok · saját hang (kedvenc zenekar) · 🔗 lánc-ébresztő kapcsoló · 🧩 feladvány-nehézség segment (Nincs/Könnyű/Kemény). A megszólalás **rendszer-UI (AlarmKit)**, nem tervezendő.
- **Beállítások › Kinézet:** élő előnézet-csempe · háttérválasztó (gradiensek + Fotó feltöltés, meglévő fotónál Csere/Törlés) · kiemelőszín (presetek + szabad választó) · „Megosztás a szülőkkel" belépő.

---

## 6. Mozgás

Visszafogott. Lüktetés (`scale 1↔1.06`, ~2.6–3.5s) csak a Panik gombon és a lélegző körön. Válaszra tapintás-visszajelzés (haptics). Nincs harsány, figyelemelvonó animáció.

---

## 7. Amit NEM ez a dokumentum ír le

- Ébresztő megszólalási képernyő, rendszer-értesítések (iOS/AlarmKit adja).
- Adatmodell, szinkron (CloudKit-hibrid), pecsétes napló mechanizmus → lásd funkcionális spec.
- Szülő-mód UI (külön kör, ha kell).
