import AppKit

/// Starts OBS in the background with its virtual camera on, so the VENCamera feed is
/// available in calls without opening OBS by hand. OBS's scene already contains a
/// Syphon source pointed at "VENCamera", which reconnects whenever VENCamera restarts.
enum OBSLauncher {
    static let bundleID = "com.obsproject.obs-studio"

    static var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static func launchIfNeeded() {
        guard !isRunning, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--startvirtualcam", "--minimize-to-tray", "--disable-shutdown-check"]
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
