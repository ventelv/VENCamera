import CGPhoto2
import Foundation

/// An open connection to a Canon camera over USB, through libgphoto2.
///
/// libgphoto2 isn't re-entrant, so every call goes through one serial queue.
public final class CanonCamera: @unchecked Sendable {
    public let model: String
    private let camera: UnsafeMutablePointer<Camera>
    private let context: OpaquePointer
    private let queue: DispatchQueue

    private init(camera: UnsafeMutablePointer<Camera>, context: OpaquePointer, model: String, queue: DispatchQueue) {
        self.camera = camera
        self.context = context
        self.model = model
        self.queue = queue
    }

    private var isClosed = false

    deinit {
        if !isClosed { gp_camera_exit(camera, context) }
        gp_camera_unref(camera)
        gp_context_unref(context)
    }

    /// Ends live view and the camera session so the next app can connect straight away.
    /// Safe to call more than once; later calls on a closed camera fail.
    /// Runs `body` on the camera's queue, refusing once the camera is closed. libgphoto2
    /// silently reopens a closed session on the next call, which would claim the camera
    /// again behind VENCamera's back (for example across sleep) and never release it.
    private func whileOpen<T>(_ body: () throws -> T) throws -> T {
        try queue.sync {
            guard !isClosed else { throw CanonError.closed }
            return try body()
        }
    }

    public func close() {
        queue.sync {
            guard !isClosed else { return }
            isClosed = true
            gp_camera_exit(camera, context)
        }
    }

    /// Connects to the first Canon camera on USB, ignoring other cameras such as a plugged-in iPhone.
    ///
    /// macOS's ptpcamerad grabs every PTP camera as soon as it's plugged in, so it's
    /// stopped first and the claim is retried while it respawns.
    public static func connect() throws -> CanonCamera {
        let queue = DispatchQueue(label: "VENCamera.gphoto2")
        return try queue.sync {
            guard let context = gp_context_new() else { throw GPhotoError(code: GP_ERROR_NO_MEMORY, call: "gp_context_new") }
            var lastError = GPhotoError(code: GP_ERROR_MODEL_NOT_FOUND, call: "Canon camera detection")
            do {
                // libgphoto2 can list the same camera twice (one entry is a stale port), so try each.
                for (model, port) in try detectCanonCameras(context) {
                    do {
                        let camera = try open(model: model, port: port, context: context)
                        return CanonCamera(camera: camera, context: context, model: model, queue: queue)
                    } catch let error as GPhotoError {
                        lastError = error
                    }
                }
            } catch {
                gp_context_unref(context)
                throw error
            }
            gp_context_unref(context)
            throw lastError
        }
    }

    private static func detectCanonCameras(_ context: OpaquePointer) throws -> [(model: String, port: String)] {
        var abilitiesList: OpaquePointer?
        var portList: OpaquePointer?
        var detected: OpaquePointer?
        try check(gp_abilities_list_new(&abilitiesList), "gp_abilities_list_new")
        defer { gp_abilities_list_free(abilitiesList) }
        try check(gp_port_info_list_new(&portList), "gp_port_info_list_new")
        defer { gp_port_info_list_free(portList) }
        try check(gp_list_new(&detected), "gp_list_new")
        defer { gp_list_unref(detected) }

        try check(gp_abilities_list_load(abilitiesList, context), "gp_abilities_list_load")
        try check(gp_port_info_list_load(portList), "gp_port_info_list_load")
        try check(gp_abilities_list_detect(abilitiesList, portList, detected, context), "gp_abilities_list_detect")

        var cameras: [(String, String)] = []
        for index in 0..<max(0, gp_list_count(detected)) {
            var name: UnsafePointer<CChar>?
            var port: UnsafePointer<CChar>?
            guard gp_list_get_name(detected, index, &name) >= GP_OK,
                  gp_list_get_value(detected, index, &port) >= GP_OK,
                  let name, let port
            else { continue }
            let model = String(cString: name)
            if model.hasPrefix("Canon") { cameras.append((model, String(cString: port))) }
        }
        return cameras
    }

    private static func open(model: String, port: String, context: OpaquePointer) throws -> UnsafeMutablePointer<Camera> {
        var abilitiesList: OpaquePointer?
        var portList: OpaquePointer?
        try check(gp_abilities_list_new(&abilitiesList), "gp_abilities_list_new")
        defer { gp_abilities_list_free(abilitiesList) }
        try check(gp_port_info_list_new(&portList), "gp_port_info_list_new")
        defer { gp_port_info_list_free(portList) }
        try check(gp_abilities_list_load(abilitiesList, context), "gp_abilities_list_load")
        try check(gp_port_info_list_load(portList), "gp_port_info_list_load")

        var camera: UnsafeMutablePointer<Camera>?
        try check(gp_camera_new(&camera), "gp_camera_new")
        guard let camera else { throw GPhotoError(code: GP_ERROR_NO_MEMORY, call: "gp_camera_new") }
        do {
            var abilities = CameraAbilities()
            let modelIndex = try check(gp_abilities_list_lookup_model(abilitiesList, model), "gp_abilities_list_lookup_model")
            try check(gp_abilities_list_get_abilities(abilitiesList, modelIndex, &abilities), "gp_abilities_list_get_abilities")
            try check(gp_camera_set_abilities(camera, abilities), "gp_camera_set_abilities")

            var portInfo: GPPortInfo?
            let portIndex = try check(gp_port_info_list_lookup_path(portList, port), "gp_port_info_list_lookup_path")
            try check(gp_port_info_list_get_info(portList, portIndex, &portInfo), "gp_port_info_list_get_info")
            try check(gp_camera_set_port_info(camera, portInfo), "gp_camera_set_port_info")

            var attempt = 0
            while true {
                stopPTPCameraDaemon()
                let result = gp_camera_init(camera, context)
                if result >= GP_OK { return camera }
                attempt += 1
                if result != GP_ERROR_IO_USB_CLAIM || attempt == 5 {
                    throw GPhotoError(code: result, call: "gp_camera_init(\(port))")
                }
                Thread.sleep(forTimeInterval: 0.3)
            }
        } catch {
            gp_camera_unref(camera)
            throw error
        }
    }

    private static func stopPTPCameraDaemon() {
        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["ptpcamerad"]
        killall.standardError = FileHandle.nullDevice
        try? killall.run()
        killall.waitUntilExit()
    }

    // MARK: Settings

    /// Every setting the camera exposes, depth first.
    public func allSettings() throws -> [CameraSetting] {
        try whileOpen {
            var root: OpaquePointer?
            try check(gp_camera_get_config(camera, &root, context), "gp_camera_get_config")
            guard let root else { return [] }
            defer { gp_widget_free(root) }
            var settings: [CameraSetting] = []
            Self.collect(root, parentPath: "", into: &settings)
            return settings
        }
    }

    public func setting(_ name: String) throws -> CameraSetting {
        try whileOpen {
            let widget = try singleConfig(name)
            defer { gp_widget_free(widget) }
            return Self.describe(widget, path: name)
        }
    }

    /// Changes a text or choice setting, such as `set("iso", to: "400")`.
    public func set(_ name: String, to value: String) throws {
        try whileOpen {
            let widget = try singleConfig(name)
            defer { gp_widget_free(widget) }
            switch Self.kind(of: widget) {
            case .text, .choice:
                _ = try value.withCString { try check(gp_widget_set_value(widget, $0), "gp_widget_set_value(\(name))") }
            case .range:
                guard var number = Float(value) else { throw CanonError.unsupportedSettingType(name) }
                try check(gp_widget_set_value(widget, &number), "gp_widget_set_value(\(name))")
            case .toggle:
                var flag: Int32 = ["1", "on", "true"].contains(value.lowercased()) ? 1 : 0
                try check(gp_widget_set_value(widget, &flag), "gp_widget_set_value(\(name))")
            default:
                throw CanonError.unsupportedSettingType(name)
            }
            try check(gp_camera_set_single_config(camera, name, widget, context), "gp_camera_set_single_config(\(name))")
        }
    }

    // MARK: Live view

    public func setLiveViewSize(_ size: LiveViewSize) throws {
        try set(CanonSettingName.liveViewSize, to: size.rawValue)
    }

    /// Captures one live view JPEG. The first call switches the camera into live view.
    public func capturePreview() throws -> Data {
        try whileOpen {
            var file: OpaquePointer?
            try check(gp_file_new(&file), "gp_file_new")
            defer { gp_file_unref(file) }
            try check(gp_camera_capture_preview(camera, file, context), "gp_camera_capture_preview")

            var bytes: UnsafePointer<CChar>?
            var size: UInt = 0
            try check(gp_file_get_data_and_size(file, &bytes, &size), "gp_file_get_data_and_size")
            guard let bytes, size > 0 else { return Data() }
            return Data(bytes: bytes, count: Int(size))
        }
    }

    public func stopLiveView() throws {
        try set(CanonSettingName.viewfinder, to: "0")
    }

    // MARK: Widget helpers (call on `queue` only)

    private func singleConfig(_ name: String) throws -> OpaquePointer {
        var widget: OpaquePointer?
        let result = gp_camera_get_single_config(camera, name, &widget, context)
        if result == GP_ERROR_BAD_PARAMETERS { throw CanonError.noSuchSetting(name) }
        try check(result, "gp_camera_get_single_config(\(name))")
        guard let widget else { throw CanonError.noSuchSetting(name) }
        return widget
    }

    private static func collect(_ widget: OpaquePointer, parentPath: String, into settings: inout [CameraSetting]) {
        let path = parentPath + "/" + text(gp_widget_get_name, widget)
        let count = gp_widget_count_children(widget)
        if count > 0 {
            for index in 0..<count {
                var child: OpaquePointer?
                if gp_widget_get_child(widget, index, &child) >= GP_OK, let child {
                    collect(child, parentPath: path, into: &settings)
                }
            }
        } else if kind(of: widget) != .section {
            settings.append(describe(widget, path: path))
        }
    }

    private static func describe(_ widget: OpaquePointer, path: String) -> CameraSetting {
        let kind = kind(of: widget)
        var readOnly: Int32 = 0
        gp_widget_get_readonly(widget, &readOnly)

        var choices: [String] = []
        if kind == .choice {
            for index in 0..<max(0, gp_widget_count_choices(widget)) {
                var choice: UnsafePointer<CChar>?
                if gp_widget_get_choice(widget, index, &choice) >= GP_OK, let choice {
                    choices.append(String(cString: choice))
                }
            }
        }

        return CameraSetting(
            path: path,
            name: text(gp_widget_get_name, widget),
            label: text(gp_widget_get_label, widget),
            kind: kind,
            value: value(of: widget, kind: kind),
            choices: choices,
            isReadOnly: readOnly != 0
        )
    }

    private static func kind(of widget: OpaquePointer) -> CameraSetting.Kind {
        var type = CameraWidgetType(0)
        gp_widget_get_type(widget, &type)
        switch type {
        case GP_WIDGET_TEXT: return .text
        case GP_WIDGET_RANGE: return .range
        case GP_WIDGET_TOGGLE: return .toggle
        case GP_WIDGET_RADIO, GP_WIDGET_MENU: return .choice
        case GP_WIDGET_BUTTON: return .button
        case GP_WIDGET_DATE: return .date
        default: return .section
        }
    }

    private static func value(of widget: OpaquePointer, kind: CameraSetting.Kind) -> CameraSetting.Value? {
        switch kind {
        case .text, .choice:
            var string: UnsafeMutablePointer<CChar>?
            guard gp_widget_get_value(widget, &string) >= GP_OK, let string else { return nil }
            return .text(String(cString: string))
        case .range:
            var number: Float = 0
            guard gp_widget_get_value(widget, &number) >= GP_OK else { return nil }
            return .number(number)
        case .toggle:
            var flag: Int32 = 0
            guard gp_widget_get_value(widget, &flag) >= GP_OK else { return nil }
            return .toggle(flag != 0)
        case .date:
            var date: Int32 = 0
            guard gp_widget_get_value(widget, &date) >= GP_OK else { return nil }
            return .date(date)
        case .section, .button:
            return nil
        }
    }

    private static func text(
        _ getter: (OpaquePointer?, UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Int32,
        _ widget: OpaquePointer
    ) -> String {
        var string: UnsafePointer<CChar>?
        guard getter(widget, &string) >= GP_OK, let string else { return "" }
        return String(cString: string)
    }
}
