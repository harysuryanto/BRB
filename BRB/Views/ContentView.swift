//
//  ContentView.swift
//  BRB
//
//  Main Control Center & Settings window for BRB.
//  Includes 5 tabs:
//  1. Device & Presence (Real-time signal diagnostics, presence badge, nearby scanner)
//  2. Screen Cover (Veil cover preview and custom image picker)
//  3. Calibration (Threshold sliders, hysteresis band, and away capture)
//  4. Timers & Security (Grace delay, suppression window, and fail-secure toggle)
//  5. About (System information, app architecture, privacy commitments, diagnostic exports)
//

import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable, Identifiable {
    case device = "Device"
    case cover = "Screen Cover"
    case calibration = "Calibration"
    case security = "Timers & Security"
    case about = "About"
    var id: String { rawValue }

    /// Short label for the TabView bar so all four tabs fit without collapsing.
    var title: String {
        switch self {
        case .device: return "Device"
        case .cover: return "Cover"
        case .calibration: return "Calibration"
        case .security: return "Security"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .device: return "antenna.radiowaves.left.and.right"
        case .cover: return "photo.on.rectangle.angled"
        case .calibration: return "slider.horizontal.3"
        case .security: return "shield.checkered"
        case .about: return "info.circle"
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
            // Onboarding shows exactly once, until Finish is tapped.
            // Never gate on pin state: pinning mid-onboarding used to jump
            // to settings (skipping Finish), and unpinning then dropped back
            // to the permission step even though consent was granted.
            if !hasCompletedOnboarding {
                OnboardingView(manager: manager) {
                    hasCompletedOnboarding = true
                }
            } else {
                mainSettingsView
            }
        }
        .background(WindowCapabilityConfigurator())
        .onAppear { manager.startMonitoring() }
    }

    private var mainSettingsView: some View {
        TabView(selection: $selectedTab) {
            ScrollView {
                deviceTab
            }
            .tabItem { Label(SettingsTab.device.title, systemImage: SettingsTab.device.icon) }
            .tag(SettingsTab.device)

            ScrollView {
                CoverSettingsView(manager: manager)
            }
            .tabItem { Label(SettingsTab.cover.title, systemImage: SettingsTab.cover.icon) }
            .tag(SettingsTab.cover)

            ScrollView {
                CalibrationSettingsView(manager: manager) {
                    selectedTab = .device
                }
            }
            .tabItem { Label(SettingsTab.calibration.title, systemImage: SettingsTab.calibration.icon) }
            .tag(SettingsTab.calibration)

            ScrollView {
                TimersSecuritySettingsView(manager: manager) {
                    hasCompletedOnboarding = false
                }
            }
            .tabItem { Label(SettingsTab.security.title, systemImage: SettingsTab.security.icon) }
            .tag(SettingsTab.security)

            ScrollView {
                AboutSettingsView(manager: manager)
            }
            .tabItem { Label(SettingsTab.about.title, systemImage: SettingsTab.about.icon) }
            .tag(SettingsTab.about)
        }
        .frame(
            minWidth: DS.windowWidth,
            idealWidth: DS.windowWidth,
            maxWidth: DS.windowMaxWidth,
            minHeight: DS.windowHeight,
            idealHeight: DS.windowHeight,
            maxHeight: DS.windowMaxHeight
        )
    }

    // MARK: - Device Tab
    private var deviceTab: some View {
        VStack(alignment: .leading, spacing: DS.spacingLG) {
            if manager.protectionPaused {
                if let rem = manager.protectionPauseRemaining {
                    DSBanner(
                        icon: "pause.circle.fill",
                        text: "Protection paused — auto-resumes in \(formatCountdown(rem)). Cover will not activate until then.",
                        tint: .orange
                    )
                } else {
                    DSBanner(
                        icon: "pause.circle",
                        text: "Protection paused indefinitely — the cover will not activate until resumed.",
                        tint: .orange
                    )
                }
            }

            // 1. Live Presence Status Card
            HStack(alignment: .center, spacing: DS.spacingLG) {
                ZStack {
                    Circle()
                        .fill(presenceColor.opacity(0.2))
                        .frame(width: 54, height: 54)
                    Image(systemName: presenceIcon)
                        .font(.system(size: 24))
                        .foregroundColor(presenceColor)
                }

                VStack(alignment: .leading, spacing: DS.spacingXS) {
                    HStack(spacing: DS.spacingSM) {
                        Text(presenceLabel)
                            .font(.headline)
                        if manager.protectionPaused {
                            if let rem = manager.protectionPauseRemaining {
                                DSPill(text: "Paused (\(formatCountdown(rem)))", tint: .orange)
                            } else {
                                DSPill(text: "Paused", tint: .orange)
                            }
                        }
                        if let remaining = manager.suppressionRemaining {
                            DSPill(text: "Suppression Active (\(formatCountdown(remaining)))", tint: .purple)
                        }
#if DEBUG
                        if let devPause = manager.developerPauseRemaining {
                            DSPill(text: "Dev Pause (\(Int(ceil(devPause)))s)", tint: .orange)
                        }
#endif
                    }

                    if let relink = manager.lastRelink, Date().timeIntervalSince(relink.at) < 60 {
                        Text("Re-linked \(relink.name) — new session")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Monitored signal only: no pin, no signal lines.
                    if manager.pinnedKey != nil, let smoothed = manager.smoothedRSSI {
                        HStack(spacing: DS.spacingSM) {
                            Text("Signal:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(round(smoothed))) dBm")
                                .font(.system(.subheadline, design: .monospaced).bold())
                        }
                        if manager.isTrackingWithoutAdverts, let title = manager.pinnedDisplayName {
                            Text("Your \(isUnnamed(title) ? "device" : title) ghosted the scanner. Rude. Signal's still great though.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if manager.pinnedKey != nil {
                        Text(manager.leStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if manager.pinnedKey != nil, let age = manager.sampleAge {
                        Text("Sample age: \(String(format: "%.1f", age))s \(manager.isStale ? "(stale)" : "")")
                            .font(.caption)
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
            .padding(DS.cardPad)
            .background(DS.emphasisBg())
            .cornerRadius(DS.radius)

            // 1b. Pause Protection controls
            VStack(alignment: .leading, spacing: DS.spacingSM) {
                HStack {
                    VStack(alignment: .leading, spacing: DS.spacingXS) {
                        HStack(spacing: 6) {
                            Text("Pause Protection")
                                .font(.subheadline.bold())
                            if manager.protectionPaused {
                                if let rem = manager.protectionPauseRemaining {
                                    Text("• Resumes in \(formatCountdown(rem))")
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                        .foregroundColor(.orange)
                                } else {
                                    Text("• Paused indefinitely")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        Text("Stops the cover from activating until resumed. Your screen stays visible while paused.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("Pause Protection", isOn: $manager.protectionPaused)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                // Preset duration buttons
                HStack(spacing: 8) {
                    pausePresetButton("15m", seconds: 15 * 60)
                    pausePresetButton("1h", seconds: 3600)
                    pausePresetButton("3h", seconds: 10800)
                    pausePresetButton("Indefinite", seconds: 0)

                    if manager.protectionPaused {
                        Button("Resume Now") {
                            manager.resumeProtection()
                        }
                        .font(.caption.weight(.medium))
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.small)
                    }
                }
            }
            .padding(DS.cardPad)
            .background(DS.cardBg)
            .cornerRadius(DS.radius)

            // 2. Monitored Device Info
            VStack(alignment: .leading, spacing: DS.spacingSM) {
                HStack {
                    Text("Monitored Device")
                        .font(.headline)
                    Spacer()
                    if manager.pinnedKey != nil {
                        Button("Unpin Device") {
                            manager.unpinLEDevice()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                    }
                }

                // Gate on pin state, not name resolvability (see liveSignalCard).
                if let pkey = manager.pinnedKey, let pinned = manager.pinnedDisplayName {
                    HStack {
                        DeviceArtView(name: manager.artName(forKey: pkey), category: manager.deviceCategory(forKey: pkey), size: 40, seed: pkey)
                        Text(pinned)
                            .font(.subheadline.bold())
                        Spacer()
                        DSPill(text: "Pinned", tint: .green)
                    }
                    .padding(DS.compactPad)
                    .background(DS.cardBg)
                    .cornerRadius(DS.radius)
                } else {
                    Text("No device pinned. Select your earbuds or phone from the scanner below to start monitoring.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // 3. Nearby Device Scanner
            VStack(alignment: .leading, spacing: DS.spacingSM) {
                Text("Nearby Bluetooth LE Devices")
                    .font(.headline)
                DevicePickerView(manager: manager)
            }
        }
        .padding(DS.outerPad)
    }

    private func pausePresetButton(_ title: String, seconds: TimeInterval) -> some View {
        Button(action: {
            manager.pauseProtection(for: seconds)
        }) {
            Text(title)
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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

// MARK: - Window Capability Configurator

/// Configures the hosting NSWindow to allow resizing while disabling fullscreen mode,
/// enforcing industry-standard min/max bounds, and removing the green zoom button.
private struct WindowCapabilityConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowTrackingView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            Self.applyConfiguration(to: window)
        }
    }

    static func applyConfiguration(to window: NSWindow) {
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.insert(.fullScreenNone)
        window.minSize = NSSize(width: DS.windowWidth, height: DS.windowHeight)
        window.maxSize = NSSize(width: DS.windowMaxWidth, height: DS.windowMaxHeight)
        if let zoomButton = window.standardWindowButton(.zoomButton) {
            zoomButton.isHidden = true
            zoomButton.isEnabled = false
        }
    }

    private final class WindowTrackingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                WindowCapabilityConfigurator.applyConfiguration(to: window)
            }
        }
    }
}

#Preview("BRB Monitoring") {
    ContentView(manager: .previewMock)
}
