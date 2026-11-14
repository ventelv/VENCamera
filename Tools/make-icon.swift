// Draws VENCamera's app icon: white rounded "vc" on a black rounded square, with a
// small red camera where a full stop would be.
//
// Usage: swift Tools/make-icon.swift <output.png>   (writes a 1024×1024 PNG)
// `make icon` turns that PNG into Resources/AppIcon.icns.

import AppKit

let size: CGFloat = 1024
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
let red = CGColor(red: 0.91, green: 0.27, blue: 0.23, alpha: 1)

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift make-icon.swift <output.png>\n".utf8))
    exit(1)
}

let context = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
// Draw in top-left coordinates, like a design tool.
context.translateBy(x: 0, y: size)
context.scaleBy(x: 1, y: -1)

// Background: the standard macOS icon grid, an 824 pt rounded square inset by 100 pt, with a soft shadow.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
context.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
context.setFillColor(black)
context.fillPath()
context.restoreGState()

// Letters: monoline strokes with round caps and joins, on a shared x-height.
let stroke: CGFloat = 58
let top: CGFloat = 405, bottom: CGFloat = 615
let half = stroke / 2
context.setStrokeColor(white)
context.setLineWidth(stroke)
context.setLineCap(.round)
context.setLineJoin(.round)

// "v"
let vLeft: CGFloat = 212, vWidth: CGFloat = 230
context.move(to: CGPoint(x: vLeft + half, y: top + half))
context.addLine(to: CGPoint(x: vLeft + vWidth / 2, y: bottom - half))
context.addLine(to: CGPoint(x: vLeft + vWidth - half, y: top + half))
context.strokePath()

// "c": an open circle, gap facing right.
let cLeft = vLeft + vWidth + 30, cWidth: CGFloat = 200
let cCenter = CGPoint(x: cLeft + cWidth / 2, y: (top + bottom) / 2)
let cRadius = (bottom - top - stroke) / 2
context.addArc(center: cCenter, radius: cRadius, startAngle: .pi * 0.28, endAngle: .pi * 1.72, clockwise: false)
context.strokePath()

// The camera, sitting on the baseline where the full stop was.
let cameraLeft = cLeft + cWidth + 28
let body = CGRect(x: cameraLeft, y: bottom - 76, width: 112, height: 76)
let viewfinder = CGRect(x: cameraLeft + 22, y: body.minY - 18, width: 40, height: 26)
context.setFillColor(red)
context.addPath(CGPath(roundedRect: viewfinder, cornerWidth: 8, cornerHeight: 8, transform: nil))
context.addPath(CGPath(roundedRect: body, cornerWidth: 18, cornerHeight: 18, transform: nil))
context.fillPath()
// Lens: a black ring with a red center, punched into the body.
let lensCenter = CGPoint(x: body.midX + 4, y: body.midY + 2)
context.setFillColor(black)
context.fillEllipse(in: CGRect(x: lensCenter.x - 25, y: lensCenter.y - 25, width: 50, height: 50))
context.setFillColor(red)
context.fillEllipse(in: CGRect(x: lensCenter.x - 12, y: lensCenter.y - 12, width: 24, height: 24))

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, "public.png" as CFString, 1, nil
)!
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
