//
//  AdvertPruner.swift
//  BRB
//
//  Extracted advertisement sample model and pure pruning logic.
//

import Foundation

/// One LE advertisement sighting, keyed by peripheral identifier.
struct AdvertSample: Codable {
    var name: String
    var rssi: Int
    var at: Date
    /// Bluetooth SIG manufacturer company ID from the packet's manufacturer
    /// data (nil when absent — many buds advertise Fast Pair instead).
    var companyID: UInt16? = nil
    /// Whether Google Fast Pair service data (0xFE2C) was present.
    var hasFastPairService: Bool = false
    /// Apple Continuity type byte (0x10 = Nearby Info/Phone, 0x07 = AirPods, 0x12 = AirTag, 0x0B = Watch).
    var appleContinuityType: UInt8? = nil
    /// Bluetooth SIG Appearance value (UUID 0x2A01) if resolved via GATT.
    var sigAppearance: UInt16? = nil
}

enum AdvertPruner {
    /// Prunes stale entries (60s TTL, 300s for the pinned key), keeps only the
    /// freshest 30. Pure function — no side effects — so it's testable without
    /// CoreBluetooth or UI.
    static func pruneAdverts(_ adverts: [String: AdvertSample], pinnedKey: String?, now: Date) -> [String: AdvertSample] {
        Dictionary(uniqueKeysWithValues:
            adverts.filter { pair in
                let limit = (pair.key == pinnedKey) ? 300.0 : 60.0
                return now.timeIntervalSince(pair.value.at) < limit
            }.sorted { $0.value.at > $1.value.at }.prefix(30).map { ($0.key, $0.value) })
    }
}
