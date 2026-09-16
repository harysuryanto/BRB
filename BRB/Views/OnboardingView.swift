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
        .frame(width: DS.windowWidth, height: DS.windowHeight)
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

            VStack(alignment: .leading, spacing: DS.spacingSM) {
                HStack {
                    Text("Live Earbud Signal:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let s = draftSample {
                        Text("\(s.rssi) dBm (LE-adv)")
                            .font(.system(.subheadline, design: .monospaced).bold())
                    } else {
                        Text("Waiting for signal…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Draft Away Threshold:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(draftVeilOn)) dBm")
                        .font(.system(.subheadline, design: .monospaced).bold())
                }
            }
            .padding(DS.cardPad)
            .background(DS.emphasisBg())
            .cornerRadius(DS.radius)

            HStack(spacing: DS.spacingMD) {
                Button("Capture Away Boundary (~2m)") {
                    let ref = Double(draftSample?.rssi ?? -80)
                    draftVeilOn = ref
                    draftVeilOff = ref + 10.0
                    calibrationCaptured = ref
                }
                .buttonStyle(.bordered)

                Button("Use Recommended Default (-80 dBm)") {
                    draftVeilOn = -80.0
                    draftVeilOff = -70.0
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

            CoverPreviewCards(isActive: previewCoverOn)

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

// MARK: - Cover preview cards (gentle preview — no fullscreen during setup)

/// Two side-by-side cards showing the cover states. Whichever matches the
/// live state pulses (sine-driven via TimelineView, so it animates correctly
/// from the very first frame — repeatForever only starts on a value *change*
/// and would leave the initially-active card static); the other dims.
/// Used in onboarding Step 3 so calibration never fullscreen-shocks the user.
private struct CoverPreviewCards: View {
    var isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            // 0…1 breathing phase, ~1.8s period.
            let pulse = 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.8)
            HStack(spacing: DS.spacingMD) {
                Spacer(minLength: 0)
                previewCard(title: "Cover Off", subtitle: "Screens visible", icon: "eye", tint: .green, active: !isActive, pulse: pulse)
                previewCard(title: "Cover On", subtitle: "Screens hidden", icon: "eye.slash", tint: .orange, active: isActive, pulse: pulse)
                Spacer(minLength: 0)
            }
        }
    }

    private func previewCard(title: String, subtitle: String, icon: String, tint: Color, active: Bool, pulse: Double) -> some View {
        VStack(spacing: DS.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(tint)
            Text(title)
                .font(.subheadline.bold())
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: DS.coverPreviewCardWidth)
        .padding(DS.cardPad)
        .background(tint.opacity(active ? 0.15 : 0.06))
        .cornerRadius(DS.radius)
        .overlay(
            RoundedRectangle(cornerRadius: DS.radius)
                .stroke(tint.opacity(active ? 0.6 : 0.15), lineWidth: active ? 2 : 1)
        )
        .opacity(active ? 1.0 : 0.6)
        .scaleEffect(active ? 1.0 + 0.03 * pulse : 1.0)
        .shadow(color: tint.opacity(active ? 0.45 * pulse : 0), radius: active ? 10 : 0)
        .animation(.easeOut(duration: 0.25), value: active)
        .accessibilityLabel("\(title), \(subtitle)\(active ? ", current state" : "")")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
