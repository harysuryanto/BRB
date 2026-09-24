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

    private func triggerUnlock() {
        if lockMode == .casual, let onCasualDismiss {
            onCasualDismiss()
        } else {
            onUnlock()
        }
    }

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
                                    HStack(spacing: 2) {
                                        Text("Space")
                                            .font(.system(size: 10, weight: .bold))
                                        Text("or")
                                            .font(.system(size: 9))
                                        Text("↵")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
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
                            .keyboardShortcut(.defaultAction)

                            Text("Locks this Mac — log back in to dismiss the cover. (Press Space, ↵, or Esc)")
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
                                    HStack(spacing: 2) {
                                        Text("Space")
                                            .font(.system(size: 10, weight: .bold))
                                        Text("or")
                                            .font(.system(size: 9))
                                        Text("↵")
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
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
                            .keyboardShortcut(.defaultAction)

                            Text("Lifts the cover without locking. (Press Space, ↵, or Esc)")
                                .font(.system(size: DS.Veil.helpSize))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        // Hidden keyboard shortcut receivers for Space and Escape
                        Button(action: triggerUnlock) {
                            EmptyView()
                        }
                        .keyboardShortcut(.space, modifiers: [])
                        .frame(width: 0, height: 0)
                        .opacity(0)
                        .accessibilityHidden(true)

                        Button(action: triggerUnlock) {
                            EmptyView()
                        }
                        .keyboardShortcut(.cancelAction)
                        .frame(width: 0, height: 0)
                        .opacity(0)
                        .accessibilityHidden(true)

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
