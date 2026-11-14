import CGPhoto2

public struct GPhotoError: Error, CustomStringConvertible {
    public let code: Int32
    public let call: String

    /// Another process (macOS's ptpcamerad, EOS Webcam Utility, EOS Utility) holds the USB interface.
    public var isUSBClaimed: Bool { code == GP_ERROR_IO_USB_CLAIM }

    public var description: String {
        "\(call) failed: \(String(cString: gp_result_as_string(code))) (\(code))"
    }
}

public enum CanonError: Error, CustomStringConvertible {
    case noSuchSetting(String)
    case unsupportedSettingType(String)
    case closed

    public var description: String {
        switch self {
        case .noSuchSetting(let name): return "The camera has no setting called \"\(name)\"."
        case .unsupportedSettingType(let name): return "The setting \"\(name)\" can't be set this way."
        case .closed: return "The camera session has been closed."
        }
    }
}

@discardableResult
func check(_ result: Int32, _ call: String) throws -> Int32 {
    guard result >= GP_OK else { throw GPhotoError(code: result, call: call) }
    return result
}
