// canon-probe: measures what the connected Canon camera really delivers over USB.
//
// Usage: canon-probe [seconds] [--all] [name=value ...]
//   seconds     how long to measure live view (default 10)
//   --all       print every setting the camera exposes, not just the control panel ones
//   name=value  change a setting while live view runs (as VENCamera does), e.g.
//               exposurecompensation=0.3 or whitebalance=Daylight, and report the
//               picture's brightness and color before and after
// Run it once with the M50's mode dial on Movie and once on a photo mode.

import CanonKit
import Foundation
import ImageIO

let arguments = CommandLine.arguments.dropFirst()
let seconds = arguments.compactMap(Double.init).first ?? 10
let printAll = arguments.contains("--all")
let changes = arguments.filter { $0.contains("=") }.map { $0.split(separator: "=", maxSplits: 1).map(String.init) }

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

/// The frame's average red, green and blue (0–255), from a small downscaled copy.
func averageColor(ofJPEG data: Data) -> (r: Double, g: Double, b: Double)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let width = 32, height = 18
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var sums = (0.0, 0.0, 0.0)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        sums.0 += Double(pixels[index]); sums.1 += Double(pixels[index + 1]); sums.2 += Double(pixels[index + 2])
    }
    let count = Double(width * height)
    return (sums.0 / count, sums.1 / count, sums.2 / count)
}

func describeColor(_ color: (r: Double, g: Double, b: Double)?) -> String {
    guard let color else { return "unreadable" }
    let brightness = 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
    return String(format: "brightness %.0f, red/blue %.2f", brightness, color.r / max(color.b, 1))
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

if !changes.isEmpty {
    print("\nChanging settings during live view")
    print("  Before:  \(describeColor(averageColor(ofJPEG: previous)))")
    for change in changes {
        do {
            try camera.set(change[0], to: change[1])
            let now = try camera.setting(change[0]).value.map(String.init(describing:)) ?? "—"
            print("  Set \(change[0]) to \(change[1]); the camera now reports \(now)")
        } catch {
            print("  Couldn't set \(change[0]): \(error)")
        }
    }
    // Keep live view running while the camera's exposure and white balance settle.
    let settle = Date().addingTimeInterval(2)
    while Date() < settle {
        if let frame = try? camera.capturePreview(), !frame.isEmpty { previous = frame }
    }
    print("  After:   \(describeColor(averageColor(ofJPEG: previous)))")
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
