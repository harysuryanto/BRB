//
//  OnboardingView.swift
//  BRB
//
//  3-Step onboarding wizard for first launch:
//  1. Bluetooth permission & consent
//  2. Live earbud discovery & pinning
//  3. Away boundary calibration (~2m walk-away)
//

import SwiftUI
import AppKit

struct OnboardingView: View {
    @Bindable var manager: ProximityManager
    var onComplete: () -> Void

    @State private var currentStep: Int = 1
    @State private var calibrationCaptured: Double? = nil

    // MARK: - Draft (registration form — nothing here touches live state
    // until Finish submits via commitOnboardingDraft).
    @State private var draftPinnedID: String?
    @State private var draftVeilOn: Double
    @State private var draftVeilOff: Double
    /// Instant preview state (no grace — see draftReading below).
    @State private var previewCoverOn: Bool = false
    /// Draft-side EMA (same α as the engine): the draft device is never
    /// pinned, so the engine filter never runs for it. Smoothing here keeps
    /// the preview, meter, and capture snapshot calm.
    @State private var draftFilter = SignalProcessor(alpha: 0.8)
    @State private var draftSmoothed: Double? = nil

    init(manager: ProximityManager = .shared, onComplete: @escaping () -> Void) {
        self.manager = manager
        self.onComplete = onComplete
        // Prefill from live so re-runs open as an edit form, not blank.
        _draftPinnedID = State(initialValue: manager.pinnedLEID)
        _draftVeilOn = State(initialValue: manager.veilOnThreshold)
        _draftVeilOff = State(initialValue: manager.veilOffThreshold)
    }

    /// Live advert sample for the DRAFT pick (read-only scan data — the draft
    /// device is never pinned, so engine liveRSSI may belong to a stranger).
    private var draftSample: AdvertSample? {
        guard let id = draftPinnedID else { return nil }
        return manager.leAdverts[id]
    }

    /// Raw advert RSSI feed for the draft filter, nil when absent/stale.
    /// Updated per packet — deliberately no grace delay (setup is not live yet).
    private var draftReading: Int? {
        guard let s = draftSample,
              Date().timeIntervalSince(s.at) < 12 else { return nil }
        return s.rssi
    }

    private var doubleReading: Double? {
        draftSmoothed
    }

    /// Pushes the latest raw advert RSSI through the draft EMA filter.
    /// Stale (nil) readings are never fed — the stale pill covers those.
    private func feedDraftFilter() {
        guard let raw = draftReading else { return }
        draftSmoothed = draftFilter.process(rawRSSI: raw)
    }

    /// Clears draft smoothing (e.g. when the picked device changes).
    private func resetDraftFilter() {
        draftFilter.reset()
        draftSmoothed = nil
    }

    private var draftIsStale: Bool {
        guard let id = draftPinnedID,
              let s = manager.leAdverts[id] else { return true }
        return Date().timeIntervalSince(s.at) >= 12
    }

    private func applyPreview(reading: Double?) {
        guard let reading else { previewCoverOn = false; return }
        if reading <= draftVeilOn { previewCoverOn = true }
        else if reading >= draftVeilOff { previewCoverOn = false }
        // Between: hold last (hysteresis gap, no flicker).
    }

    private var previewReason: String {
        guard draftPinnedID != nil else { return "Pick a device in the previous step to preview." }
        guard let s = draftSample else { return "Waiting for signal…" }
        if Date().timeIntervalSince(s.at) >= 12 { return "Signal stale — move the bud to refresh." }
        let shown = doubleReading.map { Int(round($0)) } ?? s.rssi
        if previewCoverOn {
            return "Signal \(shown) dBm is below your \(Int(draftVeilOn)) dBm boundary."
        }
        return "Signal \(shown) dBm is above your \(Int(draftVeilOn)) dBm boundary."
    }

    var body: some View {
        VStack(spacing: DS.wizardSpacing) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to BRB")
                        .font(.title2.bold())
                    Text("Step away. Your screen covers itself.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                DSPill(text: "Step \(currentStep) of 3", tint: .secondary)
            }

            Divider()

            // Step Content (scrollable — the device grid can exceed the
            // fixed window height; header/footer stay pinned).
            ScrollView {
                switch currentStep {
                case 1:
                    permissionStep
                case 2:
                    deviceStep
                case 3:
                    calibrationStep
                default:
                    EmptyView()
                }
            }

            Divider()

            // Footer Navigation
            HStack {
                if currentStep > 1 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                }

                Spacer()

                if currentStep == 1 {
                    Button("Continue") {
                        withAnimation { currentStep = 2 }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!manager.bluetoothGranted)
                } else if currentStep == 2 {
                    Button("Continue") {
                        withAnimation { currentStep = 3 }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draftPinnedID == nil)
                } else if currentStep == 3 {
                    Button("Finish Setup") {
                        manager.commitOnboardingDraft(pinnedID: draftPinnedID, veilOn: draftVeilOn, veilOff: draftVeilOff)
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(DS.wizardOuterPad)
        .frame(
            minWidth: DS.windowWidth,
            idealWidth: DS.windowWidth,
            maxWidth: DS.windowMaxWidth,
            minHeight: DS.windowHeight,
            idealHeight: DS.windowHeight,
            maxHeight: DS.windowMaxHeight
        )
    }

    // MARK: - Step 1: Bluetooth Permission
    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: DS.spacingLG) {
            Text("Step 1: Bluetooth Access")
                .font(.headline)

            Text("BRB measures the radio presence (Bluetooth LE signal strength) of your wireless earbuds to detect when you walk away from your Mac.")
                .font(.body)
                .foregroundColor(.secondary)

            HStack(spacing: DS.spacingMD) {
                Circle()
                    .fill(manager.bluetoothGranted ? Color.green : Color.orange)
                    .frame(width: 12, height: 12)
                Text(manager.bluetoothGranted ? "Bluetooth permission granted" : manager.bluetoothPermission)
                    .font(.subheadline.bold())
            }
            .padding(DS.cardPad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.emphasisBg())
            .cornerRadius(DS.radius)

            if !manager.bluetoothGranted {
                VStack(alignment: .leading, spacing: DS.spacingSM) {
                    Text("If macOS prompted you, please click **Allow**.")
                        .font(.caption)
                    Text("If denied, open System Settings → Privacy & Security → Bluetooth to enable it.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Open Bluetooth Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Step 2: Choose your Earbuds
    private var deviceStep: some View {
        VStack(alignment: .leading, spacing: DS.spacingLG) {
            Text("Step 2: Choose your Earbuds")
                .font(.headline)

            Text("Select the wireless earbuds you wear around the desk. Move the buds or wear them so BRB can detect their signal.")
                .font(.body)
                .foregroundColor(.secondary)

            if let id = draftPinnedID {
                let name = manager.leAdverts[id]?.name ?? String(id.prefix(8))
                HStack {
                    DeviceArtView(name: name, size: 32)
                    Text("Selected device: **\(name)**")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .padding(DS.compactPad)
                .background(Color.green.opacity(0.1))
                .cornerRadius(DS.radius)
            }

            DevicePickerView(
                manager: manager,
                selectedID: draftPinnedID,
                onToggle: { draftPinnedID = ($0 == draftPinnedID) ? nil : $0 },
                mode: .draft
            )
        }
    }

    // MARK: - Step 3: Away Boundary Calibration
    private var calibrationStep: some View {
        VStack(alignment: .leading, spacing: DS.spacingLG) {
            Text("Step 3: Away Boundary Calibration")
                .font(.headline)

            Text("Stand where you'd like your screen cover to activate (usually ~2 meters / 6 feet away from the desk), or use our recommended default.")
                .font(.body)
                .foregroundColor(.secondary)

            // Live Signal Range Gauge Card
            VStack(alignment: .leading, spacing: DS.spacingMD) {
                HStack {
                    Text("Live Signal Range Gauge")
                        .font(.subheadline.bold())

                    Spacer()

                    if let reading = doubleReading, !draftIsStale {
                        if reading <= draftVeilOn {
                            DSPill(text: "Away Zone (Cover On)", tint: .orange)
                        } else if reading >= draftVeilOff {
                            DSPill(text: "Desk Zone (Cover Off)", tint: .green)
                        } else {
                            DSPill(text: "Buffer Zone (Holding)", tint: .blue)
                        }
                    } else if draftIsStale && draftSample != nil {
                        DSPill(text: "Signal Stale", tint: .orange)
                    } else if draftPinnedID != nil {
                        DSPill(text: "Waiting for Signal", tint: .secondary)
                    } else {
                        DSPill(text: "No Device Selected", tint: .secondary)
                    }
                }

                if let sample = draftSample {
                    HStack(spacing: DS.spacingSM) {
                        Text("Device:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(sample.name)
                            .font(.caption.bold())

                        if let reading = doubleReading {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(round(reading))) dBm")
                                .font(.system(.caption, design: .monospaced).bold())
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(estimatedDistanceString(for: reading))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                CalibrationRangeMeterView(
                    reading: doubleReading,
                    isStale: draftIsStale,
                    veilOn: draftVeilOn,
                    veilOff: draftVeilOff
                )

                // Zone Legend
                HStack(spacing: DS.spacingMD) {
                    HStack(spacing: DS.spacingXS) {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                        Text("Away: ≤ \(Int(draftVeilOn)) dBm")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: DS.spacingXS) {
                        Circle().fill(Color.blue).frame(width: 8, height: 8)
                        let gap = Int(round(draftVeilOff - draftVeilOn))
                        Text("Buffer: \(gap >= 0 ? "+\(gap)" : "\(gap)") dBm gap")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: DS.spacingXS) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("Desk: ≥ \(Int(draftVeilOff)) dBm")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, DS.spacingXS)
            }
            .padding(DS.cardPad)
            .background(DS.emphasisBg())
            .cornerRadius(DS.radius)

            HStack(spacing: DS.spacingMD) {
                let currentCaptured = doubleReading.map { Int(round($0)) }
                Button(currentCaptured != nil ? "Capture Away Boundary (\(currentCaptured!) dBm)" : "Capture Away Boundary (~2m)") {
                    let ref = doubleReading ?? -80.0
                    draftVeilOn = ref
                    draftVeilOff = ref + 6.0
                    calibrationCaptured = ref
                }
                .buttonStyle(.borderedProminent)

                Button("Use Recommended Default (-80 dBm)") {
                    draftVeilOn = -80.0
                    draftVeilOff = -74.0
                    calibrationCaptured = -80.0
                }
                .buttonStyle(.bordered)
            }

            if let captured = calibrationCaptured {
                DSBanner(
                    icon: "checkmark.circle.fill",
                    text: "Boundary set to \(Int(captured)) dBm (Veil activates below this, lifts at \(Int(captured + 6)) dBm).",
                    tint: .green
                )
            }

            Text("Live preview — instant, no grace delay. The real fullscreen cover stays off during setup.")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(previewReason)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onAppear { feedDraftFilter(); applyPreview(reading: doubleReading) }
        .onChange(of: draftReading) { _, _ in feedDraftFilter(); applyPreview(reading: doubleReading) }
        .onChange(of: draftIsStale) { _, stale in
            if stale { previewCoverOn = false } else { feedDraftFilter(); applyPreview(reading: doubleReading) }
        }
        .onChange(of: draftPinnedID) { _, _ in resetDraftFilter(); previewCoverOn = false }
    }
}

#Preview("Onboarding — Step 3") {
    OnboardingView(manager: .previewMock) {}
}
