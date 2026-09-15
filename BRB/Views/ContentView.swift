//
//  ContentView.swift
//  BRB
//
//  Main Control Center & Settings window for BRB.
//  Includes 4 tabs:
//  1. Device & Presence (Real-time signal diagnostics, presence badge, nearby scanner)
//  2. Screen Cover (Veil cover preview and custom image picker)
//  3. Calibration (Threshold sliders, hysteresis band, and away capture)
//  4. Timers & Security (Grace delay, suppression window, and fail-secure toggle)
//

import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable, Identifiable {
    case device = "Device"
    case cover = "Screen Cover"
    case calibration = "Calibration"
    case security = "Timers & Security"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .device: return "antenna.radiowaves.left.and.right"
        case .cover: return "photo.on.rectangle.angled"
        case .calibration: return "slider.horizontal.3"
        case .security: return "shield.checkered"
        }
    }
}

struct ContentView: View {
    @Bindable var manager: ProximityManager

    @AppStorage("BRB.hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var selectedTab: SettingsTab = .device

    init(manager: ProximityManager = ProximityManager.shared) {
        self.manager = manager
    }

    var body: some View {
        Group {
            if !hasCompletedOnboarding && manager.pinnedLEID == nil {
                OnboardingView(manager: manager) {
                    hasCompletedOnboarding = true
                }
            } else {
                mainSettingsView
            }
        }
        .onAppear { manager.startMonitoring() }
    }

    private var mainSettingsView: some View {
        VStack(spacing: 0) {
            // Tab Picker Bar
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                            Text(tab.rawValue)
                        }
                        .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundColor(selectedTab == tab ? .accentColor : .primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Active Tab Content
            ScrollView {
                switch selectedTab {
                case .device:
                    deviceTab
                case .cover:
                    CoverSettingsView()
                case .calibration:
                    CalibrationSettingsView(manager: manager)
                case .security:
                    TimersSecuritySettingsView(manager: manager) {
                        hasCompletedOnboarding = false
                    }
                }
            }
        }
        .frame(width: 540, height: 500)
    }

    // MARK: - Device Tab
    private var deviceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. Live Presence Status Card
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(presenceColor.opacity(0.2))
                        .frame(width: 54, height: 54)
                    Image(systemName: presenceIcon)
                        .font(.system(size: 24))
                        .foregroundColor(presenceColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(presenceLabel)
                            .font(.title3.bold())
                        if let remaining = manager.suppressionRemaining {
                            Text("Suppression Active (\(Int(remaining))s)")
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.2))
                                .foregroundColor(.purple)
                                .clipShape(Capsule())
                        }
#if DEBUG
                        if let devPause = manager.developerPauseRemaining {
                            Text("Dev Pause (\(Int(ceil(devPause)))s)")
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .clipShape(Capsule())
                        }
#endif
                    }

                    if let rssi = manager.liveRSSI {
                        HStack(spacing: 6) {
                            Text("Live:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(rssi) dBm (\(manager.liveKind))")
                                .font(.system(.caption, design: .monospaced).bold())

                            if let smoothed = manager.smoothedRSSI {
                                Text("• Smoothed:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%.1f dBm", smoothed))
                                    .font(.system(.caption, design: .monospaced).bold())
                            }
                        }
                    } else {
                        Text(manager.leStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let age = manager.sampleAge {
                        Text("Sample age: \(String(format: "%.1f", age))s \(manager.isStale ? "(stale)" : "")")
                            .font(.caption2)
                            .foregroundColor(manager.isStale ? .orange : .secondary)
                    }
                }

                Spacer()

                if manager.suppressionRemaining != nil {
                    Button("End Suppression") {
                        manager.suppressionRemaining = nil
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
            .padding(14)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(12)

            // 2. Monitored Device Info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Monitored Earbuds")
                        .font(.headline)
                    Spacer()
                    if manager.pinnedLEID != nil {
                        Button("Unpin Device") {
                            manager.unpinLEDevice()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                    }
                }

                if let pinned = manager.pinnedName {
                    HStack {
                        Image(systemName: "headphones")
                            .foregroundColor(.accentColor)
                        Text(pinned)
                            .font(.subheadline.bold())
                        Spacer()
                        Text("Pinned")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(8)
                } else {
                    Text("No device pinned. Select your earbuds from the scanner below to start monitoring.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // 3. Nearby Device Scanner
            VStack(alignment: .leading, spacing: 8) {
                Text("Nearby Bluetooth LE Devices")
                    .font(.headline)
                DevicePickerView(manager: manager)
            }
        }
        .padding(20)
    }

    private var presenceColor: Color {
        switch manager.presenceState {
        case .near: return .green
        case .far: return .orange
        case .gone: return .red
        case .idle: return .secondary
        }
    }

    private var presenceIcon: String {
        switch manager.presenceState {
        case .near: return "person.badge.shield.checkmark.fill"
        case .far: return "figure.walk"
        case .gone: return "exclamationmark.shield.fill"
        case .idle: return "shield.slash"
        }
    }

    private var presenceLabel: String {
        switch manager.presenceState {
        case .near: return "Near (Mac Safe)"
        case .far: return "Away (Cover Active)"
        case .gone: return "Gone (Signal Lost)"
        case .idle: return "Idle (No Device)"
        }
    }
}

#Preview("BRB Monitoring") {
    ContentView(manager: .previewMock)
}
