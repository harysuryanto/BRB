//
//  DevicePickerView.swift
//  BRB
//
//  Live BLE scan list. Tap ○ to pin an entry as the monitored device —
//  pinning is by peripheral identifier, never by name (names are often
//  absent from advertisements and addresses can rotate).
//

import SwiftUI

/// Compact age label that switches to minutes for stale entries.
private func ageString(since date: Date) -> String {
    let s = max(0, Int(Date().timeIntervalSince(date)))
    if s < 90 { return "\(s)s ago" }
    return "\(s / 60)m ago"
}

struct DevicePickerView: View {
    let manager: ProximityManager

    var body: some View {
        DisclosureGroup("Nearby devices (\(manager.leAdverts.count))") {
            if manager.leAdverts.isEmpty {
                Text("Nothing heard yet — move the bud or wait for a scan burst.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(manager.leAdverts.keys.sorted(by: {
                        (manager.leAdverts[$0]?.name ?? "") < (manager.leAdverts[$1]?.name ?? "")
                    }), id: \.self) { id in
                        if let s = manager.leAdverts[id] {
                            HStack(spacing: 6) {
                                Button(manager.pinnedLEID == id ? "●" : "○") {
                                    if manager.pinnedLEID == id { manager.unpinLEDevice() }
                                    else { manager.pinLEDevice(id: id) }
                                }
                                .font(.caption)
                                .buttonStyle(.plain)
                                .help(manager.pinnedLEID == id
                                      ? "Unpin: stop monitoring this device"
                                      : "Pin: monitor this device")
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(s.name)
                                        .font(.system(.caption2, design: .monospaced))
                                        .lineLimit(1)
                                    Text(String(id.prefix(8)))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(s.rssi) dBm")
                                    .font(.system(.caption2, design: .monospaced).bold())
                                Text(ageString(since: s.at))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .textSelection(.enabled)
                            Divider().opacity(0.4)
                        }
                    }
                    Text("Tap ○ to monitor an entry — move the bud and watch dBm to identify it.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .font(.caption)
        .padding(10)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(6)
    }
}
