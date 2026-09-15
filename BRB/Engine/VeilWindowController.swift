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

    enum VeilMode: Equatable {
        case hidden
        case real
        case preview
    }

    private var veilWindows: [NSWindow] = []
    private var hostingControllers: [NSHostingController<VeilView>] = []
    private var mode: VeilMode = .hidden
    private var previewWorkItem: DispatchWorkItem?
    private var currentReason: String?

    /// Called on preview expiry to decide whether a real veil still needs
    /// to stay up (avoids a flicker gap). Set by ProximityManager to avoid
    /// a hard Veil -> Proximity dependency at import time (same module anyway).
    /// Returns (needsVeil, reason).
    var realVeilDemand: (() -> (needsVeil: Bool, reason: String?))?

    var isShowing: Bool { mode != .hidden }
    var isPreviewActive: Bool { mode == .preview }

    var onUnlockRequested: (() -> Void)?
    var onDeveloperPauseRequested: (() -> Void)?

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
        // Best-effort teardown; windows go away with the app anyway.
        for window in veilWindows {
            window.orderOut(nil)
        }
    }

    // MARK: - Logging

    private func vlog(_ message: String) {
        print("[BRB Veil] \(message)")
    }

    private func ensureMain(_ label: String) -> Bool {
        if Thread.isMainThread { return true }
        vlog("⚠️ \(label) called off-main (\(Thread.current)) — dispatching to main")
        return false
    }

    // MARK: - Public API

    /// Presents the veil across all connected displays with ~0.25s fade-in.
    func showVeil(reason: String?) {
        guard ensureMain("showVeil") else {
            DispatchQueue.main.async { [weak self] in self?.showVeil(reason: reason) }
            return
        }
        switch mode {
        case .real:
            // Already up — update stored reason (visible copy refreshes on rebuild).
            currentReason = reason
            vlog("showVeil: already real, updated reason=\(reason ?? "nil") windows=\(veilWindows.count)")
            return
        case .preview:
            // Real demand arrived mid-preview: don't hijack; engine re-asserts after preview.
            vlog("showVeil: preview active, deferring real reason=\(reason ?? "nil")")
            return
        case .hidden:
            break
        }

        mode = .real
        currentReason = reason
        vlog("showVeil: presenting real reason=\(reason ?? "nil") screens=\(NSScreen.screens.count)")
        let ok = rebuildWindows(animated: true)
        if !ok {
            vlog("❌ showVeil: rebuild produced 0 windows — resetting to hidden (screens=\(NSScreen.screens.count))")
            mode = .hidden
            currentReason = nil
        } else {
            vlog("showVeil: up with \(veilWindows.count) window(s)")
        }
    }

    /// Presents a temporary preview veil that auto-dismisses. Ignored if a real
    /// veil is already showing, so a test tap never kills (or hijacks) real state.
    func showPreview(reason: String = "Preview mode (auto-dismissing in 3s)", duration: TimeInterval = 3.0) {
        guard ensureMain("showPreview") else {
            DispatchQueue.main.async { [weak self] in self?.showPreview(reason: reason, duration: duration) }
            return
        }
        if mode == .real {
            vlog("showPreview: real veil already up — ignoring preview tap")
            return
        }

        previewWorkItem?.cancel()

        mode = .preview
        currentReason = reason
        vlog("showPreview: presenting preview duration=\(duration)s screens=\(NSScreen.screens.count)")
        let ok = rebuildWindows(animated: true)
        if !ok {
            vlog("❌ showPreview: rebuild produced 0 windows — resetting to hidden")
            mode = .hidden
            currentReason = nil
            previewWorkItem = nil
            return
        }
        vlog("showPreview: up with \(veilWindows.count) window(s)")

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.vlog("showPreview: timer fired, handing off")
            self.previewWorkItem = nil
            self.finishPreview()
        }
        previewWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func finishPreview() {
        guard ensureMain("finishPreview") else {
            DispatchQueue.main.async { [weak self] in self?.finishPreview() }
            return
        }
        // Preview over: hand off to real demand if the engine still needs cover.
        if let demand = realVeilDemand?(), demand.needsVeil {
            vlog("finishPreview: real demand still needs veil — converting to real")
            previewWorkItem?.cancel()
            previewWorkItem = nil
            mode = .real
            currentReason = demand.reason
            let ok = rebuildWindows(animated: false)
            if !ok {
                vlog("❌ finishPreview: handoff rebuild produced 0 windows — hiding")
                mode = .hidden
                currentReason = nil
            }
            return
        }
        vlog("finishPreview: no real demand — hiding")
        dismissVeilInstant()
    }

    /// Immediately lifts and closes the veil across all displays with 0 lag.
    func dismissVeilInstant() {
        guard ensureMain("dismissVeilInstant") else {
            DispatchQueue.main.async { [weak self] in self?.dismissVeilInstant() }
            return
        }
        guard mode != .hidden || !veilWindows.isEmpty else { return }
        vlog("dismissVeilInstant: hiding \(veilWindows.count) window(s) mode=\(mode)")
        previewWorkItem?.cancel()
        previewWorkItem = nil
        mode = .hidden
        currentReason = nil

        for window in veilWindows {
            window.orderOut(nil)
        }
        veilWindows.removeAll()
        hostingControllers.removeAll()
    }

    @objc private func screenParametersChanged() {
        guard mode != .hidden else { return }
        vlog("screenParametersChanged: rebuilding mode=\(mode)")
        // Re-align windows to match current screens, no animation to avoid flash.
        _ = rebuildWindows(animated: false)
    }

    // MARK: - Builders

    @discardableResult
    private func rebuildWindows(animated: Bool) -> Bool {
        for window in veilWindows {
            window.orderOut(nil)
        }
        veilWindows.removeAll()
        hostingControllers.removeAll()

        var screens = NSScreen.screens
        if screens.isEmpty, let main = NSScreen.main {
            vlog("rebuildWindows: NSScreen.screens empty — falling back to main")
            screens = [main]
        }
        guard !screens.isEmpty else {
            vlog("❌ rebuildWindows: no screens available")
            return false
        }

        for (index, screen) in screens.enumerated() {
            let (window, hosting) = makeVeilWindow(for: screen)
            veilWindows.append(window)
            hostingControllers.append(hosting)

            vlog("rebuildWindows: screen[\(index)] frame=\(screen.frame) level=\(window.level.rawValue)")

            if animated {
                window.alphaValue = 0.0
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    window.animator().alphaValue = 1.0
                } completionHandler: { [weak window] in
                    // Fallback: if the fade never committed, force visible.
                    if let w = window, w.alphaValue < 1.0 {
                        print("[BRB Veil] ⚠️ fade did not commit (alpha=\(w.alphaValue)) — forcing alpha=1.0")
                        w.alphaValue = 1.0
                    }
                }
                // Belt-and-suspenders: re-assert visibility shortly after.
                let captured = window
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak captured] in
                    guard let self, let w = captured else { return }
                    guard self.veilWindows.contains(where: { $0 === w }) else { return }
                    if !w.isVisible || w.alphaValue < 1.0 {
                        self.vlog("⚠️ window not visible after fade (visible=\(w.isVisible) alpha=\(w.alphaValue)) — forcing front + alpha=1")
                        w.alphaValue = 1.0
                        w.orderFrontRegardless()
                        w.makeKeyAndOrderFront(nil)
                    }
                    self.vlog("post-present check: visible=\(w.isVisible) alpha=\(w.alphaValue) frame=\(w.frame)")
                }
            } else {
                window.alphaValue = 1.0
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
                vlog("post-present (no anim): visible=\(window.isVisible) alpha=\(window.alphaValue) frame=\(window.frame)")
            }
        }
        return !veilWindows.isEmpty
    }

    private func makeVeilWindow(for screen: NSScreen) -> (NSWindow, NSHostingController<VeilView>) {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false

        let rootView = VeilView(reason: currentReason) { [weak self] in
            self?.onUnlockRequested?()
        } onDeveloperPause: { [weak self] in
            self?.onDeveloperPauseRequested?()
        }

        let hostingController = NSHostingController(rootView: rootView)
        window.contentViewController = hostingController
        // Assigning contentViewController can reset the window to the hosting
        // view's fitting size (0x0). Re-assert fullscreen AFTER assignment and
        // pin the hosting view to the window bounds.
        window.setFrame(screen.frame, display: true)
        if let contentView = window.contentView {
            contentView.setFrameSize(screen.frame.size)
            hostingController.view.frame = contentView.bounds
            hostingController.view.autoresizingMask = [.width, .height]
        }

        return (window, hostingController)
    }
}
