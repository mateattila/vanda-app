# 4.1 — Panikgomb 1. szint (eszközmodulok, backend nélkül) — implementációs terv

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `PanicPlaceholderView` helyére teljes értékű panik-képernyő kerül: érzés-chipek + szabad szöveg, és öt eszközmodul (légzés, 5-4-3-2-1 grounding, nyugi-mappa, NYUGI-tevékenységek, „Hívd anyát / apát") — backend nélkül, Vandával azonnal tesztelhetően.

**Architecture:** Két új CloudKit-kompatibilis SwiftData-modell (`PanicContact`, `CalmItem`); a logika (légzés-fázisok, grounding-lépések, érzés→eszköz-ajánlás, hívás-URL-ek) UI-mentes, unit-tesztelt típusokban él; a képernyők a `Screens/Panic/` alatt, a meglévő Theme-tokenekből építkezve.

**Tech Stack:** Swift + SwiftUI, SwiftData + CloudKit, Swift Testing (`@Test`/`#expect`), PhotosUI (`PhotosPicker`), meglévő `ImageDownscaler`.

**Design-forrás:** `docs/superpowers/specs/2026-07-07-phase4-panic-backend-design.md` (2. szakasz); spec 4.4; design-tokens 2. fejezet („Panik-képernyő: saját, sötétebb környezet"), 5–6. fejezet.

## Global Constraints

- **Build minden task végén hibátlan** (a repo gyökeréből):
  ```sh
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  xcodebuild -project VandaApp/VandaApp.xcodeproj -scheme VandaApp \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
  ```
- **Teszt-futtatás** (ugyanez `test`-tel; szűkíthető `-only-testing:VandaAppTests`-szel):
  ```sh
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  xcodebuild -project VandaApp/VandaApp.xcodeproj -scheme VandaApp \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:VandaAppTests
  ```
- Az Xcode-projekt **fileSystemSynchronized**: a `VandaApp/VandaApp/` és `VandaApp/VandaAppTests/` alá írt új fájlok maguktól a targetbe kerülnek, **pbxproj-t nem kell (és nem szabad) szerkeszteni**.
- **Ne nyúlj:** bundle ID, signing, entitlements, iCloud capability (CLAUDE.md).
- SwiftData-modellek CloudKit-kompatibilisen: minden mező opcionális vagy alapértékes, **nincs** `@Attribute(.unique)`, nincs `@Relationship`.
- UI csak `Theme` tokenekből (`Theme.Spacing.*`, `Theme.Radius.*`, `Theme.Gradients.panic`, `.vandaDisplay()/.vandaBody()/.vandaBodyStrong()/.vandaLabel()/.vandaCaption()`, `Color.ink/.inkMuted/.inkFaint`); nyers hex/pt érték nem szóródhat szét.
- Panik-környezet a design-tokens szerint: `Theme.Gradients.panic` háttér, fehér szöveg, `white.opacity(0.14–0.16)` chip/eszköz-felületek, elsődleges akció fehér kártyagomb ink-szöveggel (minta: a jelenlegi `PanicPlaceholderView` „Vissza" gombja).
- Hangnem: kedves, játszós, tegező magyar; se streak, se bűntudat. A szimulátor emoji-tofuja ismert környezeti hiba — ne kerülgesd kódból.
- Commit-üzenet stílus: `phase 4.1: <rövid angol összefoglaló>` (lásd `git log`).

---

### Task 1: Modellek — `PanicContact` + `CalmItem` + séma-regisztráció

**Files:**
- Create: `VandaApp/VandaApp/Models/PanicContact.swift`
- Create: `VandaApp/VandaApp/Models/CalmItem.swift`
- Modify: `VandaApp/VandaApp/Models/VandaModelContainer.swift` (schema-lista)
- Test: `VandaApp/VandaAppTests/PanicTests.swift` (új fájl)

**Interfaces:**
- Consumes: `VandaStore.schema` (meglévő), `ContentSource`-hoz hasonló modell-minták.
- Produces: `PanicContact` (`label: String`, `emoji: String`, `phoneNumber: String`, `orderIndex: Int`, `dialableNumber: String`, `telURL/faceTimeVideoURL/faceTimeAudioURL: URL?`) és `CalmItem` (`photoData: Data?`, `createdAt: Date`) — a 6., 4. és 7. task ezekre épül.

- [ ] **Step 1: Írd meg a bukó teszteket**

Új fájl: `VandaApp/VandaAppTests/PanicTests.swift`

```swift
//
//  PanicTests.swift
//  VandaAppTests
//
//  A panik-képernyő logikájának tesztjei (4. fázis): hívás-URL-ek,
//  légzés-fázisok, grounding-lépések, érzés→eszköz-ajánlás.
//

import Foundation
import Testing
@testable import VandaApp

// MARK: - Hívható szülők (PanicContact)

struct PanicContactTests {

    private func contact(_ number: String) -> PanicContact {
        let c = PanicContact()
        c.label = "Anya"
        c.phoneNumber = number
        return c
    }

    @Test func dialableNumberStripsFormatting() {
        #expect(contact("06 30 123-4567").dialableNumber == "06301234567")
    }

    @Test func dialableNumberKeepsLeadingPlus() {
        #expect(contact("+36 30 123 4567").dialableNumber == "+36301234567")
    }

    @Test func plusIsOnlyKeptAtTheStart() {
        #expect(contact("06+30 123").dialableNumber == "0630123")
    }

    @Test func emptyNumberGivesNoURLs() {
        let c = contact("   ")
        #expect(c.telURL == nil)
        #expect(c.faceTimeVideoURL == nil)
        #expect(c.faceTimeAudioURL == nil)
    }

    @Test func urlsUseTheRightSchemes() {
        let c = contact("+36301234567")
        #expect(c.telURL?.absoluteString == "tel://+36301234567")
        #expect(c.faceTimeVideoURL?.absoluteString == "facetime://+36301234567")
        #expect(c.faceTimeAudioURL?.absoluteString == "facetime-audio://+36301234567")
    }
}
```

- [ ] **Step 2: Futtasd — bukjon**

Run (repo gyökér):
```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project VandaApp/VandaApp.xcodeproj -scheme VandaApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:VandaAppTests
```
Expected: **build error** — `cannot find 'PanicContact' in scope`.

- [ ] **Step 3: Írd meg a modelleket**

Új fájl: `VandaApp/VandaApp/Models/PanicContact.swift`

```swift
//
//  PanicContact.swift
//  VandaApp
//
//  „Hívd anyát / apát" — a panik-képernyő hívás-gombjainak címzettjei
//  (spec 4.4). CloudKit-szinkronizált, a Beállításokban szerkeszthető.
//

import Foundation
import SwiftData

@Model
final class PanicContact {
    var id: UUID = UUID()
    var label: String = ""
    var emoji: String = "💛"
    /// Telefonszám — a tel: és a FaceTime linkek is ebből készülnek.
    var phoneNumber: String = ""
    var orderIndex: Int = 0
    var createdAt: Date = Date()

    init() {}
}

extension PanicContact {
    /// Csak számjegyek + esetleges vezető „+" („06 30 123-4567" → „06301234567").
    var dialableNumber: String {
        let trimmed = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ""
        for character in trimmed {
            if character.isWholeNumber {
                result.append(character)
            } else if character == "+" && result.isEmpty {
                result.append(character)
            }
        }
        return result
    }

    var telURL: URL? { deepLink(scheme: "tel") }
    var faceTimeVideoURL: URL? { deepLink(scheme: "facetime") }
    var faceTimeAudioURL: URL? { deepLink(scheme: "facetime-audio") }

    private func deepLink(scheme: String) -> URL? {
        let number = dialableNumber
        guard !number.isEmpty else { return nil }
        return URL(string: "\(scheme)://\(number)")
    }
}
```

Figyelem: a `plusIsOnlyKeptAtTheStart` teszt miatt a „+" csak akkor kerül be, ha még üres a `result` — de a „06+30" esetben a 0 után jövő „+"-t el kell dobni. A fenti `result.isEmpty` feltétel pontosan ezt adja.

Új fájl: `VandaApp/VandaApp/Models/CalmItem.swift`

```swift
//
//  CalmItem.swift
//  VandaApp
//
//  Nyugi-mappa elem (spec 4.4): Vanda által válogatott megnyugtató kép.
//  A fotó a ThemeSettings-mintát követve kicsinyítve, external storage-ben él.
//

import Foundation
import SwiftData

@Model
final class CalmItem {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var photoData: Data? = nil
    var createdAt: Date = Date()

    init() {}
}
```

Módosítás: `VandaApp/VandaApp/Models/VandaModelContainer.swift` — a schema-listába (a `ThemeSettings.self` elé) vedd fel:

```swift
        DailyTask.self,
        JournalTemplate.self,
        PanicContact.self,
        CalmItem.self,
        ThemeSettings.self,
```

- [ ] **Step 4: Futtasd — menjen át**

Run: ugyanaz a `test` parancs, mint a 2. lépésben.
Expected: **PASS** (az összes meglévő teszt + az 5 új `PanicContactTests`).

- [ ] **Step 5: Commit**

```bash
git add VandaApp/VandaApp/Models/PanicContact.swift VandaApp/VandaApp/Models/CalmItem.swift \
  VandaApp/VandaApp/Models/VandaModelContainer.swift VandaApp/VandaAppTests/PanicTests.swift
git commit -m "phase 4.1: PanicContact + CalmItem models with dial-URL helpers"
```

---

### Task 2: Légzés-motor + `BreathingView`

**Files:**
- Create: `VandaApp/VandaApp/Screens/Panic/BreathingPattern.swift`
- Create: `VandaApp/VandaApp/Screens/Panic/BreathingView.swift`
- Test: `VandaApp/VandaAppTests/PanicTests.swift` (bővítés)

**Interfaces:**
- Consumes: `Theme.Gradients.panic`, font-helperek.
- Produces: `BreathingPattern` (`.box`, `.fourSevenEight`; `displayName: String`, `cycleDuration: TimeInterval`, `phase(at:) -> (phase: BreathingPhase, progress: Double)`, `circleScale(at:) -> Double`) és `BreathingView` (paraméter nélküli, `dismiss`-szel záródó képernyő) — a 6. task fullScreenCoverben nyitja.

- [ ] **Step 1: Írd meg a bukó teszteket**

A `PanicTests.swift` végére:

```swift
// MARK: - Légzés-fázisok

struct BreathingPatternTests {

    @Test func boxCycleIsSixteenSeconds() {
        #expect(BreathingPattern.box.cycleDuration == 16)
        #expect(BreathingPattern.box.phases.count == 4)
    }

    @Test func fourSevenEightDurations() {
        let durations = BreathingPattern.fourSevenEight.phases.map(\.duration)
        #expect(durations == [4, 7, 8])
    }

    @Test func phaseAtZeroIsInhale() {
        #expect(BreathingPattern.box.phase(at: 0).phase.kind == .inhale)
    }

    @Test func boxPhaseAtFiveSecondsIsHold() {
        #expect(BreathingPattern.box.phase(at: 5).phase.kind == .hold)
    }

    @Test func phaseWrapsAroundTheCycle() {
        let wrapped = BreathingPattern.box.phase(at: 16.5)
        #expect(wrapped.phase.kind == .inhale)
        #expect(abs(wrapped.progress - 0.125) < 0.001)
    }

    @Test func circleGrowsDuringInhaleAndHoldsAfter() {
        let pattern = BreathingPattern.box
        #expect(pattern.circleScale(at: 0) < 0.7)
        #expect(pattern.circleScale(at: 3.999) > 0.99)
        // inhale utáni hold: kitágulva marad
        #expect(pattern.circleScale(at: 5) == 1.0)
        // exhale utáni hold: összehúzva marad
        #expect(pattern.circleScale(at: 13) < 0.7)
    }
}
```

- [ ] **Step 2: Futtasd — bukjon**

Run: a szokásos `test` parancs.
Expected: build error — `cannot find 'BreathingPattern' in scope`.

- [ ] **Step 3: Írd meg a motort**

Új fájl: `VandaApp/VandaApp/Screens/Panic/BreathingPattern.swift`

```swift
//
//  BreathingPattern.swift
//  VandaApp
//
//  Vezetett légzés (spec 4.4): box breathing és 4-7-8. UI-mentes motor,
//  a BreathingView TimelineView-ból hívja az eltelt idővel.
//

import Foundation

enum BreathingPhaseKind: Equatable {
    case inhale
    case hold
    case exhale
}

struct BreathingPhase: Equatable {
    let kind: BreathingPhaseKind
    let label: String
    let duration: TimeInterval
}

enum BreathingPattern: String, CaseIterable, Identifiable {
    case box
    case fourSevenEight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .box: "Négyzet"
        case .fourSevenEight: "4·7·8"
        }
    }

    var phases: [BreathingPhase] {
        switch self {
        case .box:
            [
                BreathingPhase(kind: .inhale, label: "Szívd be…", duration: 4),
                BreathingPhase(kind: .hold, label: "Tartsd bent…", duration: 4),
                BreathingPhase(kind: .exhale, label: "Fújd ki…", duration: 4),
                BreathingPhase(kind: .hold, label: "Maradj így…", duration: 4),
            ]
        case .fourSevenEight:
            [
                BreathingPhase(kind: .inhale, label: "Szívd be…", duration: 4),
                BreathingPhase(kind: .hold, label: "Tartsd bent…", duration: 7),
                BreathingPhase(kind: .exhale, label: "Fújd ki lassan…", duration: 8),
            ]
        }
    }

    var cycleDuration: TimeInterval {
        phases.reduce(0) { $0 + $1.duration }
    }

    /// A ciklusbeli pillanathoz tartozó fázis és a fázison belüli 0…1 haladás.
    func phase(at elapsed: TimeInterval) -> (phase: BreathingPhase, progress: Double) {
        let t = normalized(elapsed)
        var start: TimeInterval = 0
        for phase in phases {
            if t < start + phase.duration {
                return (phase, (t - start) / phase.duration)
            }
            start += phase.duration
        }
        return (phases[0], 0)
    }

    /// A lélegző kör skálája (0.62 összehúzva … 1.0 kitágulva); hold közben
    /// az előző fázis végállapotában marad.
    func circleScale(at elapsed: TimeInterval) -> Double {
        let minScale = 0.62
        let t = normalized(elapsed)
        var start: TimeInterval = 0
        for (index, phase) in phases.enumerated() {
            if t < start + phase.duration {
                let progress = (t - start) / phase.duration
                switch phase.kind {
                case .inhale: return minScale + (1 - minScale) * progress
                case .exhale: return 1 - (1 - minScale) * progress
                case .hold:
                    let previous = phases[(index + phases.count - 1) % phases.count]
                    return previous.kind == .inhale ? 1.0 : minScale
                }
            }
            start += phase.duration
        }
        return minScale
    }

    private func normalized(_ elapsed: TimeInterval) -> TimeInterval {
        let t = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        return t < 0 ? t + cycleDuration : t
    }
}
```

- [ ] **Step 4: Futtasd — menjen át**

Run: a szokásos `test` parancs. Expected: **PASS**.

- [ ] **Step 5: Írd meg a képernyőt**

Új fájl: `VandaApp/VandaApp/Screens/Panic/BreathingView.swift`

```swift
//
//  BreathingView.swift
//  VandaApp
//
//  Táguló-szűkülő körrel vezetett légzés. A kör animációja itt funkció,
//  nem dísz — Reduce Motion mellett is fut, mert maga a gyakorlat.
//

import SwiftUI

struct BreathingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pattern: BreathingPattern = .box
    @State private var startDate = Date()

    var body: some View {
        ZStack {
            Theme.Gradients.panic
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.cardGap) {
                HStack(spacing: Theme.Spacing.chipHorizontal / 2) {
                    ForEach(BreathingPattern.allCases) { candidate in
                        Button {
                            pattern = candidate
                            startDate = Date()
                        } label: {
                            Text(candidate.displayName)
                                .font(.vandaBodyStrong())
                                .foregroundStyle(pattern == candidate ? Color.ink : .white)
                                .padding(.vertical, Theme.Spacing.chipVertical)
                                .padding(.horizontal, Theme.Spacing.chipHorizontal)
                                .background(
                                    pattern == candidate ? Color.white : Color.white.opacity(0.15),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, Theme.Spacing.cardGap)

                Spacer()

                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(startDate)
                    let current = pattern.phase(at: elapsed)

                    VStack(spacing: 30) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.15))
                                .frame(width: 250, height: 250)
                            Circle()
                                .fill(.white.opacity(0.9))
                                .frame(width: 210, height: 210)
                                .scaleEffect(pattern.circleScale(at: elapsed))
                        }

                        Text(current.phase.label)
                            .font(.vandaDisplay())
                            .foregroundStyle(.white)
                            .sensoryFeedback(.impact(weight: .light), trigger: current.phase.label)
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Kész vagyok")
                        .font(.vandaBodyStrong())
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Color.white,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.bottom, Theme.Spacing.screenMargin)
            }
        }
    }
}

#Preview {
    BreathingView()
}
```

- [ ] **Step 6: Build + commit**

Run: a Global Constraints build-parancsa. Expected: **BUILD SUCCEEDED**.

```bash
git add VandaApp/VandaApp/Screens/Panic/BreathingPattern.swift \
  VandaApp/VandaApp/Screens/Panic/BreathingView.swift VandaApp/VandaAppTests/PanicTests.swift
git commit -m "phase 4.1: guided breathing (box + 4-7-8) with tested phase engine"
```

---

### Task 3: Grounding — 5-4-3-2-1

**Files:**
- Create: `VandaApp/VandaApp/Screens/Panic/GroundingGuide.swift`
- Create: `VandaApp/VandaApp/Screens/Panic/GroundingView.swift`
- Test: `VandaApp/VandaAppTests/PanicTests.swift` (bővítés)

**Interfaces:**
- Produces: `GroundingGuide.steps: [GroundingStep]` (`count: Int`, `emoji: String`, `title: String`, `hint: String`) és `GroundingView` (paraméter nélküli képernyő) — a 6. task fullScreenCoverben nyitja.

- [ ] **Step 1: Írd meg a bukó teszteket**

A `PanicTests.swift` végére:

```swift
// MARK: - Grounding (5-4-3-2-1)

struct GroundingGuideTests {

    @Test func hasFiveStepsCountingDown() {
        #expect(GroundingGuide.steps.map(\.count) == [5, 4, 3, 2, 1])
    }

    @Test func everyStepHasTitleAndHint() {
        for step in GroundingGuide.steps {
            #expect(!step.title.isEmpty)
            #expect(!step.hint.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Futtasd — bukjon**

Run: a szokásos `test` parancs. Expected: build error — `cannot find 'GroundingGuide' in scope`.

- [ ] **Step 3: Írd meg a lépés-adatokat**

Új fájl: `VandaApp/VandaApp/Screens/Panic/GroundingGuide.swift`

```swift
//
//  GroundingGuide.swift
//  VandaApp
//
//  5-4-3-2-1 grounding gyakorlat lépései (spec 4.4), lépésenként vezetve.
//

import Foundation

struct GroundingStep: Equatable {
    let count: Int
    let emoji: String
    let title: String
    let hint: String
}

enum GroundingGuide {
    static let steps: [GroundingStep] = [
        GroundingStep(
            count: 5, emoji: "👀",
            title: "5 dolog, amit látsz",
            hint: "Nézz körül lassan… bármi jó: egy szín, egy tárgy, egy árnyék."
        ),
        GroundingStep(
            count: 4, emoji: "✋",
            title: "4 dolog, amit megérinthetsz",
            hint: "A pulcsid, a szék, a hajad, a saját tenyered…"
        ),
        GroundingStep(
            count: 3, emoji: "👂",
            title: "3 hang, amit hallasz",
            hint: "Figyelj egy kicsit… a halk hangok is számítanak."
        ),
        GroundingStep(
            count: 2, emoji: "👃",
            title: "2 illat, amit érzel",
            hint: "Ha nem találsz, csak szívd be kétszer mélyen a levegőt — az is ér."
        ),
        GroundingStep(
            count: 1, emoji: "👅",
            title: "1 íz, amit érzel",
            hint: "Egy korty víz is tökéletes."
        ),
    ]
}
```

- [ ] **Step 4: Futtasd — menjen át**

Run: a szokásos `test` parancs. Expected: **PASS**.

- [ ] **Step 5: Írd meg a képernyőt**

Új fájl: `VandaApp/VandaApp/Screens/Panic/GroundingView.swift`

```swift
//
//  GroundingView.swift
//  VandaApp
//
//  Lépésenként vezetett 5-4-3-2-1: minden lépésben annyi pötty, ahány
//  dolgot keresünk; koppintásra telnek, a lépés a Tovább gombbal zárul.
//

import SwiftUI

struct GroundingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var stepIndex = 0
    @State private var foundCount = 0

    private var isDone: Bool { stepIndex >= GroundingGuide.steps.count }

    var body: some View {
        ZStack {
            Theme.Gradients.panic
                .ignoresSafeArea()

            if isDone {
                VStack(spacing: Theme.Spacing.cardGap) {
                    Spacer()
                    Text("🫶")
                        .font(.system(size: 52))
                    Text("Ügyes vagy. Itt vagy, most vagy.")
                        .font(.vandaDisplay())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.screenMargin)
                    Spacer()
                    closeButton(title: "Vissza az eszközökhöz")
                }
            } else {
                let step = GroundingGuide.steps[stepIndex]
                VStack(spacing: Theme.Spacing.cardGap) {
                    progressDots
                        .padding(.top, Theme.Spacing.cardGap)

                    Spacer()

                    Text(step.emoji)
                        .font(.system(size: 52))
                    Text(step.title)
                        .font(.vandaDisplay())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(step.hint)
                        .font(.vandaBody())
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.screenMargin)

                    HStack(spacing: Theme.Spacing.chipHorizontal) {
                        ForEach(0..<step.count, id: \.self) { index in
                            Circle()
                                .fill(index < foundCount ? Color.white : Color.white.opacity(0.2))
                                .frame(width: 34, height: 34)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard foundCount < step.count else { return }
                        withAnimation(.snappy) { foundCount += 1 }
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: foundCount)
                    .padding(.top, Theme.Spacing.cardGap)
                    .accessibilityLabel("Megtaláltam még egyet")
                    .accessibilityAddTraits(.isButton)

                    Spacer()

                    Button {
                        withAnimation(.snappy) {
                            stepIndex += 1
                            foundCount = 0
                        }
                    } label: {
                        Text(foundCount >= step.count ? "Tovább →" : "Ugorjunk tovább")
                            .font(.vandaBodyStrong())
                            .foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Color.white.opacity(foundCount >= step.count ? 1 : 0.7),
                                in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.bottom, Theme.Spacing.screenMargin)
                }
            }
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<GroundingGuide.steps.count, id: \.self) { index in
                Circle()
                    .fill(index <= stepIndex ? Color.white : Color.white.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func closeButton(title: String) -> some View {
        Button {
            dismiss()
        } label: {
            Text(title)
                .font(.vandaBodyStrong())
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Color.white,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.bottom, Theme.Spacing.screenMargin)
    }
}

#Preview {
    GroundingView()
}
```

- [ ] **Step 6: Build + commit**

Run: build-parancs. Expected: **BUILD SUCCEEDED**.

```bash
git add VandaApp/VandaApp/Screens/Panic/GroundingGuide.swift \
  VandaApp/VandaApp/Screens/Panic/GroundingView.swift VandaApp/VandaAppTests/PanicTests.swift
git commit -m "phase 4.1: 5-4-3-2-1 grounding exercise, step-by-step"
```

---

### Task 4: Nyugi-mappa (`CalmFolderView`)

**Files:**
- Create: `VandaApp/VandaApp/Screens/Panic/CalmFolderView.swift`

**Interfaces:**
- Consumes: `CalmItem` (Task 1), `ImageDownscaler.jpegData(from:maxDimension:quality:)` (meglévő, `Services/ImageDownscaler.swift`).
- Produces: `CalmFolderView` (paraméter nélküli képernyő) — a 6. task fullScreenCoverben nyitja.

- [ ] **Step 1: Írd meg a képernyőt**

Új fájl: `VandaApp/VandaApp/Screens/Panic/CalmFolderView.swift`

```swift
//
//  CalmFolderView.swift
//  VandaApp
//
//  Nyugi-mappa (spec 4.4): Vanda által válogatott megnyugtató képek.
//  PhotosPickerből töltődik, a fotók kicsinyítve tárolódnak (CalmItem).
//

import PhotosUI
import SwiftData
import SwiftUI

struct CalmFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CalmItem.createdAt, order: .reverse) private var items: [CalmItem]

    @State private var picks: [PhotosPickerItem] = []
    @State private var viewerItem: CalmItem?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        ZStack {
            Theme.Gradients.panic
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.cardGap) {
                ScrollView {
                    if items.isEmpty {
                        VStack(spacing: Theme.Spacing.cardGap) {
                            Text("🌿")
                                .font(.system(size: 52))
                                .padding(.top, 80)
                            Text("Ez a te nyugi-mappád")
                                .font(.vandaDisplay())
                                .foregroundStyle(.white)
                            Text("Gyűjts ide képeket, amiktől jobb kedved lesz — kedvencek, emlékek, cukiságok.")
                                .font(.vandaBody())
                                .foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.Spacing.screenMargin)
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(items) { item in
                                if let data = item.photoData, let image = UIImage(data: data) {
                                    Button {
                                        viewerItem = item
                                    } label: {
                                        Image(uiImage: image)
                                            .resizable()
                                            .aspectRatio(1, contentMode: .fill)
                                            .frame(minWidth: 100, minHeight: 100)
                                            .clipShape(RoundedRectangle(
                                                cornerRadius: Theme.Radius.cardSmall,
                                                style: .continuous
                                            ))
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            modelContext.delete(item)
                                        } label: {
                                            Label("Törlés", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.screenMargin)
                        .padding(.top, Theme.Spacing.cardGap)
                    }
                }

                PhotosPicker(selection: $picks, maxSelectionCount: 10, matching: .images) {
                    Text("📷 Képek hozzáadása")
                        .font(.vandaBodyStrong())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Color.white.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        )
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)

                Button {
                    dismiss()
                } label: {
                    Text("Vissza")
                        .font(.vandaBodyStrong())
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Color.white,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.bottom, Theme.Spacing.screenMargin)
            }
        }
        .onChange(of: picks) {
            Task { await importPicks() }
        }
        .fullScreenCover(item: $viewerItem) { item in
            CalmPhotoViewer(startItem: item, items: items)
        }
    }

    private func importPicks() async {
        for pick in picks {
            guard let data = try? await pick.loadTransferable(type: Data.self),
                  let downscaled = ImageDownscaler.jpegData(from: data, maxDimension: 1600) else { continue }
            let item = CalmItem()
            item.photoData = downscaled
            modelContext.insert(item)
        }
        picks = []
    }
}

/// Egyszerű lapozós néző a nyugi-képekhez.
private struct CalmPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let startItem: CalmItem
    let items: [CalmItem]

    @State private var selectedID: UUID?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.Gradients.panic
                .ignoresSafeArea()

            TabView(selection: $selectedID) {
                ForEach(items) { item in
                    if let data = item.photoData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .tag(Optional(item.id))
                    }
                }
            }
            .tabViewStyle(.page)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(Theme.Spacing.screenMargin)
        }
        .onAppear { selectedID = startItem.id }
    }
}

#Preview {
    CalmFolderView()
        .modelContainer(for: CalmItem.self, inMemory: true)
}
```

- [ ] **Step 2: Build + commit**

Run: build-parancs. Expected: **BUILD SUCCEEDED**.

```bash
git add VandaApp/VandaApp/Screens/Panic/CalmFolderView.swift
git commit -m "phase 4.1: calm folder — curated photo grid with picker and viewer"
```

---

### Task 5: Érzés-chipek és eszköz-ajánlás (`PanicToolbox`)

**Files:**
- Create: `VandaApp/VandaApp/Screens/Panic/PanicToolbox.swift`
- Test: `VandaApp/VandaAppTests/PanicTests.swift` (bővítés)

**Interfaces:**
- Produces: `PanicFeeling` (`label`, `emoji`), `PanicToolID: String, CaseIterable, Identifiable` (`.breathing, .grounding, .calmFolder, .calmActivities, .callParents`), `PanicToolbox.recommendedOrder(for:) -> [PanicToolID]` — a 6. task ebből rendez.

- [ ] **Step 1: Írd meg a bukó teszteket**

A `PanicTests.swift` végére:

```swift
// MARK: - Érzés → eszköz-ajánlás

struct PanicToolboxTests {

    @Test func defaultOrderContainsEveryToolOnce() {
        let order = PanicToolbox.recommendedOrder(for: nil)
        #expect(Set(order) == Set(PanicToolID.allCases))
        #expect(order.count == PanicToolID.allCases.count)
    }

    @Test(arguments: PanicFeeling.allCases)
    func everyFeelingRanksEveryToolOnce(feeling: PanicFeeling) {
        let order = PanicToolbox.recommendedOrder(for: feeling)
        #expect(Set(order) == Set(PanicToolID.allCases))
        #expect(order.count == PanicToolID.allCases.count)
    }

    @Test func scaredLeadsWithBreathing() {
        #expect(PanicToolbox.recommendedOrder(for: .scared).first == .breathing)
    }

    @Test func angryLeadsWithGrounding() {
        #expect(PanicToolbox.recommendedOrder(for: .angry).first == .grounding)
    }

    @Test func sadLeadsWithCalmFolder() {
        #expect(PanicToolbox.recommendedOrder(for: .sad).first == .calmFolder)
    }
}
```

- [ ] **Step 2: Futtasd — bukjon**

Run: a szokásos `test` parancs. Expected: build error — `cannot find 'PanicToolbox' in scope`.

- [ ] **Step 3: Írd meg a típusokat**

Új fájl: `VandaApp/VandaApp/Screens/Panic/PanicToolbox.swift`

```swift
//
//  PanicToolbox.swift
//  VandaApp
//
//  A panik-képernyő eszközkészlete (spec 4.4): érzés-chipek és a hozzájuk
//  illő eszköz-sorrend. A modulrendszer v1-e — új eszköz felvételéhez
//  a PanicToolID bővítendő, a képernyő a sorrendből dolgozik.
//

import Foundation

enum PanicFeeling: String, CaseIterable, Identifiable {
    case scared
    case angry
    case restless
    case sad

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scared: "Félek"
        case .angry: "Dühös vagyok"
        case .restless: "Nem tudok megnyugodni"
        case .sad: "Szomorú vagyok"
        }
    }

    var emoji: String {
        switch self {
        case .scared: "😨"
        case .angry: "😤"
        case .restless: "🌀"
        case .sad: "😢"
        }
    }
}

enum PanicToolID: String, CaseIterable, Identifiable {
    case breathing
    case grounding
    case calmFolder
    case calmActivities
    case callParents

    var id: String { rawValue }
}

enum PanicToolbox {
    static let defaultOrder: [PanicToolID] = [
        .breathing, .grounding, .calmFolder, .calmActivities, .callParents,
    ]

    /// Az érzéshez illő eszközök előre sorolva; a többi az alap sorrendben követ.
    static func recommendedOrder(for feeling: PanicFeeling?) -> [PanicToolID] {
        guard let feeling else { return defaultOrder }
        let lead: [PanicToolID] = switch feeling {
        case .scared: [.breathing, .callParents]
        case .angry: [.grounding, .calmActivities]
        case .restless: [.breathing, .grounding]
        case .sad: [.calmFolder, .callParents]
        }
        return lead + defaultOrder.filter { !lead.contains($0) }
    }
}
```

- [ ] **Step 4: Futtasd — menjen át**

Run: a szokásos `test` parancs. Expected: **PASS**.

- [ ] **Step 5: Commit**

```bash
git add VandaApp/VandaApp/Screens/Panic/PanicToolbox.swift VandaApp/VandaAppTests/PanicTests.swift
git commit -m "phase 4.1: feeling chips model + feeling-to-tool ranking"
```

---

### Task 6: `PanicView` kompozíció + NYUGI-tevékenységek + a placeholder cseréje

**Files:**
- Create: `VandaApp/VandaApp/Screens/Panic/PanicView.swift`
- Create: `VandaApp/VandaApp/Screens/Panic/CalmActivitiesView.swift`
- Modify: `VandaApp/VandaApp/Screens/Today/TodayView.swift:54-56` (cover-tartalom cseréje)
- Delete: `VandaApp/VandaApp/Screens/Panic/PanicPlaceholderView.swift`

**Interfaces:**
- Consumes: Task 1–5 összes produced típusa; `Activity` + `ActivityTag.calming` (meglévő); `DailyTask` (meglévő — az elfogadott tevékenység a Ma falára kerül, a `MoodCheckView.accept(_:)` mintája szerint).
- Produces: `PanicView` (paraméter nélküli képernyő, fullScreenCoverből).

- [ ] **Step 1: Írd meg a NYUGI-tevékenységek nézetet**

Új fájl: `VandaApp/VandaApp/Screens/Panic/CalmActivitiesView.swift`

```swift
//
//  CalmActivitiesView.swift
//  VandaApp
//
//  A tevékenység-katalógus NYUGI-címkés elemei a panik-képernyőről
//  (spec 3. és 4.4: közös katalógus, a panikgomb a nyugi-eszközöket ajánlja).
//

import SwiftData
import SwiftUI

struct CalmActivitiesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var activities: [Activity]

    @State private var addedID: UUID?

    private var calmActivities: [Activity] {
        activities.filter { $0.activityTags.contains(.calming) }
    }

    var body: some View {
        ZStack {
            Theme.Gradients.panic
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.cardGap) {
                ScrollView {
                    if calmActivities.isEmpty {
                        VStack(spacing: Theme.Spacing.cardGap) {
                            Text("🌿")
                                .font(.system(size: 52))
                                .padding(.top, 80)
                            Text("Még nincs nyugi-tevékenység")
                                .font(.vandaDisplay())
                                .foregroundStyle(.white)
                            Text("Az Unatkozom falon jelölj meg pár tevékenységet Nyugi címkével, és itt fognak várni.")
                                .font(.vandaBody())
                                .foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.Spacing.screenMargin)
                        }
                    } else {
                        VStack(spacing: Theme.Spacing.cardGap) {
                            ForEach(calmActivities) { activity in
                                Button {
                                    accept(activity)
                                } label: {
                                    HStack(spacing: Theme.Spacing.cardPadding) {
                                        Text(activity.emoji)
                                            .font(.system(size: 28))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(activity.title)
                                                .font(.vandaBodyStrong())
                                                .foregroundStyle(.white)
                                            if !activity.metaLine.isEmpty {
                                                Text(activity.metaLine)
                                                    .font(.vandaCaption())
                                                    .foregroundStyle(.white.opacity(0.7))
                                            }
                                        }
                                        Spacer()
                                        Text(addedID == activity.id ? "Ma-listán ✓" : "Kipróbálom")
                                            .font(.vandaCaption())
                                            .foregroundStyle(.white.opacity(0.85))
                                    }
                                    .padding(Theme.Spacing.cardPadding)
                                    .background(
                                        Color.white.opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.screenMargin)
                        .padding(.top, Theme.Spacing.cardGap)
                    }
                }

                Button {
                    dismiss()
                } label: {
                    Text("Vissza")
                        .font(.vandaBodyStrong())
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Color.white,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.bottom, Theme.Spacing.screenMargin)
            }
        }
    }

    private func accept(_ activity: Activity) {
        guard addedID != activity.id else { return }
        let task = DailyTask()
        task.title = "\(activity.emoji) \(activity.title)"
        task.source = .today
        modelContext.insert(task)
        withAnimation(.snappy) { addedID = activity.id }
    }
}

#Preview {
    CalmActivitiesView()
        .modelContainer(for: Activity.self, inMemory: true)
}
```

Megjegyzés: a `DailyTask.source = .today` mintája a `MoodCheckView.accept(_:)`-ból jön; a `DailyTaskSource.today` eset létezik (ellenőrizve: `Models/DailyTask.swift:12-30`).

- [ ] **Step 2: Írd meg a fő panik-képernyőt**

Új fájl: `VandaApp/VandaApp/Screens/Panic/PanicView.swift`

```swift
//
//  PanicView.swift
//  VandaApp
//
//  A panik-képernyő 1. szintje (spec 4.4): érzés-chipek + szabad szöveg,
//  és az érzéshez rendezett eszközmodulok. A „Szólok anyáéknak" riasztás
//  a 4.3 lépésben kerül ide; a note state már most az előszobája.
//

import SwiftData
import SwiftUI

struct PanicView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \PanicContact.orderIndex) private var contacts: [PanicContact]

    @State private var feeling: PanicFeeling?
    @State private var note = ""
    @State private var activeTool: PanicToolID?
    @State private var isPulsing = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.Gradients.panic
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.cardGap) {
                    header

                    feelingChips

                    TextField(
                        "",
                        text: $note,
                        prompt: Text("Ha szeretnéd, írd ki, mi van… (nem kötelező)")
                            .foregroundStyle(.white.opacity(0.5)),
                        axis: .vertical
                    )
                    .font(.vandaBody())
                    .foregroundStyle(.white)
                    .padding(Theme.Spacing.cardPadding)
                    .background(
                        Color.white.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
                    )

                    ForEach(PanicToolbox.recommendedOrder(for: feeling)) { tool in
                        if tool == .callParents {
                            callParentsCard
                        } else {
                            toolRow(tool)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, 70)
                .padding(.bottom, Theme.Spacing.screenMargin)
                .animation(.snappy, value: feeling)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(Theme.Spacing.screenMargin)
            .accessibilityLabel("Bezárás")
        }
        .fullScreenCover(item: $activeTool) { tool in
            switch tool {
            case .breathing: BreathingView()
            case .grounding: GroundingView()
            case .calmFolder: CalmFolderView()
            case .calmActivities: CalmActivitiesView()
            case .callParents: EmptyView()
            }
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.cardGap) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 110, height: 110)
                Circle()
                    .fill(.white.opacity(0.85))
                    .frame(width: 84, height: 84)
                    .scaleEffect(isPulsing ? Theme.Motion.pulseScale : 1)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: Theme.Motion.pulsePeriod / 2)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }

            Text("Itt vagyunk. Lélegezz egy nagyot.")
                .font(.vandaDisplay())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
    }

    private var feelingChips: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.chipVertical) {
            Text("Mi van most?")
                .font(.vandaLabel())
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.6))

            FlowLayout(spacing: Theme.Spacing.chipVertical) {
                ForEach(PanicFeeling.allCases) { candidate in
                    let isSelected = feeling == candidate
                    Button {
                        withAnimation(.snappy) {
                            feeling = isSelected ? nil : candidate
                        }
                    } label: {
                        Text("\(candidate.emoji) \(candidate.label)")
                            .font(.vandaBodyStrong(13))
                            .foregroundStyle(isSelected ? Color.ink : .white)
                            .padding(.vertical, Theme.Spacing.chipVertical)
                            .padding(.horizontal, Theme.Spacing.chipHorizontal)
                            .background(
                                isSelected ? Color.white : Color.white.opacity(0.15),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(weight: .light), trigger: feeling)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toolRow(_ tool: PanicToolID) -> some View {
        let (emoji, title, subtitle): (String, String, String) = switch tool {
        case .breathing: ("🫁", "Légzés", "Vezetett levegővétel, táguló körrel")
        case .grounding: ("🖐️", "5-4-3-2-1", "Nézz körül — visszahozunk a jelenbe")
        case .calmFolder: ("🌿", "Nyugi-mappa", "A képeid, amik jólesnek")
        case .calmActivities: ("✨", "Nyugi-tevékenységek", "Pár bevált, csendes ötlet")
        case .callParents: ("📞", "", "")
        }

        return Button {
            activeTool = tool
        } label: {
            HStack(spacing: Theme.Spacing.cardPadding) {
                Text(emoji)
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.vandaBodyStrong())
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.vandaCaption())
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(Theme.Spacing.cardPadding)
            .background(
                Color.white.opacity(0.15),
                in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var callParentsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
            HStack(spacing: Theme.Spacing.cardPadding) {
                Text("📞")
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hívd anyát / apát")
                        .font(.vandaBodyStrong())
                        .foregroundStyle(.white)
                    Text(contacts.isEmpty
                         ? "A Beállításokban tudjátok felvenni a számokat"
                         : "Egy koppintás, és ott vannak")
                        .font(.vandaCaption())
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
            }

            ForEach(contacts) { contact in
                HStack(spacing: Theme.Spacing.chipHorizontal / 2) {
                    Text("\(contact.emoji) \(contact.label)")
                        .font(.vandaBodyStrong())
                        .foregroundStyle(.white)
                    Spacer()
                    if let tel = contact.telURL {
                        contactAction("Hívás", systemImage: "phone.fill", url: tel)
                    }
                    if let facetime = contact.faceTimeVideoURL {
                        contactAction("FaceTime", systemImage: "video.fill", url: facetime)
                    }
                }
            }
        }
        .padding(Theme.Spacing.cardPadding)
        .background(
            Color.white.opacity(0.15),
            in: RoundedRectangle(cornerRadius: Theme.Radius.cardSmall, style: .continuous)
        )
    }

    private func contactAction(_ title: String, systemImage: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.vandaBodyStrong(13))
                .foregroundStyle(Color.ink)
                .padding(.vertical, Theme.Spacing.chipVertical)
                .padding(.horizontal, Theme.Spacing.chipHorizontal)
                .background(Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Egyszerű balra zárt, sortörő chip-elrendezés.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = makeRows(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in makeRows(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.range {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var range: Range<Int>
        var height: CGFloat
    }

    private func makeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var start = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                rows.append(Row(range: start..<index, height: rowHeight))
                start = index
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        if start < subviews.count {
            rows.append(Row(range: start..<subviews.count, height: rowHeight))
        }
        return rows
    }
}

#Preview {
    PanicView()
        .modelContainer(for: [PanicContact.self, CalmItem.self, Activity.self], inMemory: true)
}
```

Megjegyzés: ha a kódbázisban időközben már van FlowLayout-szerű elrendezés (`FlowChips` a `JournalTemplateFillView`-ban képernyő-privát), akkor is itt sajátot használunk — a `FlowChips` nem publikus API-ja annak a képernyőnek; közös komponenssé emelés csak akkor, ha egy harmadik hely is kell majd (YAGNI).

- [ ] **Step 3: Cseréld le a placeholdert**

`VandaApp/VandaApp/Screens/Today/TodayView.swift` 54–56. sor környékén:

```swift
            .fullScreenCover(isPresented: $isPanicPresented) {
                PanicView()
            }
```

Töröld a fájlt: `VandaApp/VandaApp/Screens/Panic/PanicPlaceholderView.swift`

```bash
git rm VandaApp/VandaApp/Screens/Panic/PanicPlaceholderView.swift
```

- [ ] **Step 4: Build + tesztek**

Run: build-parancs, majd a `test` parancs. Expected: **BUILD SUCCEEDED**, minden teszt **PASS**.

- [ ] **Step 5: Commit**

```bash
git add VandaApp/VandaApp/Screens/Panic/PanicView.swift \
  VandaApp/VandaApp/Screens/Panic/CalmActivitiesView.swift \
  VandaApp/VandaApp/Screens/Today/TodayView.swift
git commit -m "phase 4.1: real panic screen — feeling chips, ranked tools, call buttons"
```

---

### Task 7: Beállítások — hívható szülők szerkesztője

**Files:**
- Create: `VandaApp/VandaApp/Screens/Settings/PanicContactsSettingsView.swift`
- Modify: `VandaApp/VandaApp/Screens/Settings/SettingsView.swift` (új NavigationLink a „Barométer" sor után)

**Interfaces:**
- Consumes: `PanicContact` (Task 1), `settingsRow(symbol:title:subtitle:)` minta a SettingsView-ból.
- Produces: `PanicContactsSettingsView` (paraméter nélküli, pusholt képernyő).

- [ ] **Step 1: Írd meg a szerkesztőt**

Új fájl: `VandaApp/VandaApp/Screens/Settings/PanicContactsSettingsView.swift`

```swift
//
//  PanicContactsSettingsView.swift
//  VandaApp
//
//  A panik-képernyő „Hívd anyát / apát" gombjainak címzettjei.
//  Világos settings-környezet (nem a panik sötét gradiense).
//

import SwiftData
import SwiftUI

struct PanicContactsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PanicContact.orderIndex) private var contacts: [PanicContact]
    @Query private var themeSettings: [ThemeSettings]

    @State private var editingContact: PanicContact?
    @State private var isAddingNew = false

    private var theme: ThemeSettings? { themeSettings.first }

    var body: some View {
        ZStack {
            ThemedBackground(settings: theme)

            ScrollView {
                VStack(spacing: Theme.Spacing.cardGap) {
                    Text("Ezek a gombok jelennek meg a panik-képernyőn — egy koppintás, és hívja is őket.")
                        .font(.vandaCaption())
                        .foregroundStyle(Color.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(contacts) { contact in
                        Button {
                            editingContact = contact
                        } label: {
                            HStack(spacing: Theme.Spacing.cardPadding) {
                                Text(contact.emoji)
                                    .font(.system(size: 28))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.label)
                                        .font(.vandaBodyStrong())
                                        .foregroundStyle(Color.ink)
                                    Text(contact.phoneNumber)
                                        .font(.vandaCaption())
                                        .foregroundStyle(Color.inkMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.inkFaint)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .vandaCard(surface: theme?.cardSurface ?? .surface)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                modelContext.delete(contact)
                            } label: {
                                Label("Törlés", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        isAddingNew = true
                    } label: {
                        Label("Új elérhetőség", systemImage: "plus")
                            .font(.vandaBodyStrong())
                            .foregroundStyle(theme?.accentColor ?? Theme.Accent.default)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Color.surfaceTint,
                                in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, Theme.Spacing.cardGap)
            }
        }
        .navigationTitle("Hívható szülők")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $editingContact) { contact in
            PanicContactEditor(contact: contact)
        }
        .sheet(isPresented: $isAddingNew) {
            PanicContactEditor(contact: nil)
        }
    }
}

private struct PanicContactEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PanicContact.orderIndex) private var contacts: [PanicContact]

    let contact: PanicContact?

    @State private var label = ""
    @State private var emoji = "💛"
    @State private var phoneNumber = ""

    private let emojiOptions = ["💛", "💙", "🧡", "💜", "🩷", "💚"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Ki ő?") {
                    TextField("Név (pl. Anya)", text: $label)
                    Picker("Szín-szívecske", selection: $emoji) {
                        ForEach(emojiOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Telefonszám") {
                    TextField("+36 30 123 4567", text: $phoneNumber)
                        .keyboardType(.phonePad)
                }
            }
            .navigationTitle(contact == nil ? "Új elérhetőség" : "Szerkesztés")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Mégse") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mentés") { save() }
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty
                                  || phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let contact {
                    label = contact.label
                    emoji = contact.emoji
                    phoneNumber = contact.phoneNumber
                }
            }
        }
    }

    private func save() {
        let target: PanicContact
        if let contact {
            target = contact
        } else {
            target = PanicContact()
            target.orderIndex = (contacts.map(\.orderIndex).max() ?? -1) + 1
            modelContext.insert(target)
        }
        target.label = label.trimmingCharacters(in: .whitespaces)
        target.emoji = emoji
        target.phoneNumber = phoneNumber.trimmingCharacters(in: .whitespaces)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        PanicContactsSettingsView()
    }
    .modelContainer(for: [PanicContact.self, ThemeSettings.self], inMemory: true)
}
```

- [ ] **Step 2: Vedd fel a Beállítások-sort**

`VandaApp/VandaApp/Screens/Settings/SettingsView.swift` — a „Barométer" NavigationLink záró `.buttonStyle(.plain)` sora (45. sor) után szúrd be:

```swift
                    NavigationLink {
                        PanicContactsSettingsView()
                    } label: {
                        settingsRow(
                            symbol: "phone.fill",
                            title: "Hívható szülők",
                            subtitle: "A panik-képernyő hívás-gombjai"
                        )
                    }
                    .buttonStyle(.plain)
```

- [ ] **Step 3: Build + tesztek**

Run: build-parancs, majd `test` parancs. Expected: **BUILD SUCCEEDED**, minden teszt **PASS**.

- [ ] **Step 4: Commit**

```bash
git add VandaApp/VandaApp/Screens/Settings/PanicContactsSettingsView.swift \
  VandaApp/VandaApp/Screens/Settings/SettingsView.swift
git commit -m "phase 4.1: parent contacts editor in settings"
```

---

### Task 8: Zárás — teljes teszt, szimulátor-átnézés, eszközös lista

**Files:**
- Modify: `docs/decisions.md` (csak ha implementáció közben a tervtől eltérő döntés született)

- [ ] **Step 1: Teljes build + tesztfuttatás**

Run: build-parancs, majd a teljes `test` (a `-only-testing` nélkül). Expected: **BUILD SUCCEEDED**, minden teszt **PASS** (a meglévő 22 kriptó-teszt is).

- [ ] **Step 2: Szimulátor-átnézés (RootView-cserés trükk)**

A képernyő-ellenőrzés bevált módja: a `RootView` tartalmát ideiglenesen a vizsgált nézetre cserélni, screenshotolni, majd visszaállítani. Ellenőrizd screenshottal: PanicView (chip-kiválasztás átrendezi az eszközöket), BreathingView (kör animál), GroundingView (pöttyök telnek), CalmFolderView üres állapot, PanicContactsSettingsView. Az emoji-tofu a szimulátorban ismert környezeti hiba — nem hiba-jel. **A végén állítsd vissza a RootView-t, és `git status`-szal győződj meg róla, hogy nem maradt benne a csere.**

- [ ] **Step 3: Eszközös teszt-lista (Attilának, nem blokkoló)**

A következő üzenetben add át ezt a listát:
- Panik gomb → képernyő megnyílik, chipek + eszközök rendben
- Hívás/FaceTime gombok valóban hívást indítanak (szimulátorban nem megy)
- PhotosPicker → nyugi-mappa képek betöltése, iPhone↔iPad CloudKit-szinkron
- Haptika a légzés-fázisváltásokon és a grounding-pöttyökön

- [ ] **Step 4: Ha volt tervtől eltérő döntés, írd a `docs/decisions.md`-be, és commitolj**

```bash
git add docs/decisions.md
git commit -m "phase 4.1: decision log update"
```

---

## Self-review jegyzet (a terv írásakor lefutott)

- **Spec-lefedettség (design 2. szakasz):** érzés-chipek + szabad szöveg (T6), légzés (T2), grounding (T3), nyugi-mappa (T4), NYUGI-tevékenységek (T6), hívás/FaceTime + elérhetőség-szerkesztő (T6, T7), modul-jelleg (T5 `PanicToolID` + sorrend). A „Szólok anyáéknak" szándékosan NEM része — az a 4.3 (backendes riasztás).
- **Típus-konzisztencia:** `PanicContact.faceTimeVideoURL` (nem `facetimeURL`) mindenhol; `PanicToolID` `String` raw + `Identifiable` a `fullScreenCover(item:)` miatt; `CalmItem.photoData` opcionális (CloudKit).
- **Ellenőrzött hivatkozások:** `DailyTaskSource.today`, `vandaCard(surface:)` (`ThemedBackground.swift:39`), `Color.surface/.surfaceTint/.inkMuted/.inkFaint` — mind létezik a kódbázisban.
