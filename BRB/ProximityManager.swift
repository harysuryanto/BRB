//
//  ProximityManager.swift
//  BRB
//
//  Coordinates Bluetooth LE scanning, signal filtering (EMA), presence state
//  transitions (Near / Far / Gone), grace delay timers, threshold calibration,
//  multi-display veil windows, and session lock escalation.
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
    // MARK: - Permissions & Engine Status
    var bluetoothPermission: String = "Checking…"
    var bluetoothGranted: Bool = false
    var leStatus: String = "LE idle"

    // MARK: - Adverts & Live Samples
    var leAdverts: [String: AdvertSample] = [:]
    var liveRSSI: Int? = nil
    var liveRSSIAt: Date? = nil
    var liveKind: String = "—"

    // MARK: - Pinned Device
    var pinnedLEID: String? {
        didSet {
            if let id = pinnedLEID {
                UserDefaults.standard.set(id, forKey: "BRB.pinnedLEID")
            } else {
                UserDefaults.standard.removeObject(forKey: "BRB.pinnedLEID")
            }
        }
    }

    var pinnedName: String? {
        guard let pinnedLEID else { return nil }
        return leAdverts[pinnedLEID]?.name
    }

    // MARK: - Configurable Thresholds & Settings (Persisted)
    var veilOnThreshold: Double {
        didSet { UserDefaults.standard.set(veilOnThreshold, forKey: "BRB.veilOnThreshold") }
    }
    var veilOffThreshold: Double {
        didSet { UserDefaults.standard.set(veilOffThreshold, forKey: "BRB.veilOffThreshold") }
    }
    var graceDelay: TimeInterval {
        didSet { UserDefaults.standard.set(graceDelay, forKey: "BRB.graceDelay") }
    }
    var suppressDuration: TimeInterval {
        didSet { UserDefaults.standard.set(suppressDuration, forKey: "BRB.suppressDuration") }
    }
    var failSecureEnabled: Bool {
        didSet { UserDefaults.standard.set(failSecureEnabled, forKey: "BRB.failSecureEnabled") }
    }

    // MARK: - Presence State Machine
    var presenceState: PresenceState = .idle
    var smoothedRSSI: Double? = nil
    var awayDuration: TimeInterval = 0
    var isVeilActive: Bool = false {
        didSet {
            guard !Self.isPreview else { return }
            if isVeilActive {
                VeilWindowController.shared.showVeil(reason: veilReason)
            } else {
                VeilWindowController.shared.dismissVeilInstant()
            }
        }
    }
    var veilReason: String? = nil
    var isStale: Bool = false
    var sampleAge: TimeInterval? = nil

    // MARK: - Unlock & Suppression State
    var pendingManualUnlock: Bool = false
    var suppressionRemaining: TimeInterval? = nil

    // MARK: - Internal Components
    private var leReader: LERSSIReader?
    private var timer: Timer?
    private var ticks: Int = 0
    private var monitoringStartedAt: Date = Date()
    private let signalProcessor = SignalProcessor(alpha: 0.2)

    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var pinnedUUID: UUID? {
        guard let pinnedLEID else { return nil }
        return UUID(uuidString: pinnedLEID)
    }

    init() {
        let defaults = UserDefaults.standard
        self.veilOnThreshold = defaults.object(forKey: "BRB.veilOnThreshold") as? Double ?? -80.0
        self.veilOffThreshold = defaults.object(forKey: "BRB.veilOffThreshold") as? Double ?? -70.0
        self.graceDelay = defaults.object(forKey: "BRB.graceDelay") as? TimeInterval ?? 10.0
        self.suppressDuration = defaults.object(forKey: "BRB.suppressDuration") as? TimeInterval ?? 900.0 // 15 mins
        self.failSecureEnabled = defaults.object(forKey: "BRB.failSecureEnabled") as? Bool ?? true
        self.pinnedLEID = defaults.string(forKey: "BRB.pinnedLEID")

        setupLockAndVeilCallbacks()
    }

    private func setupLockAndVeilCallbacks() {
        guard !Self.isPreview else { return }

        // Wire veil unlock action -> escalate to macOS session lock
        VeilWindowController.shared.onUnlockRequested = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingManualUnlock = true
                SessionLockManager.shared.lockScreen()
            }
        }

        // Wire screen unlock listener
        SessionLockManager.shared.onSessionUnlocked = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.pendingManualUnlock {
                    self.pendingManualUnlock = false
                    self.startSuppression()
                } else {
                    // Normal evaluation with fresh grace delay
                    self.awayDuration = 0
                    self.isVeilActive = false
                }
            }
        }
    }

    // MARK: - Lifecycle
    func startMonitoring() {
        guard !Self.isPreview else { return }
        monitoringStartedAt = Date()

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
                guard let self else { return }
                self.recordSample(rssi: value, kind: "GATT")
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

                // A pinned advertisement feeds the live sample stream even without a held GATT link.
                if key == self.pinnedLEID {
                    self.recordSample(rssi: rssi, kind: "LE-adv")
                }
            }
        }

        reader.onNameResolved = { [weak self] id, name in
            DispatchQueue.main.async {
                guard let self else { return }
                let key = id.uuidString
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

        // 0.5s engine tick: poll readRSSI, check sample freshness, evaluate state machine
        ticks = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.engineTick()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        leReader?.stop()
        leReader = nil
        isVeilActive = false
    }

    func handleAppTermination() {
        if failSecureEnabled {
            SessionLockManager.shared.lockScreen()
        }
    }

    // MARK: - Engine Tick (0.5s interval)
    private func engineTick() {
        ticks += 1

        // 1. Request GATT read if link is connected
        leReader?.requestRead()

        // 2. Scan hygiene restart every ~60s (120 ticks * 0.5s)
        if ticks % 120 == 0 {
            leReader?.restartScan()
        }

        // 3. Update sample age & staleness
        let now = Date()
        if let last = liveRSSIAt {
            let age = now.timeIntervalSince(last)
            sampleAge = age
            isStale = (age > 12.0)
        } else {
            sampleAge = now.timeIntervalSince(monitoringStartedAt)
            isStale = true
        }

        // 4. Check suppression window countdown
        if let remaining = suppressionRemaining, remaining > 0 {
            let nextRemaining = max(0, remaining - 0.5)
            // If the bud returns mid-suppression, cancel suppression immediately and resume normal evaluation
            if isSampleFresh, let smoothed = smoothedRSSI, smoothed >= veilOffThreshold {
                suppressionRemaining = nil
                presenceState = .near
                awayDuration = 0
                isVeilActive = false
                veilReason = nil
            } else if nextRemaining == 0 {
                suppressionRemaining = nil
            } else {
                suppressionRemaining = nextRemaining
                // While suppression is active, keep veil down
                isVeilActive = false
                return
            }
        }

        // 5. Presence state evaluation
        evaluatePresenceState()
    }

    private var isSampleFresh: Bool {
        guard let age = sampleAge else { return false }
        if liveKind == "GATT" {
            return age < 3.0
        } else {
            return age < 12.0
        }
    }

    private func recordSample(rssi: Int, kind: String) {
        liveRSSI = rssi
        liveRSSIAt = Date()
        liveKind = kind
        let smoothed = signalProcessor.process(rawRSSI: rssi)
        smoothedRSSI = smoothed
    }

    private func evaluatePresenceState() {
        guard pinnedLEID != nil else {
            presenceState = .idle
            awayDuration = 0
            isVeilActive = false
            veilReason = nil
            return
        }

        let effectiveAge = sampleAge ?? Date().timeIntervalSince(monitoringStartedAt)

        // Gone condition: No sightings for >= 2 * graceDelay
        if effectiveAge >= (2.0 * graceDelay) {
            presenceState = .gone
            isVeilActive = true
            veilReason = "Device gone (no signal detected for \(Int(effectiveAge))s)"
            return
        }

        guard isSampleFresh, let smoothed = smoothedRSSI else {
            // Signal temporarily unavailable or stale, but within 2x grace
            return
        }

        if smoothed <= veilOnThreshold {
            presenceState = .far
            awayDuration += 0.5
            if awayDuration >= graceDelay {
                isVeilActive = true
                veilReason = "Away from Mac for \(Int(awayDuration))s"
            }
        } else if smoothed >= veilOffThreshold {
            presenceState = .near
            awayDuration = 0
            isVeilActive = false
            veilReason = nil
        } else {
            // Hysteresis gap (between veilOn and veilOff)
            if presenceState == .far {
                awayDuration += 0.5
                if awayDuration >= graceDelay {
                    isVeilActive = true
                    veilReason = "Away from Mac for \(Int(awayDuration))s"
                }
            } else {
                presenceState = .near
                awayDuration = 0
                isVeilActive = false
                veilReason = nil
            }
        }
    }

    // MARK: - Device Management
    func pinLEDevice(id: String) {
        guard !Self.isPreview else { return }
        pinnedLEID = id
        resetStateAndFilter()
        leReader?.stop()
        leReader?.start(targetName: "", pinnedID: pinnedUUID)
    }

    func unpinLEDevice() {
        pinnedLEID = nil
        resetStateAndFilter()
        leReader?.stop()
        leReader?.start(targetName: "", pinnedID: nil)
    }

    private func resetStateAndFilter() {
        liveRSSI = nil
        liveRSSIAt = nil
        liveKind = "—"
        signalProcessor.reset()
        smoothedRSSI = nil
        presenceState = .idle
        awayDuration = 0
        isVeilActive = false
        veilReason = nil
        isStale = false
        sampleAge = nil
        suppressionRemaining = nil
    }

    // MARK: - Calibration Actions
    func calibrateAwayBoundary(currentRSSI: Double? = nil) {
        let reference = currentRSSI ?? smoothedRSSI ?? (liveRSSI != nil ? Double(liveRSSI!) : -80.0)
        veilOnThreshold = reference
        veilOffThreshold = reference + 10.0
    }

    func resetThresholdsToDefault() {
        veilOnThreshold = -80.0
        veilOffThreshold = -70.0
    }

    // MARK: - Suppression Trigger (Used by Veil Unlock Flow)
    func startSuppression() {
        suppressionRemaining = suppressDuration
        isVeilActive = false
        veilReason = nil
        awayDuration = 0
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
        mock.smoothedRSSI = -58.2
        mock.presenceState = .near
        mock.leAdverts = [
            "AAAAAAAA-0000-0000-0000-000000000001": AdvertSample(name: "AirPods Pro", rssi: -55, at: Date()),
            "AAAAAAAA-0000-0000-0000-000000000002": AdvertSample(name: "(unnamed)", rssi: -72, at: Date())
        ]
        mock.pinnedLEID = "AAAAAAAA-0000-0000-0000-000000000001"
        return mock
    }
}
