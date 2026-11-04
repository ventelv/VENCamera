/// One entry in the camera's settings tree, as libgphoto2 exposes it.
public struct CameraSetting: Sendable {
    public enum Kind: Sendable {
        case section, text, range, toggle, choice, button, date
    }

    public enum Value: Sendable, CustomStringConvertible {
        case text(String)
        case number(Float)
        case toggle(Bool)
        case date(Int32)

        public var description: String {
            switch self {
            case .text(let value): return value
            case .number(let value): return String(value)
            case .toggle(let value): return value ? "on" : "off"
            case .date(let value): return String(value)
            }
        }
    }

    /// The path in the tree, such as "/main/imgsettings/iso".
    public let path: String
    /// The key used to read or change it, such as "iso".
    public let name: String
    public let label: String
    public let kind: Kind
    public let value: Value?
    public let choices: [String]
    public let isReadOnly: Bool
}

/// libgphoto2's names for the Canon EOS settings VENCamera's control panel uses.
public enum CanonSettingName {
    public static let model = "cameramodel"
    public static let battery = "batterylevel"
    public static let modeDial = "autoexposuremodedial"
    public static let aperture = "aperture"
    public static let shutterSpeed = "shutterspeed"
    public static let iso = "iso"
    public static let exposureCompensation = "exposurecompensation"
    public static let whiteBalance = "whitebalance"
    public static let colorTemperature = "colortemperature"
    public static let pictureStyle = "picturestyle"
    public static let focusMode = "focusmode"
    public static let afMethod = "afmethod"
    public static let continuousAF = "continuousaf"
    public static let movieServoAF = "movieservoaf"
    public static let liveViewSize = "liveviewsize"
    public static let viewfinder = "viewfinder"

    // Actions rather than settings: writing to them makes the camera do something.
    public static let autofocusDrive = "autofocusdrive"
    public static let manualFocusDrive = "manualfocusdrive"
    public static let zoom = "eoszoom"
    public static let zoomPosition = "eoszoomposition"
    public static let remoteRelease = "eosremoterelease"

    public static let controlPanel = [
        model, battery, modeDial, aperture, shutterSpeed, iso, exposureCompensation,
        whiteBalance, colorTemperature, pictureStyle, focusMode, afMethod, continuousAF,
        movieServoAF, manualFocusDrive, liveViewSize,
    ]
}

/// The M50's live view sizes over USB. Only `large` gives 1024×576; the camera defaults to `small`.
public enum LiveViewSize: String, Sendable {
    case large = "Large"
    case medium = "Medium"
    case small = "Small"
}
