import CoreImage
import Metal
import Syphon

/// Turns each live view frame into the 1920×1080 picture OBS receives over Syphon.
///
/// The M50 sends 1024×576, which is already 16:9, so the frame is scaled by
/// 1.875 with Lanczos, lightly sharpened and, if asked, mirrored. Everything stays
/// on the GPU: Core Image renders into a Metal texture that Syphon publishes.
final class FramePipeline {
    static let outputSize = CGSize(width: 1920, height: 1080)
    static let serverName = "VENCamera"

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let context: CIContext
    private let output: MTLTexture
    private let server: SyphonMetalServer
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue()
        else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Int(Self.outputSize.width),
            height: Int(Self.outputSize.height),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let output = device.makeTexture(descriptor: descriptor) else { return nil }
        let server = SyphonMetalServer(name: Self.serverName, device: device, options: nil)

        self.device = device
        self.commandQueue = commandQueue
        self.output = output
        self.server = server
        context = CIContext(mtlDevice: device, options: [.workingColorSpace: colorSpace, .cacheIntermediates: false])
    }

    deinit {
        server.stop()
    }

    var hasClients: Bool { server.hasClients }

    func publish(_ frame: CGImage, mirrored: Bool, sharpness: Double) {
        let size = Self.outputSize
        var image = CIImage(cgImage: frame)

        // Scale to cover the output, then center-crop anything that overhangs.
        let scale = max(size.width / image.extent.width, size.height / image.extent.height)
        image = image.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1.0,
        ])
        image = image.transformed(by: CGAffineTransform(
            translationX: (size.width - image.extent.width) / 2 - image.extent.minX,
            y: (size.height - image.extent.height) / 2 - image.extent.minY
        ))
        if sharpness > 0 {
            image = image.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: sharpness])
        }
        if mirrored {
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -size.width, y: 0))
        }
        // No vertical flip: rendering into the Metal texture already gives Syphon a top-left origin.

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        let bounds = CGRect(origin: .zero, size: size)
        context.render(image.cropped(to: bounds), to: output, commandBuffer: commandBuffer, bounds: bounds, colorSpace: colorSpace)
        server.publishFrameTexture(output, on: commandBuffer, imageRegion: bounds, flipped: false)
        commandBuffer.commit()
    }
}
