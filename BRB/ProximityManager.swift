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
    /// Bluetooth SIG manufacturer company ID from the packet's manufacturer
    /// data (nil when absent — many buds advertise Fast Pair instead).
    var companyID: UInt16? = nil
    /// Whether Google Fast Pair service data (0xFE2C) was present.
    var hasFastPairService: Bool = false
}

// MARK: - Device identity (single source of truth for every surface)
//
// Scanner cards, monitored cards, onboarding, and the menu bar all render
// device identity through these helpers — never raw AdvertSample.name — so
// art and naming stay consistent everywhere.

/// Whether the stored name is a placeholder rather than a real device name.
func isUnnamed(_ name: String) -> Bool {
    let n = name.trimmingCharacters(in: .whitespaces)
    return n.isEmpty || n.lowercased().contains("(unnamed)")
}

/// SIG-verified manufacturer company IDs for audio/wearable-relevant vendors.
/// Unmapped IDs show no chip (silent fallback) — never invent a vendor.
func vendorName(for companyID: UInt16?) -> String? {
    guard let companyID else { return nil }
    switch companyID {
    case 0x004C: return "Apple"
    case 0x0075: return "Samsung"
    case 0x012D: return "Sony"
    case 0x009E: return "Bose"
    case 0x00E0: return "Google"
    case 0x0006: return "Microsoft"
    case 0x0057: return "Harman"
    case 0x0055: return "Poly"
    case 0x0082: return "Sennheiser"
    case 0x0087: return "Garmin"
    case 0x006B: return "Polar"
    case 0x008A: return "Jawbone"
    case 0x0059: return "Nordic"
    case 0x005D: return "Realtek"
    default: return nil
    }
}

/// Stable 4-hex device suffix from the identifier. Suffix (not prefix) avoids
/// duplicating the prefix-8 shown in scanner subtitles. Deterministic
/// across launches — macOS identifiers are per-peripheral stable.
func deviceSuffix(for id: String) -> String {
    String(id.filter { $0.isHexDigit }.suffix(4)).uppercased()
}

/// Placeholder title when no sample exists at all (advert fully aged out).
func displayTitle(for id: String) -> String {
    let suffix = deviceSuffix(for: id)
    return suffix.isEmpty ? "Unknown" : "Unknown • \(suffix)"
}

/// Secondary identity chip for an unnamed sample: vendor, else Fast Pair
/// hint (many buds advertise 0xFE2C instead of manufacturer data), else nil.
/// Named samples get no chip — the name suffices.
func chipText(for sample: AdvertSample) -> String? {
    guard isUnnamed(sample.name) else { return nil }
    if let vendor = vendorName(for: sample.companyID) { return vendor }
    if sample.hasFastPairService { return "Fast Pair" }
    return nil
}

/// How dismissible the veil cover is.
/// - secure: lifts only on TWS return or macOS login (real protection).
/// - casual: also offers a Hide button that lifts it once with no auth
///   (aesthetic only — it returns after the grace delay if still away).
enum VeilLockMode: String, CaseIterable {
    case secure
    case casual
}

@Observable
class ProximityManager {
    static let shared = ProximityManager()

    // MARK: - Permissions & Engine Status
    var bluetoothPermission: String = "Checking…"
    var bluetoothGranted: Bool = false
    var leStatus: String = "LE idle"

    // MARK: - Adverts & Live Samples
    var leAdverts: [String: AdvertSample] = [:]
    var liveRSSI: Int? = nil
    var liveRSSIAt: Date? = nil
    var liveKind: String = "—"

    // MARK: - Device Name Cache (persisted identity hints)

    /// Last-known real identity for a peripheral identifier. Names are the
    /// volatile half of device identity (user-renamable, advert-optional),
    /// so this is a hint with an expiry — live data always wins, and a miss
    /// degrades to the stable placeholder. Placeholders are never stored.
    /// Local-only, same store as the pinned identifier.
    struct CachedDevice: Codable {
        var name: String
        var companyID: UInt16?
        var hasFastPair: Bool
        var lastSeen: Date
    }

    private static let nameCacheKey = "BRB.deviceIdentities"
    private static let nameCacheLimit = 30
    private static let nameCacheTTL: TimeInterval = 30 * 86400 // 30 days
    private static let nameCacheSaveThrottle: TimeInterval = 3600 // 1 hour

    /// Identifier → last-known real identity. Session working copy of the
    /// persisted cache; views never read it directly (see resolvedName).
    private var nameCache: [String: CachedDevice] = [:]
    private var lastNameCacheSave = Date.distantPast

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

    /// Never-blank monitored identity, consistent with scanner cards: the
    /// resolved name when known, otherwise the stable "Unknown • XXXX"
    /// placeholder. Nil only when nothing is pinned — views gate monitored UI
    /// on pin state, never on name resolvability, so the monitored card can
    /// no longer flip to "no device" mid-pin when adverts age out.
    var pinnedDisplayName: String? {
        guard let pinnedLEID else { return nil }
        return displayName(for: pinnedLEID)
    }

    /// Live-or-cached real name for an identifier (nil when neither knows one).
    /// Single resolution point for every surface: live data always wins, the
    /// cache covers advert gaps and cold starts, and a miss degrades to the
    /// placeholder at the call site.
    private func resolvedName(for id: String) -> String? {
        if let live = leAdverts[id]?.name, !isUnnamed(live) { return live }
        if let cached = nameCache[id]?.name, !isUnnamed(cached) { return cached }
        return nil
    }

    /// Display name for any identifier on any surface.
    func displayName(for id: String) -> String {
        if let resolved = resolvedName(for: id) { return resolved }
        return displayTitle(for: id)
    }

    /// Identity chip for any identifier: live vendor hints, else cached ones.
    func identityChip(for id: String) -> String? {
        if let sample = leAdverts[id], let chip = chipText(for: sample) { return chip }
        guard let cached = nameCache[id] else { return nil }
        let pseudo = AdvertSample(name: "(unnamed)", rssi: 0, at: .distantPast,
                                  companyID: cached.companyID, hasFastPairService: cached.hasFastPair)
        return chipText(for: pseudo)
    }

    /// Raw name for artwork categorization. Same precedence as displayName
    /// (live-if-real, else cached-if-real, else "") so art changes only on
    /// the same events as the title — a nameless packet must not flip a
    /// known device back to generic art.
    func artName(for id: String) -> String {
        if let live = leAdverts[id]?.name, !isUnnamed(live) { return live }
        if let cached = nameCache[id]?.name, !isUnnamed(cached) { return cached }
        return ""
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
    var veilOnGoneEnabled: Bool {
        didSet { UserDefaults.standard.set(veilOnGoneEnabled, forKey: "BRB.veilOnGone") }
    }
    var veilLockMode: VeilLockMode {
        didSet { UserDefaults.standard.set(veilLockMode.rawValue, forKey: "BRB.veilLockMode") }
    }

    // MARK: - Presence State Machine
    var presenceState: PresenceState = .idle
    var smoothedRSSI: Double? = nil
    var awayDuration: TimeInterval = 0
    var isVeilActive: Bool = false {
        didSet {
            reconcileVeilPresentation()
        }
    }
    /// Single choke point for veil windows. State (`isVeilActive`) evaluates
    /// freely at all times; presentation additionally requires onboarding
    /// completion — so setup can never fullscreen-shock the user, with zero
    /// view-layer writes. Called from `isVeilActive.didSet` (immediacy), the
    /// engine tick (covers open-mid-veil / finish-while-away no-refire cases),
    /// and onboarding submit.
    private func reconcileVeilPresentation() {
        guard !Self.isPreview else { return }
        // Test preview drives windows directly — engine must not tear it down.
        guard !VeilWindowController.shared.isPreviewActive else { return }
        guard UserDefaults.standard.bool(forKey: "BRB.hasCompletedOnboarding"),
              isVeilActive else {
            VeilWindowController.shared.dismissVeilInstant()
            return
        }
        VeilWindowController.shared.showVeil(reason: veilReason)
    }
    var veilReason: String? = nil
    var isStale: Bool = false
    var sampleAge: TimeInterval? = nil

    // MARK: - Unlock & Suppression State
    var pendingManualUnlock: Bool = false
    var suppressionRemaining: TimeInterval? = nil

    // MARK: - Manual Protection Pause (user toggle)
    /// User-facing pause: while true the veil never activates and any active
    /// veil is dismissed. Session-only (never persisted) so a relaunch always
    /// resumes protection — a crash must never leave the screen uncovered.
    var protectionPaused: Bool = false {
        didSet {
            awayDuration = 0
            if protectionPaused {
                isVeilActive = false
                veilReason = nil
            }
        }
    }

    // MARK: - Calibration Cooldown
    /// Veil activation is paused until this date after calibrating, giving the
    /// user time to walk back to the desk before cover/lock can trigger.
    var calibrationPauseUntil: Date? = nil
    /// Countdown mirror for UI display, refreshed each engine tick.
    var calibrationPauseRemaining: TimeInterval? = nil
    static let calibrationPauseDuration: TimeInterval = 5.0

    // MARK: - Developer Pause (DEBUG builds only)
    /// Temporary veil pause triggered from the cover's debug button so the
    /// veil doesn't keep firing while developing. Not persisted.
    var developerPauseUntil: Date? = nil
    /// Countdown mirror for UI display, refreshed each engine tick.
    var developerPauseRemaining: TimeInterval? = nil
    static let developerPauseDuration: TimeInterval = 15.0

    // MARK: - Internal Components
    private var leReader: LERSSIReader?
    private var timer: Timer?
    private var ticks: Int = 0
    private var monitoringStartedAt: Date = Date()
    // α=0.8: light touch (history weight 0.2, a quarter of the old 0.8) —
    // tracks fast, leans on the hysteresis band + grace timer for stability.
    private let signalProcessor = SignalProcessor(alpha: 0.8)

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
        self.veilOffThreshold = defaults.object(forKey: "BRB.veilOffThreshold") as? Double ?? -74.0
        self.graceDelay = defaults.object(forKey: "BRB.graceDelay") as? TimeInterval ?? 10.0
        self.suppressDuration = defaults.object(forKey: "BRB.suppressDuration") as? TimeInterval ?? 900.0 // 15 mins
        self.failSecureEnabled = defaults.object(forKey: "BRB.failSecureEnabled") as? Bool ?? true
        self.veilOnGoneEnabled = defaults.object(forKey: "BRB.veilOnGone") as? Bool ?? true
        self.veilLockMode = VeilLockMode(rawValue: defaults.string(forKey: "BRB.veilLockMode") ?? "") ?? .secure
        self.pinnedLEID = defaults.string(forKey: "BRB.pinnedLEID")
        self.nameCache = Self.loadNameCache()

        setupLockAndVeilCallbacks()
    }

    private static func loadNameCache() -> [String: CachedDevice] {
        guard let data = UserDefaults.standard.data(forKey: nameCacheKey),
              let decoded = try? JSONDecoder().decode([String: CachedDevice].self, from: data) else {
            return [:]
        }
        let cutoff = Date().addingTimeInterval(-nameCacheTTL)
        return decoded.filter { $0.value.lastSeen >= cutoff }
    }

    private func saveNameCache() {
        guard let data = try? JSONEncoder().encode(nameCache) else { return }
        UserDefaults.standard.set(data, forKey: Self.nameCacheKey)
    }

    /// Upserts a real (never placeholder) identity sighting. Disk writes
    /// happen on identity change, otherwise throttled — duplicates-mode
    /// traffic (many packets/sec) must never hammer disk, while lastSeen
    /// still advances often enough to keep daily-seen entries alive.
    /// Evicts oldest-seen beyond the cap.
    private func cacheIdentity(id: String, name: String, companyID: UInt16?, hasFastPair: Bool) {
        guard !isUnnamed(name) else { return }
        let previous = nameCache[id]
        let changed = previous?.name != name || previous?.companyID != companyID
            || previous?.hasFastPair != hasFastPair
        nameCache[id] = CachedDevice(name: name, companyID: companyID,
                                     hasFastPair: hasFastPair, lastSeen: Date())
        if nameCache.count > Self.nameCacheLimit,
           let evict = nameCache.min(by: { $0.value.lastSeen < $1.value.lastSeen })?.key {
            nameCache.removeValue(forKey: evict)
        }
        if changed || Date().timeIntervalSince(lastNameCacheSave) > Self.nameCacheSaveThrottle {
            lastNameCacheSave = Date()
            saveNameCache()
        }
    }

    private func setupLockAndVeilCallbacks() {
        guard !Self.isPreview else { return }

        // Let preview expiry hand off to real demand without a flicker gap.
        VeilWindowController.shared.realVeilDemand = { [weak self] in
            guard let self else { return (false, nil) }
            return (self.isVeilActive, self.veilReason)
        }

        // Wire veil unlock action -> escalate to macOS session lock
        VeilWindowController.shared.onUnlockRequested = { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingManualUnlock = true
                SessionLockManager.shared.lockScreen()
            }
        }

        // Wire veil debug button -> dismiss + pause veil briefly (DEBUG builds)
        VeilWindowController.shared.onDeveloperPauseRequested = { [weak self] in
            DispatchQueue.main.async {
                self?.pauseVeilForDeveloper()
            }
        }

        // Wire veil casual button -> lift once with no auth (snoozes one grace period)
        VeilWindowController.shared.onCasualDismissRequested = { [weak self] in
            DispatchQueue.main.async {
                self?.dismissVeilCasually()
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

        reader.onAdvertisement = { [weak self] id, name, rssi, companyID, hasFastPair in
            DispatchQueue.main.async {
                guard let self else { return }
                let key = id.uuidString
                let label = name.isEmpty ? "(unnamed)" : name
                // Vendor hints can vary packet to packet (advert vs. scan
                // response) — prefer the fresh value, keep the previous one
                // as fallback so the chip doesn't flicker.
                let previous = self.leAdverts[key]
                self.leAdverts[key] = AdvertSample(
                    name: label,
                    rssi: rssi,
                    at: Date(),
                    companyID: companyID ?? previous?.companyID,
                    hasFastPairService: hasFastPair || (previous?.hasFastPairService ?? false)
                )
                if !isUnnamed(label) {
                    self.cacheIdentity(id: key, name: label,
                                       companyID: companyID ?? previous?.companyID,
                                       hasFastPair: hasFastPair || (previous?.hasFastPairService ?? false))
                }

                let now = Date()
                self.leAdverts = Dictionary(uniqueKeysWithValues:
                    self.leAdverts.filter { pair in
                        let limit = (pair.key == self.pinnedLEID) ? 300.0 : 60.0
                        return now.timeIntervalSince(pair.value.at) < limit
                    }.sorted { $0.value.at > $1.value.at }.prefix(30).map { ($0.key, $0.value) })

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
                    // GATT names are highest-trust: always overwrite the cache.
                    self.cacheIdentity(id: key, name: name, companyID: s.companyID,
                                       hasFastPair: s.hasFastPairService)
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

        // 4. Manual protection pause (user toggle): dominate everything —
        // no veil, no grace accumulation, no state evaluation.
        if protectionPaused {
            awayDuration = 0
            isVeilActive = false
            veilReason = nil
            return
        }

        // 5. Calibration cooldown: pause veil activation so the user can walk
        // back to the desk after capturing the away boundary.
        if let until = calibrationPauseUntil {
            let pauseLeft = until.timeIntervalSince(now)
            if pauseLeft > 0 {
                calibrationPauseRemaining = pauseLeft
                awayDuration = 0
                isVeilActive = false
                veilReason = nil
                return
            } else {
                calibrationPauseUntil = nil
                calibrationPauseRemaining = nil
            }
        }

        // 6. Developer pause (DEBUG cover button): keep veil down while it runs.
        if let until = developerPauseUntil {
            let pauseLeft = until.timeIntervalSince(now)
            if pauseLeft > 0 {
                developerPauseRemaining = pauseLeft
                awayDuration = 0
                isVeilActive = false
                veilReason = nil
                return
            } else {
                developerPauseUntil = nil
                developerPauseRemaining = nil
            }
        }

        // 7. Check suppression window countdown
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

        // 8. Presence state evaluation
        evaluatePresenceState()

        // 9. Keep windows in sync (no-refire cases: onboarding opened
        // mid-veil, setup finished while away).
        reconcileVeilPresentation()
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
        // Unpinned samples (e.g. an in-flight GATT read landing after unpin)
        // must never repopulate the monitored signal — no pin, no signal.
        guard pinnedLEID != nil else { return }
        let now = Date()
        // Stale-EMA reset: if the previous sample is older than the freshness
        // horizon, the old smoothed value describes a different situation
        // (e.g. pre-walk-away). Reset so this sample passes straight through
        // instead of dragging stale history into the return decision.
        if let last = liveRSSIAt, now.timeIntervalSince(last) > 12.0 {
            signalProcessor.reset()
        }
        liveRSSI = rssi
        liveRSSIAt = now
        liveKind = kind
        smoothedRSSI = signalProcessor.process(rawRSSI: rssi)
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

        // Gone condition: No sightings for >= 2 * graceDelay.
        // Floor at 2s so Instant (0s) grace doesn't flag Gone immediately on every tick.
        let goneThreshold = max(2.0 * graceDelay, 2.0)
        if effectiveAge >= goneThreshold {
            presenceState = .gone
            // Latch: when covering on Gone is disabled, leave any existing
            // veil state untouched (a Far-established veil stays up).
            guard veilOnGoneEnabled else { return }
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
                veilReason = graceDelay <= 0 ? "Away from Mac (instant cover)" : "Away from Mac for \(Int(awayDuration))s"
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
                    veilReason = graceDelay <= 0 ? "Away from Mac (instant cover)" : "Away from Mac for \(Int(awayDuration))s"
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

    // MARK: - Onboarding Submit
    /// The one and only write path from onboarding (the "submit" button).
    /// Applies the draft atomically: thresholds persist via didSets, pinning
    /// persists the identifier and attaches the link (reset clears histories
    /// but never thresholds). Fresh pins always re-accumulate grace.
    /// Quitting before this runs leaves live state byte-identical.
    func commitOnboardingDraft(pinnedID: String?, veilOn: Double, veilOff: Double) {
        guard !Self.isPreview else { return }
        veilOnThreshold = veilOn
        veilOffThreshold = veilOff
        if let pinnedID { pinLEDevice(id: pinnedID) }
        UserDefaults.standard.set(true, forKey: "BRB.hasCompletedOnboarding")
        reconcileVeilPresentation()
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
        calibrationPauseUntil = nil
        calibrationPauseRemaining = nil
        developerPauseUntil = nil
        developerPauseRemaining = nil
    }

    // MARK: - Calibration Actions
    func calibrateAwayBoundary(currentRSSI: Double? = nil) {
        let reference = currentRSSI ?? smoothedRSSI ?? (liveRSSI != nil ? Double(liveRSSI!) : -80.0)
        veilOnThreshold = reference
        veilOffThreshold = reference + 6.0
        startCalibrationPause()
    }

    func resetThresholdsToDefault() {
        veilOnThreshold = -80.0
        veilOffThreshold = -74.0
        startCalibrationPause()
    }

    /// Pauses veil activation for a few seconds after calibration so the user
    /// can walk back to the desk without the cover firing immediately.
    private func startCalibrationPause() {
        calibrationPauseUntil = Date().addingTimeInterval(Self.calibrationPauseDuration)
        calibrationPauseRemaining = Self.calibrationPauseDuration
        awayDuration = 0
        isVeilActive = false
        veilReason = nil
    }

    // MARK: - Developer Pause (DEBUG cover button)
    /// Dismisses the veil and pauses all veil activation for `seconds`
    /// (default 15s) to ease development. Not persisted.
    func pauseVeilForDeveloper(seconds: TimeInterval = 15.0) {
        developerPauseUntil = Date().addingTimeInterval(seconds)
        developerPauseRemaining = seconds
        awayDuration = 0
        isVeilActive = false
        veilReason = nil
    }

    // MARK: - Casual Dismiss (Casual lock mode)
    /// Lifts the veil once with no auth. The grace timer restarts from zero,
    /// so if you're still away the veil returns after `graceDelay` (snooze).
    func dismissVeilCasually() {
        guard !Self.isPreview else { return }
        awayDuration = 0
        veilReason = nil
        if VeilWindowController.shared.isPreviewActive {
            // Hiding a preview: dismiss windows directly (no real veil exists).
            VeilWindowController.shared.dismissVeilInstant()
        } else {
            isVeilActive = false
        }
    }

    // MARK: - Suppression Trigger (Used by Veil Unlock Flow)
    func startSuppression() {
        // Instant (0) means no suppression window — resume normal evaluation.
        suppressionRemaining = suppressDuration > 0 ? suppressDuration : nil
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
            "AAAAAAAA-0000-0000-0000-000000000002": AdvertSample(name: "(unnamed)", rssi: -72, at: Date(), companyID: 0x004C),
        ]
        mock.pinnedLEID = "AAAAAAAA-0000-0000-0000-000000000001"
        return mock
    }
}
