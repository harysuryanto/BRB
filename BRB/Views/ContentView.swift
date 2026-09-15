//
//  ContentView.swift
//  BRB
//
//  Task 1 scope: permission state, monitored-device row, live sample,
//  engine status, nearby picker. Veil/threshold UI arrives later.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var manager: ProximityManager

    init(manager: ProximityManager = ProximityManager()) {
        _manager = State(initialValue: manager)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("BRB")
                    .font(.title2.bold())
                Spacer()
                Circle()
                    .fill(manager.bluetoothGranted ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(manager.bluetoothPermission)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !manager.bluetoothGranted {
                Button("Open Bluetooth Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!)
                }
                .font(.caption)
            }

            Divider()

            // Monitored device
            VStack(alignment: .leading, spacing: 4) {
                Text("Monitored device:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(manager.pinnedName ?? "None — pin a device below")
                    .font(.headline)
                if let rssi = manager.liveRSSI {
                    Text("\(rssi) dBm · via \(manager.liveKind)")
                        .font(.system(.body, design: .monospaced).bold())
                } else {
                    Text("Waiting for signal…")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Engine status + picker
            VStack(alignment: .leading, spacing: 8) {
                Text(manager.leStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
                DevicePickerView(manager: manager)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { manager.startMonitoring() }
        .onDisappear { manager.stopMonitoring() }
    }
}

#Preview("BRB Monitoring") {
    ContentView(manager: .previewMock)
        .frame(width: 480, height: 600)
}

#Preview("BRB Empty") {
    ContentView(manager: ProximityManager())
        .frame(width: 480, height: 600)
}
