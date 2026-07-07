//
//  RootView.swift
//  VandaApp
//
//  Gyerek/szülő mód váz (spec 2. fejezet, „Szerepek"): ugyanaz az app két módban
//  fut, első indításkor választva. A szerep eszköz-szintű, ezért UserDefaults-ban
//  él, NEM a CloudKit-szinkronizált adatban.
//

import SwiftUI
import SwiftData

enum AppRole: String {
    case child   // Vanda telefonja/iPadje: minden funkció
    case parent  // anya/apa telefonja: riasztások fogadása, párosítás (4. fázis)
}

struct RootView: View {
    @AppStorage("appRole") private var appRoleRaw: String = ""

    var body: some View {
        switch AppRole(rawValue: appRoleRaw) {
        case .child:
            MainTabView()
        case .parent:
            ParentModeView()
        case nil:
            RoleSelectionView()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(VandaStore.makeContainer())
}
