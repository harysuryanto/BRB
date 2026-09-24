//
//  MenuBarPopoverView.swift
//  BRB
//
//  Rich window popover for the MenuBarExtra item with quick device status
//  and timed protection pause options.
//

import SwiftUI

struct MenuBarPopoverView: View {
    @Bindable var manager: ProximityManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: DS.spacingMD) {
            // MARK: - Header Status Row
            headerSection

            Divider()

            // MARK: - Monitored Device & Signal
            deviceSection

            Divider()

            // MARK: - Protection Pause Controls
            pauseSection

            Divider()

            // MARK: - Footer Actions
            footerSection
        }
        .padding(DS.cardPad)
        .frame(width: 300)
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(spacing: DS.spacingSM) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: statusIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("BRB Protection")
                    .font(.headline)
                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            DSPill(text: statusBadgeText, tint: statusColor)
        }
    }

    // MARK: - Device Info
    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let pinned = manager.pinnedDisplayName {
                HStack(spacing: 8) {
                    Image(systemName: deviceCategoryIcon)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)

                    Text(pinned)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Spacer()

                    if let rssi = manager.smoothedRSSI {
                        HStack(spacing: 4) {
                            if manager.isStale {
                                Text("Stale •")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            Text("\(Int(round(rssi))) dBm")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                                .contentTransition(.numericText())
                                .animation(.smooth(duration: 0.25), value: Int(round(rssi)))
                        }
                    } else {
                        Text("Searching…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Mini RSSI Proximity Bar
                if let rssi = manager.smoothedRSSI {
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            let ratio = proximityRatio(rssi: rssi)
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(height: 5)
                                Capsule()
                                    .fill(manager.isStale ? Color.secondary.opacity(0.4) : statusColor)
                                    .frame(width: max(5, geo.size.width * ratio), height: 5)
                                    .animation(.smooth(duration: 0.4), value: ratio)
                                    .animation(.smooth(duration: 0.3), value: statusColor)
                                    .animation(.smooth(duration: 0.3), value: manager.isStale)
                            }
                        }
                        .frame(height: 5)

                        Text(proximityLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(manager.isStale ? .secondary : statusColor)
                            .animation(.smooth(duration: 0.3), value: manager.presenceState)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("No device pinned")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Pair…") {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "main")
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(DS.compactPad)
        .background(DS.cardBg)
        .cornerRadius(DS.radius)
    }

    // MARK: - Pause Controls
    private var pauseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if manager.protectionPaused {
                // Active Pause Banner with Resume Button
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "pause.circle.fill")
                            .foregroundColor(.orange)
                        if let remaining = manager.protectionPauseRemaining {
                            Text("Resumes in \(formatCountdown(remaining))")
                                .font(.subheadline.weight(.semibold))
                        } else {
                            Text("Protection Paused")
                                .font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                    }

                    Button(action: {
                        manager.resumeProtection()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.caption)
                            Text("Resume Protection Now")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding(DS.compactPad)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(DS.radius)
            } else {
                // Quick Pause Options
                Text("Pause Protection")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    pauseDurationButton("15m", seconds: 15 * 60)
                    pauseDurationButton("1h", seconds: 60 * 60)
                    pauseDurationButton("3h", seconds: 3 * 3600)
                    pauseDurationButton("Indefinite", seconds: 0)
                }
            }
        }
    }

    private func pauseDurationButton(_ title: String, seconds: TimeInterval) -> some View {
        Button(action: {
            manager.pauseProtection(for: seconds)
        }) {
            Text(title)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Footer
    private var footerSection: some View {
        HStack {
            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                    Text("Settings…")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Spacer()

            Button(role: .destructive, action: {
                NSApplication.shared.terminate(nil)
            }) {
                Text("Quit")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers
    private var statusColor: Color {
        if manager.protectionPaused { return .orange }
        guard manager.bluetoothGranted else { return .red }
        switch manager.presenceState {
        case .near: return .green
        case .far: return .orange
        case .gone: return .red
        case .idle: return .secondary
        }
    }

    private var statusIcon: String {
        if manager.protectionPaused { return "pause.fill" }
        guard manager.bluetoothGranted else { return "exclamationmark.shield" }
        switch manager.presenceState {
        case .near: return "checkmark.shield.fill"
        case .far: return "figure.walk"
        case .gone: return "exclamationmark.shield.fill"
        case .idle: return "shield.slash"
        }
    }

    private var statusSubtitle: String {
        if manager.protectionPaused {
            if let rem = manager.protectionPauseRemaining {
                return "Auto-resumes in \(formatCountdown(rem))"
            }
            return "Paused indefinitely"
        }
        switch manager.presenceState {
        case .near: return "Monitoring • At desk"
        case .far: return "Cover active • Away"
        case .gone: return "Device out of range"
        case .idle: return "Waiting for signal…"
        }
    }

    private var statusBadgeText: String {
        if manager.protectionPaused { return "Paused" }
        switch manager.presenceState {
        case .near: return "Active"
        case .far: return "Away"
        case .gone: return "Gone"
        case .idle: return "Idle"
        }
    }

    private var deviceCategoryIcon: String {
        guard let key = manager.pinnedKey else { return "wave.3.right" }
        let cat = manager.deviceCategory(forKey: key)
        return cat.symbol
    }

    private var proximityLabel: String {
        if manager.isStale { return "Stale" }
        switch manager.presenceState {
        case .near: return "Near Desk"
        case .far: return "Away"
        case .gone: return "Gone"
        case .idle: return "Idle"
        }
    }

    private func proximityRatio(rssi: Double) -> CGFloat {
        // Matches CalibrationRangeMeterView bounds (-95 dBm far, -40 dBm immediate desk)
        let minV: Double = -95.0
        let maxV: Double = -40.0
        let clamped = min(max(rssi, minV), maxV)
        return CGFloat((clamped - minV) / (maxV - minV))
    }
}
