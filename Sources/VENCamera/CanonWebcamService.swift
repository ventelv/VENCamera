import AppKit

/// Canon's EOS Webcam Utility keeps the camera even when its window is closed: a
/// launch agent (`com.canon.usa.EWCService`, which runs EOSWebcamService) starts at
/// login, is kept alive by launchd and claims the camera over USB.
///
/// Taking the camera stops that agent with `launchctl bootout`. That lasts until
/// you log out or hand the camera back; it never edits or deletes Canon's files.
enum CanonWebcamService {
    static let appBundleID = "com.electron.eos-webcam-utility" // EOS Webcam Utility Pro is an Electron app
    static let agentLabel = "com.canon.usa.EWCService"
    static let agentPlist = "/Library/LaunchAgents/com.canon.usa.EWCService.plist"

    static var isHoldingCamera: Bool { appIsRunning || agentIsRunning }

    static var appIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == appBundleID }
    }

    static var agentIsRunning: Bool {
        run("/usr/bin/pgrep", ["-x", "EOSWebcamService"]) == 0
    }

    /// Quits Canon's app and stops its service so VENCamera can claim the camera.
    static func release() {
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == appBundleID {
            app.terminate()
        }
        run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(agentLabel)"])
    }

    /// Restarts Canon's service and opens its app, for when you want to use it instead.
    static func restore() {
        run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", agentPlist])
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
