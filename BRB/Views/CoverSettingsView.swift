//
//  CoverSettingsView.swift
//  BRB
//
//  Settings tab for choosing, previewing, and resetting the veil cover image.
//

import SwiftUI
import AppKit

struct CoverSettingsView: View {
    @Bindable var manager: ProximityManager
    @State private var imageManager = VeilImageManager.shared
    @State private var isTestPreviewActive: Bool = false
    @State private var coverActiveHint: Bool = false

    /// Main-display aspect so the Settings thumbnail crops exactly like the
    /// real veil. Falls back to 16:9 with no display (e.g. canvas previews).
    private var displayAspect: CGFloat {
        guard let screen = NSScreen.main, screen.frame.height > 0 else { return 16.0 / 9.0 }
        return screen.frame.width / screen.frame.height
    }

    private var previewRenderSize: CGSize {
        CGSize(width: 640, height: 640 / displayAspect)
    }

    private var displayPixelSize: CGSize {
        guard let screen = NSScreen.main else { return .zero }
        let s = screen.backingScaleFactor > 0 ? screen.backingScaleFactor : 1
        return CGSize(width: (screen.frame.width * s).rounded(),
                      height: (screen.frame.height * s).rounded())
    }

    private var displayName: String {
        NSScreen.main?.localizedName ?? "main display"
    }

    /// Human aspect like "21:9": nearest common ratio within 2.5%,
    /// else reduced W:H from pixel dims.
    private var displayAspectLabel: String {
        let a = displayAspect
        let common: [(String, CGFloat)] = [
            ("16:9", 16.0 / 9.0), ("16:10", 16.0 / 10.0), ("21:9", 21.0 / 9.0),
            ("32:9", 32.0 / 9.0), ("4:3", 4.0 / 3.0), ("3:2", 3.0 / 2.0), ("1:1", 1.0)
        ]
        if let hit = common.first(where: { abs($0.1 - a) / $0.1 < 0.025 }) { return hit.0 }
        let px = displayPixelSize
        guard px.width > 0, px.height > 0 else { return String(format: "%.2f:1", a) }
        func gcd(_ x: Int, _ y: Int) -> Int { y == 0 ? x : gcd(y, x % y) }
        let d = gcd(Int(px.width), Int(px.height))
        guard d > 0 else { return String(format: "%.2f:1", a) }
        return "\(Int(px.width) / d):\(Int(px.height) / d)"
    }

    private var displayCaption: String {
        let px = displayPixelSize
        if px.width > 0 {
            return "Preview cropped like your \(displayName) · \(Int(px.width))×\(Int(px.height)) · \(displayAspectLabel)"
        }
        return "Preview cropped like your display · \(displayAspectLabel)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.spacingXL) {
            Text("Screen Cover Image")
                .font(.headline)

            Text("This image is rendered full-bleed across all your displays when you step away.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Image Preview Thumbnail — boxed to the MAIN display's aspect so
            // the crop is WYSIWYG with the real veil (a fixed 16:9 box lies
            // on ultrawide/portrait displays).
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: DS.radius)
                    .fill(Color.black)

                Image(nsImage: imageManager.effectiveImage(for: previewRenderSize))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
                    .cornerRadius(DS.radius)

                HStack {
                    if imageManager.isCustomImage {
                        Label("Custom Image", systemImage: "photo")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(DS.radius)
                    } else {
                        Label("Default Wordmark", systemImage: "sparkles")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(DS.radius)
                    }
                    Spacer()
                }
                .padding(DS.compactPad)
            }
            .aspectRatio(displayAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radius)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            Text(displayCaption)
                .font(.caption2)
                .foregroundColor(.secondary)

            if let error = imageManager.bookmarkError {
                DSBanner(icon: "exclamationmark.triangle.fill", text: error, tint: .orange)
            }

            // Action Buttons
            HStack(spacing: DS.spacingMD) {
                Button("Choose Image…") {
                    imageManager.pickImage()
                }
                .buttonStyle(.borderedProminent)

                if imageManager.isCustomImage {
                    Button("Reset to Default") {
                        imageManager.resetToDefault()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("Test Cover Preview (3s)") {
                    triggerTestPreview()
                }
                .buttonStyle(.bordered)
                .disabled(isTestPreviewActive)
            }

            if coverActiveHint {
                DSBanner(
                    icon: "info.circle.fill",
                    text: "Cover is already active — preview skipped to avoid tearing it down.",
                    tint: .blue
                )
            }

            Divider()

            // Cover Lock Mode
            VStack(alignment: .leading, spacing: DS.spacingSM) {
                Text("Cover Lock")
                    .font(.subheadline.bold())
                Picker("Cover Lock", selection: $manager.veilLockMode) {
                    Text("Secure").tag(VeilLockMode.secure)
                    Text("Casual").tag(VeilLockMode.casual)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if manager.veilLockMode == .secure {
                    Text("Secure: the cover lifts only when your earbuds return or via Mac login. Real protection.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Casual: adds a Hide button that lifts the cover with no login — aesthetic only, anyone nearby can click it.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(DS.cardPad)
            .background(DS.cardBg)
            .cornerRadius(DS.radius)
        }
        .padding(DS.outerPad)
    }

    private func triggerTestPreview() {
        // Don't stack previews, and don't hijack a real Away/Gone veil.
        guard !isTestPreviewActive else { return }
        guard !VeilWindowController.shared.isShowing else {
            coverActiveHint = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                coverActiveHint = false
            }
            return
        }
        coverActiveHint = false
        isTestPreviewActive = true
        print("[BRB Veil] Test button tapped — calling showPreview")
        VeilWindowController.shared.showPreview(duration: 3.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) {
            isTestPreviewActive = false
        }
    }
}
