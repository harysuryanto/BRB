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
        .defaultSize(width: DS.windowWidth, height: DS.windowHeight)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            menuBarContent
        } label: {
            Image(systemName: menuBarIcon)
        }
    }

    @ViewBuilder
    private var menuBarContent: some View {
        // NOTE: menu Text becomes native menu items (layout modifiers like
        // .frame are ignored), so width stability comes from constant-width
        // strings + always-visible rows — never appear/disappear or padding.
        Text(menuBarStatusText)
            .font(.headline)

        // Pin-gated (not name-gated) so the row never vanishes mid-pin when
        // the cached advert name ages out — see pinnedDisplayName.
        if let pinned = manager.pinnedDisplayName {
            Text("Device: \(pinned)")
                .font(.headline)
        }

        Divider()

        Toggle("Pause Protection", isOn: $manager.protectionPaused)

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
        if manager.protectionPaused {
            return "pause.circle"
        }
        guard manager.bluetoothGranted else {
            return "exclamationmark.shield"
        }
        switch manager.presenceState {
        case .near:
            return "person.badge.shield.checkmark.fill"
        case .far:
            return "figure.walk"
        case .gone:
            return "exclamationmark.shield.fill"
        case .idle:
            return "shield.slash"
        }
    }

    private var menuBarStatusText: String {
        if manager.protectionPaused {
            return "BRB: Paused"
        }
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
