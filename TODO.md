# BRB — Project TODO & Roadmap

Tracking implementation progress against the [Product Requirements Document](PRD.md).

---

## 📋 Status Overview

- [x] **Phase 0: Project Setup & BLE Foundation**
- [x] **Phase 1: Signal Engine & State Machine**
- [ ] **Phase 2: Fullscreen Veil Window & Display Management**
- [ ] **Phase 3: Veil Image Storage & Rendering**
- [ ] **Phase 4: Lock Escalation & Post-Unlock Suppression**
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

## Phase 2: Fullscreen Veil Window & Display Management

- [ ] **Multi-Display Window Controller:**
  - [ ] Create an `NSWindowController` managing borderless windows across all screens (`NSScreen.screens`).
  - [ ] Configure `NSWindow`:
    - `level = .screenSaver`
    - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`
    - Exclude from Exposé and Mission Control.
    - Intercept and block mouse/keyboard events beneath the veil.
  - [ ] Listen to `NSApplication.didChangeScreenParametersNotification` to add/remove windows on display attach/detach.
- [ ] **Presentation & Animation:**
  - [ ] Fast fade-in (~0.25s) when the state machine triggers `Far` (post-grace) or `Gone`.
  - [ ] Instant dismiss without animation when signal returns past the hysteresis gap.
- [ ] **Veil UI Overlay:**
  - [ ] Full-bleed cover image rendering (aspect-fill).
  - [ ] Single button overlay: **"Unlock with Mac Login"** with subtitle _"Locks this Mac — log back in to dismiss the cover for a while."_

---

## Phase 3: Veil Image Storage & Rendering

- [ ] **Image Selection & Security-Scoped Bookmarks:**
  - [ ] Implement `NSOpenPanel` for user image selection (PNG, JPEG, TIFF, HEIC, BMP, GIF 1st frame).
  - [ ] Persist selected file as a security-scoped bookmark (`URL.bookmarkData(options: .withSecurityScope)`) in `UserDefaults` under `BRB.veilImageBookmark`.
  - [ ] Implement safe bookmark resolution (`startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`).
  - [ ] Handle unresolvable/stale bookmark fallback with user notice.
- [ ] **Rendering & Asset Bundling:**
  - [ ] Create default bundled asset image (dark gradient with _"BRB — stepped away"_ wordmark).
  - [ ] Downscale and cache the image matching each screen's backing pixel dimensions.
  - [ ] Provide "Reset to default" button in settings.

---

## Phase 4: Lock Escalation & Post-Unlock Suppression

- [ ] **Lock Escalation Action:**
  - [ ] Wire the veil's "Unlock with Mac Login" button to trigger macOS session lock (e.g. `SACLockScreenImmediate()` or private/system framework call).
  - [ ] Set `pendingManualUnlock` state flag prior to locking.
- [ ] **Unlock & Return Detection:**
  - [ ] Observe unlock event via `NSWorkspace.sessionDidBecomeActiveNotification` or `com.apple.screenIsUnlocked` distributed notification.
  - [ ] If `pendingManualUnlock` is active:
    - Dismiss veil.
    - Start suppression timer window (default: 15 min, configurable 5–60 min).
    - Clear `pendingManualUnlock`.
  - [ ] If unlock occurs without `pendingManualUnlock` (e.g. manual user lock, fail-secure lock): re-evaluate normally with fresh grace timer.
- [ ] **Suppression Management:**
  - [ ] If the earbud returns mid-suppression: immediately cancel suppression and return to normal proximity evaluation.
  - [ ] Crash safety: ensure application restarts or crashes never default to suppression mode.

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
