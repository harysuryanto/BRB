//
//  LERSSIReader.swift
//  BRB
//
//  CoreBluetooth LE proximity engine, ported from the BudSense research app
//  where every behavior below was verified live against real hardware
//  (soundcore R60i NC, BLE mouse).
//
//  Design notes (do not regress):
//  - LE-first: Classic HCI RSSI is unreliable on Apple Silicon for many buds
//    (connected yet handle 0x0000, eternal zero reads). GATT readRSSI +
//    advertisement RSSI are the primary sources.
//  - Connected buds stop advertising (power saving), so discovery alone
//    never sees them: tryAttached() asks the system for held LE links first.
//  - Advertisement packets (31 bytes) often carry NO name: display
//    "(unnamed)" honestly, resolve via GATT 0x1800/0x2A00 + 0x180A/0x2A24,0x2A29.
//  - Pin by peripheral IDENTIFIER, never by name (names absent, IDs stable).
//  - Never invent data: freshness gates at the call site; reconnect budget
//    capped so a gone bud falls back to scanning, never hot-loops.
//

import CoreBluetooth
import Foundation
import os

final class LERSSIReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onState: ((CBManagerState) -> Void)?
    var onRSSI: ((Int) -> Void)?
    var onStatus: ((String) -> Void)?
    /// Name resolved over GATT (peripheral id, name). Advertisements often
    /// omit the name; the GATT database usually still answers.
    var onNameResolved: ((UUID, String) -> Void)?
    /// Bluetooth SIG Appearance resolved over GATT (UUID 0x2A01).
    var onAppearanceResolved: ((UUID, UInt16) -> Void)?
    /// Every advertisement seen: identifier, name (may be ""), RSSI,
    /// manufacturer company ID (nil when absent), whether Google Fast Pair
    /// service data (0xFE2C) is present, and Apple Continuity type byte if present.
    var onAdvertisement: ((UUID, String, Int, UInt16?, Bool, UInt8?) -> Void)?
    /// Returns true when the nearby-device list UI wants full advertisement
    /// traffic (not just the pinned device). Checked on the BLE queue before
    /// forwarding a non-pinned packet, to avoid unnecessary main-thread work.
    var trackAllAdvertisements: (() -> Bool)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var targetName: String = ""
    /// Current locator for the pin (ephemeral): id match wins while visible,
    /// the pinned target name follows across identifier rotation.
    var pinnedID: UUID?

    // MARK: - Name Resolution Queue (unnamed singletons)
    /// One-shot GATT name reads for lingering unnamed sightings. Fully
    /// separate from the held monitor link: resolution peripherals never
    /// touch `peripheral`/`reconnectTries`, and their RSSI is gated out of
    /// presence (see didReadRSSI). Results flow through onNameResolved, so
    /// groups re-key and badges appear with no extra plumbing.
    var resolutionEnabled: Bool = true
    private var resolutionPeripherals: [UUID: CBPeripheral] = [:]
    private var resolutionStartedAt: [UUID: Date] = [:]
    private var resolutionAttemptedAt: [UUID: Date] = [:]
    private var lastResolutionAttempt = Date.distantPast
    private static let resolutionTimeout: TimeInterval = 10.0
    private static let resolutionRetryAfter: TimeInterval = 86400 // 24h per UUID
    private static let resolutionGap: TimeInterval = 5.0
    private let resolveLog = Logger(subsystem: "com.harysuryanto.brb", category: "resolve")

    /// Identifiers with a resolution connection currently in flight (for UI).
    var resolvingIdentifiers: Set<UUID> { Set(resolutionPeripherals.keys) }

    /// Attempt a one-shot name resolution for a fresh unnamed sighting.
    /// Throttled: one in flight, minimum gap, one attempt per UUID per day.
    func resolveName(_ p: CBPeripheral) {
        let id = p.identifier
        guard resolutionEnabled,
              resolutionPeripherals.isEmpty,
              Date().timeIntervalSince(lastResolutionAttempt) >= Self.resolutionGap,
              Date().timeIntervalSince(resolutionAttemptedAt[id] ?? .distantPast) >= Self.resolutionRetryAfter,
              let central, central.state == .poweredOn else { return }
        lastResolutionAttempt = Date()
        resolutionAttemptedAt[id] = Date()
        resolutionStartedAt[id] = Date()
        resolutionPeripherals[id] = p
        resolveLog.info("resolve: connecting \(id.uuidString.prefix(8), privacy: .public)")
        central.connect(p, options: nil)
    }

    /// Forget a recorded attempt so the next sighting may try again.
    /// Used on pin: picking an unnamed card signals intent, so its name
    /// resolution must not stay suppressed behind the 24h backoff.
    func clearResolutionAttempt(_ id: UUID) {
        resolutionAttemptedAt.removeValue(forKey: id)
    }

    /// Disconnect timed-out resolutions. Called from the engine tick.
    func sweepResolutions() {
        guard let central else { return }
        let now = Date()
        for (id, started) in resolutionStartedAt
        where now.timeIntervalSince(started) > Self.resolutionTimeout {
            if let p = resolutionPeripherals[id] {
                resolveLog.info("resolve: timeout \(id.uuidString.prefix(8), privacy: .public)")
                central.cancelPeripheralConnection(p)
            }
            resolutionPeripherals.removeValue(forKey: id)
            resolutionStartedAt.removeValue(forKey: id)
        }
    }

    private func finishResolution(_ p: CBPeripheral, reason: String) {
        guard resolutionPeripherals[p.identifier] != nil else { return }
        resolveLog.info("resolve: \(reason, privacy: .public) \(p.identifier.uuidString.prefix(8), privacy: .public)")
        resolutionPeripherals.removeValue(forKey: p.identifier)
        resolutionStartedAt.removeValue(forKey: p.identifier)
        central?.cancelPeripheralConnection(p)
    }
    private var lastRequest: Date = .distantPast
    private var seenCount: Int = 0
    private var lastHeartbeat: Date = .distantPast
    /// Whether a duplicates-mode scan is currently running. The scan stays up
    /// even while a monitor link is held — stopping it froze the nearby list
    /// (no new devices, and pruning stalled because it only runs on advert
    /// receipt). Scanning and a held GATT link coexist fine on CoreBluetooth.
    private var isScanning = false
    /// Direct-reconnect budget for a dropped HELD link (no scan round-trip).
    /// Capped so a truly-gone bud falls back to scanning, not a hot loop.
    private var reconnectTries: Int = 0
    private let maxReconnectTries = 3

    func start(targetName: String, pinnedID: UUID? = nil) {
        self.targetName = targetName
        // Unconditional: a nil pin (unpin path) must clear the previous
        // identifier, otherwise the reader keeps id-only matching the old
        // bud and re-attaches to it after unpinning.
        self.pinnedID = pinnedID
        if central == nil {
            central = CBCentralManager(delegate: self, queue: DispatchQueue(label: "com.harysuryanto.brb.ble", qos: .utility))
        } else if central?.state == .poweredOn {
            startScan()
        }
    }

    func stop() {
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        for (_, p) in resolutionPeripherals { central?.cancelPeripheralConnection(p) }
        resolutionPeripherals.removeAll()
        resolutionStartedAt.removeAll()
        peripheral = nil
        reconnectTries = 0
        central?.stopScan()
        isScanning = false
    }

    /// Hygiene restart: with duplicates-mode streaming there are no gaps to
    /// close; restarts only reset counters. Never touches the held monitor
    /// link — it only recycles the scan.
    func restartScan() {
        guard central?.state == .poweredOn else { return }
        central?.stopScan()
        isScanning = false
        startScan()
    }

    /// Throttled: at most one read per second (called on a faster tick).
    func requestRead() {
        guard let p = peripheral, p.state == .connected else { return }
        guard Date().timeIntervalSince(lastRequest) >= 1.0 else { return }
        lastRequest = Date()
        p.readRSSI()
    }

    private func startScan() {
        // Connected buds stop advertising to save power, so active
        // discovery alone never sees them. First ask the system for LE
        // peripherals it already holds (GAP 0x1800 is mandatory on every
        // GATT server, BAS/DIS cover most buds).
        tryAttached()
        guard central?.state == .poweredOn, !isScanning else { return }
        seenCount = 0
        onStatus?("Scanning LE…")
        // Duplicates ON: every received packet reports fresh RSSI instead of
        // one sighting per scan session. Costs more radio/CPU — acceptable
        // for a plugged-in desk tool, and it closes the restart gaps.
        // NOTE: the scan intentionally keeps running while a monitor link is
        // held so the nearby-device list stays live.
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
    }

    /// Attach to a system-connected LE peripheral matching the picked bud.
    /// Never stops the scan — the nearby list must keep updating.
    private func tryAttached() {
        guard let central else { return }
        let uuids = ["1800", "180F", "180A"].map { CBUUID(string: $0) }
        for p in central.retrieveConnectedPeripherals(withServices: uuids) {
            if peripheral?.identifier == p.identifier { continue } // already held
            let name = p.name ?? ""
            if matches(id: p.identifier, name: name) {
                peripheral = p
                reconnectTries = 0
                onStatus?("Attaching LE: \(name.isEmpty ? p.identifier.uuidString : name)")
                central.connect(p, options: nil)
                return
            }
        }
    }

    private func matches(id: UUID, name: String) -> Bool {
        // Current locator wins while visible. Name follow second: identifiers
        // rotate across case cycles, so a pinned target name re-claims the
        // link under a fresh identifier (same-name strangers remain a known
        // collision case, handled with vendor checks at the engine layer).
        if let pinnedID, id == pinnedID { return true }
        if !targetName.isEmpty { return matches(name: name) }
        return false
    }

    /// Name match with TWS hints fallback.
    private func matches(name: String) -> Bool {
        let target = targetName.lowercased()
        let n = name.lowercased()
        if !target.isEmpty, !target.contains("searching"),
           !n.isEmpty, (n.contains(target) || target.contains(n)) { return true }
        if n.isEmpty { return false }
        let hints = ["soundcore", "r60i", "airpods", "buds", "headphone", "headset",
                     "earbuds", "freebuds", "life ", "aero", "jbl", "sony", "beats", "bose"]
        return hints.contains { n.contains($0) }
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onState?(central.state)
        if central.state == .poweredOn { startScan() }
        else {
            isScanning = false
            onStatus?("LE unavailable (\(central.state.rawValue))")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = p.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        seenCount += 1
        // Identity hints for unnamed packets: manufacturer company ID (first
        // 2 bytes, little-endian), Apple Continuity type byte, and Google Fast Pair service data (0xFE2C).
        var companyID: UInt16? = nil
        var continuityType: UInt8? = nil
        if let mfr = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           mfr.count >= 2 {
            companyID = UInt16(mfr[mfr.startIndex]) | (UInt16(mfr[mfr.startIndex + 1]) << 8)
            if companyID == 0x004C, mfr.count >= 3 {
                continuityType = mfr[mfr.startIndex + 2]
            }
        }
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let hasFastPair = serviceUUIDs.contains(CBUUID(string: "FE2C"))

        let isPinnedMatch = matches(id: p.identifier, name: name)
        let shouldForward = isPinnedMatch || (trackAllAdvertisements?() ?? false)

        if shouldForward {
            onAdvertisement?(p.identifier, name, RSSI.intValue, companyID, hasFastPair, continuityType)
            if isUnnamed(name) {
                resolveName(p)
            }
        }

        guard isPinnedMatch else {
            // Time-throttled heartbeat (duplicates mode is chatty): proves
            // the scan works and shows whether the bud advertises at all.
            if Date().timeIntervalSince(lastHeartbeat) > 5.0 {
                lastHeartbeat = Date()
                onStatus?("Scanning LE… (seen \(seenCount) other devices)")
            }
            return
        }
        // A monitor link is already held — keep it, keep scanning for the list.
        guard peripheral == nil else { return }
        peripheral = p
        reconnectTries = 0
        onStatus?("Connecting LE: \(name)")
        central.connect(p, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        reconnectTries = 0
        onStatus?("LE connected: \(p.name ?? "?")")
        p.delegate = self
        p.readRSSI()
        // Ask the GATT database for identity: Generic Access (Device Name + Appearance)
        // + Device Information (Model/Manufacturer). Advertisements often
        // carry none, but these characteristics usually answer.
        p.discoverServices([CBUUID(string: "1800"), CBUUID(string: "180A")])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        resolutionPeripherals.removeValue(forKey: p.identifier)
        resolutionStartedAt.removeValue(forKey: p.identifier)
        guard peripheral === p else { return }
        // Our own 1Hz readRSSI traffic normally keeps the link up. On a
        // drop, retry the HELD object directly first (no scan round-trip);
        // give up to scanning after the budget so a gone bud can't hot-loop.
        if reconnectTries < maxReconnectTries {
            reconnectTries += 1
            onStatus?("LE dropped, re-attaching (\(reconnectTries)/\(maxReconnectTries))…")
            central.connect(p, options: nil)
        } else {
            peripheral = nil
            reconnectTries = 0
            onStatus?("LE disconnected, rescanning…")
            startScan()
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        resolutionPeripherals.removeValue(forKey: p.identifier)
        resolutionStartedAt.removeValue(forKey: p.identifier)
        guard peripheral === p else { return }
        // Same budget as drops: retry the held object, then scan.
        if reconnectTries < maxReconnectTries {
            reconnectTries += 1
            onStatus?("LE connect failed, retrying (\(reconnectTries)/\(maxReconnectTries))…")
            central.connect(p, options: nil)
        } else {
            peripheral = nil
            reconnectTries = 0
            // No hot-loop rescan here: the periodic restartScan() retries.
            onStatus?("LE connect failed (\(error?.localizedDescription ?? "unknown")), will retry…")
        }
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        // Monitor link only: resolution one-shots must never feed presence.
        guard let held = self.peripheral, peripheral === held else { return }
        onRSSI?(RSSI.intValue)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        // Only 1800/180A were requested; their char sets are tiny.
        for s in services {
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let chars = service.characteristics else { return }
        for c in chars where ["2A00", "2A01", "2A24", "2A29"].contains(c.uuid.uuidString) {
            peripheral.readValue(for: c)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, !data.isEmpty else { return }
        let uuidStr = characteristic.uuid.uuidString

        // 2A01 is standard 16-bit Bluetooth SIG Appearance
        if uuidStr == "2A01", data.count >= 2 {
            let appearance = UInt16(data[data.startIndex]) | (UInt16(data[data.startIndex + 1]) << 8)
            onAppearanceResolved?(peripheral.identifier, appearance)
            return
        }

        guard ["2A00", "2A24", "2A29"].contains(uuidStr) else { return }
        let name = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .controlCharacters).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onNameResolved?(peripheral.identifier, name)
        // Resolution links are one-shot: name in hand, let go.
        finishResolution(peripheral, reason: "resolved")
    }
}
