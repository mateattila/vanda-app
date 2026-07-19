//
//  FamilyLinkModel.swift
//  VandaApp
//
//  A párosítás állapotgépe: ezt fogyasztja Vanda Család képernyője és a szülő
//  mód egyaránt. A hálózati réteg protokoll mögött van, hogy a tesztek
//  hálózat nélkül futhassanak.
//

import Foundation
import Observation

/// A BackendClient azon szelete, amire a párosítás támaszkodik.
protocol FamilyLinking {
    func createFamily(deviceName: String) async throws -> DeviceCredentials
    func redeemPairingCode(_ code: String, deviceName: String) async throws -> DeviceCredentials
    func createPairingCode(role: AppRole, token: String) async throws -> PairingCode
    func sendTestPush(token: String) async throws -> [TestPushResult]
    func deleteDevice(token: String) async throws
}

extension BackendClient: FamilyLinking {}

enum FamilyLink: Equatable {
    case unlinked
    case linked(DeviceCredentials)
}

/// A párosító kód sheet-jének teljes állapota: melyik szerephez kértünk
/// kódot, és hol tart a kérés. Ez a modell tudja, nem a nézet — a nézet
/// csak a `role`-lal szűr rá arra, ami épp az ő sheet-jét érinti, hogy egy
/// korábban, MÁSIK szerephez kiadott (vagy elhalt) kód sose villanhasson fel
/// tévesen (lásd finding 1: „szülő meghívása" nem mutathat gyerek-kódot).
enum PairingCodeState: Equatable {
    case idle
    case loading(role: AppRole)
    case ready(PairingCode)
    case failed(role: AppRole, message: String)
}

/// A `PairingCodeSheet` szempontjából releváns fázis: csak a sheet SAJÁT
/// szerepéhez tartozó kész kódot vagy hibát fogadja el. Ez korábban a nézet
/// belsejében, egy privát `Phase` enumként és `where`-kikötéses szűrésként
/// élt — semmi sem tesztelte, egy jövőbeli, meglazított `where`-kikötés pedig
/// csendben visszahozhatta volna azt a hibát, amit ez a szűrés eredetileg
/// javított (lásd finding 1: a sheet sose lehet üres, és sose mutathat másik
/// szerephez kiadott kódot). Ide, a `PairingCodeState` mellé költöztetve
/// tiszta függvényként tesztelhető nézet nélkül is.
enum PairingCodePhase: Equatable {
    case loading
    case ready(PairingCode)
    case failed(String)
}

extension PairingCodeState {
    /// Minden, ami NEM a megadott szerephez tartozó kész kód vagy hiba
    /// (beleértve a `.idle`-t és egy MÁSIK szerep `.loading`/`.ready`/
    /// `.failed`-jét is), `.loading`-ra képződik le — így a hívó sose kap
    /// üres vagy rossz szerephez tartozó fázist.
    func phase(for role: AppRole) -> PairingCodePhase {
        switch self {
        case .ready(let code) where code.role == role:
            return .ready(code)
        case .failed(let failedRole, let message) where failedRole == role:
            return .failed(message)
        default:
            return .loading
        }
    }
}

/// MainActor-izolált (explicit, nem a projekt alapértelmezésére támaszkodva):
/// az idempotencia-őrnek (lásd `claim(requireUnlinked:)`) szinkron
/// ellenőrzés-és-állításra van szüksége, amit csak akkor garantál a nyelv,
/// ha egyetlen végrehajtási szál futtathatja a metódusait egyszerre. Mivel
/// ez egy `@Observable` modell, ami SwiftUI-nézetekből fog futni, ez amúgy
/// is a természetes hely.
@MainActor
@Observable
final class FamilyLinkModel {

    private(set) var link: FamilyLink
    private(set) var isBusy = false
    var errorMessage: String?
    private(set) var codeState: PairingCodeState = .idle
    private(set) var testPushResults: [TestPushResult]?

    private let client: FamilyLinking
    private let store: DeviceCredentialStoring
    private let registrar: PushRegistrar

    init(
        client: FamilyLinking = BackendClient.shared,
        store: DeviceCredentialStoring = KeychainDeviceCredentialStore.shared,
        registrar: PushRegistrar = .shared
    ) {
        self.client = client
        self.store = store
        self.registrar = registrar
        self.link = store.load().map(FamilyLink.linked) ?? .unlinked
    }

    var credentials: DeviceCredentials? {
        if case .linked(let credentials) = link { return credentials }
        return nil
    }

    var isLinked: Bool { credentials != nil }
    var deliveredCount: Int { (testPushResults ?? []).filter(\.delivered).count }
    var failedCount: Int { (testPushResults ?? []).filter { !$0.delivered }.count }

    // MARK: - Műveletek

    func createFamily(deviceName: String) async {
        // Idempotencia-őr: a `claim` szinkron, még az első `await` előtt fut,
        // hogy két egymást átfedő hívás (dupla koppintás, timeout utáni
        // újrapróbálás) közül csak az egyik juthasson el a hálózatig — így
        // sosem keletkezhet második, árva család a szerveren. Egy `guard
        // !isLinked` önmagában NEM elég: az csak a hálózati kör lezárása
        // (`persist`) UTÁN válik igazzá, tehát két, még folyamatban lévő
        // hívás mindkettője átjutna rajta.
        guard claim(requireUnlinked: true) else { return }
        await run {
            let credentials = try await self.client.createFamily(deviceName: deviceName)
            self.persist(credentials)
        }
    }

    func joinWithCode(_ code: String, deviceName: String) async {
        guard claim(requireUnlinked: true) else { return }
        await run {
            let credentials = try await self.client.redeemPairingCode(code, deviceName: deviceName)
            self.persist(credentials)
        }
    }

    /// `joinWithCode` szülő módból hívva (lásd `ParentModeView`): a beváltott
    /// kódnak `.parent` szerepet KELL adnia. Két, azonosan kinéző 6 jegyű kód
    /// létezik — Vanda „Szülő meghívása” (parent) és „Másik eszközöm
    /// hozzáadása” (child) kódja —, és ha a szülő véletlenül az utóbbit írja
    /// be, a backend egy `child` szerepű eszközt mintáz. Sem a teszt-push,
    /// sem a 4.3-as riasztás nem célozza a `child` eszközöket (mindkettő csak
    /// `role == 'parent'`-et) — az eszköz csendben kimaradna, miközben a
    /// képernyő azt hazudná, hogy össze van kötve. Ezért itt, a modellben (nem
    /// a nézetben — ez a fázis korábbi code review-ja már kétszer visszaküldte
    /// a nézetbe csempészett döntési logikát) azonnal visszavonjuk a hibás
    /// párosítást, hogy a szülő újra tudja próbálni a helyes kóddal.
    func joinAsParent(code: String, deviceName: String) async {
        await joinWithCode(code, deviceName: deviceName)
        guard let credentials, credentials.role != .parent else { return }
        // Az `unlink()` ugyanazon a `claim()`-en fut át, mint minden más
        // művelet, de itt ez nem ütközik: a fenti `joinWithCode` `run(_:)`-ja
        // már lezárta a saját hívását, `isBusy`-t vissza is állította false-ra
        // — a MainActor-izoláció miatt eddig a pontig más hívás nem
        // szúrhatta közbe magát, tehát az `unlink()` `claim()`-je itt
        // garantáltan átenged.
        await unlink()
        errorMessage = "Ez a kód Vanda saját eszközének szól, nem a szülőknek. Kérd el tőle a „Szülő meghívása” kódot, és azzal próbáld újra!"
    }

    func issueCode(role: AppRole) async {
        // Nem a közös `run(_:)`-ot használjuk: a hiba itt NEM a megosztott
        // `errorMessage`-be megy (azt a főképernyő mutatja, a sheet MÖGÖTT —
        // pont ez volt a hiba, amit a code review kifogásolt), hanem a
        // `codeState`-be, szerephez kötve, hogy a sheet, ami épp látszik,
        // közvetlenül meg tudja jeleníteni. A `codeState` emellett `.loading`
        // állapotba kerül MÁR a hálózati hívás előtt (nem `nil`-re állítva,
        // mint korábban) — a nézet ebből épít folyamatosan látható, sose üres
        // sheet-tartalmat.
        guard let credentials, claim() else { return }
        codeState = .loading(role: role)
        do {
            let code = try await client.createPairingCode(role: role, token: credentials.token)
            codeState = .ready(code)
        } catch let error as BackendError {
            codeState = .failed(role: role, message: error.friendlyMessage)
        } catch {
            codeState = .failed(role: role, message: BackendError.transport(error.localizedDescription).friendlyMessage)
        }
        isBusy = false
        await registrar.flush()
    }

    func rename(to newName: String) async {
        guard var credentials else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        credentials.deviceName = trimmed
        persist(credentials)
    }

    func sendTestPush() async {
        guard let credentials, claim() else { return }
        testPushResults = nil
        await run {
            self.testPushResults = try await self.client.sendTestPush(token: credentials.token)
        }
    }

    func unlink() async {
        // Ugyanazon a `claim`-en fut át, mint a másik négy művelet: ha épp
        // egy issueCode/sendTestPush hívás van folyamatban (már túl a saját
        // claim()-jén, a hálózatra várva), az unlink nem indulhat el
        // mellette. Enélkül az unlink a saját `deleteDevice`-ával
        // megelőzhetné a másik hívás lezárását, az pedig — visszatérve — egy
        // már leválasztott modellbe írna vissza (`codeState` vagy
        // `testPushResults` nem üres, miközben a store üres, `link` mégis
        // `.unlinked`). Elfoglaltság esetén — ugyanúgy, mint a másik négy
        // metódusnál — az unlink csendben nem csinál semmit; a hívó
        // felelőssége újra megpróbálni.
        guard let credentials, claim() else { return }
        // A szerver-hívás hibája sem ragaszthatja ide az eszközt: a helyi
        // törlés akkor is megtörténik, hogy újra lehessen párosítani.
        do {
            try await client.deleteDevice(token: credentials.token)
        } catch let error as BackendError {
            errorMessage = error.friendlyMessage
        } catch {
            // Ugyanaz a két ágú catch, mint `run(_:)`-ban: egy jövőbeli,
            // nem-BackendError-t dobó FamilyLinking-implementáció se
            // némíthassa el csendben a hibaüzenetet.
            errorMessage = BackendError.transport(error.localizedDescription).friendlyMessage
        }
        self.store.clear()
        registrar.forgetUploadState()
        link = .unlinked
        codeState = .idle
        testPushResults = nil
        isBusy = false
    }

    // MARK: - Belső

    /// Nem `store(_:)` a neve, hogy ne ütközzön a `store` property-vel.
    private func persist(_ credentials: DeviceCredentials) {
        // A `store.save` (Keychain) elméletileg elbukhat. Ha ezt csendben
        // hagynánk, a modell "össze vagytok kötve"-t mutatna, miközben a
        // bearer token — ami egy EGYSZER-használatos párosító kódból lett
        // kiváltva — sehol sincs elmentve: újraindítás után a hitelesítés
        // eltűnik, a kód pedig már nem váltható be újra. Ezért sikertelen
        // mentés esetén NEM linkeljük a modellt, hanem látható hibát mutatunk.
        guard store.save(credentials) else {
            errorMessage = "Nem sikerült elmenteni a párosítást ezen a telefonon. Próbáljuk újra?"
            return
        }
        link = .linked(credentials)
    }

    /// Szinkron igény-bejelentés: minden hálózatot érintő művelet ezzel
    /// indul, még az első `await` előtt. Mivel az osztály `@MainActor`, ez a
    /// „nézd meg, majd állítsd be" pár egyetlen, megszakíthatatlan lépésben
    /// fut le — egy másik hívás nem szúrhatja közbe magát a kettő közé, mert
    /// a MainActor csak a következő valódi felfüggesztési pontnál engedi át
    /// a vezérlést. `requireUnlinked` a párosítást indító két metódusnak
    /// (`createFamily`, `joinWithCode`) kell, a többinek nem.
    private func claim(requireUnlinked: Bool = false) -> Bool {
        guard !isBusy, !(requireUnlinked && isLinked) else { return false }
        isBusy = true
        errorMessage = nil
        return true
    }

    /// Az `isBusy`/`errorMessage` kezdő beállítását a hívó fél (`claim`)
    /// végzi el — `run` csak a hiba lekezeléséért, az `isBusy` lezárásáért és
    /// a push-flush-ért felel, hogy ne legyen dupla állítás.
    private func run(_ work: @escaping () async throws -> Void) async {
        do {
            try await work()
        } catch let error as BackendError {
            errorMessage = error.friendlyMessage
        } catch {
            errorMessage = BackendError.transport(error.localizedDescription).friendlyMessage
        }
        isBusy = false
        await registrar.flush()
    }
}
