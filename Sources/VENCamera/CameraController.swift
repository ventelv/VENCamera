import AppKit
import CanonKit
import CGPhoto2
import ImageIO

/// Owns the camera connection, the live view loop and the settings the UI shows.
@MainActor
final class CameraController: ObservableObject {
    enum Status: Equatable {
        case searching
        case blockedByCanonApp
        case handedBackToCanon
        case live
        case failed(String)
    }

    @Published private(set) var status: Status = .searching
    @Published private(set) var model = ""
    @Published private(set) var framesPerSecond = 0.0
    @Published private(set) var settings: [String: CameraSetting] = [:]
    @Published private(set) var lastError: String?
    @Published var mirrored = UserDefaults.standard.bool(forKey: "mirrored") {
        didSet { UserDefaults.standard.set(mirrored, forKey: "mirrored"); frameOptions.mirrored = mirrored }
    }
    @Published var sharpness = UserDefaults.standard.object(forKey: "sharpness") as? Double ?? 0.4 {
        didSet { UserDefaults.standard.set(sharpness, forKey: "sharpness"); frameOptions.sharpness = sharpness }
    }
    /// Take the camera from Canon's webcam service automatically, so VENCamera works every time.
    /// Open OBS in the background with its virtual camera on whenever the camera connects.
    @Published var startsOBS = UserDefaults.standard.object(forKey: "startsOBS") as? Bool ?? true {
        didSet { UserDefaults.standard.set(startsOBS, forKey: "startsOBS"); if startsOBS, status == .live { OBSLauncher.launchIfNeeded() } }
    }
    @Published var takesCameraFromCanon = UserDefaults.standard.object(forKey: "takesCameraFromCanon") as? Bool ?? true {
        didSet { UserDefaults.standard.set(takesCameraFromCanon, forKey: "takesCameraFromCanon") }
    }

    /// The preview view draws whatever is here; it's set from the live view thread.
    let preview = PreviewSink()

    private let frameOptions = FrameOptions()
    private let pipeline = FramePipeline()
    private let work = DispatchQueue(label: "VENCamera.settings", qos: .userInitiated)
    private var camera: CanonCamera?
    private var liveView: Thread?
    private var liveViewStopped: DispatchSemaphore?
    private var reconnectTimer: Timer?
    private var settingsTimer: Timer?

    init() {
        frameOptions.mirrored = mirrored
        frameOptions.sharpness = sharpness
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.connectIfNeeded() }
        }
        connectIfNeeded()
    }

    var outputIsAvailable: Bool { pipeline != nil }

    // MARK: Connection

    private var isConnecting = false

    func connectIfNeeded() {
        guard camera == nil, !isConnecting, status != .handedBackToCanon else { return }
        isConnecting = true
        let takeFromCanon = takesCameraFromCanon
        work.async { [self] in
            if takeFromCanon, CanonWebcamService.isHoldingCamera {
                CanonWebcamService.release()
                Thread.sleep(forTimeInterval: 1) // let the USB claim go
            }
            let result = Result { try CanonCamera.connect() }
            Task { @MainActor in finishConnecting(result) }
        }
    }

    private func finishConnecting(_ result: Result<CanonCamera, Error>) {
        isConnecting = false
        switch result {
        case .success(let camera):
            self.camera = camera
            model = camera.model
            status = .live
            lastError = nil
            startLiveView(on: camera)
            refreshSettings()
            if startsOBS { OBSLauncher.launchIfNeeded() }
        case .failure(let error as GPhotoError) where error.isUSBClaimed:
            status = CanonWebcamService.isHoldingCamera ? .blockedByCanonApp : .failed("Another app is using the camera.")
        case .failure(let error as GPhotoError) where error.code == -105:
            // GP_ERROR_MODEL_NOT_FOUND: no camera, or Canon's service has it and hides it from USB.
            status = CanonWebcamService.isHoldingCamera ? .blockedByCanonApp : .searching
        case .failure(let error as GPhotoError) where error.code == GP_ERROR_IO || error.code == GP_ERROR_TIMEOUT:
            // The M50 can get stuck mid-session (for example after an app was force-quit); only a power cycle clears it.
            status = .failed("The camera isn't responding. Switch it off and on again.")
        case .failure(let error):
            status = .failed(String(describing: error))
        }
    }

    /// Takes the camera from Canon's webcam app and service right now.
    func takeCameraFromCanon() {
        if status == .handedBackToCanon { status = .searching }
        work.async { CanonWebcamService.release() }
        connectIfNeeded()
    }

    /// Lets go of the camera and restarts Canon's webcam app, until you take it back.
    func handCameraBackToCanon() {
        disconnect(reason: nil)
        status = .handedBackToCanon
        work.async { CanonWebcamService.restore() }
    }

    /// Stops live view and closes the camera session cleanly. Called when quitting, too.
    func shutdown() {
        disconnect(reason: nil)
    }

    private func disconnect(reason: String?) {
        liveView?.cancel()
        _ = liveViewStopped?.wait(timeout: .now() + 1)
        liveView = nil
        liveViewStopped = nil
        camera?.close()
        camera = nil
        framesPerSecond = 0
        preview.clear()
        status = .searching
        lastError = reason
    }

    // MARK: Live view

    private func startLiveView(on camera: CanonCamera) {
        try? camera.setLiveViewSize(.large)
        let pipeline = pipeline
        let options = frameOptions
        let preview = preview
        let owner = WeakBox(self)
        let stopped = DispatchSemaphore(value: 0)
        let thread = Thread {
            defer { stopped.signal() }
            var failures = 0
            var frames = 0
            var windowStart = Date()
            while !Thread.current.isCancelled {
                // Core Image, Metal and Syphon hand back autoreleased objects every frame. This
                // thread never returns to a run loop, so without a pool per frame they're never
                // freed and memory grows by gigabytes an hour.
                let keepGoing: Bool = autoreleasepool {
                    guard let jpeg = try? camera.capturePreview(), let frame = Self.decode(jpeg) else {
                        failures += 1
                        if failures >= 5 {
                            Task { @MainActor in owner.value?.disconnect(reason: "Lost the camera. Check that it's on and plugged in.") }
                            return false
                        }
                        Thread.sleep(forTimeInterval: 0.1)
                        return true
                    }
                    failures = 0
                    pipeline?.publish(frame, mirrored: options.mirrored, sharpness: options.sharpness)
                    preview.show(frame, mirrored: options.mirrored)

                    frames += 1
                    let elapsed = Date().timeIntervalSince(windowStart)
                    if elapsed >= 1 {
                        let fps = Double(frames) / elapsed
                        frames = 0
                        windowStart = Date()
                        Task { @MainActor in owner.value?.framesPerSecond = fps }
                    }
                    return true
                }
                if !keepGoing { return }
            }
        }
        thread.name = "VENCamera.liveView"
        thread.qualityOfService = .userInteractive
        thread.start()
        liveView = thread
        liveViewStopped = stopped
    }

    private nonisolated static func decode(_ jpeg: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    // MARK: Settings

    /// Keeps the settings in sync with the camera's own dials while the settings window is open.
    func settingsWindowVisible(_ visible: Bool) {
        settingsTimer?.invalidate()
        settingsTimer = nil
        guard visible else { return }
        refreshSettings()
        settingsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSettings() }
        }
    }

    func refreshSettings() {
        guard let camera else { return }
        work.async { [self] in
            var fresh: [String: CameraSetting] = [:]
            for name in CanonSettingName.controlPanel {
                if let setting = try? camera.setting(name) { fresh[name] = setting }
            }
            let snapshot = fresh
            Task { @MainActor in settings = snapshot }
        }
    }

    func set(_ name: String, to value: String) {
        guard let camera else { return }
        work.async { [self] in
            let result = Result { try camera.set(name, to: value) }
            let updated = try? camera.setting(name)
            Task { @MainActor in
                if case .failure(let error) = result { lastError = "Couldn't change \(name): \(error)" }
                if let updated { settings[name] = updated }
            }
        }
    }

    /// Triggers a camera action such as a one-time autofocus or a focus nudge.
    func perform(_ name: String, value: String) {
        guard let camera else { return }
        work.async { [self] in
            if case .failure(let error) = Result(catching: { try camera.set(name, to: value) }) {
                Task { @MainActor in lastError = "Couldn't run \(name): \(error)" }
            }
        }
    }
}

/// Lets the live view thread reach the controller without keeping it alive.
private final class WeakBox<Object: AnyObject>: @unchecked Sendable {
    weak var value: Object?
    init(_ value: Object) { self.value = value }
}

/// Frame options read by the live view thread on every frame.
final class FrameOptions: @unchecked Sendable {
    private let lock = NSLock()
    private var _mirrored = false
    private var _sharpness = 0.4

    var mirrored: Bool {
        get { lock.withLock { _mirrored } }
        set { lock.withLock { _mirrored = newValue } }
    }

    var sharpness: Double {
        get { lock.withLock { _sharpness } }
        set { lock.withLock { _sharpness = newValue } }
    }
}
