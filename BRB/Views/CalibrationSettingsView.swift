//
//  CalibrationSettingsView.swift
//  BRB
//
//  Settings tab for calibrating signal thresholds, visualizing live range
//  and signal strength of monitored earbuds, and configuring hysteresis gaps.
//

import SwiftUI

struct CalibrationSettingsView: View {
    @Bindable var manager: ProximityManager
    var onGoToDeviceTab: (() -> Void)? = nil

    /// Whether there is a currently pinned device with an active, non-gone signal.
    private var hasActiveSignal: Bool {
        manager.pinnedLEID != nil &&
        manager.presenceState != .gone &&
        manager.presenceState != .idle &&
        effectiveReading != nil
    }

    /// Smoothed-only display reading: what the engine acts on is what the UI
    /// shows. Nil while no filtered sample exists (waiting state), never a
    /// raw fallback.
    private var effectiveReading: Double? {
        guard manager.pinnedLEID != nil else { return nil }
        guard manager.presenceState != .gone, manager.presenceState != .idle else { return nil }
        return manager.smoothedRSSI
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.spacingXL) {
            // Header
            VStack(alignment: .leading, spacing: DS.spacingXS) {
                Text("Proximity Thresholds & Calibration")
                    .font(.headline)

                Text("Adjust when BRB covers your screen as you walk away, and when it dismisses as you return. Monitor your live earbud signal in real time below.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // 1. Live Signal & Device Status Card
            liveSignalCard

            // 2. Interactive Range & Threshold Gauge (only when actively receiving signal from pinned earbuds)
            if hasActiveSignal {
                signalGaugeCard
            }

            // 3. Threshold Sliders & Hysteresis
            thresholdSlidersCard

            // 4. Calibration Actions
            calibrationActionsCard
        }
        .padding(DS.outerPad)
    }

    // MARK: - 1. Live Signal Card
    @ViewBuilder
    private var liveSignalCard: some View {
        if let pinnedName = manager.pinnedName, manager.pinnedLEID != nil {
            HStack(alignment: .center, spacing: DS.spacingMD) {
                DeviceArtView(name: pinnedName, size: 44)

                VStack(alignment: .leading, spacing: DS.spacingXS) {
                    HStack(spacing: DS.spacingSM) {
                        Text(pinnedName)
                            .font(.subheadline.bold())

                        if manager.presenceState == .gone {
                            DSPill(text: "Device Gone", tint: .red)
                        } else {
                            DSPill(text: "Monitored", tint: .green)

                            if manager.isStale && manager.smoothedRSSI != nil {
                                DSPill(text: "Stale Signal", tint: .orange)
                            }

                            currentZonePill
                        }
                    }

                    if manager.presenceState == .gone {
                        Text("Signal lost — earbuds may be in their case, out of Bluetooth range, or powered off.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let smoothed = manager.smoothedRSSI {
                        HStack(spacing: DS.spacingSM) {
                            Text("Signal:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(Int(round(smoothed))) dBm")
                                .font(.system(.caption, design: .monospaced).bold())

                            if let age = manager.sampleAge {
                                Text("• \(String(format: "%.1f", age))s ago")
                                    .font(.caption)
                                    .foregroundColor(manager.isStale ? .orange : .secondary)
                            }
                        }
                    } else {
                        Text("Waiting for signal packets… Move or wear your earbuds to wake them.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if manager.presenceState != .gone, let smoothed = manager.smoothedRSSI {
                    VStack(alignment: .trailing, spacing: DS.spacingXS) {
                        SignalBarsView(rssi: Int(round(smoothed)), stale: manager.isStale)
                        if let reading = effectiveReading {
                            Text(estimatedDistanceString(for: reading))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(DS.cardPad)
            .background(DS.emphasisBg())
            .cornerRadius(DS.radius)
        } else {
            HStack(spacing: DS.spacingMD) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: DS.spacingXS) {
                    Text("No Earbuds Pinned")
                        .font(.subheadline.bold())
                    Text("Select and pin your wireless earbuds in the Device tab to view live signal and calibrate thresholds.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let onGoToDeviceTab {
                    Button("Select Device") {
                        onGoToDeviceTab()
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.caption)
                }
            }
            .padding(DS.cardPad)
            .background(DS.cardBg)
            .cornerRadius(DS.radius)
        }
    }

    // MARK: - Current Zone Pill
    @ViewBuilder
    private var currentZonePill: some View {
        if let reading = effectiveReading, !manager.isStale {
            if reading <= manager.veilOnThreshold {
                DSPill(text: "Away Zone", tint: .orange)
            } else if reading >= manager.veilOffThreshold {
                DSPill(text: "Desk Zone", tint: .green)
            } else {
                DSPill(text: "Buffer Zone", tint: .blue)
            }
        }
    }

    // MARK: - 2. Signal Gauge Card
    private var signalGaugeCard: some View {
        VStack(alignment: .leading, spacing: DS.spacingMD) {
            HStack {
                Text("Live Signal Range Gauge")
                    .font(.subheadline.bold())

                Spacer()

                if let reading = effectiveReading {
                    Text(rangeDescription(for: reading))
                        .font(.caption.bold())
                        .foregroundColor(reading <= manager.veilOnThreshold ? .orange : (reading >= manager.veilOffThreshold ? .green : .accentColor))
                }
            }

            CalibrationRangeMeterView(
                reading: effectiveReading,
                isStale: manager.isStale,
                veilOn: manager.veilOnThreshold,
                veilOff: manager.veilOffThreshold
            )

            // Zone Legend
            HStack(spacing: DS.spacingMD) {
                HStack(spacing: DS.spacingXS) {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                    Text("Away: ≤ \(Int(manager.veilOnThreshold)) dBm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: DS.spacingXS) {
                    Circle().fill(Color.blue).frame(width: 8, height: 8)
                    let gap = Int(round(manager.veilOffThreshold - manager.veilOnThreshold))
                    Text("Buffer: \(gap >= 0 ? "+\(gap)" : "\(gap)") dBm gap")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: DS.spacingXS) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("Desk: ≥ \(Int(manager.veilOffThreshold)) dBm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, DS.spacingXS)
        }
        .padding(DS.cardPad)
        .background(DS.cardBg)
        .cornerRadius(DS.radius)
    }

    // MARK: - 3. Threshold Sliders Card
    private var thresholdSlidersCard: some View {
        VStack(spacing: DS.spacingLG) {
            // Veil-On Threshold (Away)
            VStack(alignment: .leading, spacing: DS.spacingSM) {
                HStack {
                    Text("Veil-On Threshold (Stepped Away):")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("\(Int(manager.veilOnThreshold)) dBm")
                        .font(.system(.subheadline, design: .monospaced).bold())
                }

                Slider(value: $manager.veilOnThreshold, in: -95...(-50), step: 1)

                HStack {
                    Text("When signal drops to or below this level for the grace duration, the cover activates.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if let reading = effectiveReading {
                        let diff = Int(round(reading - manager.veilOnThreshold))
                        if diff >= 0 {
                            Text("Current is +\(diff) dBm above")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                        } else {
                            Text("Current is \(abs(diff)) dBm below (Triggers)")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                        }
                    }
                }
            }

            Divider()

            // Veil-Off Threshold (Return)
            VStack(alignment: .leading, spacing: DS.spacingSM) {
                HStack {
                    Text("Veil-Off Threshold (Returned):")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("\(Int(manager.veilOffThreshold)) dBm")
                        .font(.system(.subheadline, design: .monospaced).bold())
                }

                Slider(value: $manager.veilOffThreshold, in: -85...(-40), step: 1)

                HStack {
                    Text("When signal rises to or above this level, the cover dismisses immediately.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if let reading = effectiveReading {
                        let diff = Int(round(reading - manager.veilOffThreshold))
                        if diff >= 0 {
                            Text("Current is +\(diff) dBm above (Dismissed)")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                        } else {
                            Text("Current is \(abs(diff)) dBm below")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if manager.veilOffThreshold <= manager.veilOnThreshold {
                DSBanner(
                    icon: "exclamationmark.triangle.fill",
                    text: "Veil-Off should be higher than Veil-On (recommended buffer is +4 to +6 dBm) to prevent screen flickering.",
                    tint: .orange
                )
            }
        }
        .padding(DS.cardPad)
        .background(DS.cardBg)
        .cornerRadius(DS.radius)
    }

    // MARK: - 4. Calibration Actions Card
    private var calibrationActionsCard: some View {
        VStack(alignment: .leading, spacing: DS.spacingSM) {
            Text("Calibration Actions")
                .font(.subheadline.bold())

            if let pauseLeft = manager.calibrationPauseRemaining {
                DSBanner(
                    icon: "pause.circle.fill",
                    text: "Veil paused (\(Int(ceil(pauseLeft)))s) — walk back to your desk.",
                    tint: .blue
                )
            }

            HStack(spacing: DS.spacingMD) {
                let currentCaptured = effectiveReading.map { Int(round($0)) }
                Button(currentCaptured != nil ? "Calibrate Away Boundary (\(currentCaptured!) dBm)" : "Calibrate Away Boundary (~2m)") {
                    manager.calibrateAwayBoundary(currentRSSI: effectiveReading)
                }
                .buttonStyle(.borderedProminent)

                Button("Reset to Defaults (-80 / -74 dBm)") {
                    manager.resetThresholdsToDefault()
                }
                .buttonStyle(.bordered)
            }

            if let currentCaptured = effectiveReading.map({ Int(round($0)) }) {
                Text("Stand where you want the veil to activate (current signal: \(currentCaptured) dBm, \(estimatedDistanceString(for: Double(currentCaptured)))), then click 'Calibrate Away Boundary'. Veil-On will set to \(currentCaptured) dBm and Veil-Off to \(currentCaptured + 6) dBm with a 5s walking pause.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Stand where you'd like the veil to activate, then click 'Calibrate Away Boundary'. Veil-On will set to that dBm and Veil-Off to +6 dBm.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Range Helpers
    private func rangeDescription(for rssi: Double) -> String {
        if rssi <= manager.veilOnThreshold {
            return "Cover would trigger (Away)"
        } else if rssi >= manager.veilOffThreshold {
            return "Cover dismissed (In Range)"
        } else {
            return "Inside hysteresis buffer"
        }
    }
}
