//
//  AboutSettingsView.swift
//  BRB
//
//  Minimal native macOS About tab displaying essential application identity,
//  version, copyright, and repository link.
//

import SwiftUI
import AppKit

struct AboutSettingsView: View {
    var manager: ProximityManager = .shared

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "BRB"
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private var copyrightNotice: String {
        let plistCopyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
        if let plistCopyright, !plistCopyright.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plistCopyright
        }
        return "© 2026 Hary Suryanto. All rights reserved."
    }

    private var appIconImage: NSImage {
        if let icon = NSImage(named: "AppIcon") {
            return icon
        }
        return NSApplication.shared.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }

    private let githubURL = URL(string: "https://github.com/harysuryanto/BRB")!

    var body: some View {
        VStack(spacing: DS.spacingXL) {
            Spacer(minLength: DS.spacingXL)

            VStack(spacing: DS.spacingMD) {
                // App Icon
                Image(nsImage: appIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                    )

                // App Title & Tagline
                VStack(spacing: DS.spacingXS) {
                    Text(appName)
                        .font(.title2.bold())

                    Text("Step away. Your screen covers itself.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Version & Build
                Text(versionString)
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(.secondary)

                // GitHub Link Button
                Link(destination: githubURL) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.caption)
                        Text("GitHub Repository")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding(.top, DS.spacingSM)

                // Copyright
                Text(copyrightNotice)
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(.top, DS.spacingXS)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.wizardSpacing)
            .padding(.horizontal, DS.wizardOuterPad)
            .background(DS.cardBg)
            .cornerRadius(DS.radius)

            Spacer(minLength: DS.spacingXL)
        }
        .padding(DS.outerPad)
    }
}

#Preview {
    AboutSettingsView(manager: .previewMock)
        .frame(width: DS.windowWidth, height: DS.windowHeight)
}
