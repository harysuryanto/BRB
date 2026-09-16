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

    var body: some View {
        VStack(alignment: .leading, spacing: DS.spacingXL) {
            Text("Screen Cover Image")
                .font(.headline)

            Text("This image is rendered full-bleed across all your displays when you step away.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Image Preview Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: DS.radius)
                    .fill(Color.black)

                Image(nsImage: imageManager.effectiveImage(for: CGSize(width: 480, height: 270)))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipped()
                    .cornerRadius(DS.radius)

                VStack {
                    Spacer()
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
            }
            .frame(height: 220)
            .overlay(
                RoundedRectangle(cornerRadius: DS.radius)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

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
