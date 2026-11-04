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

    deinit {
        gp_camera_exit(camera, context)
        gp_camera_unref(camera)
        gp_context_unref(context)
    }

    /// Connects to the first camera libgphoto2 finds.
    ///
    /// macOS's ptpcamerad grabs every PTP camera as soon as it's plugged in, so it's
    /// stopped first and the claim is retried while it respawns.
    public static func connect() throws -> CanonCamera {
        let queue = DispatchQueue(label: "VENCamera.gphoto2")
        return try queue.sync {
            guard let context = gp_context_new() else { throw GPhotoError(code: GP_ERROR_NO_MEMORY, call: "gp_context_new") }
            var camera: UnsafeMutablePointer<Camera>?
            try check(gp_camera_new(&camera), "gp_camera_new")
            guard let camera else { throw GPhotoError(code: GP_ERROR_NO_MEMORY, call: "gp_camera_new") }

            var attempt = 0
            while true {
                stopPTPCameraDaemon()
                let result = gp_camera_init(camera, context)
                if result >= GP_OK { break }
                attempt += 1
                if result != GP_ERROR_IO_USB_CLAIM || attempt == 5 {
                    gp_camera_unref(camera)
                    gp_context_unref(context)
                    throw GPhotoError(code: result, call: "gp_camera_init")
                }
                Thread.sleep(forTimeInterval: 0.3)
            }

            var abilities = CameraAbilities()
            gp_camera_get_abilities(camera, &abilities)
            let model = withUnsafeBytes(of: abilities.model) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return CanonCamera(camera: camera, context: context, model: model, queue: queue)
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
        try queue.sync {
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
        try queue.sync {
            let widget = try singleConfig(name)
            defer { gp_widget_free(widget) }
            return Self.describe(widget, path: name)
        }
    }

    /// Changes a text or choice setting, such as `set("iso", to: "400")`.
    public func set(_ name: String, to value: String) throws {
        try queue.sync {
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
        try queue.sync {
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
