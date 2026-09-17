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

    /// Instant preview reading: advert RSSI, nil when absent/stale. Updated
    /// per packet — deliberately no grace delay (setup is not live yet).
    private var draftReading: Int? {
        guard let s = draftSample,
              Date().timeIntervalSince(s.at) < 12 else { return nil }
        return s.rssi
    }

    private var draftIsStale: Bool {
        guard let id = draftPinnedID,
              let s = manager.leAdverts[id] else { return true }
        return Date().timeIntervalSince(s.at) >= 12
    }

    private func applyPreview(reading: Int?) {
        guard let reading else { previewCoverOn = false; return }
        if reading <= Int(draftVeilOn.rounded()) { previewCoverOn = true }
        else if reading >= Int(draftVeilOff.rounded()) { previewCoverOn = false }
        // Between: hold last (hysteresis gap, no flicker).
    }

    private var previewReason: String {
        guard draftPinnedID != nil else { return "Pick a device in the previous step to preview." }
        guard let s = draftSample else { return "Waiting for signal…" }
        if Date().timeIntervalSince(s.at) >= 12 { return "Signal stale — move the bud to refresh." }
        if previewCoverOn {
            return "Signal \(s.rssi) dBm is below your \(Int(draftVeilOn)) dBm boundary."
        }
        return "Signal \(s.rssi) dBm is above your \(Int(draftVeilOn)) dBm boundary."
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

    // MARK: - Step 2: Device Selection
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

            SignalBarView(reading: draftReading, boundary: draftVeilOn, previewOn: previewCoverOn)

            HStack(spacing: DS.spacingMD) {
                Button("Capture Away Boundary (~2m)") {
                    let ref = Double(draftSample?.rssi ?? -80)
                    draftVeilOn = ref
                    draftVeilOff = ref + 6.0
                    calibrationCaptured = ref
                }
                .buttonStyle(.bordered)

                Button("Use Recommended Default (-80 dBm)") {
                    draftVeilOn = -80.0
                    draftVeilOff = -74.0
                    calibrationCaptured = -80.0
                }
                .buttonStyle(.borderless)
            }

            if let captured = calibrationCaptured {
                DSBanner(
                    icon: "checkmark.circle.fill",
                    text: "Boundary set to \(Int(captured)) dBm (Veil activates below this).",
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
        .onChange(of: draftReading) { _, reading in applyPreview(reading: reading) }
        .onChange(of: draftIsStale) { _, stale in
            if stale { previewCoverOn = false } else { applyPreview(reading: draftReading) }
        }
        .onChange(of: draftPinnedID) { _, _ in previewCoverOn = false }
    }
}

// MARK: - Signal bar (live setup gauge — no fullscreen during setup)

/// Straight horizontal gauge mapping draft advert RSSI to person position:
/// left = near (strong), right = far (weak). Fixed −50…−95 dBm window (same
/// bounds as the Calibration sliders), so the boundary tick visibly travels
/// when you Capture or reset. Instant (no grace): setup is not live yet.
/// The human needle glides per packet.
private struct SignalBarView: View {
    var reading: Int?
    var boundary: Double
    var previewOn: Bool

    private let minV: Double = -95
    private let maxV: Double = -50

    private func fraction(_ rssi: Double) -> Double {
        min(1, max(0, (rssi - minV) / (maxV - minV)))
    }

    var body: some View {
        VStack(spacing: DS.spacingSM) {
            HStack {
                Text("Live Signal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let reading {
                    Text("\(reading) dBm")
                        .font(.system(.subheadline, design: .monospaced).bold())
                } else {
                    Text("—")
                        .font(.system(.subheadline, design: .monospaced).bold())
                        .foregroundColor(.secondary)
                }
                DSPill(text: previewOn ? "Cover On" : "Cover Off", tint: previewOn ? .orange : .green)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let bx = (1 - fraction(boundary)) * w
                ZStack(alignment: .topLeading) {
                    // Zone bar with a hard stop at the boundary.
                    RoundedRectangle(cornerRadius: 5)
                        .fill(zoneFill(total: w, split: bx))
                        .frame(height: 10)
                        .offset(y: 34)
                    // Boundary tick.
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2, height: 18)
                        .offset(x: bx - 1, y: 30)
                    // Human needle.
                    if let reading {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 24))
                            .foregroundColor(previewOn ? .orange : .green)
                            .offset(x: (1 - fraction(Double(reading))) * w - 12, y: 2)
                            // Slow glide (packets retarget several×/s): reads as
                            // a person walking, not a needle jumping.
                            .animation(.easeInOut(duration: 0.9), value: reading)
                    }
                }
            }
            .frame(height: 50)
            // Boundary tick and zones glide when Capture/Default moves it.
            .animation(.easeOut(duration: 0.3), value: boundary)

            HStack {
                Text("Near \(Int(maxV))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(boundary))")
                    .font(.system(.caption, design: .monospaced).bold())
                Spacer()
                Text("Far \(Int(minV))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(DS.cardPad)
        .background(DS.emphasisBg())
        .cornerRadius(DS.radius)
        .animation(.easeOut(duration: 0.25), value: previewOn)
    }

    private func zoneFill(total w: CGFloat, split bx: CGFloat) -> LinearGradient {
        let f = w > 0 ? Double(bx / w) : 0.5
        let near: Color = reading == nil ? .secondary : .green
        let far: Color = reading == nil ? .secondary : .orange
        return LinearGradient(
            stops: [
                .init(color: near.opacity(previewOn ? 0.35 : 1.0), location: 0),
                .init(color: near.opacity(previewOn ? 0.35 : 1.0), location: f),
                .init(color: far.opacity(previewOn ? 1.0 : 0.35), location: f),
                .init(color: far.opacity(previewOn ? 1.0 : 0.35), location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }
}

#Preview("Signal Bar — Near") {
    SignalBarView(reading: -62, boundary: -80, previewOn: false)
        .padding()
        .frame(width: 560)
}

#Preview("Signal Bar — Far") {
    SignalBarView(reading: -88, boundary: -80, previewOn: true)
        .padding()
        .frame(width: 560)
}

#Preview("Signal Bar — Waiting") {
    SignalBarView(reading: nil, boundary: -80, previewOn: false)
        .padding()
        .frame(width: 560)
}
