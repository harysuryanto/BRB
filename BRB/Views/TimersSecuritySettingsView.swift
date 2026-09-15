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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Timers & Security Policies")
                .font(.headline)

            VStack(spacing: 16) {
                // Grace Delay Stepper
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Grace Delay")
                            .font(.subheadline.bold())
                        Text("Wait time before covering screen once signal drops below threshold.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Stepper("\(Int(manager.graceDelay)) sec", value: $manager.graceDelay, in: 5...60, step: 1)
                        .labelsHidden()
                    Text("\(Int(manager.graceDelay))s")
                        .font(.system(.subheadline, design: .monospaced).bold())
                        .frame(width: 44, alignment: .trailing)
                }

                Divider()

                // Suppression Window Stepper
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Post-Unlock Suppression")
                            .font(.subheadline.bold())
                        Text("Keeps the cover down after authenticating at loginwindow without your earbuds.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    let minutes = Int(manager.suppressDuration / 60)
                    Stepper("\(minutes) min", value: Binding(
                        get: { Int(manager.suppressDuration / 60) },
                        set: { manager.suppressDuration = TimeInterval($0 * 60) }
                    ), in: 5...60, step: 5)
                        .labelsHidden()
                    Text("\(minutes)m")
                        .font(.system(.subheadline, design: .monospaced).bold())
                        .frame(width: 44, alignment: .trailing)
                }

                Divider()

                // Fail-Secure Policy
                Toggle(isOn: $manager.failSecureEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fail-Secure (Lock Mac on App Quit)")
                            .font(.subheadline.bold())
                        Text("Locks your Mac session if BRB is terminated gracefully, preventing bypass.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
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
}
