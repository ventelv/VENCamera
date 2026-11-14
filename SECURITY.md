# Security

This page explains what VENCamera does on your Mac, what was checked before it was published, and how to report a problem.

## What VENCamera does on your Mac
- **Talks to your camera over USB** through libgphoto2, using the camera's PTP protocol. It reads and changes camera settings, and pulls live view frames (1024×576 JPEGs).
- **Shows a preview and publishes video locally** to OBS over [Syphon](https://github.com/Syphon/Syphon-Framework). Syphon shares GPU memory between apps on the same Mac; nothing leaves your Mac.
- **Makes no network connections.** There's no telemetry, no update check and no account.
- **Stores only preferences** (mirror, sharpening, and the toggles in the menu) in macOS user defaults under `com.ventel.VENCamera`. It doesn't save images or video. The separate `canon-probe` tool saves one sample frame, `probe-frame.jpg`, in the folder you run it from.
- **Writes status lines to the macOS log** under the `com.ventel.VENCamera` subsystem: connection status, disconnects and which camera setting was changed. No images or personal data.
- **Runs these system commands**, always by absolute path, with fixed arguments and no shell:

  | Command | When | Why |
  |---|---|---|
  | `/usr/bin/killall ptpcamerad` | Just before connecting to a Canon camera it has found | macOS's `ptpcamerad` claims every camera that's plugged in, which blocks VENCamera. macOS restarts it on its own. |
  | `/usr/bin/pgrep -x EOSWebcamService` | When the camera can't be reached | Checks whether Canon's webcam service is holding it. |
  | `/bin/launchctl bootout gui/<your user ID>/com.canon.usa.EWCService` | Only after you choose *Use the Camera in VENCamera* | Pauses Canon's webcam service until you log out. Canon's files aren't changed. |
  | `/bin/launchctl bootstrap gui/<your user ID> /Library/LaunchAgents/com.canon.usa.EWCService.plist` | When you choose *Hand the Camera Back to EOS Webcam Utility* | Restarts Canon's service. |

- **Opens OBS** in the background with `--startvirtualcam --minimize-to-tray --disable-shutdown-check` when the camera connects, if *Start OBS Virtual Camera Automatically* is on. `--disable-shutdown-check` stops OBS from asking about safe mode after OBS itself quit unexpectedly.

VENCamera needs no administrator password, no special macOS permissions and no system extension.

## Things to know before you install
- **Other apps can see the video.** Syphon servers can be read by any app on your Mac, without a camera permission prompt. That isn't much of a change from normal: macOS's camera permission doesn't cover USB cameras that use PTP, so any app could already talk to the camera directly. Quit VENCamera when you don't want the camera live.
- **There's no green camera light.** macOS only shows its camera indicator for webcams it manages, so it won't light up for VENCamera itself. VENCamera's menu bar icon is filled while the camera is live.
- **Photo imports from other cameras can be interrupted.** Stopping `ptpcamerad` can briefly interrupt Image Capture or Photos importing from another camera or an iPhone. It only happens when VENCamera connects to a Canon camera.

## Install only from source
Build VENCamera yourself with `make install` (see the README). That's the safe way to install it:
- The app is **ad-hoc signed and not notarized by Apple**. A copy downloaded from the internet would be blocked by Gatekeeper. Don't download prebuilt copies from anyone, and don't bypass Gatekeeper (for example with `xattr` or "Open Anyway") to run one.
- A local build links to Homebrew's libgphoto2 on your Mac. It isn't a self-contained app that could run on another Mac.

## Audit, November 2026
Before the repository was published, the code, the build files and the full git history were reviewed.

### Fixed
| Issue | Risk | Fix |
|---|---|---|
| A closed camera session could be silently reopened, because libgphoto2 reconnects on the next call. A late settings refresh could then hold the camera indefinitely, for example across sleep. | Medium: camera stays claimed, other apps locked out | Closed sessions now refuse every call. |
| Canon's webcam service was paused automatically, without asking. | Medium: changes another vendor's software without consent | Now opt-in: VENCamera asks the first time and remembers the answer. |
| Memory grew by about 70 MB a second while live (26 GB observed), which can make a Mac unresponsive. | High: availability | Fixed in `a58505f`. Memory now stays at about 60–100 MB. |
| A camera session left open across Mac sleep could leave the camera unresponsive until it was switched off and on. | Low: availability | Fixed in `baf179c`. The session is now closed before sleep and reopened after wake. |
| The README referred to the author's own Mac and to a private file path. | Low: personal information | Rewritten for public readers. |

### Checked, no problem found
- **Secrets:** no API keys, tokens, passwords or private keys in any file or in the git history. No large or binary files apart from the app icon.
- **Command execution:** the commands listed above all use absolute paths and fixed arguments, and nothing from the camera or the user is passed to a shell.
- **Network:** the app makes no network connections.
- **Inputs from the camera:** frames are decoded by Apple's ImageIO, and camera data is parsed by libgphoto2 (LGPL-2.1, from Homebrew). A malicious USB device posing as a camera is the remaining attack surface. That's the same as for any app that supports PTP cameras.
- **Third-party code:** Syphon is vendored from a recorded upstream commit, with every change listed in `Sources/Syphon/VENDORED.md`. libgphoto2 and OBS come from Homebrew.
- **Build files:** `Package.swift` and the `Makefile` only build, copy and ad-hoc sign the app. The only file `make install` deletes is a previous `/Applications/VENCamera.app`.

### Done before publishing
- **License:** MIT, in `LICENSE`. The vendored Syphon code keeps its BSD-2 license.
- **Personal information:** every file version, commit message and commit identity in the history was checked for personal details (email addresses, home folder paths, device and computer names, network addresses). The author's personal email was replaced with a GitHub `noreply` address throughout the history.
- **GitHub settings:** *Private vulnerability reporting*, *Secret scanning* and *Push protection* are on.

### Still open
- **Prebuilt downloads:** only offer these after setting up Developer ID signing, the hardened runtime and Apple notarization, and bundling libgphoto2 with its LGPL notice.

## Reporting a vulnerability
Please don't open a public issue for a security problem. Use GitHub's **Report a vulnerability** button on this repository's Security tab, so the report stays private until it's fixed.
