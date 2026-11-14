import CanonKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var camera: CameraController

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                PreviewView(sink: camera.preview)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay { StatusOverlay() }
                StatusLine()
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(minWidth: 520)

            Divider()

            Form {
                BrightnessSection()
                WhiteBalanceSection()
                PictureSection()
                FocusSection()
                ExposureSection()
            }
            .formStyle(.grouped)
            .frame(width: 400)
            .disabled(camera.status != .live)
        }
        .frame(minHeight: 560)
    }
}

// MARK: Preview area

private struct StatusOverlay: View {
    @EnvironmentObject private var camera: CameraController

    var body: some View {
        switch camera.status {
        case .live:
            EmptyView()
        case .searching:
            message("Looking for the camera…", detail: "Switch the M50 on and connect it with the USB cable.")
        case .blockedByCanonApp:
            VStack(spacing: 10) {
                message(
                    "EOS Webcam Utility is using the camera",
                    detail: "Only one app can use the camera at a time. VENCamera can quit Canon's app and pause its background service until you log out; Canon's files aren't changed. You can turn this off in the menu."
                )
                Button("Use the Camera in VENCamera") { camera.takeCameraFromCanon() }
            }
        case .handedBackToCanon:
            VStack(spacing: 10) {
                message("The camera is with EOS Webcam Utility", detail: "You handed it back to Canon's app.")
                Button("Use the Camera in VENCamera") { camera.takeCameraFromCanon() }
            }
        case .failed(let reason):
            message("Can't connect to the camera", detail: reason)
        }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .foregroundStyle(.white)
    }
}

private struct StatusLine: View {
    @EnvironmentObject private var camera: CameraController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 16) {
                if camera.status == .live {
                    Label(camera.model, systemImage: "camera.fill")
                    if let battery = camera.settings[CanonSettingName.battery]?.value {
                        Label("Battery \(battery.description)", systemImage: "battery.100")
                    }
                    Label(String(format: "%.0f fps", camera.framesPerSecond), systemImage: "speedometer")
                }
            }
            .font(.callout)
            Text(camera.outputIsAvailable
                 ? "Sending 1920×1080 to OBS over Syphon as \"\(FramePipeline.serverName)\". In your call, choose OBS Virtual Camera."
                 : "Couldn't start the video output (no Metal device).")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = camera.lastError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

// MARK: Settings sections

private struct BrightnessSection: View {
    var body: some View {
        Section("Brightness") {
            ChoiceSlider(title: "Exposure compensation", name: CanonSettingName.exposureCompensation) { value in
                value.hasPrefix("-") || value == "0" ? value : "+\(value)"
            }
        }
    }
}

private struct WhiteBalanceSection: View {
    @EnvironmentObject private var camera: CameraController

    var body: some View {
        Section("White balance") {
            ChoicePicker(title: "White balance", name: CanonSettingName.whiteBalance)
            if camera.settings[CanonSettingName.whiteBalance]?.value?.description == "Color Temperature" {
                ChoiceSlider(title: "Color temperature", name: CanonSettingName.colorTemperature) { "\($0) K" }
            }
        }
    }
}

private struct PictureSection: View {
    @EnvironmentObject private var camera: CameraController

    var body: some View {
        Section("Picture") {
            ChoicePicker(title: "Picture Style", name: CanonSettingName.pictureStyle)
            Toggle("Mirror image", isOn: $camera.mirrored)
            LabeledContent("Sharpening") {
                Slider(value: $camera.sharpness, in: 0...1)
            }
        }
    }
}

private struct FocusSection: View {
    @EnvironmentObject private var camera: CameraController

    var body: some View {
        Section("Focus") {
            ChoicePicker(title: "Autofocus method", name: CanonSettingName.afMethod) { choice in
                ["LiveFace": "Face tracking", "LiveZone": "Zone", "Live": "Single point"][choice] ?? choice
            }
            ChoiceToggle(title: "Continuous autofocus", name: CanonSettingName.continuousAF)
            ChoiceToggle(title: "Movie Servo AF", name: CanonSettingName.movieServoAF)
            LabeledContent("Adjust") {
                HStack {
                    Button("Focus now") {
                        camera.perform(CanonSettingName.autofocusDrive, value: "1")
                        camera.perform(CanonSettingName.autofocusDrive, value: "0")
                    }
                    Button("Nearer") { camera.perform(CanonSettingName.manualFocusDrive, value: "Near 1") }
                    Button("Farther") { camera.perform(CanonSettingName.manualFocusDrive, value: "Far 1") }
                }
            }
        }
    }
}

private struct ExposureSection: View {
    @EnvironmentObject private var camera: CameraController

    private var isAutomatic: Bool {
        [CanonSettingName.aperture, CanonSettingName.shutterSpeed, CanonSettingName.iso]
            .allSatisfy { (camera.settings[$0]?.choices.count ?? 0) <= 1 }
    }

    var body: some View {
        Section {
            ChoicePicker(title: "Aperture", name: CanonSettingName.aperture)
            ChoicePicker(title: "Shutter speed", name: CanonSettingName.shutterSpeed)
            ChoicePicker(title: "ISO", name: CanonSettingName.iso)
        } header: {
            Text("Exposure")
        } footer: {
            if isAutomatic {
                Text("The camera is choosing these itself. To set them by hand, put the mode dial on Movie and choose manual exposure (M) in the shooting menu.")
            }
        }
    }
}

// MARK: Controls bound to camera settings

private struct ChoicePicker: View {
    @EnvironmentObject private var camera: CameraController
    let title: String
    let name: String
    var label: (String) -> String = { $0 }

    var body: some View {
        if let setting = camera.settings[name] {
            Picker(title, selection: Binding(
                get: { setting.value?.description ?? "" },
                set: { camera.set(name, to: $0) }
            )) {
                ForEach(setting.choices, id: \.self) { Text(label($0)).tag($0) }
            }
            .disabled(setting.isReadOnly || setting.choices.count <= 1)
        } else {
            LabeledContent(title, value: "—")
        }
    }
}

/// A slider that steps through a setting's choices, for ordered values like exposure or Kelvin.
private struct ChoiceSlider: View {
    @EnvironmentObject private var camera: CameraController
    let title: String
    let name: String
    var label: (String) -> String = { $0 }
    @State private var dragIndex: Double?

    var body: some View {
        if let setting = camera.settings[name], setting.choices.count > 1 {
            let current = Double(setting.choices.firstIndex(of: setting.value?.description ?? "") ?? 0)
            let index = Int((dragIndex ?? current).rounded())
            VStack(alignment: .leading) {
                LabeledContent(title, value: label(setting.choices[index]))
                Slider(
                    value: Binding(get: { dragIndex ?? current }, set: { dragIndex = $0 }),
                    in: 0...Double(setting.choices.count - 1),
                    step: 1
                ) { editing in
                    if !editing, let dragIndex {
                        camera.set(name, to: setting.choices[Int(dragIndex.rounded())])
                        self.dragIndex = nil
                    }
                }
            }
        } else {
            LabeledContent(title, value: "—")
        }
    }
}

/// A toggle for settings the camera exposes as an On/Off choice.
private struct ChoiceToggle: View {
    @EnvironmentObject private var camera: CameraController
    let title: String
    let name: String

    var body: some View {
        if let setting = camera.settings[name] {
            Toggle(title, isOn: Binding(
                get: { setting.value?.description == "On" },
                set: { camera.set(name, to: $0 ? "On" : "Off") }
            ))
        } else {
            LabeledContent(title, value: "—")
        }
    }
}
