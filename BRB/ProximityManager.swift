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
import IOBluetooth
import os

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

/// SIG-verified manufacturer company IDs for audio/wearable/mobile vendors.
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
    case 0x02B0, 0x0742, 0x0499: return "Anker"
    case 0x004F: return "Logitech"
    case 0x038F: return "Xiaomi"
    case 0x0735, 0x0853: return "OnePlus"
    case 0x0548: return "OPPO"
    case 0x063B: return "Realme"
    case 0x0746: return "Vivo"
    case 0x0660: return "Transsion"
    case 0x098A: return "Infinix"
    case 0x08A8: return "Tecno"
    case 0x027D: return "Huawei"
    case 0x0171: return "Amazon"
    case 0x0986: return "Nothing"
    case 0x000F: return "Broadcom"
    case 0x01D0: return "ZTE"
    case 0x0286: return "Asus"
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

    /// True while a UI surface showing the nearby-device picker is visible
    /// (Device tab in Settings, or onboarding's device-selection step).
    /// Drives whether BLE scanning runs at all when nothing is pinned yet.
    var nearbyListEnabled: Bool = false {
        didSet {
            guard pinnedKey == nil else { return }  // pinned device always keeps scanning
            if nearbyListEnabled {
                leReader?.start(targetName: "", pinnedID: nil)
            } else {
                leReader?.stop()
            }
        }
    }

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
        var sigAppearance: UInt16? = nil
    }

    private static let nameCacheKey = "BRB.deviceIdentities"
    private static let nameCacheLimit = 30
    private static let nameCacheTTL: TimeInterval = 30 * 86400 // 30 days
    private static let nameCacheSaveThrottle: TimeInterval = 3600 // 1 hour

    /// Identifier → last-known real identity. Session working copy of the
    /// persisted cache; views never read it directly (see resolvedName).
    private var nameCache: [String: CachedDevice] = [:]
    private var lastNameCacheSave = Date.distantPast

    // MARK: - Pinned Device (stable-keyed; UUIDs rotate)
    /// Stable pin key: normalized device name. LE peripheral identifiers
    /// rotate across case cycles on unpaired buds, so the pin follows the
    /// name; the current identifier is kept only as a locator hint.
    var pinnedKey: String? {
        didSet {
            if let pinnedKey {
                UserDefaults.standard.set(pinnedKey, forKey: "BRB.pinnedKey")
            } else {
                UserDefaults.standard.removeObject(forKey: "BRB.pinnedKey")
            }
        }
    }
    /// Latest locator identifier for the pin (ephemeral; refreshed on every
    /// same-name sighting). Preferred while visible, never trusted alone.
    var pinnedUUIDHint: String? {
        didSet {
            if let pinnedUUIDHint {
                UserDefaults.standard.set(pinnedUUIDHint, forKey: "BRB.pinnedUUIDHint")
            } else {
                UserDefaults.standard.removeObject(forKey: "BRB.pinnedUUIDHint")
            }
        }
    }
    /// Last silent re-link (session-only): surfaced briefly in the Device tab
    /// so rotations are visible, never silent-mysterious.
    var lastRelink: (name: String, at: Date)? = nil
    private var lastReaderAim = Date.distantPast

    private var pinnedUUID: UUID? {
        guard let pinnedUUIDHint else { return nil }
        return UUID(uuidString: pinnedUUIDHint)
    }

    /// Normalized stable identity key for a name (nil for placeholders).
    /// The key — not the identifier — is what survives case cycles.
    static func stableKey(forName name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !n.isEmpty, !n.contains("(unnamed)") else { return nil }
        return n
    }

    /// One physical device: all same-name sightings collapsed, so a bud is a
    /// single row even as its identifier rotates underneath.
    struct DeviceGroup {
        var key: String // stableKey, or "uuid:<uuid>" for unnamed singletons
        var name: String // title-ready, never blank
        var art: String // real name or "" — drives category + tint gate
        var uuids: [String] // locator identifiers, latest-first
        var sample: AdvertSample // freshest sighting (RSSI/age)
        var chip: String? // vendor / Fast Pair (unnamed only)
        var isNamed: Bool
        var category: DeviceCategory
        var locator: String { uuids.first ?? "" }
    }

    /// Scanner/monitor model, grouped by stable key. Named A–Z, unnamed last.
    var deviceGroups: [DeviceGroup] {
        var buckets: [String: [String]] = [:]
        for (uuid, s) in leAdverts {
            let k = Self.stableKey(forName: s.name) ?? "uuid:" + uuid
            buckets[k, default: []].append(uuid)
        }
        var groups: [DeviceGroup] = []
        for (key, uuids) in buckets {
            let ordered = uuids.sorted {
                (leAdverts[$0]?.at ?? .distantPast) > (leAdverts[$1]?.at ?? .distantPast)
            }
            guard let first = ordered.first, let fresh = leAdverts[first] else { continue }
            let named = !key.hasPrefix("uuid:")
            var real: String? = nil
            for u in ordered {
                if let n = leAdverts[u]?.name, !isUnnamed(n) { real = n; break }
            }
            let cached: String? = {
                guard let c = self.nameCache[key]?.name, !isUnnamed(c) else { return nil }
                return c
            }()
            let title = real ?? cached ?? (named ? key : displayTitle(for: first))
            let art = real ?? cached ?? ""
            let mergedCompany: UInt16? = ordered.lazy.compactMap({ self.leAdverts[$0]?.companyID }).first
                ?? self.nameCache[key]?.companyID
            let fp = ordered.contains(where: { self.leAdverts[$0]?.hasFastPairService == true })
                || (self.nameCache[key]?.hasFastPair ?? false)
            let contType: UInt8? = ordered.lazy.compactMap({ self.leAdverts[$0]?.appleContinuityType }).first
            let appearance: UInt16? = ordered.lazy.compactMap({ self.leAdverts[$0]?.sigAppearance }).first
                ?? self.nameCache[key]?.sigAppearance
            let category = classifyDevice(
                name: art.isEmpty ? title : art,
                companyID: mergedCompany,
                appleContinuityType: contType,
                sigAppearance: appearance,
                hasFastPair: fp
            )
            var chip: String? = nil
            if !named {
                chip = vendorName(for: mergedCompany) ?? (fp ? "Fast Pair" : nil)
            }
            groups.append(DeviceGroup(key: key, name: title, art: art, uuids: ordered,
                                      sample: fresh, chip: chip, isNamed: named,
                                      category: category))
        }
        return groups.sorted {
            if $0.isNamed != $1.isNamed { return $0.isNamed }
            if $0.isNamed {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return ($0.uuids.first ?? "") < ($1.uuids.first ?? "")
        }
    }

    func group(forKey key: String) -> DeviceGroup? {
        deviceGroups.first { $0.key == key }
    }

    /// Identifiers with a name-resolution connection in flight (for UI).
    var resolvingIDs: Set<String> {
        guard let leReader else { return [] }
        return Set(leReader.resolvingIdentifiers.map(\.uuidString))
    }

    /// Display title for a stable key. Never blank while the key is known.
    /// Tier: live group → Classic bond record → name cache → placeholder.
    /// The bond tier is what survives rotation + namelessness for paired buds.
    func displayName(forKey key: String) -> String {
        if let g = group(forKey: key) { return g.name }
        if let b = bond(forKey: key) { return b.name }
        if let cached = nameCache[key]?.name, !isUnnamed(cached) { return cached }
        return key.hasPrefix("uuid:") ? "Unknown" : key
    }

    /// Raw name for artwork categorization. Same precedence as the title.
    func artName(forKey key: String) -> String {
        if let g = group(forKey: key) { return g.art }
        if let cached = nameCache[key]?.name, !isUnnamed(cached) { return cached }
        return ""
    }

    /// Device category for artwork & icons. Live group -> cache -> fallback.
    func deviceCategory(forKey key: String) -> DeviceCategory {
        if let g = group(forKey: key) { return g.category }
        let name = artName(forKey: key)
        let cached = nameCache[key]
        return classifyDevice(
            name: name,
            companyID: cached?.companyID,
            sigAppearance: cached?.sigAppearance
        )
    }

    /// Display title for the pin, or nil when unpinned. Never blank while
    /// pinned (live → cached → placeholder chain above).
    var pinnedDisplayName: String? {
        guard let pinnedKey else { return nil }
        return displayName(forKey: pinnedKey)
    }

    /// True when the monitored signal is live but the pin has no advert entry
    /// at all (connected buds stop advertising — the "number without a row"
    /// state). A stale-but-visible row already explains itself, so only the
    /// fully-absent case reports.
    var isTrackingWithoutAdverts: Bool {
        guard let pkey = pinnedKey, smoothedRSSI != nil else { return false }
        return group(forKey: pkey) == nil
    }

    /// Whether a sighting belongs to the pin. The UUID hint wins while
    /// visible; otherwise same stable name with vendor compatibility — the
    /// name arm is what survives identifier rotation.
    func isPinnedSight(uuid: String, name: String, companyID: UInt16?) -> Bool {
        guard let pinnedKey else { return false }
        if uuid == pinnedUUIDHint { return true }
        guard Self.stableKey(forName: name) == pinnedKey else { return false }
        if let a = companyID, let b = pinnedVendorID, a != b { return false }
        return true
    }

    /// Current pin vendor hint (live group, else cache), for adopt sanity.
    private var pinnedVendorID: UInt16? {
        guard let pinnedKey, let g = group(forKey: pinnedKey) else { return nil }
        for u in g.uuids {
            if let c = leAdverts[u]?.companyID { return c }
        }
        return nameCache[pinnedKey]?.companyID
    }

    /// Silent re-link: follow the pin across identifier rotation. The hint
    /// and note update on every adopt; the GATT re-aim is throttled so two
    /// same-named devices alternating packets can't hot-loop the reader
    /// (the advert path keeps presence live regardless).
    func adoptLocator(uuid: String) {
        guard let pinnedKey, uuid != pinnedUUIDHint else { return }
        pinnedUUIDHint = uuid
        lastRelink = (name: displayName(forKey: pinnedKey), at: Date())
        if Date().timeIntervalSince(lastReaderAim) > 30 {
            lastReaderAim = Date()
            leReader?.stop()
            leReader?.start(targetName: Self.readerTargetName(forKey: pinnedKey),
                            pinnedID: UUID(uuidString: uuid))
        }
    }

    /// Reader name-match target for a key. Unnamed singleton keys ("uuid:…")
    /// carry no name — id-only matching within the cycle.
    static func readerTargetName(forKey key: String) -> String {
        key.hasPrefix("uuid:") ? "" : key
    }

    /// Prunes stale entries (60s TTL, 300s for the pinned key), keeps only the
    /// freshest 30. Pure function — delegates to AdvertPruner.
    static func pruneAdverts(_ adverts: [String: AdvertSample], pinnedKey: String?, now: Date) -> [String: AdvertSample] {
        AdvertPruner.pruneAdverts(adverts, pinnedKey: pinnedKey, now: now)
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
    private var advertPruneTickCounter: Int = 0
    private var monitoringStartedAt: Date = Date()
    // α=0.8: light touch (history weight 0.2, a quarter of the old 0.8) —
    // tracks fast, leans on the hysteresis band + grace timer for stability.
    private let signalProcessor = SignalProcessor(alpha: 0.8)

    private static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
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
        let cache = Self.loadNameCache()
        // One-time: re-key legacy UUID-keyed entries by embedded real names.
        var rekeyed: [String: CachedDevice] = [:]
        for (k, v) in cache {
            let nk = Self.stableKey(forName: v.name) ?? k
            if let e = rekeyed[nk] {
                let newest = v.lastSeen >= e.lastSeen ? v : e
                let older = v.lastSeen >= e.lastSeen ? e : v
                rekeyed[nk] = CachedDevice(name: newest.name,
                                           companyID: newest.companyID ?? older.companyID,
                                           hasFastPair: newest.hasFastPair || older.hasFastPair,
                                           lastSeen: newest.lastSeen,
                                           sigAppearance: newest.sigAppearance ?? older.sigAppearance)
            } else {
                rekeyed[nk] = v
            }
        }
        self.nameCache = rekeyed
        // One-time: migrate a legacy UUID pin via the (pre-rekey) cache name.
        // didSet doesn't fire in init, so the migrated values persist explicitly.
        self.pinnedKey = defaults.string(forKey: "BRB.pinnedKey")
        self.pinnedUUIDHint = defaults.string(forKey: "BRB.pinnedUUIDHint")
        if self.pinnedKey == nil, let legacy = defaults.string(forKey: "BRB.pinnedLEID") {
            if let oldName = cache[legacy]?.name, let k = Self.stableKey(forName: oldName) {
                self.pinnedKey = k
                self.pinnedUUIDHint = legacy
                defaults.set(k, forKey: "BRB.pinnedKey")
                defaults.set(legacy, forKey: "BRB.pinnedUUIDHint")
            }
            defaults.removeObject(forKey: "BRB.pinnedLEID")
        }

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

    /// Upserts a real (never placeholder) identity sighting, keyed by stable
    /// name (falling back to the identifier for unnamed singletons). Disk
    /// writes happen on identity change, otherwise throttled — duplicates-mode
    /// traffic (many packets/sec) must never hammer disk, while lastSeen
    /// still advances often enough to keep daily-seen entries alive.
    /// Evicts oldest-seen beyond the cap.
    private func cacheIdentity(id: String, name: String, companyID: UInt16?, hasFastPair: Bool, sigAppearance: UInt16? = nil) {
        guard !isUnnamed(name) else { return }
        let ck = Self.stableKey(forName: name) ?? id
        let previous = nameCache[ck]
        let app = sigAppearance ?? previous?.sigAppearance
        let changed = previous?.name != name || previous?.companyID != companyID
            || previous?.hasFastPair != hasFastPair || previous?.sigAppearance != app
        nameCache[ck] = CachedDevice(name: name, companyID: companyID,
                                     hasFastPair: hasFastPair, lastSeen: Date(),
                                     sigAppearance: app)
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
                }
            }
        }
    }

    // MARK: - Monitoring Lifecycle
    func startMonitoring() {
        guard !Self.isPreview else { return }
        stopMonitoring()
        monitoringStartedAt = Date()
        refreshClassicBonds()
        startLEEngine()
    }

    private func startLEEngine() {
        let reader = LERSSIReader()
        leReader = reader

        reader.onState = { [weak self] state in
            DispatchQueue.main.async {
                guard let self else { return }
                self.bluetoothGranted = (state == .poweredOn)
                self.bluetoothPermission = (state == .poweredOn) ? "Granted" : "LE unavailable"
            }
        }

        reader.onRSSI = { [weak self] value in
            DispatchQueue.main.async {
                guard let self else { return }
                self.recordSample(rssi: value, kind: "GATT")
            }
        }

        reader.onAdvertisement = { [weak self] id, name, rssi, companyID, hasFastPair, continuityType in
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
                    hasFastPairService: hasFastPair || (previous?.hasFastPairService ?? false),
                    appleContinuityType: continuityType ?? previous?.appleContinuityType,
                    sigAppearance: previous?.sigAppearance
                )
                if !isUnnamed(label) {
                    self.cacheIdentity(id: key, name: label,
                                       companyID: companyID ?? previous?.companyID,
                                       hasFastPair: hasFastPair || (previous?.hasFastPairService ?? false),
                                       sigAppearance: previous?.sigAppearance)
                }

                // A pinned advertisement feeds the live sample stream even without a
                // held GATT link. Name matching (not the identifier) is what survives
                // rotation — a fresh locator is adopted silently (see adoptLocator).
                if self.isPinnedSight(uuid: key, name: label, companyID: companyID ?? previous?.companyID) {
                    if key != self.pinnedUUIDHint { self.adoptLocator(uuid: key) }
                    self.recordSample(rssi: rssi, kind: "LE-adv")
                }
            }
        }

        reader.onAppearanceResolved = { [weak self] id, appearance in
            DispatchQueue.main.async {
                guard let self else { return }
                let key = id.uuidString
                if var s = self.leAdverts[key] {
                    s.sigAppearance = appearance
                    self.leAdverts[key] = s
                }
                let cacheKey = (self.leAdverts[key].flatMap { Self.stableKey(forName: $0.name) }) ?? key
                if let c = self.nameCache[cacheKey] {
                    self.nameCache[cacheKey] = CachedDevice(
                        name: c.name,
                        companyID: c.companyID,
                        hasFastPair: c.hasFastPair,
                        lastSeen: Date(),
                        sigAppearance: appearance
                    )
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
                                       hasFastPair: s.hasFastPairService,
                                       sigAppearance: s.sigAppearance)
                    // A resolved name can complete the pin across rotation —
                    // adopt without waiting for the next advert.
                    if self.isPinnedSight(uuid: key, name: name, companyID: s.companyID) {
                        if key != self.pinnedUUIDHint { self.adoptLocator(uuid: key) }
                    }
                }
            }
        }

        reader.trackAllAdvertisements = { [weak self] in self?.nearbyListEnabled ?? false }

        reader.onStatus = { [weak self] status in
            DispatchQueue.main.async { self?.leStatus = status }
        }

        if pinnedKey != nil || nearbyListEnabled {
            let target = pinnedKey.map { Self.readerTargetName(forKey: $0) } ?? ""
            reader.start(targetName: target, pinnedID: pinnedUUID)
        }

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

    // MARK: - Classic Bond Records (stable identity source)
    /// One Classic paired device: stable MAC + user-visible name, straight
    /// from the OS bond database (the same record system Settings shows).
    /// Refreshed at monitoring start and on pin; the bond DB is the
    /// persistence, so nothing here is written to disk. Enumeration runs
    /// off-main (pairedDevices() can block on TCC) and logs to the unified
    /// log — query with:
    /// `log show --predicate 'subsystem == "com.harysuryanto.brb"' --last 1d`.
    struct ClassicBond {
        var name: String
        var address: String
        var connected: Bool
    }

    /// Current Classic bond snapshot. Mutated on main; @Observable fans out.
    var classicBonds: [ClassicBond] = []

    /// Bond whose name matches a stable key (case-insensitive). Named keys
    /// only — uuid-singleton keys can never match a bond record.
    func bond(forKey key: String) -> ClassicBond? {
        guard !key.hasPrefix("uuid:") else { return nil }
        return classicBonds.first { Self.stableKey(forName: $0.name) == key }
    }

    private func refreshClassicBonds() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let log = Logger(subsystem: "com.harysuryanto.brb", category: "bond")
            guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
                log.warning("bond-spike: pairedDevices() returned nil (possible TCC denial)")
                return
            }
            let bonds = paired.map {
                ClassicBond(name: $0.name ?? "(no name)",
                            address: $0.addressString ?? "?",
                            connected: $0.isConnected())
            }
            log.info("bond-spike: paired count: \(bonds.count, privacy: .public)")
            for b in bonds {
                log.info("bond-spike: \(b.name, privacy: .public) @ \(b.address, privacy: .public) [\(b.connected ? "connected" : "not-connected", privacy: .public)]")
            }
            DispatchQueue.main.async { self?.classicBonds = bonds }
        }
    }

    // MARK: - Engine Tick (0.5s interval)
    private func engineTick() {
        ticks += 1

        // 1. Request GATT read if link is connected; sweep stale resolutions
        leReader?.requestRead()
        leReader?.sweepResolutions()

        // 2. Scan hygiene restart every ~60s (120 ticks * 0.5s)
        if ticks % 120 == 0 {
            leReader?.restartScan()
        }

        // 2b. Prune stale adverts at ~1Hz (every 2nd tick of 0.5s timer)
        advertPruneTickCounter += 1
        if advertPruneTickCounter >= 2 {
            advertPruneTickCounter = 0
            let pruned = Self.pruneAdverts(leAdverts, pinnedKey: pinnedUUIDHint, now: Date())
            if pruned.keys != leAdverts.keys || pruned.count != leAdverts.count {
                leAdverts = pruned
            }
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
        guard pinnedKey != nil else { return }
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
        guard pinnedKey != nil else {
            presenceState = .idle
            awayDuration = 0
            isVeilActive = false
            veilReason = nil
            return
        }

        // Pinned but no sample from the current pin yet (e.g. just switched
        // devices): absence of evidence is not evidence of absence — stay
        // idle with the veil down until the first sample arrives. Without
        // this, the Gone branch below fires on the huge fallback age
        // (time-since-launch) and flashes the veil on every switch.
        guard liveRSSIAt != nil else {
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
    func pinLEDevice(key: String, uuid: String) {
        guard !Self.isPreview else { return }
        refreshClassicBonds()
        if let hint = UUID(uuidString: uuid) { leReader?.clearResolutionAttempt(hint) }
        pinnedKey = key
        pinnedUUIDHint = uuid
        lastRelink = nil
        lastReaderAim = Date()
        resetStateAndFilter()
        leReader?.stop()
        leReader?.start(targetName: Self.readerTargetName(forKey: key), pinnedID: UUID(uuidString: uuid))
    }

    func unpinLEDevice() {
        pinnedKey = nil
        pinnedUUIDHint = nil
        lastRelink = nil
        resetStateAndFilter()
        leReader?.stop()
        leReader?.start(targetName: "", pinnedID: nil)
    }

    // MARK: - Onboarding Submit
    /// The one and only write path from onboarding (the "submit" button).
    /// Applies the draft atomically: thresholds persist via didSets, pinning
    /// persists the stable key plus the current locator (reset clears histories
    /// but never thresholds). Fresh pins always re-accumulate grace.
    /// Quitting before this runs leaves live state byte-identical.
    func commitOnboardingDraft(pinnedKey: String?, uuidHint: String?, veilOn: Double, veilOff: Double) {
        guard !Self.isPreview else { return }
        veilOnThreshold = veilOn
        veilOffThreshold = veilOff
        if let pinnedKey { pinLEDevice(key: pinnedKey, uuid: uuidHint ?? "") }
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
            "AAAAAAAA-0000-0000-0000-000000000002": AdvertSample(name: "(unnamed)", rssi: -72, at: Date(), companyID: 0x004C, appleContinuityType: 0x10),
        ]
        mock.pinnedKey = "airpods pro"
        mock.pinnedUUIDHint = "AAAAAAAA-0000-0000-0000-000000000001"
        return mock
    }
}
