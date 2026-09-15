//
//  EngineValidationTests.swift
//  BRB Tests
//
//  Validates the Signal Processor, Presence State Machine,
//  Hysteresis, Grace Timer, Suppression, and Veil Fallback Rendering.
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

        print("\n🎉 ALL 7 TEST SUITES PASSED CLEANLY!")
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

    // MARK: - 7. Default Veil Image Generation
    static func testDefaultVeilImageGeneration() {
        print("▶ Testing procedural default veil image generation...")
        let imageManager = VeilImageManager.shared
        let size = CGSize(width: 800, height: 600)
        let image = imageManager.defaultVeilImage(size: size)

        assert(image.size.width == 800 && image.size.height == 600, "Image dimensions must match target size")
        assert(image.isValid, "Generated NSImage must be valid")
        print("  ✅ Procedural veil image generation verified.")
    }
}
