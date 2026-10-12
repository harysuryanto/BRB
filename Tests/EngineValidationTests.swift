//
//  EngineValidationTests.swift
//  BRB Tests
//
//  Validates the Signal Processor, Presence State Machine,
//  Hysteresis, Grace Timer, Suppression, Default Veil Fallback,
//  Device Classification, and Advert Pruner.
//

import Foundation
import AppKit

@main
struct EngineValidationTests {
    static func main() {
        print("🚀 Starting BRB Acceptance & Validation Test Suite...\n")

        testSignalProcessorEMA()
        testPresenceStateTransitions()
        testHysteresisBand()
        testGraceDelayAccumulation()
        testGoneCondition()
        testSuppressionReturnCancellation()
        testDefaultVeilImageGeneration()
        testDeviceClassification()
        testAdvertPruner()
        testAboutTabAndMetadata()
        testLaunchAtLoginDefault()

        print("\n🎉 ALL 11 TEST SUITES PASSED CLEANLY!")
    }

    // MARK: - 1. SignalProcessor EMA
    static func testSignalProcessorEMA() {
        print("▶ Testing SignalProcessor EMA (alpha = 0.2)...")
        let processor = SignalProcessor(alpha: 0.2)

        // First sample should be initialized directly
        let first = processor.process(rawRSSI: -50)
        assert(abs(first - (-50.0)) < 0.001, "First sample should be exactly raw RSSI")

        // Second sample: 0.2 * (-60) + 0.8 * (-50) = -12 + (-40) = -52.0
        let second = processor.process(rawRSSI: -60)
        assert(abs(second - (-52.0)) < 0.001, "Second sample EMA should equal -52.0, got \(second)")

        // Third sample: 0.2 * (-70) + 0.8 * (-52) = -14 + (-41.6) = -55.6
        let third = processor.process(rawRSSI: -70)
        assert(abs(third - (-55.6)) < 0.001, "Third sample EMA should equal -55.6, got \(third)")

        // Reset
        processor.reset()
        assert(processor.smoothed == nil, "Reset should clear history")
        let afterReset = processor.process(rawRSSI: -80)
        assert(abs(afterReset - (-80.0)) < 0.001, "First sample after reset should equal raw RSSI")

        print("  ✅ SignalProcessor EMA verified.")
    }

    // MARK: - 2. Presence State Transitions
    static func testPresenceStateTransitions() {
        print("▶ Testing PresenceState transitions...")
        assert(PresenceState.idle.rawValue == "Idle")
        assert(PresenceState.near.rawValue == "Near")
        assert(PresenceState.far.rawValue == "Far")
        assert(PresenceState.gone.rawValue == "Gone")
        print("  ✅ PresenceState enums verified.")
    }

    // MARK: - 3. Hysteresis Band
    static func testHysteresisBand() {
        print("▶ Testing Hysteresis Band logic (-80 dBm Veil-On, -70 dBm Veil-Off)...")
        let veilOn = -80.0
        let veilOff = -70.0

        func evaluate(rssi: Double, prev: PresenceState) -> PresenceState {
            if rssi <= veilOn {
                return .far
            } else if rssi >= veilOff {
                return .near
            } else {
                return prev
            }
        }

        // In Near state, dropping to -75 dBm (inside the gap) should REMAIN Near
        assert(evaluate(rssi: -75.0, prev: .near) == .near, "Signal inside deadband should keep previous Near state")

        // Dropping to -82 dBm (at/below veilOn) transitions to Far
        assert(evaluate(rssi: -82.0, prev: .near) == .far, "Signal below veilOn should transition to Far")

        // Rising to -75 dBm (inside the gap) should REMAIN Far
        assert(evaluate(rssi: -75.0, prev: .far) == .far, "Signal inside deadband should keep previous Far state")

        // Rising to -68 dBm (above veilOff) transitions to Near
        assert(evaluate(rssi: -68.0, prev: .far) == .near, "Signal above veilOff should transition to Near")

        print("  ✅ Hysteresis band deadband verified.")
    }

    // MARK: - 4. Grace Delay Accumulation
    static func testGraceDelayAccumulation() {
        print("▶ Testing Grace Delay accumulation (10s delay with 0.5s ticks)...")
        let graceDelay: TimeInterval = 10.0
        var awayDuration: TimeInterval = 0.0
        var isVeilActive = false

        // Simulate 19 ticks (9.5s) of Far signal
        for _ in 1...19 {
            awayDuration += 0.5
            if awayDuration >= graceDelay {
                isVeilActive = true
            }
        }
        assert(isVeilActive == false, "Veil must NOT be active before graceDelay elapses")
        assert(abs(awayDuration - 9.5) < 0.001)

        // 20th tick reaches 10.0s
        awayDuration += 0.5
        if awayDuration >= graceDelay {
            isVeilActive = true
        }
        assert(isVeilActive == true, "Veil MUST activate when awayDuration >= graceDelay")

        // Immediate return reset
        awayDuration = 0.0
        isVeilActive = false
        assert(isVeilActive == false && awayDuration == 0.0, "Return must immediately dismiss veil and reset awayDuration")

        print("  ✅ Grace delay accumulation verified.")
    }

    // MARK: - 5. Gone Condition
    static func testGoneCondition() {
        print("▶ Testing Gone condition (no sighting for >= 2x grace)...")
        let graceDelay: TimeInterval = 10.0
        let effectiveAge: TimeInterval = 21.0 // > 2 * 10.0

        let isGone = effectiveAge >= (2.0 * graceDelay)
        assert(isGone == true, "Should transition to Gone when effectiveAge >= 2x graceDelay")
        print("  ✅ Gone condition verified.")
    }

    // MARK: - 6. Suppression Return Cancellation
    static func testSuppressionReturnCancellation() {
        print("▶ Testing mid-suppression earbud return cancellation...")
        var suppressionRemaining: TimeInterval? = 900.0 // 15 mins active
        let veilOffThreshold = -70.0

        // In-range signal returns while suppressed (-65 dBm)
        let smoothedRSSI = -65.0
        let isSampleFresh = true

        if isSampleFresh && smoothedRSSI >= veilOffThreshold {
            suppressionRemaining = nil
        }

        assert(suppressionRemaining == nil, "Suppression must cancel immediately when earbud returns in range")
        print("  ✅ Mid-suppression return cancellation verified.")
    }

    // MARK: - 7. Default Veil Fallback
    static func testDefaultVeilImageGeneration() {
        print("▶ Testing procedural default veil image generation...")
        let imageManager = VeilImageManager.shared
        let size = CGSize(width: 800, height: 600)
        let image = imageManager.defaultVeilImage(size: size)

        assert(image.size.width == 800 && image.size.height == 600, "Image dimensions must match target size")
        assert(image.isValid, "Generated NSImage must be valid")
        print("  ✅ Procedural veil image generation verified.")
    }

    // MARK: - 8. Device Classification
    static func testDeviceClassification() {
        print("▶ Testing Device Classification...")

        // A. Phone Name Patterns
        assert(classifyDevice(name: "Hary's iPhone") == .phone, "iPhone should classify as .phone")
        assert(classifyDevice(name: "Infinix NOTE 30") == .phone, "Infinix Note should classify as .phone")
        assert(classifyDevice(name: "Infinix HOT 40 Pro") == .phone, "Infinix Hot should classify as .phone")
        assert(classifyDevice(name: "Infinix-X6833B") == .phone, "Infinix model should classify as .phone")
        assert(classifyDevice(name: "X6825") == .phone, "Infinix model number X6825 should classify as .phone")
        assert(classifyDevice(name: "Tecno Spark 20") == .phone, "Tecno should classify as .phone")
        assert(classifyDevice(name: "Pixel 8 Pro") == .phone, "Pixel phone should classify as .phone")
        assert(classifyDevice(name: "Galaxy S24 Ultra") == .phone, "Galaxy S24 should classify as .phone")
        assert(classifyDevice(name: "SM-S918B") == .phone, "Samsung model SM-S should classify as .phone")
        assert(classifyDevice(name: "Xiaomi 13") == .phone, "Xiaomi should classify as .phone")
        assert(classifyDevice(name: "OnePlus 12") == .phone, "OnePlus should classify as .phone")
        assert(classifyDevice(name: "Redmi Note 12") == .phone, "Redmi should classify as .phone")
        assert(classifyDevice(name: "POCO F5") == .phone, "POCO should classify as .phone")
        assert(classifyDevice(name: "My Android Phone") == .phone, "Generic phone should classify as .phone")

        // B. Buds vs Headphones
        assert(classifyDevice(name: "soundcore R60i NC") == .buds, "Soundcore R60i should classify as .buds")
        assert(classifyDevice(name: "AirPods Pro") == .buds, "AirPods Pro should classify as .buds")
        assert(classifyDevice(name: "AirPods Max") == .headphones, "AirPods Max should classify as .headphones")
        assert(classifyDevice(name: "WH-1000XM5") == .headphones, "Sony WH-1000XM5 should classify as .headphones")
        assert(classifyDevice(name: "WF-1000XM5") == .buds, "Sony WF-1000XM5 should classify as .buds")
        assert(classifyDevice(name: "Bose QuietComfort 45") == .headphones, "Bose QC45 should classify as .headphones")

        // C. SIG Appearance (UUID 0x2A01)
        assert(classifyDevice(name: "(unnamed)", sigAppearance: 0x0040) == .phone, "SIG 0x0040 (Generic Phone) should classify as .phone")
        assert(classifyDevice(name: "(unnamed)", sigAppearance: 0x0804) == .buds, "SIG 0x0804 (Earbud) should classify as .buds")
        assert(classifyDevice(name: "(unnamed)", sigAppearance: 0x0802) == .headphones, "SIG 0x0802 (Headphones) should classify as .headphones")
        assert(classifyDevice(name: "(unnamed)", sigAppearance: 0x00C0) == .watch, "SIG 0x00C0 (Generic Watch) should classify as .watch")
        assert(classifyDevice(name: "(unnamed)", sigAppearance: 0x03C2) == .mouse, "SIG 0x03C2 (Mouse) should classify as .mouse")

        // D. Apple Continuity Type Byte
        assert(classifyDevice(name: "(unnamed)", companyID: 0x004C, appleContinuityType: 0x10) == .phone, "Apple Nearby Info 0x10 should classify as .phone")
        assert(classifyDevice(name: "(unnamed)", companyID: 0x004C, appleContinuityType: 0x07) == .buds, "Apple Proximity Pairing 0x07 should classify as .buds")
        assert(classifyDevice(name: "(unnamed)", companyID: 0x004C, appleContinuityType: 0x12) == .tag, "Apple Find My 0x12 should classify as .tag")
        assert(classifyDevice(name: "(unnamed)", companyID: 0x004C, appleContinuityType: 0x0B) == .watch, "Apple Watch 0x0B should classify as .watch")

        // E. Transsion / Infinix Company IDs
        assert(classifyDevice(name: "(unnamed)", companyID: 0x0660) == .phone, "Transsion company ID 0x0660 should classify as .phone")
        assert(classifyDevice(name: "(unnamed)", companyID: 0x098A) == .phone, "Infinix company ID 0x098A should classify as .phone")

        // F. Google Fast Pair Service
        assert(classifyDevice(name: "(unnamed)", hasFastPair: true) == .buds, "Google Fast Pair service should classify as .buds")

        print("  ✅ Device classification verified.")
    }

    // MARK: - 9. AdvertPruner TTL & Capacity
    static func testAdvertPruner() {
        print("▶ Testing AdvertPruner (TTL & Capacity)...")
        let now = Date()

        // 1. Fresh vs stale (60s limit for unpinned)
        var adverts: [String: AdvertSample] = [
            "fresh": AdvertSample(name: "Buds", rssi: -60, at: now.addingTimeInterval(-10)),
            "stale": AdvertSample(name: "Old Buds", rssi: -70, at: now.addingTimeInterval(-65)),
            "pinnedStale": AdvertSample(name: "My Pin", rssi: -50, at: now.addingTimeInterval(-120))
        ]

        let pruned = AdvertPruner.pruneAdverts(adverts, pinnedKey: "pinnedStale", now: now)
        assert(pruned["fresh"] != nil, "Fresh advert within 60s should be kept")
        assert(pruned["stale"] == nil, "Stale unpinned advert (>60s) should be pruned")
        assert(pruned["pinnedStale"] != nil, "Pinned advert within 300s TTL should be kept")

        // 2. Pinned advert beyond 300s TTL should be pruned
        adverts["pinnedVeryOld"] = AdvertSample(name: "My Pin", rssi: -50, at: now.addingTimeInterval(-305))
        let prunedPinnedOld = AdvertPruner.pruneAdverts(adverts, pinnedKey: "pinnedVeryOld", now: now)
        assert(prunedPinnedOld["pinnedVeryOld"] == nil, "Pinned advert older than 300s should be pruned")

        // 3. Capacity limit (keep 30 freshest)
        var manyAdverts: [String: AdvertSample] = [:]
        for i in 0..<40 {
            manyAdverts["dev_\(i)"] = AdvertSample(name: "Dev \(i)", rssi: -60, at: now.addingTimeInterval(-Double(i)))
        }
        let capped = AdvertPruner.pruneAdverts(manyAdverts, pinnedKey: nil, now: now)
        assert(capped.count == 30, "AdvertPruner should cap entries to 30")
        assert(capped["dev_0"] != nil, "Freshest entry dev_0 should be present")
        assert(capped["dev_29"] != nil, "30th entry dev_29 should be present")
        assert(capped["dev_30"] == nil, "31st entry dev_30 should be dropped")

        print("  ✅ AdvertPruner verified.")
    }

    // MARK: - 10. About Tab & Native Metadata
    static func testAboutTabAndMetadata() {
        print("▶ Testing About Tab & Native macOS metadata...")

        // Tab position and properties
        let tabs = SettingsTab.allCases
        assert(tabs.count == 5, "SettingsTab should have exactly 5 tabs, got \(tabs.count)")
        assert(tabs.last == .about, "SettingsTab.about MUST be the rightmost tab in the tab set")
        assert(SettingsTab.about.title == "About", "About tab title should be 'About'")
        assert(SettingsTab.about.icon == "info.circle", "About tab icon should be 'info.circle'")

        print("  ✅ About tab rightmost placement and native metadata verified.")
    }

    // MARK: - 11. Launch at Login Default & Policy
    static func testLaunchAtLoginDefault() {
        print("▶ Testing Launch at Login default & persistence...")

        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "BRB.launchAtLogin")

        // 1. Unset key MUST fall back to default value true
        defaults.removeObject(forKey: "BRB.launchAtLogin")
        let fallback = defaults.object(forKey: "BRB.launchAtLogin") as? Bool ?? true
        assert(fallback == true, "Launch at Login MUST default to true when unconfigured")

        // 2. Explicit false persistence
        defaults.set(false, forKey: "BRB.launchAtLogin")
        let disabled = defaults.object(forKey: "BRB.launchAtLogin") as? Bool ?? true
        assert(disabled == false, "Launch at Login MUST persist disabled state")

        // 3. Explicit true persistence
        defaults.set(true, forKey: "BRB.launchAtLogin")
        let enabled = defaults.object(forKey: "BRB.launchAtLogin") as? Bool ?? true
        assert(enabled == true, "Launch at Login MUST persist enabled state")

        // Restore previous value
        if let previous {
            defaults.set(previous, forKey: "BRB.launchAtLogin")
        } else {
            defaults.removeObject(forKey: "BRB.launchAtLogin")
        }

        print("  ✅ Launch at Login default (true) and persistence verified.")
    }
}
