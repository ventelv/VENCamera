import AppKit
import SwiftUI

/// Hands frames from the live view thread to the on-screen preview layer.
final class PreviewSink: @unchecked Sendable {
    private let lock = NSLock()
    private weak var layer: CALayer?

    func attach(_ layer: CALayer) {
        lock.withLock { self.layer = layer }
    }

    /// Only the newest frame is kept, so frames can't pile up if the main thread is busy.
    private var pending: (frame: CGImage, mirrored: Bool)?

    func show(_ frame: CGImage, mirrored: Bool) {
        let needsUpdate: Bool = lock.withLock {
            guard layer != nil else { return false }
            let wasIdle = pending == nil
            pending = (frame, mirrored)
            return wasIdle
        }
        guard needsUpdate else { return }
        DispatchQueue.main.async { [self] in
            guard let (layer, next) = lock.withLock({ () -> (CALayer, (frame: CGImage, mirrored: Bool))? in
                defer { pending = nil }
                guard let layer, let pending else { return nil }
                return (layer, pending)
            }) else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contents = next.frame
            layer.setAffineTransform(next.mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
            CATransaction.commit()
        }
    }

    func clear() {
        guard let layer = lock.withLock({ self.layer }) else { return }
        DispatchQueue.main.async { layer.contents = nil }
    }
}

struct PreviewView: NSViewRepresentable {
    let sink: PreviewSink

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = CALayer()
        layer.contentsGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        view.layer = layer
        sink.attach(layer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
