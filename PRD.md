# Product Requirements Document (PRD): BRB

**Tagline:** *Step away. Your screen covers itself.*
**Prototype target:** macOS menu-bar / single-window SwiftUI app (Swift 5.9+, macOS 14+).
**Suggested bundle ID:** `com.harysuryanto.brb`

> Terminology: "veil" = cover. A veil is a thin curtain that hides something —
> the veil is the fullscreen image covering your desktop. "Cover/covered" may
> be used interchangeably in UI copy.

## 1. Overview

BRB is a macOS presence-privacy app for TWS (True Wireless Stereo) users. While the user sits at the Mac, nothing happens. When the user walks away (buds leave ~2m radio range — e.g. getting water), BRB covers **all displays** with a user-chosen fullscreen image (the *veil*) so passersby see nothing sensitive. A single **Unlock with Mac Login** button on the veil locks the Mac; the user authenticates at the real macOS login screen (Touch ID / password) and the veil lifts with a suppress window as backup. When the user returns with the buds, the veil lifts automatically with no clicks at all.

Positioning vs existing tools (BLEUnlock, SignalLock, B.R.I.O.S., WalkLock): they go straight to *lock*. BRB is veil-first, lock-on-demand — friendlier for offices where every water run shouldn't nuke your session.

## 2. Problem Statement

Unlocked Macs in shared spaces expose sensitive screens the moment the owner steps away. Manual locking (Ctrl-Cmd-Q) is forgotten; auto-lock timers fire while reading. TWS earbuds already ride along on every trip — their radio presence is a free, continuous "user is here" signal the OS doesn't productize.

## 3. Goals & Non-Goals

### 3.1 Goals (prototype)
- Detect a user-picked TWS via Bluetooth LE and estimate Near/Far continuously.
- Veil all displays with a custom image when Far persists past a grace delay.
- Lift the veil automatically on return; manual dismiss via macOS screen login.
- Single-button escalation to the real macOS lock screen from the veil.
- Fail-secure option: lock the Mac if BRB itself quits.
- Settings UI: device picker, threshold calibration, veil image picker, grace delay, suppress window, fail-secure toggle.

### 3.2 Non-Goals
- No automatic macOS *unlock* (security hole — the veil only reveals an already-unlocked session).
- No Classic-Bluetooth-only strategy (proven dead on Apple Silicon for many buds — see §5).
- No analytics, network calls, iCloud sync, login-item (post-prototype).

## 4. Locked Decisions

| # | Decision | Value |
|---|----------|-------|
| 1 | Product name | **BRB** |
| 2 | Manual veil dismiss | **Via macOS screen login** (no in-app password prompt): press Unlock → system lock → loginwindow auth → suppress window |
| 3 | Grace delay default | **10s**, customisable 5–60s |
| 4 | Veil coverage | **All displays**, mirrored image |
| 5 | Fail-secure on quit | **In scope** (toggle, default on) |
| 6 | Primary radio | **CoreBluetooth LE** (GATT readRSSI + advertisement RSSI); Classic HCI best-effort only |
| 7 | Data honesty | Freeze + mark stale; never extrapolate or invent samples |
| 8 | Veil buttons | **Single button**: "Unlock with Mac Login" (pure-escalation path merged away) |
| 9 | Suppress window | **Settings stepper, 5–60 min, default 15** |
| 10 | Distribution | **Unsandboxed** (Developer ID, direct download — sandbox blocks lock-spawning and caused Bluetooth entitlement friction) |

## 5. System Architecture & Tech Stack

- **Platform:** macOS 14.0+, Swift 5.9+, SwiftUI.
- **Frameworks:** `CoreBluetooth` (detection), `SwiftUI`/`AppKit` (veil window, settings), `CoreAudio` (informational: current system-output name only).
- **Pipeline:** 0.5s poll tick → LE sample (GATT ~1Hz when held, else advertisements) → EMA smoothing (α=0.2) → hysteresis bands → grace timer → veil on/off. Classic `IOBluetooth` runs alongside as fallback only.
- **Why LE-first (do not regress):** on Apple Silicon a connected Classic A2DP bud can report `isConnected=true` with `connectionHandle=0x0000` and `rawRSSI()==0` forever (LE-Audio transport / shim limitation — verified over 200+ polls on soundcore R60i NC). LE advertisement + GATT reads work on the same machine (verified live: BLE mouse tracked at −63 dBm end-to-end). `system_profiler device_rssi` no longer exists on macOS 26; inquiry RSSI needs discoverability buds don't offer. There is no third public API.

## 6. Functional Requirements

### 6.1 Onboarding (first launch, 3 steps)
1. Bluetooth consent screen explaining why access is needed (creating `CBCentralManager` IS the system prompt — there is no other way to ask).
2. Live scan list (name + live dBm, per-identifier rows, unnamed entries shown honestly) → pick TWS → identifier persisted.
3. "Stand where away starts (~2m) → Set away boundary" capturing dBm as veil-on threshold; defaults −80 dBm on / −70 dBm off if skipped.

### 6.2 Detection Engine
- Duplicates-allowed BLE scan; per-identifier advertisement ring (prune unpinned >60s, pinned >300s, cap 30).
- Pin-by-identifier (never by name — names are often absent from ad packets and addresses can rotate).
- GATT hold + `readRSSI()` throttled to 1Hz when the bud accepts connection; direct-reconnect budget 3, then back to scanning (never hot-loop).
- GATT name resolution after connect (Generic Access `0x2A00`, Device Info `0x2A24`/`0x2A29`) fills "(unnamed)" rows only, never overwrites real names.
- Freshness gates: GATT samples <3s, advertisement samples <12s. Older samples never feed decisions.
- Away = smoothed signal below veil-on threshold persisting through grace delay. Gone (no sightings for 2× grace: bud cased/dead/BT off) veils with its own reason line. Any in-range sample resets the timer.
- Switching monitored device resets histories/EMA/counters/link AND clears the LE pin (a stale pin misattributes distance — real bug, do not reintroduce).

### 6.3 Veil (Screen Cover)
- Borderless window on **every** display, `NSWindow.Level.screenSaver`, `canJoinAllSpaces`, excluded from Exposé/Mission Control, fast fade-in (~0.25s), instant dismiss on return past the hysteresis gap.
- Content: user image full-bleed (see §6.4) + **one button**. Nothing else.
- Single button labeled **"Unlock with Mac Login"**, subtitled *"Locks this Mac — log back in to dismiss the cover for a while."* Press → system lock → user authenticates at loginwindow (Touch ID / password, whichever the system offers) → veil lifts with a suppress window (the §6.6 stepper value) → normal evaluation resumes afterwards.
- Return detection: unlock observed via `NSWorkspace.sessionDidBecomeActiveNotification` (or `com.apple.screenIsUnlocked`); a `pendingManualUnlock` flag set when *we* initiated the lock applies suppression; otherwise (user locked manually, fail-secure lock) state re-evaluates normally — bud still away → veil returns with a fresh grace timer (no instant-flash loop).
- If the bud returns mid-suppression: suppression clears, normal tracking resumes (veil already down — nothing to do).
- A crash is never a trust signal: post-crash unlock gets normal evaluation, never suppression.
- Honest limit (document in Settings footnote): screen *sharing* broadcasts the veil image (intended); anything visible *before* veiling already left — grace-delay tuning is the mitigation.

### 6.4 Image Settings (Settings → Cover tab)
- **Choose image:** `NSOpenPanel` (files only, single select; types PNG/JPEG/TIFF/HEIC/BMP/GIF, **animated GIFs play** via `GIFFrame` decode + `TimelineView` driver in `CoverAnimation.swift`/`AnimatedCoverView.swift`) + **Reset to default** button + thumbnail preview of current selection (preview plays GIFs too).
- **Persistence (sandbox-safe):** store a **security-scoped bookmark** (`URL.bookmarkData(options: .withSecurityScope)`) under `BRB.veilImageBookmark`, NOT a raw path. On launch/display: resolve bookmark → `startAccessingSecurityScopedResource()` → load → `stopAccessing…`. Stale/unresolvable bookmark → fall back to default + show "Image unavailable — please re-choose" notice row in Settings.
- **Rendering:** aspect-fill (preserve ratio, cover, black surround), mirrored identically on all displays (prototype scope — no per-display images), downscaled to each screen's backing size and cached; reload on display-configuration change.
- **Default image (bundled asset):** dark gradient + "BRB — stepped away" wordmark. Used when nothing chosen or file missing. Never a broken/empty veil.
- **Validation:** unreadable/corrupt file → default + notice. No crash path on bad input.

### 6.5 Lock Escalation & Fail-Secure
- The veil's single button performs a real session lock (password/Touch ID to return). One call, no private API (unlocked distribution assumed per §4.10).
- Fail-secure toggle (default on): graceful termination locks the Mac in `applicationWillTerminate`. Documented limit: SIGKILL/force-quit cannot run cleanup — bulletproof fail-secure needs a tiny watcher helper (post-prototype).

### 6.6 Settings UI Summary
Device picker (live list, re-pinnable) · threshold slider + recalibrate · veil image (picker/preview/reset) · grace stepper 5–60s (default 10s) · suppress stepper 5–60 min (default 15) · fail-secure toggle. Status line always shows: state, dBm + source badge (`LE`/`LE-adv`), sample age, stale marker past 12s.

## 7. Permissions & Project Config (both Debug AND Release)

| Item | Value |
|---|---|
| Distribution | Unsandboxed (`ENABLE_APP_SANDBOX = NO`), no entitlements file |
| `NSBluetoothAlwaysUsageDescription` | "reads the connected headset's Bluetooth signal strength (RSSI)…" |
| TCC consent | `CBCentralManager` instantiation triggers it; Denied must degrade to Settings instructions, never hang |
| Test environment | Real Mac only (no simulator Bluetooth); first-launch Allow required |

**Threading rule (caused a real abort):** `IOBluetoothDevice.pairedDevices()` can semaphore-wait when TCC denies — call it on a background queue, publish on main. `openConnection()` likewise off-main, and always surface its `IOReturn` hex (`0x0` = success) — it is the best Classic-path diagnostic.

**Swift/Xcode pitfalls (each cost hours):** `device.rssi()` not `RSSI()`; `IOBluetoothDevice(addressString:)` not `deviceWithAddressString`; re-resolve Classic devices every poll (cached objects go stale); one giant `[String: Any]` literal breaks preview type-checking (small `Codable` structs instead); no `static` stored props in `@Observable` classes; no nested `ScrollView`s.

## 8. Success Metrics & Milestones

- **Prototype:** pick bud → walk to ~2m → veil within grace+2s on all displays → return → instant lift → Unlock button locks → login returns with suppression → quit with fail-secure on locks the Mac.
- **Calibration pass:** 1m stand-still per reference bud to fit real `measuredPower`; verify trend tracking near→far.
- **Later:** login-item, per-display images, multi-bud, presence API.

## Appendix A — Drop-in LE Connection Engine

> Paste `import CoreBluetooth` plus the following verbatim. Wire the five callbacks into your manager per the contract in A.2. No veil/lock/settings code here by design.

```swift
final class LERSSIReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onState: ((CBManagerState) -> Void)?
    var onRSSI: ((Int) -> Void)?
    var onStatus: ((String) -> Void)?
    var onNameResolved: ((UUID, String) -> Void)?
    var onAdvertisement: ((UUID, String, Int) -> Void)?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var targetName: String = ""
    var pinnedID: UUID?
    private var lastRequest: Date = .distantPast
    private var seenCount: Int = 0
    private var lastHeartbeat: Date = .distantPast
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

    func restartScan() {
        guard central?.state == .poweredOn, peripheral == nil else { return }
        central?.stopScan()
        startScan()
    }

    func requestRead() {
        guard let p = peripheral, p.state == .connected else { return }
        guard Date().timeIntervalSince(lastRequest) >= 1.0 else { return }
        lastRequest = Date()
        p.readRSSI()
    }

    private func startScan() {
        guard peripheral == nil else { return }
        tryAttached()
        guard peripheral == nil else { return }
        seenCount = 0
        onStatus?("Scanning LE…")
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

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

    private func matches(name: String) -> Bool {
        let target = targetName.lowercased()
        let n = name.lowercased()
        if !target.isEmpty, !target.contains("no tws"), !target.contains("searching"),
           !n.isEmpty, (n.contains(target) || target.contains(n)) { return true }
        if n.isEmpty { return false }
        let hints = ["soundcore", "r60i", "airpods", "buds", "headphone", "headset",
                     "earbuds", "freebuds", "life ", "aero", "jbl", "sony", "beats", "bose"]
        return hints.contains { n.contains($0) }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onState?(central.state)
        if central.state == .poweredOn { startScan() }
        else { onStatus?("LE unavailable (\(central.state.rawValue))") }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = p.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        seenCount += 1
        onAdvertisement?(p.identifier, name, RSSI.intValue)
        guard matches(id: p.identifier, name: name) else {
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
        p.discoverServices([CBUUID(string: "1800"), CBUUID(string: "180A")])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard peripheral === p else { return }
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
        if reconnectTries < maxReconnectTries {
            reconnectTries += 1
            onStatus?("LE connect failed, retrying (\(reconnectTries)/\(maxReconnectTries))…")
            central.connect(p, options: nil)
        } else {
            peripheral = nil
            reconnectTries = 0
            onStatus?("LE connect failed (\(error?.localizedDescription ?? "unknown")), will retry…")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        onRSSI?(RSSI.intValue)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for s in services { peripheral.discoverCharacteristics(nil, for: s) }
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
```

### A.2 Manager contract (implement around the class)

- State: `leRSSI/leRSSIAt/leKind ("LE"|"LE-adv")/leStatus/leAdverts[pinned-aware]/pinnedLEID (UserDefaults)/rssiSource/sampleAge`.
- `onAdvertisement`: store per identifier, prune unpinned >60s / pinned >300s / cap 30; feed live sample (kind `LE-adv`) when identifier == pin or name matches picked device. `onRSSI`: live sample, kind `LE`. GATT names fill "(unnamed)" rows only.
- 0.5s tick: retarget on device change, `requestRead()`, hygiene `restartScan()` ~60s, Classic-if-valid else LE-if-fresh (GATT <3s, adv <12s), record source.
- Pin/unpin by identifier UUID string (persisted); device switch resets histories/EMA/counters/link/pin.
- Classic path (best-effort): background-queue `pairedDevices()`, re-resolve via `addressString` each poll, discard `rawRSSI` `0`/`127`, surface `openConnection()` IOReturn hex.

## Appendix B — Acceptance protocol

1. Always-visible LE device (mouse): `LE connected`, live dBm, distance/zone move. (Proves pipeline; run first.)
2. Target TWS streaming: some LE path (attach/adv/name) must yield data; Classic zeros alone are expected on some buds, not a failure of your code.
3. Move-the-bud: dBm more negative with distance, recovers on return; anonymous entries identified this way.
4. BT toggle off/on mid-run: guidance shown, no hang/crash, recovery without restart.
5. Device switch mid-run: chart restarts empty.
6. Veil: walk past boundary → veil within grace+2s on all displays → return → instant lift → Unlock button locks → login returns with suppression → quit with fail-secure on locks.
