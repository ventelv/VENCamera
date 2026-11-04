import AppKit
import SwiftUI

/// Hands frames from the live view thread to the on-screen preview layer.
final class PreviewSink: @unchecked Sendable {
    private let lock = NSLock()
    private weak var layer: CALayer?

    func attach(_ layer: CALayer) {
        lock.withLock { self.layer = layer }
    }

    func show(_ frame: CGImage, mirrored: Bool) {
        guard let layer = lock.withLock({ self.layer }) else { return }
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contents = frame
            layer.setAffineTransform(mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity)
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
