# BRB — Project TODO & Roadmap

Tracking implementation progress against the [Product Requirements Document](PRD.md).

---

## 📋 Status Overview

- [x] **Phase 0: Project Setup & BLE Foundation**
- [x] **Phase 1: Signal Engine & State Machine**
- [x] **Phase 2: Fullscreen Veil Window & Display Management**
- [x] **Phase 3: Veil Image Storage & Rendering**
- [x] **Phase 4: Lock Escalation & Post-Unlock Suppression**
- [x] **Phase 5: Fail-Secure & App Lifecycle**
- [x] **Phase 6: Onboarding & Settings UI**
- [x] **Phase 7: Testing & Acceptance Validation**

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

## Phase 5: Fail-Secure & App Lifecycle _(Completed)_

- [x] **Fail-Secure Mechanism:**
  - [x] `failSecureEnabled` setting (`UserDefaults`, default: `true`).
  - [x] Hook `NSApplicationDelegate.applicationWillTerminate(_:)` in `AppDelegate` to lock the Mac if `failSecureEnabled` is `true`.
- [x] **App Presentation Model:**
  - [x] Menu bar extra (`MenuBarExtra`) showing dynamic status icon based on proximity state (`near`, `far`, `gone`, `idle`).
  - [x] Menu items: Real-time presence state, monitored device, live RSSI, "Lock Mac Now", "Open BRB Settings", "Quit BRB".
  - [x] Seamless window opening and activation.

---

## Phase 6: Onboarding & Settings UI _(Completed)_

- [x] **3-Step Onboarding Flow (First Launch):**
  - [x] Step 1: Bluetooth consent explanation with status badge and system settings shortcut.
  - [x] Step 2: Live earbud discovery and one-tap TWS pinning (`DevicePickerView`).
  - [x] Step 3: Away boundary calibration (~2m walk-away capture with `-80 dBm` default option).
- [x] **Settings UI:**
  - [x] **Device Tab:** Monitored device info, presence badge, live dBm, smoothed dBm, sample freshness age, suppression banner, nearby scanner table.
  - [x] **Screen Cover Tab:** Image thumbnail preview, "Choose Image…" button, "Reset to Default", test 3-second cover preview, missing file alert.
  - [x] **Calibration Tab:** Threshold sliders (Veil-On / Veil-Off) with hysteresis band enforcement + "Calibrate away boundary" action + reset to defaults.
  - [x] **Timers & Security Tab:**
    - Grace Delay stepper (5–60s, step 1s, default: 10s).
    - Suppress Window stepper (5–60 min, step 5 min, default: 15 min).
    - Fail-secure toggle with security disclaimer.
    - "Re-run Onboarding Setup" action.

---

## Phase 7: Testing & Acceptance Validation _(Completed)_

- [x] SignalProcessor EMA verification: smoothing math with $\alpha = 0.2$, initial value pass-through, history reset.
- [x] Presence state transitions: `idle` -> `near` -> `far` -> `gone`.
- [x] Hysteresis band verification: deadband retention prevents boundary thrashing.
- [x] Grace delay timer accumulation and immediate return cancellation.
- [x] Gone condition verification: sighting age $\ge 2 \times \text{graceDelay}$.
- [x] Mid-suppression earbud return: cancels suppression and restores normal monitoring.
- [x] Procedural default veil image asset rendering.
- [x] Full build verification and test runner execution (`Tests/EngineValidationTests.swift`).

---

## Phase 8: Stable Identity Across LE Identifier Rotation _(Parked)_

> Parking note (2026-09-17): retention still does not survive case cycles.
> Everything below is recorded so work can resume without redoing analysis.

- [ ] **Symptom (user-observed, reproducible):** buds cased → reopened → back as Unknown cards; name reverts to `Unknown` every cycle; previously-visible hex changed value each cycle; pin/monitoring do not carry over.
- [ ] **Root cause (established):** LE peripheral identifiers rotate across case cycles on this hardware (Classic A2DP pairing does not bond the LE side, so LE-privacy rotations surface new CB identifiers). Platform sources (Apple docs, Punch Through guide, field reports) confirm UUIDs are *not guaranteed stable* — usually long-lived, but observed rotating spontaneously with no reset. Everything UUID-keyed breaks: pin, name cache, suffix/tint seed, scanner rows, reader re-attach.
- [ ] **Compounding finding (from on-disk + user answers):** post-cycle packets carry **no usable name** — `BRB.deviceIdentities` was never written despite live cards being visible across sessions, so passive learning is barren on this hardware; names likely exist only behind GATT. H2 (old build) ruled out: hex-free subtitles confirm the new build runs. The hex changing per cycle independently confirms rotation.
- [ ] **Done (newest first):**
  - [x] `e6c9f91` — Full name-keyed identity: `stableKey` (normalized name), `DeviceGroup` collapsing (one card per bud), pin-by-key + locator hint (`BRB.pinnedKey` / `BRB.pinnedUUIDHint`), silent re-link w/ 30s GATT re-aim throttle + transient note, reader name-follow (`matches(id:name:)`), vendor-sanity on adopt, legacy UUID-pin + UUID-keyed-cache migration, `2× seen` collision note. Scanner hex restored as an explicitly-labeled *session locator* (leading subtitle element; identity lives in title/key).
  - [x] `26dedde` — `BRB.deviceIdentities` cache (30 entries / 30-day TTL, placeholders never stored); `artName` precedence aligned with title; FNV-1a constants corrected (one-time hue re-roll).
  - [x] `24dcda6` — `Unknown • XXXX` titles, SIG-verified vendor chips + Fast Pair hint, id-seeded art tint, shared identity helpers, `pinnedDisplayName`.
  - [x] `71be553` — monitored UI pin-gated (no phantom signal unpinned), reader pin cleared on unpin, `recordSample` pin guard.
- [ ] **Next approaches, ranked (passive designs exhausted — post-cycle packets lack names):**
  - [ ] **A (primary): Active GATT resolution queue.** Unnamed lingering singleton → connect → read `0x2A00`/`0x2A24` → disconnect → cache under the stable name. Once per UUID, concurrency 1, never disturbing the pinned link. The only method that learns names this hardware never advertises.
  - [ ] **B (complement): Continuity/model + timing heuristic.** Unnamed new UUID + same vendor/model appearing as the old goes silent → provisional inherit, confirmed by A. Apple-leaning.
  - [ ] **C (last resort): Manual nicknames.** Override tier above live names + edit UI. Separate feature, not a fix.
- [ ] **Resume diagnostics (zero/low effort):** with the app running across a case cycle, `defaults read com.harysuryanto.brb` and compare `BRB.pinnedKey` / `BRB.pinnedUUIDHint` / `BRB.deviceIdentities` before vs after; note whether suffix/title/chip persisted. Gap: `lastRelink` is session-only (not persisted) — persist it if relink evidence must survive relaunch.
- [ ] **Deferred:** re-link confirm dialog; serial-number (`0x2A25`) tiebreak; PRD doc updates (PRD still documents UUID pinning — stale).
