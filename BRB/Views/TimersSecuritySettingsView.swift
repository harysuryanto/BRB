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
        VStack(alignment: .leading, spacing: DS.spacingXL) {
            Text("Timers & Security Policies")
                .font(.headline)

            VStack(spacing: DS.spacingLG) {
                // Grace Delay Dropdown
                HStack {
                    VStack(alignment: .leading, spacing: DS.spacingXS) {
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
                    VStack(alignment: .leading, spacing: DS.spacingXS) {
                        Text("Post-Unlock Suppression")
                            .font(.subheadline.bold())
                        Text("Keeps the cover down after authenticating at loginwindow without your device.")
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
                    VStack(alignment: .leading, spacing: DS.spacingXS) {
                        Text("Cover When Signal Is Lost")
                            .font(.subheadline.bold())
                        Text("Also cover the screen when device signal vanishes (cased, dead, Bluetooth off). When off, the status still shows Gone but no new cover appears.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("Cover When Signal Is Lost", isOn: $manager.veilOnGoneEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Divider()

                // Cover Lock Mode
                VStack(alignment: .leading, spacing: DS.spacingSM) {
                    HStack {
                        Text("Cover Lock")
                            .font(.subheadline.bold())
                        Spacer()
                        Picker("Cover Lock", selection: $manager.veilLockMode) {
                            Text("Secure").tag(VeilLockMode.secure)
                            Text("Casual").tag(VeilLockMode.casual)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    if manager.veilLockMode == .secure {
                        Text("Secure: the cover lifts only when your device returns or via Mac login. Real protection.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Casual: adds a Hide button that lifts the cover with no login — aesthetic only, anyone nearby can click it.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Divider()

                // Fail-Secure Policy
                HStack {
                    VStack(alignment: .leading, spacing: DS.spacingXS) {
                        Text("Fail-Secure (Lock Mac on App Quit)")
                            .font(.subheadline.bold())
                        Text("Quitting BRB while the cover is up takes you to your normal macOS login screen — not just hides it.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("Fail-Secure (Lock Mac on App Quit)", isOn: $manager.failSecureEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            .padding(DS.cardPad)
            .background(DS.cardBg)
            .cornerRadius(DS.radius)

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
        .padding(DS.outerPad)
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
