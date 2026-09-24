//
//  SignalProcessor.swift
//  BRB
//
//  Filters and smooths raw RSSI readings using Exponential Moving Average (EMA).
//

import Foundation

final class SignalProcessor {
    /// Global default smoothing factor (EMA α) used across the app (engine & draft filters).
    /// α = 0.8: fast-tracking (80% weight on new packet, 20% on history).
    static let defaultAlpha: Double = 0.8

    let alpha: Double
    private(set) var smoothed: Double?

    init(alpha: Double = SignalProcessor.defaultAlpha) {
        self.alpha = alpha
    }

    /// Feeds a new raw RSSI reading into the filter and returns the updated smoothed value.
    @discardableResult
    func process(rawRSSI: Int) -> Double {
        let val = Double(rawRSSI)
        if let current = smoothed {
            let next = (alpha * val) + ((1.0 - alpha) * current)
            smoothed = next
            return next
        } else {
            smoothed = val
            return val
        }
    }

    /// Resets smoothed history (e.g. when changing monitored device).
    func reset() {
        smoothed = nil
    }
}
