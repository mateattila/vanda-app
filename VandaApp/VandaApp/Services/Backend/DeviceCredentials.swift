//
//  DeviceCredentials.swift
//  VandaApp
//
//  Egy eszköz backend-identitása: melyik családhoz tartozik, milyen szerepben,
//  és milyen bearer tokennel hitelesíti magát.
//

import Foundation

struct DeviceCredentials: Codable, Equatable {
    var familyId: String
    var deviceId: String
    var token: String
    var role: AppRole
    var deviceName: String
}
