//
//  PresenceState.swift
//  BRB
//
//  State model representing the user's presence relative to the Mac.
//

import Foundation

/// Presence state determined by smoothed BLE signal strength and freshness.
enum PresenceState: String, CaseIterable, Codable {
    /// No device pinned, or waiting for initial detection.
    case idle = "Idle"
    /// Bud is nearby (smoothed signal >= veil-off threshold).
    case near = "Near"
    /// Bud is beyond the boundary (smoothed signal <= veil-on threshold). Grace timer running.
    case far = "Far"
    /// No sightings for 2x grace delay (e.g. bud cased, dead battery, out of range).
    case gone = "Gone"

    var badgeColor: String {
        switch self {
        case .idle: return "gray"
        case .near: return "green"
        case .far: return "orange"
        case .gone: return "red"
        }
    }
}
