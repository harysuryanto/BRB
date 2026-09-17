//
//  DevicePickerView.swift
//  BRB
//
//  Card-based BLE picker, TWS-app style. Each card shows generated art,
//  title, and signal strength. The whole card is the pin toggle —
//  pinning is by peripheral identifier, never by name (names are often
//  absent from advertisements and addresses can rotate).
//

import SwiftUI
import AppKit

/// Compact age label that switches to minutes for stale entries.
private func ageString(since date: Date) -> String {
    let s = max(0, Int(Date().timeIntervalSince(date)))
    if s < 90 { return "\(s)s ago" }
    return "\(s / 60)m ago"
}

// MARK: - Signal helpers

/// 0...4 bars from RSSI. Thresholds tuned for desk range (-40 strong … -95 edge).
private func rssiLevel(_ rssi: Int) -> Int {
    if rssi >= -60 { return 4 }
    if rssi >= -70 { return 3 }
    if rssi >= -80 { return 2 }
    return 1
}

private func rssiColor(_ rssi: Int, stale: Bool) -> Color {
    if stale { return .secondary }
    if rssi >= -60 { return .green }
    if rssi >= -75 { return .orange }
    return .red
}

private func isStaleSample(_ sample: AdvertSample) -> Bool {
    Date().timeIntervalSince(sample.at) > 12.0
}

// MARK: - Device class (inferred from name — BLE carries no photos/class)

private enum DeviceCategory {
    case buds
    case headphones
    case phone
    case computer
    case tablet
    case watch
    case mouse
    case keyboard
    case speaker
    case tag
    case unknown

    var symbol: String {
        switch self {
        case .buds: return "airpodspro"
        case .headphones: return "headphones"
        case .phone: return "iphone"
        case .computer: return "macbook"
        case .tablet: return "ipad"
        case .watch: return "applewatch"
        case .mouse: return "computermouse"
        case .keyboard: return "keyboard"
        case .speaker: return "hifispeaker"
        case .tag: return "airtag"
        case .unknown: return "antenna.radiowaves.left.and.right"
        }
    }

    /// Dark-enough stops throughout: the 28pt glyph is white, so every
    /// gradient must keep contrast (no yellows / light greys / cyans).
    var gradient: (Color, Color) {
        switch self {
        case .buds: return (.purple, .blue)
        case .headphones: return (.indigo, .teal)
        case .phone: return (.green, .teal)
        case .computer: return (Color(red: 0.32, green: 0.35, blue: 0.43), .black)
        case .tablet: return (.blue, .indigo)
        case .watch: return (.orange, .pink)
        case .mouse: return (.orange, .brown)
        case .keyboard: return (.purple, .pink)
        case .speaker: return (.red, .orange)
        case .tag: return (.teal, .blue)
        case .unknown: return (Color(white: 0.35), .black)
        }
    }

    /// Short spoken/written label for accessibility.
    var label: String {
        switch self {
        case .buds: return "Earbuds"
        case .headphones: return "Headphones"
        case .phone: return "Phone"
        case .computer: return "Computer"
        case .tablet: return "Tablet"
        case .watch: return "Watch"
        case .mouse: return "Mouse"
        case .keyboard: return "Keyboard"
        case .speaker: return "Speaker"
        case .tag: return "Tracker tag"
        case .unknown: return "Bluetooth device"
        }
    }
}

// MARK: - Device identity
// Shared identity helpers (isUnnamed, vendorName, deviceSuffix,
// displayTitle, identityChip) live next to AdvertSample in
// ProximityManager.swift — every surface uses the same source of truth.

/// Scanner subtitle: session-locator hex, freshness age, vendor chip,
/// collision note. The leading hex is the CURRENT locator identifier — it
/// rotates across case cycles, so it identifies the session, not the device
/// (identity lives in the title/key). Kept because it is the strongest
/// glanceable differentiator between otherwise-identical Unknown cards.
private func deviceSubtitle(sample: AdvertSample, chip: String?, multi: Bool, locator: String, resolving: Bool = false) -> String {
    var parts = [String(locator.prefix(8)), ageString(since: sample.at)]
    if let chip { parts.append(chip) }
    if multi { parts.append("2× seen") }
    if resolving { parts.append("Identifying…") }
    return parts.joined(separator: " • ")
}

/// Stable hue in [0,1) from a string (FNV-1a — Swift Hasher is per-process
/// random and must not drive UI identity).
private func stableHue(for string: String) -> Double {
    var hash: UInt64 = 14_695_981_039_346_656_037 // FNV-1a 64 offset basis
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211 // FNV-1a 64 prime
    }
    return Double(hash % 1000) / 1000.0
}

private func deviceCategory(for name: String) -> DeviceCategory {
    let n = name.lowercased()
    if isUnnamed(name) { return .unknown }
    // Buds / headphones first (primary use case — check before generic "buds" traps).
    if n.contains("airpods") { return .buds }
    if n.contains("buds") || n.contains("freebuds") || n.contains("soundcore")
        || n.contains("r60i") || n.contains("aero") || n.contains("life ")
        || n.contains("pixel buds") || n.contains("echo buds") { return .buds }
    if n.contains("headphone") || n.contains("headset")
        || n.contains("sony") || n.contains("bose") || n.contains("beats")
        || n.contains("jbl") || n.contains("sennheiser") || n.contains("shure")
        || n.contains("audio-technica") || n.contains("arctis") || n.contains("hyperx") { return .headphones }
    // Phones / computers / tablets.
    if n.contains("iphone") || n.contains("pixel") || n.contains("galaxy s")
        || n.contains("galaxy a") || n.contains("galaxy z") || n.contains("oneplus")
        || n.contains("xiaomi") || n.contains("oppo") || n.contains("vivo")
        || n.contains("honor") || n.contains("motorola") || n.contains("nothing phone") { return .phone }
    if n.contains("macbook") || n.contains("thinkpad") || n.contains("surface")
        || n.contains("laptop") || n.contains("desktop") || n.contains("imac")
        || n.contains("mac mini") || n.contains("mac studio") || n.contains("dell")
        || n.contains("hp ") || n.contains("lenovo") { return .computer }
    if n.contains("ipad") || n.contains("tablet") || n.contains("tab s") { return .tablet }
    // Wearables / tags.
    if n.contains("watch") || n.contains("fitbit") || n.contains("garmin")
        || n.contains("amazfit") || n.contains("versa") || n.contains("sense")
        || n.contains("charge 5") || n.contains("band ") { return .watch }
    if n.contains("airtag") || n.contains("tile") || n.contains("chipolo")
        || n.contains("smarttag") { return .tag }
    // Desk peripherals.
    if n.contains("mouse") || n.contains("mx master") || n.contains("magic mouse")
        || n.contains("m350") || n.contains("m650") || n.contains("g pro")
        || n.contains("deathadder") || n.contains("trackpad") { return .mouse }
    if n.contains("keyboard") || n.contains("mx keys") || n.contains("k380")
        || n.contains("k780") || n.contains("magic keyboard") || n.contains("keychron") { return .keyboard }
    // Speakers / displays.
    if n.contains("speaker") || n.contains("homepod") || n.contains("echo")
        || n.contains("nest") || n.contains("sonos") || n.contains("flip")
        || n.contains("charge 4") || n.contains("charge 5") || n.contains("go 3")
        || n.contains("soundbar") { return .speaker }
    return .unknown
}

// MARK: - Art helpers (generated — BLE carries no photos)

private func deviceSymbol(for name: String) -> String {
    deviceCategory(for: name).symbol
}

/// Runtime guard: an invalid SF Symbol name renders as *nothing* (blank tile),
/// so verify against AppKit and fall back to a known-good symbol.
private func safeSymbol(_ name: String) -> String {
    if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil { return name }
    return "antenna.radiowaves.left.and.right"
}

private func deviceGradient(for name: String) -> (Color, Color) {
    deviceCategory(for: name).gradient
}

// MARK: - Subviews

struct DeviceArtView: View {
    var name: String
    var size: CGFloat = DS.deviceArtSize
    /// Stable per-device tint seed (identifier). Tints only the generic
    /// unknown art so unnamed cards are visually distinct without implying
    /// a device type we don't know. Nil = category gradient as before.
    var seed: String? = nil

    var body: some View {
        let (c1, c2): (Color, Color) = {
            if let seed, deviceCategory(for: name) == .unknown {
                let h = stableHue(for: seed)
                return (Color(hue: h, saturation: 0.55, brightness: 0.45),
                        Color(hue: (h + 0.08).truncatingRemainder(dividingBy: 1.0),
                              saturation: 0.6, brightness: 0.3))
            }
            return deviceGradient(for: name)
        }()
        ZStack {
            RoundedRectangle(cornerRadius: DS.radius)
                .fill(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
            Image(systemName: safeSymbol(deviceSymbol(for: name)))
                .font(.system(size: size * 0.44))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        }
        .accessibilityHidden(true)
    }
}

struct SignalBarsView: View {
    var rssi: Int
    var stale: Bool

    var body: some View {
        let level = stale ? 0 : rssiLevel(rssi)
        let tint = rssiColor(rssi, stale: stale)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < level ? tint : Color.secondary.opacity(0.25))
                    .frame(width: 4, height: CGFloat(4 + i * 3))
            }
        }
        .accessibilityLabel("\(level) of 4 bars")
    }
}

/// Live settings list vs. onboarding draft list. Draft copy never promises
/// monitoring — selection is only submitted on Finish.
enum PickerMode {
    case live
    case draft
}

struct DeviceCardView: View {
    /// One physical device (same-name sightings collapsed). The group key is
    /// the stable identity; the locator UUID inside rotates freely.
    var group: ProximityManager.DeviceGroup
    var isSelected: Bool
    var mode: PickerMode = .live
    /// Whether a GATT name resolution is currently in flight for this group.
    var resolving: Bool = false
    var action: () -> Void

    private var pillText: String { mode == .live ? "Monitored" : "Selected" }
    private var toggleHint: String {
        mode == .live ? "Tap again to unpin" : "Tap again to deselect"
    }

    var body: some View {
        let sample = group.sample
        let stale = isStaleSample(sample)
        Button(action: action) {
            VStack(spacing: DS.spacingSM) {
                ZStack(alignment: .topTrailing) {
                    DeviceArtView(name: group.art, seed: group.key)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.accentColor)
                            .background(Circle().fill(Color(NSColor.windowBackgroundColor)))
                            .offset(x: 10, y: -10)
                    }
                }
                .padding(.top, DS.spacingXS)

                Text(group.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    SignalBarsView(rssi: sample.rssi, stale: stale)
                    Text("\(sample.rssi) dBm")
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundColor(stale ? .secondary : .primary)
                }

                Text(deviceSubtitle(sample: sample, chip: group.chip, multi: group.uuids.count > 1, locator: group.locator, resolving: resolving))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                // Selection affordance rows are always rendered (hidden when
                // unselected) so every card measures the same height and the
                // grid stays uniform.
                DSPill(text: pillText, tint: .green)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(!isSelected)
                Text(isSelected ? toggleHint : " ")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(!isSelected)
            }
            .frame(maxWidth: .infinity)
            .padding(DS.cardPad)
            .background(isSelected ? Color.accentColor.opacity(0.08) : DS.cardBg)
            .cornerRadius(DS.radius)
            .opacity(stale && !isSelected ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
        .help(mode == .live
              ? (isSelected ? "Monitored — click again to unpin" : "Monitor this device")
              : (isSelected ? "Selected — click again to deselect" : "Select this device"))
        .accessibilityLabel(mode == .live
            ? (isSelected
               ? "Monitored, \(deviceCategory(for: sample.name).label), \(group.name), \(sample.rssi) dBm. Activate to unpin."
               : "Monitor \(deviceCategory(for: sample.name).label), \(group.name), \(sample.rssi) dBm.")
            : (isSelected
               ? "Selected, \(deviceCategory(for: sample.name).label), \(group.name), \(sample.rssi) dBm. Activate to deselect."
               : "Select \(deviceCategory(for: sample.name).label), \(group.name), \(sample.rssi) dBm."))
        .contextMenu {
            Button("Copy session ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(group.locator, forType: .string)
            }
        }
    }
}

// MARK: - Picker

struct DevicePickerView: View {
    let manager: ProximityManager
    /// Selection override for draft contexts (onboarding): when set, cards
    /// highlight/toggle this stable key instead of the live pin, so picking
    /// writes no live state. Nil (settings) = follow the live pin directly.
    var selectedID: String? = nil
    var onToggle: ((ProximityManager.DeviceGroup) -> Void)? = nil
    var mode: PickerMode = .live

    private let columns = [
        GridItem(.adaptive(minimum: DS.deviceCardMinWidth, maximum: DS.deviceCardMaxWidth), spacing: DS.deviceGridSpacing)
    ]

    private var effectiveSelectedID: String? { selectedID ?? manager.pinnedKey }

    private func toggle(_ group: ProximityManager.DeviceGroup) {
        if let onToggle { onToggle(group); return }
        if manager.pinnedKey == group.key { manager.unpinLEDevice() }
        else { manager.pinLEDevice(key: group.key, uuid: group.locator) }
    }

    var body: some View {
        let groups = manager.deviceGroups
        let paired = groups.filter { manager.bond(forKey: $0.key) != nil }
        let nearby = groups.filter { manager.bond(forKey: $0.key) == nil }
        VStack(alignment: .leading, spacing: DS.spacingSM) {
            if !paired.isEmpty {
                sectionHeader(title: "Your devices", count: paired.count)
                deviceGrid(for: paired)
            }

            sectionHeader(title: "Nearby devices", count: nearby.count)

            if groups.isEmpty {
                VStack(spacing: DS.spacingSM) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Nothing heard yet — move the bud or wait for a scan burst.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(DS.cardPad)
                .background(DS.cardBg)
                .cornerRadius(DS.radius)
                .transition(.opacity)
            } else {
                if !nearby.isEmpty {
                    deviceGrid(for: nearby)
                }
                Text(mode == .live
                      ? "Tap a card to monitor — named A–Z, unknown devices at the end."
                      : "Tap a card to select it — nothing is monitored until you finish setup.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        // Fires only when the group set/order changes (insert/remove) — live
        // dBm/age text updates don't retrigger it.
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: groups.map(\.key))
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.bold())
            DSPill(text: "\(count)", tint: .secondary)
            Spacer()
        }
    }

    private func deviceGrid(for list: [ProximityManager.DeviceGroup]) -> some View {
        LazyVGrid(columns: columns, spacing: DS.deviceGridSpacing) {
            ForEach(list, id: \.key) { group in
                        DeviceCardView(
                            group: group,
                            isSelected: effectiveSelectedID == group.key,
                            mode: mode,
                            resolving: manager.resolvingIDs.contains(group.locator)
                        ) {
                    toggle(group)
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.85).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
    }
}
