//
//  VeilView.swift
//  BRB
//
//  Fullscreen cover view displayed across all monitors when user steps away.
//  Contains full-bleed cover image and the single "Unlock with Mac Login" button.
//

import SwiftUI
import AppKit

struct VeilView: View {
    var reason: String?
    var onUnlock: () -> Void

    @State private var imageManager = VeilImageManager.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                // Full-bleed cover image (Aspect-fill)
                Image(nsImage: imageManager.effectiveImage(for: proxy.size))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                // Bottom-anchored action button card
                VStack {
                    Spacer()

                    VStack(spacing: 8) {
                        Button(action: onUnlock) {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("Unlock with Mac Login")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.18))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        Text("Locks this Mac — log back in to dismiss the cover for a while.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.65))

                        if let reason, !reason.isEmpty {
                            Text(reason)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.40))
                                .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                    .background(.ultraThinMaterial.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                    .padding(.bottom, max(36, proxy.safeAreaInsets.bottom + 20))
                }
            }
        }
        .ignoresSafeArea()
    }
}
