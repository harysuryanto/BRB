//
//  VeilWindowController.swift
//  BRB
//
//  Manages borderless fullscreen veil windows across all active displays.
//

import AppKit
import SwiftUI

final class VeilWindowController: NSObject {
    static let shared = VeilWindowController()

    private var veilWindows: [NSWindow] = []
    private(set) var isShowing: Bool = false
    private var currentReason: String?

    var onUnlockRequested: (() -> Void)?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        dismissVeilInstant()
    }

    /// Presents the veil across all connected displays with ~0.25s fade-in.
    func showVeil(reason: String?) {
        guard !isShowing else {
            // Update reason if already visible
            self.currentReason = reason
            return
        }

        self.isShowing = true
        self.currentReason = reason

        rebuildWindows(animated: true)
    }

    /// Immediately lifts and closes the veil across all displays with 0 lag.
    func dismissVeilInstant() {
        guard isShowing || !veilWindows.isEmpty else { return }
        isShowing = false
        currentReason = nil

        for window in veilWindows {
            window.orderOut(nil)
        }
        veilWindows.removeAll()
    }

    @objc private func screenParametersChanged() {
        guard isShowing else { return }
        // Re-align windows to match current screens
        rebuildWindows(animated: false)
    }

    private func rebuildWindows(animated: Bool) {
        // Clean up previous windows without animation
        for window in veilWindows {
            window.orderOut(nil)
        }
        veilWindows.removeAll()

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        for screen in screens {
            let window = makeVeilWindow(for: screen)
            veilWindows.append(window)

            if animated {
                window.alphaValue = 0.0
                window.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    window.animator().alphaValue = 1.0
                }
            } else {
                window.alphaValue = 1.0
                window.orderFrontRegardless()
            }
        }
    }

    private func makeVeilWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.setFrame(screen.frame, display: true)

        let rootView = VeilView(reason: currentReason) { [weak self] in
            self?.onUnlockRequested?()
        }

        let hostingController = NSHostingController(rootView: rootView)
        window.contentViewController = hostingController

        return window
    }
}
