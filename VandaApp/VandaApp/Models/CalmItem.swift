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
