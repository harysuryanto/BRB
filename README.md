# BRB — Step away. Your screen covers itself.

BRB is a macOS presence-privacy app for wireless-earbud wearers. While you sit at your Mac, nothing happens. When you walk away (your buds leave radio range — e.g. getting water), BRB covers **all displays** with a fullscreen image (the *veil*) so passersby see nothing sensitive. Walk back and it lifts on its own — no clicks. A single **Unlock with Mac Login** button on the veil locks the Mac for real when you want authentication on return.

Unlike lock-on-walk tools, BRB is **veil-first, lock-on-demand**: every water run doesn't nuke your session.

## Requirements

- Real Mac with Bluetooth (no simulator — CoreBluetooth needs hardware)
- Xcode 17+, Swift 5, macOS 26 SDK (target: macOS 26.5+, `com.harysuryanto.brb`)
- Unsandboxed Developer-ID-style build (sandbox blocks session lock + Bluetooth); first launch **Allow** when macOS asks for Bluetooth

## Installation

Download the pre-built installer from the [GitHub Releases](https://github.com/harysuryanto/BRB/releases) page:

1. Download the latest **`.dmg`** installer from the [Releases](https://github.com/harysuryanto/BRB/releases) page.
2. Open the downloaded `.dmg` and drag **`BRB.app`** into your `/Applications` folder.
3. **⚠️ MANDATORY: Clear the Gatekeeper quarantine before opening**
   Because BRB is an open-source, unsandboxed utility distributed outside the Mac App Store without an Apple Notary certificate, **macOS will block launch or falsely report the app is damaged** if opened directly.

   Open Terminal and run this one-line command:
   ```bash
   xattr -cr /Applications/BRB.app
   ```

   *(Alternative without Terminal: Right-click / Control-click **`BRB.app`** in Finder → click **Open** → click **Open** in the dialog. If blocked, open **System Settings → Privacy & Security** and click **Open Anyway**).*

4. Launch **`BRB.app`** from `/Applications`.
5. When prompted, click **Allow** for **Bluetooth access** (required to monitor your device's radio proximity).

---

## Building from source

```bash
git clone git@github.com:harysuryanto/BRB.git
cd BRB
open BRB.xcodeproj   # ⌘R to build & run
```

Or headless:

```bash
xcodebuild -project BRB.xcodeproj -scheme BRB -configuration Debug -destination 'platform=macOS' build
```

To package a distributable drag-and-drop DMG:

```bash
./scripts/build-dmg.sh
```

## First launch & setup

First launch walks through 3 onboarding steps (draft until you hit Finish — quitting early changes nothing):

1. **Bluetooth access** — creating the scanner *is* the system prompt; allow it.
2. **Pick your earbuds** — tap a card in the Nearby grid (selection only stages; monitoring starts on Finish).
3. **Away boundary** — stand ~2 m out, capture the dBm (or take the −80 dBm default), and watch the live signal gauge flip the preview between Cover Off / Cover On. No fullscreen happens during setup, ever.

## Using it

- **Menu bar**: status (`Near` / `Away` / `Gone` / `Idle` / `Paused`), monitored device, Pause Protection toggle, Settings, Quit.
- **Settings tabs**:
  - *Device* — live presence, monitored bud, Pause Protection, nearby scanner grid.
  - *Cover* — custom veil image (picker/preview/reset) + Secure/Casual lock mode.
  - *Calibration* — Veil-On/Veil-Off threshold sliders + away-boundary capture.
  - *Timers & Security* — grace delay, post-unlock suppression, cover-on-signal-lost, fail-secure (lock on quit).
  - *About* — app identity, version, copyright, and GitHub repository link.

### Defaults

| Setting | Default |
|---|---|
| Veil-On / Veil-Off thresholds | −80 / −74 dBm (6 dBm hysteresis band) |
| Grace delay | 10 s |
| Post-unlock suppression | 15 min |
| Cover Lock mode | Secure (lifts only on device return or Mac login) |
| Cover on Signal Lost | On (covers screen if bud signal vanishes) |
| Fail-secure (lock on quit) | On |
| Launch at Login | On |
| Pause Protection | Off, session-only (relaunch always resumes protection) |

## How it works

0.5 s tick → LE sample (held-link GATT ~1 Hz, else advertisements) → EMA smoothing (α = 0.8) → hysteresis bands → grace timer → veil on/off. Freshness gates (GATT < 3 s, adv < 12 s); stale data freezes and is marked, never extrapolated. Devices are pinned by peripheral identifier, never by name. Classic Bluetooth RSSI is best-effort only (unreliable on Apple Silicon).

## Project layout

```
BRB/
  BRBApp.swift            Menu bar extra + main window entry
  ProximityManager.swift  Engine coordinator (tick, state machine, veil, lock, settings)
  Engine/                 LERSSIReader, SignalProcessor, PresenceState, DeviceClassifier,
                          AdvertPruner, VeilWindowController, VeilImageManager, CoverAnimation,
                          SessionLockManager
  Views/                  ContentView (TabView), OnboardingView, DevicePickerView,
                          MenuBarPopoverView, CalibrationRangeMeterView, CoverSettingsView,
                          CalibrationSettingsView, TimersSecuritySettingsView, AboutSettingsView,
                          VeilView, AnimatedCoverView, DesignTokens
scripts/
  build-dmg.sh            Drag-and-drop DMG packager (BRB-v{version}.dmg)
  generate-app-icon.swift macOS app icon generator (Signal & Lock vector artwork)
  generate-dmg-background.swift High-DPI DMG background generator
Tests/EngineValidationTests.swift   Standalone 11-suite @main acceptance suite
PRD.md                    Full product requirements
TODO.md                   Build roadmap / status
```
## Tests

Standalone suite (EMA, presence transitions, hysteresis, grace, gone, suppression, default veil image, device classification, advert pruner, about metadata, launch at login) — all 11 currently green:

```bash
swiftc -o /tmp/brb-tests Tests/EngineValidationTests.swift BRB/ProximityManager.swift BRB/Engine/*.swift BRB/Views/*.swift -framework AppKit -framework CoreBluetooth -framework ServiceManagement && /tmp/brb-tests
```

## Docs

- [`PRD.md`](PRD.md) — requirements, architecture, acceptance protocol (note: some sections predate the dropdown timers + instant-preview onboarding — code wins on conflicts).
- [`TODO.md`](TODO.md) — implementation roadmap and status.
