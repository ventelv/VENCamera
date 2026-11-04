import ServiceManagement
import SwiftUI

@main
struct VENCameraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var app

    var body: some Scene {
        MenuBarExtra {
            MenuContent(app: app).environmentObject(app.camera)
        } label: {
            MenuBarIcon().environmentObject(app.camera)
        }
    }
}

/// Owns the camera and the settings window. The window is managed by hand
/// because a menu-bar-only app can't otherwise open a SwiftUI window at launch
/// or when you double-click the app again.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let camera = CameraController()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Open the window on the very first launch so it's obvious where the app lives.
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        camera.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func showSettings() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environmentObject(camera)))
            window.title = "VENCamera"
            window.styleMask.insert([.resizable, .fullSizeContentView])
            window.setContentSize(NSSize(width: 1080, height: 620))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("VENCameraSettings")
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        camera.settingsWindowVisible(true)
    }

    func windowWillClose(_ notification: Notification) {
        camera.settingsWindowVisible(false)
    }
}

private struct MenuBarIcon: View {
    @EnvironmentObject private var camera: CameraController

    var body: some View {
        Image(systemName: camera.menuBarSymbol)
    }
}

private struct MenuContent: View {
    let app: AppDelegate
    @EnvironmentObject private var camera: CameraController
    @State private var startsAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Text(camera.statusText)
        Divider()
        Button("Open VENCamera…") { app.showSettings() }
            .keyboardShortcut(",")
        Toggle("Mirror Image", isOn: $camera.mirrored)
        Divider()
        if camera.status == .blockedByCanonApp || camera.status == .handedBackToCanon {
            Button("Use the Camera in VENCamera") { camera.takeCameraFromCanon() }
        } else {
            Button("Hand the Camera Back to EOS Webcam Utility") { camera.handCameraBackToCanon() }
        }
        Toggle("Always Take the Camera from Canon", isOn: $camera.takesCameraFromCanon)
        Toggle("Start OBS Virtual Camera Automatically", isOn: $camera.startsOBS)
        Divider()
        Toggle("Start at Login", isOn: Binding(
            get: { startsAtLogin },
            set: { enable in
                try? enable ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                startsAtLogin = SMAppService.mainApp.status == .enabled
            }
        ))
        Button("Quit VENCamera") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

extension CameraController {
    var menuBarSymbol: String {
        switch status {
        case .live: return "camera.fill"
        case .searching, .handedBackToCanon: return "camera"
        case .blockedByCanonApp, .failed: return "exclamationmark.triangle"
        }
    }

    var statusText: String {
        switch status {
        case .live: return "\(model) · \(String(format: "%.0f", framesPerSecond)) fps"
        case .searching: return "Looking for the camera…"
        case .blockedByCanonApp: return "EOS Webcam Utility is using the camera"
        case .handedBackToCanon: return "The camera is with EOS Webcam Utility"
        case .failed(let reason): return reason
        }
    }
}
