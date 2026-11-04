// canon-probe: measures what the connected Canon camera really delivers over USB.
//
// Usage: canon-probe [seconds] [--all]
//   seconds  how long to measure live view (default 10)
//   --all    print every setting the camera exposes, not just the control panel ones
// Run it once with the M50's mode dial on Movie and once on a photo mode.

import CanonKit
import Foundation
import ImageIO

let arguments = CommandLine.arguments.dropFirst()
let seconds = arguments.compactMap(Double.init).first ?? 10
let printAll = arguments.contains("--all")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func pixelSize(ofJPEG data: Data) -> String? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = props[kCGImagePropertyPixelWidth] as? Int,
          let height = props[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return "\(width)×\(height)"
}

func describe(_ setting: CameraSetting) -> String {
    let value = setting.value.map(String.init(describing:)) ?? "—"
    let access = setting.isReadOnly ? " (read-only)" : ""
    let choices: String
    switch setting.choices.count {
    case 0: choices = ""
    case ...40: choices = "\n      choices: " + setting.choices.joined(separator: " | ")
    default: choices = "\n      \(setting.choices.count) choices"
    }
    return "  \(setting.name.padding(toLength: 22, withPad: " ", startingAt: 0)) \(value)\(access)\(choices)"
}

let camera: CanonCamera
do {
    camera = try CanonCamera.connect()
} catch let error as GPhotoError where error.isUSBClaimed {
    fail("Another app is holding the camera. Quit EOS Webcam Utility and EOS Utility, then try again.")
} catch {
    fail("Couldn't connect: \(error)")
}
print("Connected: \(camera.model)\n")

if printAll {
    print("All settings")
    for setting in (try? camera.allSettings()) ?? [] {
        print(describe(setting).replacingOccurrences(of: "  \(setting.name)", with: "  \(setting.path)", options: .anchored))
    }
} else {
    print("Control panel settings (run with --all for everything)")
    for name in CanonSettingName.controlPanel {
        if let setting = try? camera.setting(name) {
            print(describe(setting))
        } else {
            print("  \(name.padding(toLength: 22, withPad: " ", startingAt: 0)) unavailable")
        }
    }
}

let originalSize = (try? camera.setting(CanonSettingName.liveViewSize))?.value.map(String.init(describing:))
do {
    try camera.setLiveViewSize(.large)
} catch {
    print("\nCouldn't switch live view to Large: \(error)")
}

// The first few frames arrive at the old size while the camera switches over.
var previous = Data()
let warmUp = Date().addingTimeInterval(1)
while Date() < warmUp {
    do { previous = try camera.capturePreview() } catch { fail("Live view failed: \(error)") }
}

print("\nMeasuring live view for \(Int(seconds)) s…")
var uniqueFrames = 0
var captures = 0
var totalBytes = 0
var totalCapture: TimeInterval = 0
var sizes: [String: Int] = [:]
let start = Date()
while Date().timeIntervalSince(start) < seconds {
    let before = Date()
    guard let frame = try? camera.capturePreview(), !frame.isEmpty else { continue }
    totalCapture += Date().timeIntervalSince(before)
    captures += 1
    // Asking faster than the camera refreshes returns the same frame again.
    guard frame != previous else { continue }
    previous = frame
    uniqueFrames += 1
    totalBytes += frame.count
    sizes[pixelSize(ofJPEG: frame) ?? "unreadable", default: 0] += 1
}
let elapsed = Date().timeIntervalSince(start)

let samplePath = FileManager.default.currentDirectoryPath + "/probe-frame.jpg"
try? previous.write(to: URL(fileURLWithPath: samplePath))

if let originalSize, let size = LiveViewSize(rawValue: originalSize) { try? camera.setLiveViewSize(size) }
try? camera.stopLiveView()

print("""

Live view results
  Frame size(s):      \(sizes.sorted { $0.value > $1.value }.map { "\($0.key) (\($0.value))" }.joined(separator: ", "))
  Unique frames/s:    \(String(format: "%.1f", Double(uniqueFrames) / elapsed))
  Captures/s:         \(String(format: "%.1f", Double(captures) / elapsed))
  Avg capture time:   \(String(format: "%.1f", captures > 0 ? totalCapture / Double(captures) * 1000 : 0)) ms
  Avg JPEG size:      \(uniqueFrames > 0 ? totalBytes / uniqueFrames / 1024 : 0) KB
  Sample frame:       \(samplePath)
""")
