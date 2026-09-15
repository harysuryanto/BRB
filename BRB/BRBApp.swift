//
//  BRBApp.swift
//  BRB — Step away. Your screen covers itself.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        ProximityManager.shared.handleAppTermination()
    }
}

@main
struct BRBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var manager = ProximityManager.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("BRB Control Center", id: "main") {
            ContentView(manager: manager)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            menuBarContent
        } label: {
            Image(systemName: menuBarIcon)
        }
    }

    @ViewBuilder
    private var menuBarContent: some View {
        // Status row
        Text(menuBarStatusText)
            .font(.headline)

        if let pinned = manager.pinnedName {
            Text("Device: \(pinned)")
                .font(.caption)
        }

        if let rssi = manager.liveRSSI {
            Text("Live RSSI: \(rssi) dBm (\(manager.liveKind))")
                .font(.caption)
        }

        Divider()

        Button("Lock Mac Now") {
            SessionLockManager.shared.lockScreen()
        }

        Button("Open BRB Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }

        Divider()

        Button("Quit BRB") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var menuBarIcon: String {
        guard manager.bluetoothGranted else {
            return "exclamationmark.shield"
        }
        switch manager.presenceState {
        case .near:
            return "lock.shield.fill"
        case .far:
            return "figure.walk"
        case .gone:
            return "shield.slash"
        case .idle:
            return "lock.shield"
        }
    }

    private var menuBarStatusText: String {
        switch manager.presenceState {
        case .near:
            return "BRB: Near (Active)"
        case .far:
            return "BRB: Away (Veil Active)"
        case .gone:
            return "BRB: Device Gone"
        case .idle:
            return "BRB: Idle"
        }
    }
}
