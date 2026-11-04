# VENCamera

A personal webcam app for the Canon EOS M50 (Mk1) on this MacBook Pro (M1 Pro). It does what EOS Webcam Utility Pro does, without the subscription. It's built and installed directly on this Mac, with no App Store.

It talks to the camera through [libgphoto2](http://gphoto.org/proj/libgphoto2/). That library is free, open source and installed with Homebrew, so there's no Canon account or SDK download.

The full plan is in `~/.claude/plans/plan-me-a-compelling-cosmic-backus.md`.

## What the M50 delivers over USB (measured 2026-11-04 with `canon-probe`)
These were measured with the mode dial on **Movie**:

| Live view size setting | Frame size | Frame rate | Average JPEG |
|---|---|---|---|
| Small (the camera's default) | 512×288 | ~26 fps | 58 KB |
| Medium | 512×288 | ~30 fps | 58 KB |
| **Large** | **1024×576** | **30.0 fps** | 210 KB |

Each capture takes about 33 ms, so the camera is the limit, not USB. VENCamera switches the camera to *Large* when it connects and upscales that to 1080p.

Settings we can control (names as libgphoto2 uses them):
- **Exposure:** `aperture`, `shutterspeed`, `iso`, `exposurecompensation`.
- **Color:** `whitebalance` (including Color Temperature), `colortemperature` (76 Kelvin steps), `picturestyle`.
- **Focus:** `afmethod` (LiveFace / LiveZone / Live), `continuousaf`, `movieservoaf`, `manualfocusdrive` (Near 1–3 / Far 1–3), `autofocusdrive`.
- **Zoom:** `eoszoom` and `eoszoomposition`.
- **Stills:** `eosremoterelease`.
- **Status:** `batterylevel`.

In Movie mode with automatic exposure, aperture, shutter and ISO only offer "auto". To control them by hand, set the mode dial to **Movie manual exposure** (Movie mode, then the M menu option).

## One-time setup
1. Install libgphoto2:
   ```bash
   brew install libgphoto2
   ```
   It's already installed on this Mac. OBS is installed too.
2. **Quit EOS Webcam Utility** before using VENCamera. Only one app can hold the camera. VENCamera stops macOS's `ptpcamerad` itself, because that daemon grabs every camera as soon as it's plugged in.
3. **OBS:** add a *Syphon Client* source pointed at "VENCamera", then click **Start Virtual Camera**. Apps will see the feed as "OBS Virtual Camera". This works from Phase 2.
4. **Xcode, from Phase 2 on:** the menu-bar app, its Metal pipeline and the `/Applications` install need full Xcode. Download the `.xip` from <https://developer.apple.com/download/all/> with a free Apple ID. The Command Line Tools on this Mac are enough for the current package.
5. Recommended: a dummy battery (Canon ACK-E12 or a compatible one). Live view drains the LP-E12 battery in about an hour.

## Phase 1 probe
```bash
swift run canon-probe 10
```
This prints the control panel settings and their choices, then measures live view for 10 seconds and saves `probe-frame.jpg`. Add `--all` to list all 84 settings the camera exposes. The probe puts the live view size back to what it was when it finishes.

## Layout
- `Sources/CGPhoto2/`: module map for the Homebrew libgphoto2 (found through pkg-config).
- `Sources/CanonKit/`: Swift wrapper. `CanonCamera` handles connecting, the settings tree, reading and changing settings, and live view, with every call going through one serial queue. `CanonSettingName` lists the setting names.
- `Sources/canon-probe/`: the Phase 1 measurement tool.
