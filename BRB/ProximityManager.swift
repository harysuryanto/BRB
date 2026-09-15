//
//  ProximityManager.swift
//  BRB
//
//  Owns the LE engine and publishes scan/selection state.
//  Task 1 scope: permission, nearby list, pin-by-identifier, live samples.
//  Thresholds / hysteresis / grace state machine arrive in a later task.
//

import CoreBluetooth
import Foundation

/// One LE advertisement sighting, keyed by peripheral identifier.
struct AdvertSample: Codable {
    var name: String
    var rssi: Int
    var at: Date
}

@Observable
class ProximityManager {
    /// Bluetooth permission state (creating CBCentralManager IS the prompt).
    var bluetoothPermission: String = "Checking…"
    var bluetoothGranted: Bool = false
    /// Engine status line ("Scanning LE…", "LE connected: …", …).
    var leStatus: String = "LE idle"
    /// Last advertisement seen per peripheral identifier (UUID string).
    /// Pruned to <60s old (pinned: <300s), capped at 30 entries.
    var leAdverts: [String: AdvertSample] = [:]
    /// Latest GATT readRSSI sample, if a link is held.
    var liveRSSI: Int? = nil
    var liveRSSIAt: Date? = nil
    /// "GATT" (held-link read) or "advertisement".
    var liveKind: String = "—"
    /// User-pinned LE peripheral identifier (UUID string), persisted.
    /// Pinning beats name matching: identifiers survive renames.
    var pinnedLEID: String? {
        didSet {
            if let id = pinnedLEID { UserDefaults.standard.set(id, forKey: "BRB.pinnedLEID") }
            else { UserDefaults.standard.removeObject(forKey: "BRB.pinnedLEID") }
        }
    }

    /// Display name of the pinned entry, if currently visible.
    var pinnedName: String? {
        guard let pinnedLEID else { return nil }
        return leAdverts[pinnedLEID]?.name
    }

    private var leReader: LERSSIReader?
    private var timer: Timer?

    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var pinnedUUID: UUID? {
        guard let pinnedLEID else { return nil }
        return UUID(uuidString: pinnedLEID)
    }

    func startMonitoring() {
        // Never touch Bluetooth hardware in SwiftUI previews: IOBluetooth
        // deadlocks the preview host and CoreBluetooth prompts make no
        // sense on canvas.
        guard !Self.isPreview else { return }
        if pinnedLEID == nil {
            pinnedLEID = UserDefaults.standard.string(forKey: "BRB.pinnedLEID")
        }
        guard leReader == nil else { return }
        let reader = LERSSIReader()
        self.leReader = reader
        reader.onState = { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                switch state {
                case .poweredOn:
                    self.bluetoothPermission = "Granted"
                    self.bluetoothGranted = true
                case .unauthorized:
                    self.bluetoothPermission = "Denied — enable in System Settings → Privacy & Security → Bluetooth"
                    self.bluetoothGranted = false
                case .poweredOff:
                    self.bluetoothPermission = "Bluetooth is off"
                    self.bluetoothGranted = false
                case .unsupported:
                    self.bluetoothPermission = "Bluetooth unsupported"
                    self.bluetoothGranted = false
                case .resetting, .unknown:
                    self.bluetoothPermission = "Checking…"
                    self.bluetoothGranted = false
                @unknown default:
                    self.bluetoothPermission = "Unknown"
                    self.bluetoothGranted = false
                }
            }
        }
        reader.onRSSI = { [weak self] value in
            DispatchQueue.main.async {
                self?.liveRSSI = value
                self?.liveRSSIAt = Date()
                self?.liveKind = "GATT"
            }
        }
        reader.onAdvertisement = { [weak self] id, name, rssi in
            DispatchQueue.main.async {
                guard let self else { return }
                let key = id.uuidString
                let label = name.isEmpty ? "(unnamed)" : name
                self.leAdverts[key] = AdvertSample(name: label, rssi: rssi, at: Date())
                let now = Date()
                self.leAdverts = Dictionary(uniqueKeysWithValues:
                    self.leAdverts.filter { pair in
                        let limit = (pair.key == self.pinnedLEID) ? 300.0 : 60.0
                        return now.timeIntervalSince(pair.value.at) < limit
                    }.prefix(30).map { ($0.key, $0.value) })
                // A pinned advertisement is a live sample even with no GATT link.
                if key == self.pinnedLEID {
                    self.liveRSSI = rssi
                    self.liveRSSIAt = Date()
                    self.liveKind = "advertisement"
                }
            }
        }
        reader.onNameResolved = { [weak self] id, name in
            DispatchQueue.main.async {
                guard let self else { return }
                let key = id.uuidString
                // Fill blanks only: never clobber a real advertised name.
                if var s = self.leAdverts[key], s.name == "(unnamed)" || s.name.isEmpty {
                    s.name = name
                    self.leAdverts[key] = s
                }
            }
        }
        reader.onStatus = { [weak self] status in
            DispatchQueue.main.async { self?.leStatus = status }
        }
        reader.start(targetName: "", pinnedID: pinnedUUID)
        // 1s engine tick: GATT reads + hourly hygiene scan restarts.
        var ticks = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.leReader?.requestRead()
            ticks += 1
            if ticks % 60 == 0 { self.leReader?.restartScan() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        leReader?.stop()
    }

    /// Pin a Nearby entry: its samples become the monitored signal.
    func pinLEDevice(id: String) {
        guard !Self.isPreview else { return }
        pinnedLEID = id
        liveRSSI = nil
        liveRSSIAt = nil
        liveKind = "—"
        leReader?.stop()
        leReader?.start(targetName: "", pinnedID: pinnedUUID)
    }

    func unpinLEDevice() {
        pinnedLEID = nil
        liveRSSI = nil
        liveRSSIAt = nil
        liveKind = "—"
        leReader?.stop()
        leReader?.start(targetName: "", pinnedID: nil)
    }
}

// MARK: - Mock for SwiftUI Canvas Preview

extension ProximityManager {
    static var previewMock: ProximityManager {
        let mock = ProximityManager()
        mock.bluetoothPermission = "Granted"
        mock.bluetoothGranted = true
        mock.leStatus = "LE connected: AirPods Pro"
        mock.liveRSSI = -57
        mock.liveRSSIAt = Date()
        mock.liveKind = "GATT"
        mock.leAdverts = [
            "AAAAAAAA-0000-0000-0000-000000000001": AdvertSample(name: "AirPods Pro", rssi: -55, at: Date()),
            "AAAAAAAA-0000-0000-0000-000000000002": AdvertSample(name: "(unnamed)", rssi: -72, at: Date())
        ]
        mock.pinnedLEID = "AAAAAAAA-0000-0000-0000-000000000001"
        return mock
    }
}
