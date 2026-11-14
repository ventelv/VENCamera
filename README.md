# VENCamera

A free macOS webcam app for Canon EOS cameras. It covers what EOS Webcam Utility Pro does (live view at up to 1080p, plus camera controls on your Mac) without the subscription. You build it from source on your own Mac; there's no App Store download and no prebuilt binary.

It talks to the camera over USB through [libgphoto2](http://gphoto.org/proj/libgphoto2/), which is free, open source and installed with Homebrew, so there's no Canon account or SDK download. It was built and tested with a **Canon EOS M50** on an Apple Silicon Mac (M1 Pro) running macOS 15. See [Compatible cameras](#compatible-cameras) for the other models it should work with.

VENCamera is an independent project and isn't affiliated with or endorsed by Canon. Canon, EOS and PowerShot are trademarks of Canon Inc.

Before installing, read [SECURITY.md](SECURITY.md). It explains exactly what VENCamera does on your Mac.

## Install
You'll need:
- A Mac on macOS 14 (Sonoma) or later. Only Apple Silicon has been tested.
- A [compatible Canon camera](#compatible-cameras) and a USB cable that carries data, not just power.
- About 15 minutes.

### 1. Install the tools
Install Apple's Command Line Tools (skip this if you already have Xcode):
```bash
xcode-select --install
```

Install [Homebrew](https://brew.sh) if you don't have it, by following the instructions on its website. Then install libgphoto2, pkgconf (which the build uses to find libgphoto2) and OBS:
```bash
brew install libgphoto2 pkgconf
```
```bash
brew install --cask obs
```

### 2. Download and build VENCamera
```bash
git clone https://github.com/ventelv/VENCamera.git
```
```bash
cd VENCamera && make install
```
This builds VENCamera, copies it to `/Applications/VENCamera.app`, signs it to run on your Mac only (ad-hoc signing) and opens it. The first build takes a minute or two. A camera icon appears in your menu bar, and the VENCamera window opens.

### 3. Set up the camera
1. Connect the camera to your Mac with the USB cable and switch it on.
2. Set the mode dial to **Movie**. That gives a 16:9 picture.
3. In the camera's menu, turn off **Auto power off**, so it doesn't switch off mid-call.
4. If the camera is connected to a phone or computer over Wi-Fi or Bluetooth, turn that off. Most Canon cameras won't accept USB control while a wireless connection is active.
5. If **EOS Webcam Utility** is installed, VENCamera shows *EOS Webcam Utility is using the camera*. Click **Use the Camera in VENCamera**. VENCamera pauses Canon's background service until you log out; see [How it stays reliable](#how-it-stays-reliable).

The VENCamera window should now show the live picture, with the frame rate under it.

### 4. Set up OBS (once)
Video apps receive VENCamera's picture through OBS's virtual camera.
1. Open **OBS**. If the Auto-Configuration Wizard appears, choose **I will only be using the virtual camera** and accept the suggested settings.
2. Go to **Settings › Video** and set *Base (Canvas) Resolution* and *Output (Scaled) Resolution* to **1920×1080**, and *Common FPS Values* to **30**. Click **OK**.
3. Under **Sources**, click **+**, choose **Syphon Client**, name it `VENCamera` and click **OK**. In its properties, set *Source* to **[VENCamera] VENCamera** and click **OK**.
4. Right-click the source and choose **Transform › Fit to screen**.
5. Click **Start Virtual Camera**. The first time, macOS asks you to allow OBS's camera extension: go to **System Settings › General › Login Items & Extensions › Camera Extensions**, turn on **OBS Virtual Camera**, then quit and reopen OBS.

From now on you don't need to open OBS yourself. Whenever the camera connects, VENCamera starts OBS in the background with the virtual camera on.

### 5. Use it in calls
In Zoom, Google Meet, Teams, FaceTime, Loom or any other video app, choose **OBS Virtual Camera** as the camera. If the app was already open, quit and reopen it so it finds the camera.

Optional: choose **Start at Login** in VENCamera's menu so it's ready after every restart. For calls longer than about an hour, use a dummy battery (an AC adapter that fits in the battery slot; for the M50 that's the Canon ACK-E12 or a compatible one).

### Update or uninstall
To update to the latest version, run this in the `VENCamera` folder:
```bash
git pull && make install
```
To remove VENCamera:
```bash
make uninstall
```
Its preferences can be removed too:
```bash
defaults delete com.ventel.VENCamera
```

## Compatible cameras
VENCamera needs a camera that can send live view over USB. The libgphoto2 version it's built against (2.5.34) lists live view support for the Canon models below. Being on this list means VENCamera should be able to connect and show a picture. **Only the EOS M50 has been tested.** If you try another model, please open an issue to say whether it worked.

To check a camera before relying on it, quit VENCamera, connect the camera and run:
```bash
swift run canon-probe 10
```
It shows whether the camera connects, which settings VENCamera can change, and the live view size and frame rate the camera delivers.

### Tested
- **EOS M50**: 1024×576 at 30 fps over USB, with all controls working.

### Should work: EOS mirrorless
These use the same Canon USB protocol as the M50, so live view and most controls should work.
- **EOS R series:** EOS R, RP, R1, R3, R5, R5 C, R5 Mark II (listed by libgphoto2 as "EOS 5Rm2"), R6, R6 Mark II, R6 Mark III, R7, R8, R10, R50, R50 V, R100
- **EOS M series:** EOS M, M2, M3, M5, M6, M6 Mark II, M10, M50 Mark II, M100, M200

### Should work: EOS DSLRs
Live view and most controls should work. Set the mode dial to Movie, or turn live view on, for the best picture.
- **Professional and full frame:** EOS-1D Mark IV, 1D C, 1D X, 1D X Mark II, 1D X Mark III, 5D Mark II, 5D Mark III, 5D Mark IV, 5DS, 5DS R, 6D, 6D Mark II
- **Enthusiast:** EOS 7D, 7D Mark II, 40D, 50D, 60D, 70D, 77D, 80D, 90D
- **Entry level:** EOS 100D, 200D, 250D, 450D, 500D, 550D, 600D, 650D, 700D, 750D, 760D, 800D, 850D, 1000D, 1100D, 1200D, 1300D, 1500D, 2000D, 4000D
- **Also listed under their Americas and Japan names:** Rebel XSi, T1i, T2i, T3, T3i, T4i, T6, T7i, T8i; Kiss X2, X3. Rebel and Kiss models are the same cameras as the numbered EOS models above.

On the EOS 40D, 450D, Rebel XSi and Kiss X2, set the camera's communication mode to **PTP** in its menu first.

### Might work: PowerShot and IXUS compacts
libgphoto2 lists live view for these, but VENCamera's controls are built for EOS cameras. Expect a picture at best (on older models a small, low-resolution one), with most controls showing a dash.

<details>
<summary>PowerShot and IXUS models with live view in libgphoto2</summary>

- **PowerShot G:** G3, G5, G6, G7, G9, G10, G3 X, G5 X, G7 X, G7 X Mark II, G7 X Mark III, G9 X Mark II
- **PowerShot SX:** SX70 HS, SX100 IS, SX110 IS, SX530 HS, SX540 HS, SX600 HS, SX620 HS, SX720 HS, SX730 HS, SX740 HS
- **PowerShot A:** A60, A70, A75, A80, A85, A95, A300, A310, A400, A460, A510, A520, A620, A640, A650 IS
- **PowerShot S and SD:** S1 IS, S2 IS, S3 IS, S5 IS, S50, S60, S70, S80, S230, S400, S410, S500, SD100, SD110, SD500
- **IXUS:** Digital IXUS II, IIs, v3, 180, 400, 430, 500

Many older models must be set to **PTP** communication mode in their menu.
</details>

### Won't work
- **EOS models libgphoto2 can't get live view from:** EOS 10D, 20D, 30D, 300D, 350D, 400D, 5D (the original), 1D Mark II, 1D Mark III, Digital Rebel, Rebel XT and XTi, Kiss Digital, Kiss Digital N and X.
- **Models newer than libgphoto2 2.5.34**, until a later libgphoto2 adds them. `brew upgrade libgphoto2` followed by `make install` picks up new models.
- Cameras whose USB port only charges, or that only offer remote control over Wi-Fi.

### What differs between cameras
- **Picture size and frame rate:** the M50 sends 1024×576 at 30 fps, which VENCamera upscales to 1920×1080. Other models may send more or less.
- **Settings:** VENCamera's controls use libgphoto2's Canon EOS setting names. Any control your camera doesn't offer shows a dash.

## Using VENCamera
- **Menu bar:** a camera icon at the top of the screen. It's filled while the camera is live and a warning triangle when something is wrong. The menu has *Open VENCamera…* (⌘,), *Mirror Image*, *Start at Login*, *Quit*, and buttons to take the camera from EOS Webcam Utility or hand it back.
- **Settings window:** opens on the first launch, and whenever you double-click VENCamera in Applications or choose *Open VENCamera…*. It shows the live preview and these controls:
  - **Brightness:** exposure compensation.
  - **White balance:** preset or Kelvin.
  - **Picture:** Picture Style, mirror and sharpening.
  - **Focus:** autofocus method, continuous AF, Movie Servo AF, and *Focus now / Nearer / Farther*.
  - **Exposure:** aperture, shutter and ISO. In Movie mode with automatic exposure these are set by the camera; to set them yourself, choose manual exposure (M) for movies in the camera's menu.
- **In video apps:** choose **OBS Virtual Camera**. VENCamera sends 1920×1080 to OBS over Syphon, and OBS passes it on.

### How it stays reliable
- **Canon's webcam service:** if EOS Webcam Utility is installed, its `EOSWebcamService` launch agent starts at login and holds the camera even when its app is closed. The first time this happens, VENCamera asks before doing anything. If you choose *Use the Camera in VENCamera*, it quits Canon's app and pauses that agent with `launchctl bootout`. The pause lasts until you log out, and Canon's files aren't touched. Your choice is remembered (*Always Take the Camera from Canon* in the menu). *Hand the Camera Back to EOS Webcam Utility* restarts the agent.
- **macOS's `ptpcamerad`:** this daemon grabs every camera that's plugged in. VENCamera stops it just before connecting.
- **Other cameras:** only Canon cameras are used. A plugged-in iPhone, which also shows up as a PTP camera, is skipped.
- **Sleep and unplugging:** VENCamera closes the camera session before your Mac sleeps and reconnects after it wakes. It also reconnects on its own when the camera is switched off and on or unplugged and plugged back in.

### Troubleshooting
- **"Looking for the camera…" doesn't change:** check that the camera is on and the cable carries data, and turn off the camera's Wi-Fi and Bluetooth connections.
- **"The camera isn't responding":** switch the camera off and on again. VENCamera reconnects within a few seconds.
- **Black picture or the OBS logo in calls:** click OBS's menu bar icon and choose *Start Virtual Camera*, and check that OBS's Syphon source is set to **[VENCamera] VENCamera**.
- **OBS Virtual Camera isn't listed in your video app:** check that it's turned on under System Settings › General › Login Items & Extensions › Camera Extensions, then restart the video app. After an OBS update, macOS may ask you to allow it again.
- **The build fails with a pkg-config or libgphoto2 error:** run `brew install libgphoto2 pkgconf`, then `make install` again.

## The M50 over USB
Measured on 2026-11-04 with `canon-probe`, mode dial on **Movie**:

| Live view size setting | Frame size | Frame rate | Average JPEG |
|---|---|---|---|
| Small (the camera's default) | 512×288 | ~26 fps | 58 KB |
| Medium | 512×288 | ~30 fps | 58 KB |
| **Large** | **1024×576** | **30.0 fps** | 210 KB |

Each capture takes about 33 ms, so the camera is the limit, not USB. VENCamera switches the camera to *Large* when it connects.

Settings VENCamera can control (names as libgphoto2 uses them):
- **Exposure:** `aperture`, `shutterspeed`, `iso`, `exposurecompensation`.
- **Color:** `whitebalance` (including Color Temperature), `colortemperature` (76 Kelvin steps), `picturestyle`.
- **Focus:** `afmethod` (LiveFace / LiveZone / Live), `continuousaf`, `movieservoaf`, `manualfocusdrive` (Near 1–3 / Far 1–3), `autofocusdrive`.
- **Zoom:** `eoszoom` and `eoszoomposition`.
- **Stills:** `eosremoterelease`.
- **Status:** `batterylevel`.

## canon-probe
```bash
swift run canon-probe 10
```
Quit VENCamera first, because only one app can use the camera at a time. The probe prints the control panel settings and their choices, measures live view for 10 seconds and saves `probe-frame.jpg`. Add `--all` to list every setting the camera exposes (84 on the M50). Add `name=value` arguments to change settings while live view runs, for example `exposurecompensation=0.3` or `whitebalance=Daylight`; the probe prints the picture's brightness and color balance before and after. It puts the live view size back to what it was when it finishes.

## Project layout
- `Sources/VENCamera/`: the menu-bar app.
  - `CameraController`: connection, live view thread and settings.
  - `FramePipeline`: Core Image Lanczos upscale to 1080p, then Syphon.
  - `SettingsView`: the settings window.
  - `CanonWebcamService` and `OBSLauncher`: handling for Canon's webcam app and OBS.
- `Sources/CanonKit/`: Swift wrapper for libgphoto2. `CanonCamera` handles connecting, the settings tree, reading and changing settings, and live view, with every call going through one serial queue. `CanonSettingName` lists the setting names.
- `Sources/CGPhoto2/`: module map for the Homebrew libgphoto2 (found through pkg-config).
- `Sources/Syphon/`: the Metal server part of [Syphon](https://github.com/Syphon/Syphon-Framework), vendored under BSD-2. See `Sources/Syphon/VENDORED.md` for the upstream commit and the changes made.
- `Sources/canon-probe/`: the measurement tool.
- `Tools/make-icon.swift`: draws the app icon. `make icon` rebuilds `Resources/AppIcon.icns` from it.

## License
MIT. See [LICENSE](LICENSE). The vendored Syphon code in `Sources/Syphon/` is BSD-2-Clause.
