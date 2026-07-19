//
//  NotificationPermission.swift
//  VandaApp
//
//  A szülő módban a push-engedély két úton kérhető: párosítás után azonnal,
//  és — ha hiányzik — egy tartósan látható gombbal. A rendszer csak egyszer
//  kérdez; ha már megtagadták, a Beállításokba kell vinni.
//

import Foundation
import Observation
import UIKit
import UserNotifications

@Observable
final class NotificationPermission {

    private(set) var status: UNAuthorizationStatus = .notDetermined

    /// Tiszta függvényként tesztelhető — nincs szükség rendszerhívásra vagy
    /// nézetre ahhoz, hogy ellenőrizzük, mikor kell szólnia a képernyőnek.
    static func needsAttention(for status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: return false
        default: return true
        }
    }

    /// A rendszer-dialógus csak `notDetermined` állapotban jelenik meg; utána
    /// már csak a Beállításokban lehet visszakapcsolni.
    static func requiresSettingsTrip(for status: UNAuthorizationStatus) -> Bool {
        status == .denied
    }

    var needsAttention: Bool { Self.needsAttention(for: status) }
    var requiresSettingsTrip: Bool { Self.requiresSettingsTrip(for: status) }

    static func settingsURL() -> URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
    }

    func request() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        await refresh()
    }
}
