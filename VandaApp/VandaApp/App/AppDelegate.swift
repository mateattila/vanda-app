//
//  AppDelegate.swift
//  VandaApp
//
//  Az APNs device-token átvételéhez kell (SwiftUI-ból csak app delegate-en át
//  érhető el). A helyi notificationök továbbra is UNUserNotificationCenterrel
//  mennek — ez a delegate kizárólag a távoli push regisztrációjáért felel.
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // A regisztráció NEM igényel notification-engedélyt (az csak a
        // megjelenítést szabályozza), ezért minden indításkor lefuttatjuk —
        // a token változhat, és a PushRegistrar úgyis csak eltérés esetén tölt fel.
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushRegistrar.shared.didReceive(deviceToken: deviceToken)
        Task { await PushRegistrar.shared.flush() }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Szimulátoron ez normális; eszközön hálózat- vagy provisioning-hiba.
        print("VandaApp: APNs-regisztráció nem sikerült — \(error.localizedDescription)")
    }
}
