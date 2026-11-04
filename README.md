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

## Install
```bash
make install
```
This builds VENCamera, copies it to `/Applications/VENCamera.app`, signs it to run on this Mac and opens it. No App Store or Apple account is involved. Run it again after any code change. To remove the app, run `make uninstall`.

Requirements: libgphoto2 (`brew install libgphoto2`) and OBS (`brew install --cask obs`). Both are already installed on this Mac.

## Using VENCamera
- **Menu bar:** a camera icon at the top of the screen. It's filled when the M50 is live and a warning triangle when something is wrong. The menu has *Open VENCamera…* (⌘,), *Mirror Image*, *Start at Login*, *Quit*, and buttons to take the camera from EOS Webcam Utility or hand it back.
- **Settings window:** opens on the first launch, and whenever you double-click VENCamera in Applications or choose *Open VENCamera…*. It shows the live preview and the controls:
  - **Brightness:** exposure compensation.
  - **White balance:** preset or Kelvin.
  - **Picture:** Picture Style, mirror and sharpening.
  - **Focus:** autofocus method, continuous AF, Movie Servo AF, and *Focus now / Nearer / Farther*.
  - **Exposure:** aperture, shutter and ISO, which you can only change when the mode dial is set to Movie manual.
- **In Zoom, Meet, FaceTime and other apps:** choose **OBS Virtual Camera**. VENCamera sends 1920×1080 over Syphon to OBS. OBS's scene has a Syphon source called *VENCamera*, and VENCamera opens OBS in the background with the virtual camera on whenever the M50 connects.

### One-time steps you must do yourself
1. **Approve OBS's virtual camera:** go to System Settings › General › Login Items & Extensions › Camera Extensions and turn on **OBS Virtual Camera**. Then quit and reopen OBS.
2. Optional: choose **Start at Login** in VENCamera's menu.
3. Recommended: a dummy battery (Canon ACK-E12 or a compatible one). Live view drains the LP-E12 battery in about an hour.

### How it stays reliable
- **Canon's webcam service:** Canon's `EOSWebcamService` launch agent starts at login and holds the camera even when its app is closed. With *Always Take the Camera from Canon* on (the default), VENCamera quits Canon's app and stops that agent with `launchctl bootout`. That lasts until you log out, and Canon's files aren't touched. *Hand the Camera Back to EOS Webcam Utility* restarts it.
- **macOS's `ptpcamerad`:** this daemon grabs every camera that's plugged in. VENCamera stops it before connecting.
- **Other cameras:** only Canon cameras are used. A plugged-in iPhone, which also shows up as a PTP camera, is skipped.
- **Clean shutdown:** VENCamera closes the camera session when it quits. If the camera ever stops responding (PTP timeout), switch it off and on again, and VENCamera reconnects on its own.

## Phase 1 probe
```bash
swift run canon-probe 10
```
Quit VENCamera first, because only one app can use the camera. Add `name=value` arguments to change settings, for example `exposurecompensation=0.3` or `whitebalance=Daylight`. The probe prints the control panel settings and their choices, then measures live view for 10 seconds and saves `probe-frame.jpg`. Add `--all` to list all 84 settings the camera exposes. The probe puts the live view size back to what it was when it finishes.

## Layout
- `Sources/VENCamera/`: the menu-bar app.
  - `CameraController`: connection, live view thread and settings.
  - `FramePipeline`: Core Image Lanczos upscale to 1080p, then Syphon.
  - `SettingsView`: the settings window.
  - `CanonWebcamService` and `OBSLauncher`: handling for Canon's webcam app and OBS.
- `Sources/Syphon/`: the Metal server part of [Syphon](https://github.com/Syphon/Syphon-Framework), vendored under BSD-2. Its shader is compiled when the app starts, because the Command Line Tools have no Metal compiler.
- `Sources/CGPhoto2/`: module map for the Homebrew libgphoto2 (found through pkg-config).
- `Sources/CanonKit/`: Swift wrapper. `CanonCamera` handles connecting, the settings tree, reading and changing settings, and live view, with every call going through one serial queue. `CanonSettingName` lists the setting names.
- `Sources/canon-probe/`: the Phase 1 measurement tool.
