//
//  VandaAppApp.swift
//  VandaApp
//
//  Created by Máté Attila on 2026. 07. 06..
//

import SwiftUI
import SwiftData
import UIKit

@main
struct VandaAppApp: App {
    init() {
        #if DEBUG
        // A custom fontok (Resources/Fonts + Info.plist UIAppFonts) regisztrációjának
        // őre: ha egy fontfájl kiesne a bundle-ből, itt derüljön ki, ne némán
        // rendszerfontra visszaesve.
        for name in ["Quicksand-Medium", "Quicksand-SemiBold", "Quicksand-Bold",
                     "Nunito-SemiBold", "Nunito-Bold", "Nunito-ExtraBold"] {
            assert(UIFont(name: name, size: 12) != nil, "Hiányzó custom font: \(name)")
        }
        print("VandaApp: custom fontok rendben regisztrálva")
        #endif

        configureNavigationBarTypography()
        ReminderScheduler.shared.configure(container: modelContainer)
    }

    /// A navigation bar címei is a Soft Dusk tipográfiát beszéljék (Quicksand),
    /// ne a rendszer San Franciscót — SwiftUI-ból ez csak appearance-szel érhető el.
    private func configureNavigationBarTypography() {
        let appearance = UINavigationBar.appearance()
        let ink = UIColor(Color.ink)
        if let large = UIFont(name: "Quicksand-Bold", size: 28) {
            appearance.largeTitleTextAttributes = [.font: large, .foregroundColor: ink]
        }
        if let inline = UIFont(name: "Quicksand-Bold", size: 17) {
            appearance.titleTextAttributes = [.font: inline, .foregroundColor: ink]
        }
    }

    private let modelContainer = VandaStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    // Induláskor újraütemezzük az aktív emlékeztetőket — így egy
                    // másik eszközről (CloudKit) érkezett módosítás is érvénybe lép.
                    await ReminderScheduler.shared.resyncFromStore()
                    // A kérdésbank seedelése + a heti aksi-rákérdezések újrasorsolása.
                    QuestionSeeder.seedFactoryPackIfNeeded(in: modelContainer.mainContext)
                    await MoodPromptScheduler.shared.resyncFromStore(container: modelContainer)
                }
        }
        .modelContainer(modelContainer)
    }
}
