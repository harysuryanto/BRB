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

final class LERSSIReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onState: ((CBManagerState) -> Void)?
    var onRSSI: ((Int) -> Void)?
    var onStatus: ((String) -> Void)?
    /// Name resolved over GATT (peripheral id, name). Advertisements often
    /// omit the name; the GATT database usually still answers.
    var onNameResolved: ((UUID, String) -> Void)?
    /// Every advertisement seen: identifier, name (may be ""), RSSI.
    var onAdvertisement: ((UUID, String, Int) -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var targetName: String = ""
    /// User-pinned LE peripheral: matched by identifier, not name.
    var pinnedID: UUID?
    private var lastRequest: Date = .distantPast
    private var seenCount: Int = 0
    private var lastHeartbeat: Date = .distantPast
    /// Direct-reconnect budget for a dropped HELD link (no scan round-trip).
    /// Capped so a truly-gone bud falls back to scanning, not a hot loop.
    private var reconnectTries: Int = 0
    private let maxReconnectTries = 3

    func start(targetName: String, pinnedID: UUID? = nil) {
        self.targetName = targetName
        if let pinnedID { self.pinnedID = pinnedID }
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
        } else if central?.state == .poweredOn {
            startScan()
        }
    }

    func stop() {
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        reconnectTries = 0
        central?.stopScan()
    }

    /// Hygiene restart: with duplicates-mode streaming there are no gaps to
    /// close; restarts only reset counters.
    func restartScan() {
        guard central?.state == .poweredOn, peripheral == nil else { return }
        central?.stopScan()
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
        guard peripheral == nil else { return }
        // Connected buds stop advertising to save power, so active
        // discovery alone never sees them. First ask the system for LE
        // peripherals it already holds (GAP 0x1800 is mandatory on every
        // GATT server, BAS/DIS cover most buds).
        tryAttached()
        guard peripheral == nil else { return }
        seenCount = 0
        onStatus?("Scanning LE…")
        // Duplicates ON: every received packet reports fresh RSSI instead of
        // one sighting per scan session. Costs more radio/CPU — acceptable
        // for a plugged-in desk tool, and it closes the restart gaps.
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    /// Attach to a system-connected LE peripheral matching the picked bud.
    private func tryAttached() {
        guard let central else { return }
        let uuids = ["1800", "180F", "180A"].map { CBUUID(string: $0) }
        for p in central.retrieveConnectedPeripherals(withServices: uuids) {
            let name = p.name ?? ""
            if matches(id: p.identifier, name: name) {
                peripheral = p
                reconnectTries = 0
                central.stopScan()
                onStatus?("Attaching LE: \(name.isEmpty ? p.identifier.uuidString : name)")
                central.connect(p, options: nil)
                return
            }
        }
    }

    private func matches(id: UUID, name: String) -> Bool {
        if let pinnedID, id == pinnedID { return true }
        return matches(name: name)
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
        else { onStatus?("LE unavailable (\(central.state.rawValue))") }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = p.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        seenCount += 1
        // Advertisement RSSI is free proximity data — report it before any
        // match/connect logic so even non-connectable beacons show up.
        onAdvertisement?(p.identifier, name, RSSI.intValue)
        guard matches(id: p.identifier, name: name) else {
            // Time-throttled heartbeat (duplicates mode is chatty): proves
            // the scan works and shows whether the bud advertises at all.
            if Date().timeIntervalSince(lastHeartbeat) > 5.0 {
                lastHeartbeat = Date()
                onStatus?("Scanning LE… (seen \(seenCount) other devices)")
            }
            return
        }
        peripheral = p
        reconnectTries = 0
        central.stopScan()
        onStatus?("Connecting LE: \(name)")
        central.connect(p, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        reconnectTries = 0
        onStatus?("LE connected: \(p.name ?? "?")")
        p.delegate = self
        p.readRSSI()
        // Ask the GATT database for a name: Generic Access (Device Name)
        // + Device Information (Model/Manufacturer). Advertisements often
        // carry none, but these characteristics usually answer.
        p.discoverServices([CBUUID(string: "1800"), CBUUID(string: "180A")])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
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
        for c in chars where ["2A00", "2A24", "2A29"].contains(c.uuid.uuidString) {
            peripheral.readValue(for: c)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              ["2A00", "2A24", "2A29"].contains(characteristic.uuid.uuidString),
              let data = characteristic.value, !data.isEmpty else { return }
        let name = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .controlCharacters).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        onNameResolved?(peripheral.identifier, name)
    }
}
