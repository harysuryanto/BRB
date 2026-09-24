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

    var body: some Scene {
        WindowGroup("BRB Control Center", id: "main") {
            ContentView(manager: manager)
        }
        .defaultSize(width: DS.windowWidth, height: DS.windowHeight)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarPopoverView(manager: manager)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        if manager.protectionPaused {
            return manager.protectionPauseUntil != nil ? "pause.circle.fill" : "pause.circle"
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
}
