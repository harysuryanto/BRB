//
//  CalibrationSettingsView.swift
//  BRB
//
//  Settings tab for calibrating signal thresholds and hysteresis gaps.
//

import SwiftUI

struct CalibrationSettingsView: View {
    @Bindable var manager: ProximityManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Proximity Thresholds & Hysteresis")
                .font(.headline)

            Text("BRB uses a hysteresis band to prevent the screen cover from flickering when you are right on the edge of your desk area.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 16) {
                // Veil-On Threshold (Away)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Veil-On Threshold (Stepped Away):")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(Int(manager.veilOnThreshold)) dBm")
                            .font(.system(.subheadline, design: .monospaced).bold())
                    }
                    Slider(value: $manager.veilOnThreshold, in: -95...(-50), step: 1)
                    Text("When signal drops to or below this level for the grace duration, the cover activates.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Veil-Off Threshold (Return)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Veil-Off Threshold (Returned):")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(Int(manager.veilOffThreshold)) dBm")
                            .font(.system(.subheadline, design: .monospaced).bold())
                    }
                    Slider(value: $manager.veilOffThreshold, in: -85...(-40), step: 1)
                    Text("When signal rises to or above this level, the cover dismisses immediately.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(10)

            // Calibration actions
            VStack(alignment: .leading, spacing: 10) {
                Text("Calibration Actions")
                    .font(.subheadline.bold())

                HStack(spacing: 12) {
                    Button("Calibrate Away Boundary (~2m)") {
                        manager.calibrateAwayBoundary()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reset to Defaults (-80 / -70 dBm)") {
                        manager.resetThresholdsToDefault()
                    }
                    .buttonStyle(.bordered)
                }

                Text("Stand where you'd like the veil to activate, then click 'Calibrate Away Boundary'. Veil-On will set to that dBm and Veil-Off to +10 dBm.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
    }
}
