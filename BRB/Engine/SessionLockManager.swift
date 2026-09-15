//
//  SessionLockManager.swift
//  BRB
//
//  Handles locking the macOS session cleanly and observing unlock events.
//

import AppKit
import Foundation

final class SessionLockManager: NSObject {
    static let shared = SessionLockManager()

    var onSessionUnlocked: (() -> Void)?

    private typealias SACLockScreenImmediateFunc = @convention(c) () -> Int32
    private var lockFunc: SACLockScreenImmediateFunc?

    override init() {
        super.init()

        // Load SACLockScreenImmediate from login framework
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY) {
            if let sym = dlsym(handle, "SACLockScreenImmediate") {
                self.lockFunc = unsafeBitCast(sym, to: SACLockScreenImmediateFunc.self)
            }
        }

        // 1. Observe workspace session active
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSessionUnlock),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        // 2. Observe distributed notification for screen unlock
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSessionUnlock),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    /// Triggers macOS session lock screen immediately.
    func lockScreen() {
        if let lock = lockFunc {
            _ = lock()
            return
        }

        // Fallback: spawn CGSession -suspend
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession")
        task.arguments = ["-suspend"]
        try? task.run()
    }

    @objc private func handleSessionUnlock() {
        DispatchQueue.main.async { [weak self] in
            self?.onSessionUnlocked?()
        }
    }
}
