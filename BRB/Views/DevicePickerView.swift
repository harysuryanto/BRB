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

// MARK: - Art helpers (generated — BLE carries no photos)

private func deviceSymbol(for name: String) -> String {
    let n = name.lowercased()
    if n.contains("(unnamed)") || n.isEmpty { return "bluetooth" }
    if n.contains("airpods") { return n.contains("pro") ? "airpodspro" : "airpods" }
    if n.contains("speaker") || n.contains("homepod") { return "hifispeaker" }
    return "headphones"
}

private let deviceGradients: [(Color, Color)] = [
    (.blue, .purple),
    (.pink, .orange),
    (.green, .teal),
    (.indigo, .cyan),
    (.orange, .red),
]

private func deviceGradient(for id: String) -> (Color, Color) {
    let h = abs(id.hashValue)
    return deviceGradients[h % deviceGradients.count]
}

private func sortedDeviceIDs(_ manager: ProximityManager) -> [String] {
    manager.leAdverts.keys.sorted { a, b in
        let aPinned = (manager.pinnedLEID == a)
        let bPinned = (manager.pinnedLEID == b)
        if aPinned != bPinned { return aPinned }
        return (manager.leAdverts[a]?.rssi ?? -100) > (manager.leAdverts[b]?.rssi ?? -100)
    }
}

// MARK: - Subviews

struct DeviceArtView: View {
    var name: String
    var id: String

    var body: some View {
        let (c1, c2) = deviceGradient(for: id)
        ZStack {
            RoundedRectangle(cornerRadius: DS.radius)
                .fill(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: DS.deviceArtSize, height: DS.deviceArtSize)
            Image(systemName: deviceSymbol(for: name))
                .font(.system(size: 28))
                .foregroundColor(.white)
        }
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

struct DeviceCardView: View {
    var id: String
    var sample: AdvertSample
    var isPinned: Bool
    var action: () -> Void

    var body: some View {
        let stale = isStaleSample(sample)
        Button(action: action) {
            VStack(spacing: DS.spacingSM) {
                ZStack(alignment: .topTrailing) {
                    DeviceArtView(name: sample.name, id: id)
                    if isPinned {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.accentColor)
                            .background(Circle().fill(Color(NSColor.windowBackgroundColor)))
                            .offset(x: 10, y: -10)
                    }
                }
                .padding(.top, DS.spacingXS)

                Text(sample.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    SignalBarsView(rssi: sample.rssi, stale: stale)
                    Text("\(sample.rssi) dBm")
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundColor(stale ? .secondary : .primary)
                }

                Text("\(String(id.prefix(8))) • \(ageString(since: sample.at))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if isPinned {
                    DSPill(text: "Monitored", tint: .green)
                    Text("Tap again to unpin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(DS.cardPad)
            .background(isPinned ? Color.accentColor.opacity(0.08) : DS.cardBg)
            .cornerRadius(DS.radius)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radius)
                    .stroke(isPinned ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .opacity(stale && !isPinned ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Monitored — click again to unpin" : "Monitor this device")
        .accessibilityLabel(isPinned
            ? "Monitored, \(sample.name), \(sample.rssi) dBm. Activate to unpin."
            : "Monitor \(sample.name), \(sample.rssi) dBm.")
        .contextMenu {
            Button("Copy device ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(id, forType: .string)
            }
        }
    }
}

// MARK: - Picker

struct DevicePickerView: View {
    let manager: ProximityManager

    private let columns = [
        GridItem(.flexible(), spacing: DS.deviceGridSpacing),
        GridItem(.flexible(), spacing: DS.deviceGridSpacing),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.spacingSM) {
            HStack {
                Text("Nearby devices")
                    .font(.subheadline.bold())
                DSPill(text: "\(manager.leAdverts.count)", tint: .secondary)
                Spacer()
            }

            if manager.leAdverts.isEmpty {
                VStack(spacing: DS.spacingSM) {
                    Image(systemName: "bluetooth")
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
            } else {
                LazyVGrid(columns: columns, spacing: DS.deviceGridSpacing) {
                    ForEach(sortedDeviceIDs(manager), id: \.self) { id in
                        if let s = manager.leAdverts[id] {
                            DeviceCardView(
                                id: id,
                                sample: s,
                                isPinned: manager.pinnedLEID == id
                            ) {
                                if manager.pinnedLEID == id { manager.unpinLEDevice() }
                                else { manager.pinLEDevice(id: id) }
                            }
                        }
                    }
                }
                Text("Tap a card to monitor — move the bud and watch it rise to the top.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
