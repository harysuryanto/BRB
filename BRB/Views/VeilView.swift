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
    var onDeveloperPause: (() -> Void)? = nil
    var onCasualDismiss: (() -> Void)? = nil
    var lockMode: VeilLockMode = .secure

    @State private var imageManager = VeilImageManager.shared

    var body: some View {
        GeometryReader { proxy in
            let safeWidth = proxy.size.width > 0 ? proxy.size.width : (NSScreen.main?.frame.width ?? 1920)
            let safeHeight = proxy.size.height > 0 ? proxy.size.height : (NSScreen.main?.frame.height ?? 1080)
            let safeSize = CGSize(width: safeWidth, height: safeHeight)

            ZStack {
                Color.black.ignoresSafeArea()

                // Full-bleed cover image (Aspect-fill, animated when GIF)
                CoverImageView(
                    frames: imageManager.animatedFrames(),
                    staticImage: imageManager.effectiveImage(for: safeSize)
                )
                .frame(width: safeWidth, height: safeHeight)
                .clipped()

                // Bottom-anchored action button card
                VStack {
                    Spacer()

                    VStack(spacing: DS.spacingSM) {
                        if lockMode == .secure {
                            Button(action: onUnlock) {
                                HStack(spacing: DS.spacingSM) {
                                    Image(systemName: "lock.shield.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("Unlock with Mac Login")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .padding(.horizontal, DS.Veil.btnHPad)
                                .padding(.vertical, DS.Veil.btnVPad)
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
                                .font(.system(size: DS.Veil.helpSize))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        if lockMode == .casual, let onCasualDismiss {
                            Button(action: onCasualDismiss) {
                                HStack(spacing: DS.spacingSM) {
                                    Image(systemName: "eye.slash.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("Hide Cover")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .padding(.horizontal, DS.Veil.btnHPad)
                                .padding(.vertical, DS.Veil.btnVPad)
                                .background(Color.white.opacity(0.12))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)

                            Text("Lifts the cover without locking — it returns if you're still away.")
                                .font(.system(size: DS.Veil.helpSize))
                                .foregroundColor(.white.opacity(0.7))
                        }

#if DEBUG
                        if let onDeveloperPause {
                            Button(action: onDeveloperPause) {
                                HStack(spacing: DS.spacingSM) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("Close & Pause 15s (Debug)")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .padding(.horizontal, DS.Veil.btnHPad)
                                .padding(.vertical, DS.Veil.btnVPad)
                                .background(Color.orange.opacity(0.25))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
#endif
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial.opacity(0.85))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                    .padding(.bottom, 48)
                }
            }
        }
        .ignoresSafeArea()
    }
}
