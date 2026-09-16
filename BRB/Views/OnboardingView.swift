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

            // Step Content
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

            Spacer(minLength: 0)

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
                    .disabled(manager.pinnedLEID == nil)
                } else if currentStep == 3 {
                    Button("Finish Setup") {
                        UserDefaults.standard.set(true, forKey: "BRB.hasCompletedOnboarding")
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

            if let pinned = manager.pinnedName {
                HStack {
                    Image(systemName: "headphones")
                        .foregroundColor(.accentColor)
                    Text("Pinned device: **\(pinned)**")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .padding(DS.compactPad)
                .background(Color.green.opacity(0.1))
                .cornerRadius(DS.radius)
            }

            DevicePickerView(manager: manager)
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
                    if let rssi = manager.liveRSSI {
                        Text("\(rssi) dBm (\(manager.liveKind))")
                            .font(.system(.subheadline, design: .monospaced).bold())
                    } else {
                        Text("Waiting for signal…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("Current Away Threshold:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(manager.veilOnThreshold)) dBm")
                        .font(.system(.subheadline, design: .monospaced).bold())
                }
            }
            .padding(DS.cardPad)
            .background(DS.emphasisBg())
            .cornerRadius(DS.radius)

            HStack(spacing: DS.spacingMD) {
                Button("Capture Away Boundary (~2m)") {
                    manager.calibrateAwayBoundary()
                    calibrationCaptured = manager.veilOnThreshold
                }
                .buttonStyle(.bordered)

                Button("Use Recommended Default (-80 dBm)") {
                    manager.resetThresholdsToDefault()
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

            if let pauseLeft = manager.calibrationPauseRemaining {
                DSBanner(
                    icon: "pause.circle.fill",
                    text: "Veil paused (\(Int(ceil(pauseLeft)))s) — walk back to your desk, then finish setup.",
                    tint: .blue
                )
            }
        }
    }
}
