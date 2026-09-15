# BRB — Project TODO & Roadmap

Tracking implementation progress against the [Product Requirements Document](PRD.md).

---

## 📋 Status Overview

- [x] **Phase 0: Project Setup & BLE Foundation**
- [x] **Phase 1: Signal Engine & State Machine**
- [x] **Phase 2: Fullscreen Veil Window & Display Management**
- [x] **Phase 3: Veil Image Storage & Rendering**
- [x] **Phase 4: Lock Escalation & Post-Unlock Suppression**
- [ ] **Phase 5: Fail-Secure & App Lifecycle**
- [ ] **Phase 6: Onboarding & Settings UI**
- [ ] **Phase 7: Testing & Acceptance Validation**

---

## Phase 0: Project Setup & BLE Foundation _(Completed)_

- [x] Xcode project structure and SwiftUI app target (`com.harysuryanto.brb`).
- [x] Low-level CoreBluetooth engine (`LERSSIReader.swift`):
  - [x] Duplicates-allowed LE scanning.
  - [x] Held-link GATT RSSI reading (`readRSSI()`) throttled to 1Hz.
  - [x] Direct-reconnect budget (max 3 retries) before falling back to scan.
  - [x] GATT name resolution for unnamed devices (`0x2A00`, `0x2A24`, `0x2A29`).
- [x] Basic `ProximityManager.swift` state coordinator:
  - [x] Bluetooth permission handling.
  - [x] Device pinning by UUID identifier.
  - [x] Nearby device list pruning (unpinned >60s, pinned >300s, max 30).
- [x] Preliminary UI: `ContentView.swift` and `DevicePickerView.swift`.

---

## Phase 1: Signal Engine & Proximity State Machine _(Completed)_

- [x] **Tick & Sampling Rate:**
  - [x] Switch engine tick to 0.5s intervals.
  - [x] Implement data freshness gates (GATT samples <3s, advertisement samples <12s; freeze + mark stale past 12s; never extrapolate).
- [x] **Signal Processing:**
  - [x] Implement Exponential Moving Average (EMA) smoothing with $\alpha = 0.2$ (`SignalProcessor.swift`).
  - [x] Implement hysteresis band logic:
    - Veil-On threshold (default: `-80 dBm`).
    - Veil-Off threshold (default: `-70 dBm`).
- [x] **Presence State Machine:**
  - [x] Implement states: `Near`, `Far`, `Gone` (no sighting for $2 \times \text{grace}$ delay, e.g. bud cased/dead) (`PresenceState.swift`).
  - [x] Implement Grace Timer (default: 10s, configurable 5–60s). Any valid in-range sample resets the timer.
  - [x] Ensure switching monitored device completely resets histories, EMA, counters, active link, and pinned LE UUID.
  - [x] Away boundary calibration logic and reset-to-defaults methods.

---

## Phase 2: Fullscreen Veil Window & Display Management _(Completed)_

- [x] **Multi-Display Window Controller:**
  - [x] Created `VeilWindowController.swift` managing borderless windows across all screens (`NSScreen.screens`).
  - [x] Configured `NSWindow`:
    - `level = .screenSaver`
    - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`
    - Excluded from Exposé and Mission Control.
    - Intercepts and blocks mouse/keyboard events beneath the veil.
  - [x] Listens to `NSApplication.didChangeScreenParametersNotification` to re-sync windows on display attach/detach.
- [x] **Presentation & Animation:**
  - [x] Fast fade-in (~0.25s) when the state machine triggers `Far` (post-grace) or `Gone`.
  - [x] Instant dismiss without animation when signal returns past the hysteresis gap.
- [x] **Veil UI Overlay:**
  - [x] Full-bleed cover image rendering (`VeilView.swift`, aspect-fill).
  - [x] Single button overlay: **"Unlock with Mac Login"** with subtitle _"Locks this Mac — log back in to dismiss the cover for a while."_

---

## Phase 3: Veil Image Storage & Rendering _(Completed)_

- [x] **Image Selection & Security-Scoped Bookmarks:**
  - [x] Implemented `NSOpenPanel` for user image selection (PNG, JPEG, TIFF, HEIC, BMP, GIF) in `VeilImageManager.swift`.
  - [x] Persist selected file as a security-scoped bookmark in `UserDefaults` under `BRB.veilImageBookmark`.
  - [x] Implemented safe bookmark resolution (`startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`).
  - [x] Handles unresolvable/stale bookmark fallback with user notice.
- [x] **Rendering & Asset Bundling:**
  - [x] Procedural default fallback image asset (high-res dark gradient with _"BRB — stepped away"_ wordmark and vignette).
  - [x] "Reset to default" capability.

---

## Phase 4: Lock Escalation & Post-Unlock Suppression _(Completed)_

- [x] **Lock Escalation Action:**
  - [x] Created `SessionLockManager.swift` invoking macOS session lock via `SACLockScreenImmediate()` with fallback to `CGSession -suspend`.
  - [x] Set `pendingManualUnlock` state flag prior to locking.
- [x] **Unlock & Return Detection:**
  - [x] Observe unlock events via `NSWorkspace.sessionDidBecomeActiveNotification` and `com.apple.screenIsUnlocked`.
  - [x] If `pendingManualUnlock` is active:
    - Dismisses veil immediately.
    - Starts configurable suppression timer window (default: 15 min, 5–60 min).
    - Clears `pendingManualUnlock`.
  - [x] If unlock occurs without `pendingManualUnlock`: re-evaluates normally with fresh grace timer.
- [x] **Suppression Management:**
  - [x] If the earbud returns mid-suppression: immediately cancels suppression and returns to normal proximity evaluation.
  - [x] Crash safety: application restarts or crashes never default to suppression mode.

---

## Phase 5: Fail-Secure & App Lifecycle

- [ ] **Fail-Secure Mechanism:**
  - [ ] `failSecureEnabled` setting (`UserDefaults`, default: `true`).
  - [ ] Hook `NSApplicationDelegate.applicationWillTerminate(_:)` to lock the Mac if `failSecureEnabled` is `true`.
- [ ] **App Presentation Model:**
  - [ ] Menu bar item (`NSStatusItem`) showing current connection / proximity status icon.
  - [ ] Menu items: Current State, Monitored Device, Open Settings, Lock Mac Now, Quit.
  - [ ] Support clean window toggling for Settings/Preferences.

---

## Phase 6: Onboarding & Settings UI

- [ ] **3-Step Onboarding Flow (First Launch):**
  - [ ] Step 1: Bluetooth consent explanation (handling granted vs denied states).
  - [ ] Step 2: Live device discovery and one-tap TWS pinning.
  - [ ] Step 3: Away boundary calibration (~2m walk-away capture with `-80 dBm` default option).
- [ ] **Settings UI:**
  - [ ] **Device Tab:** Monitored device info, RSSI badge (`LE` / `LE-adv`), live dBm, sample age, nearby scanner.
  - [ ] **Calibration & Thresholds:** Threshold sliders (Veil-On / Veil-Off) + "Recalibrate away boundary" action.
  - [ ] **Cover Tab:** Image thumbnail preview, "Choose Image..." button, "Reset to Default", missing file alert.
  - [ ] **Timers Tab:**
    - Grace Delay stepper (5–60s, step 1s, default: 10s).
    - Suppress Window stepper (5–60 min, step 5 min, default: 15 min).
  - [ ] **Security Tab:** Fail-secure toggle with disclaimer note.

---

## Phase 7: Testing & Acceptance Validation

- [ ] Verify LE device pipeline using reference peripheral (mouse or earbuds).
- [ ] Test distance variation: signal attenuation when walking away and recovery on return.
- [ ] Verify multi-display veil behavior (all screens covered, screen Saver window level, no Mission Control leaks).
- [ ] Verify manual unlock flow: click button -> lock screen -> authenticate Touch ID/password -> suppression active.
- [ ] Verify mid-suppression earbud return clears suppression.
- [ ] Verify Bluetooth toggle off/on mid-execution handles graceful recovery.
- [ ] Verify fail-secure on quit triggers Mac lock.
