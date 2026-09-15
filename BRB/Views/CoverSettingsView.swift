//
//  CoverSettingsView.swift
//  BRB
//
//  Settings tab for choosing, previewing, and resetting the veil cover image.
//

import SwiftUI
import AppKit

struct CoverSettingsView: View {
    @State private var imageManager = VeilImageManager.shared
    @State private var isTestPreviewActive: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Screen Cover Image")
                .font(.headline)

            Text("This image is rendered full-bleed across all your displays when you step away.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Image Preview Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)

                Image(nsImage: imageManager.effectiveImage(for: CGSize(width: 480, height: 270)))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipped()
                    .cornerRadius(12)

                VStack {
                    Spacer()
                    HStack {
                        if imageManager.isCustomImage {
                            Label("Custom Image", systemImage: "photo")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                        } else {
                            Label("Default Wordmark", systemImage: "sparkles")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .cornerRadius(6)
                        }
                        Spacer()
                    }
                    .padding(10)
                }
            }
            .frame(height: 220)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            if let error = imageManager.bookmarkError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Action Buttons
            HStack(spacing: 12) {
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
            }
        }
        .padding(20)
    }

    private func triggerTestPreview() {
        VeilWindowController.shared.showVeil(reason: "Preview mode (auto-dismissing in 3s)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            VeilWindowController.shared.dismissVeilInstant()
        }
    }
}
