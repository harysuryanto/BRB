# Changelog

All notable changes to BRB are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.1] - 2026-10-12

### Fixed
- **Resolved severe memory leak on device selection:** Removed `.contentTransition(.numericText())` and `.animation()` from the live RSSI readout in `MenuBarPopoverView`. High-frequency BLE packet arrivals were interrupting in-flight glyph morph transitions, causing SwiftUI and CoreAnimation to accumulate unreleased layer snapshots and driving memory consumption over 600 MB. Memory usage now stays flat at ~55–60 MB during active monitoring.

### Documentation
- Updated README documentation, screenshots, and DMG distribution references.

---

## [1.0.0] - 2026-10-12

Initial public release of **BRB (Be Right Back)** — native macOS automatic screen cover and lock based on Bluetooth proximity.

### Features
- **Proximity Monitoring:**
  - CoreBluetooth LE scanning with duplicates-mode streaming for responsive proximity detection.
  - Exponential Moving Average (EMA) signal smoothing ($\alpha = 0.8$) to filter high-frequency RSSI jitter.
  - Dual-threshold hysteresis band (Veil-On / Veil-Off) to eliminate edge flicker.
  - Configurable Grace Delay timer and Post-Unlock Suppression window.
  - Device identity retention and auto-relink across Bluetooth LE peripheral identifier rotations.

- **Screen Cover (Veil) & Security:**
  - Multi-display borderless fullscreen cover windows across all active screens.
  - Procedural dark gradient wordmark fallback or custom user cover image via security-scoped bookmarks.
  - Animated GIF playback support with per-frame delay timing.
  - Secure lock mode escalating to macOS login screen (`SACLockScreenImmediate` / `CGSession`).
  - Casual lock mode with temporary dismiss without requiring re-authentication.
  - Fail-secure protection: locks macOS screen on unexpected app termination while away.

- **Interface & Control Center:**
  - Native SwiftUI Control Center with 5 dedicated settings tabs (Device, Screen Cover, Calibration, Timers & Security, About).
  - TWS-style card grid for nearby and bonded Bluetooth LE devices.
  - Interactive live signal range meter and away boundary calibration.
  - Device classification by Bluetooth SIG Appearance, Apple Continuity signatures, Google Fast Pair, and vendor company IDs.
  - Menu bar status item and rich popover with timed protection pause presets (15m, 1h, 3h, Indefinite).
  - First-launch 3-step onboarding wizard.
  - Launch at Login preference managed through `SMAppService`.
