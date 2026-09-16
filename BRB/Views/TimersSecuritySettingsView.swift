//
//  TimersSecuritySettingsView.swift
//  BRB
//
//  Settings tab for configuring grace timers, suppression windows, and fail-secure lock.
//

import SwiftUI

struct TimersSecuritySettingsView: View {
    @Bindable var manager: ProximityManager
    var onResetOnboarding: () -> Void

    /// Grace options (seconds): Instant + multiples of 5 up to 60.
    private let graceOptions: [Int] = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60]
    /// Suppression options (minutes): Instant + multiples of 5 up to 60.
    private let suppressMinuteOptions: [Int] = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Timers & Security Policies")
                .font(.headline)

            VStack(spacing: 16) {
                // Grace Delay Dropdown
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Grace Delay")
                            .font(.subheadline.bold())
                        Text("Wait time before covering screen once signal drops below threshold.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("Grace Delay", selection: Binding(
                        get: { Self.nearestOption(graceOptions, to: Int(manager.graceDelay.rounded())) },
                        set: { manager.graceDelay = TimeInterval($0) }
                    )) {
                        ForEach(graceOptions, id: \.self) { seconds in
                            Text(graceLabel(seconds)).tag(seconds)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 190)
                }

                Divider()

                // Suppression Window Dropdown
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Post-Unlock Suppression")
                            .font(.subheadline.bold())
                        Text("Keeps the cover down after authenticating at loginwindow without your earbuds.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("Post-Unlock Suppression", selection: Binding(
                        get: { Self.nearestOption(suppressMinuteOptions, to: Int((manager.suppressDuration / 60).rounded())) },
                        set: { manager.suppressDuration = TimeInterval($0 * 60) }
                    )) {
                        ForEach(suppressMinuteOptions, id: \.self) { minutes in
                            Text(suppressLabel(minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 190)
                }

                Divider()

                // Cover on Signal Lost (Gone)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cover When Signal Is Lost")
                            .font(.subheadline.bold())
                        Text("Also cover the screen when earbuds vanish (cased, dead, Bluetooth off). When off, the status still shows Gone but no new cover appears.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("Cover When Signal Is Lost", isOn: $manager.veilOnGoneEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Divider()

                // Fail-Secure Policy
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fail-Secure (Lock Mac on App Quit)")
                            .font(.subheadline.bold())
                        Text("Locks your Mac session if BRB is terminated gracefully, preventing bypass.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("Fail-Secure (Lock Mac on App Quit)", isOn: $manager.failSecureEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            .padding(14)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(10)

            Spacer(minLength: 0)

            Divider()

            HStack {
                Button("Re-run Onboarding Setup…") {
                    onResetOnboarding()
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Spacer()
            }
        }
        .padding(20)
    }

    private func graceLabel(_ seconds: Int) -> String {
        seconds <= 0 ? "Instant (no delay)" : "\(seconds)s"
    }

    private func suppressLabel(_ minutes: Int) -> String {
        minutes <= 0 ? "Instant (no suppression)" : "\(minutes)m"
    }

    /// Snaps a stored value to the nearest dropdown option (legacy values may
    /// predate the multiples-of-5 options). Exact 0 stays Instant.
    private static func nearestOption(_ options: [Int], to value: Int) -> Int {
        if value <= 0 { return 0 }
        return options.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
    }
}
