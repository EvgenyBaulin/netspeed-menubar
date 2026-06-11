// Generates images/icon.png (1024×1024 PNG with alpha): a macOS-style
// rounded-square gradient tile with bold ↓/↑ arrows. Replace the PNG with
// your own art any time — scripts/bundle.sh only needs the file to exist.
//
// Run from the project root (immediate mode `swift scripts/...` fails on
// current toolchains with a JIT "Symbols not found" ObjC-interop error,
// so compile first):
//   xcrun swiftc scripts/make-icon.swift -o /tmp/make-icon && /tmp/make-icon
import AppKit

let pixels = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("could not create drawing context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

// Tile: rounded square with a vertical blue gradient (macOS icon grid-ish).
let tile = NSRect(x: 64, y: 64, width: 896, height: 896)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 198, yRadius: 198)
let gradient = NSGradient(
    colors: [
        NSColor(calibratedRed: 0.07, green: 0.32, blue: 0.92, alpha: 1.0),
        NSColor(calibratedRed: 0.27, green: 0.62, blue: 1.00, alpha: 1.0),
    ]
)!
gradient.draw(in: tilePath, angle: 90)

// Bold ↓ / ↑ arrows.
func drawArrow(centerX x: CGFloat, pointingUp: Bool, color: NSColor) {
    let shaftTop: CGFloat = 700
    let shaftBottom: CGFloat = 320
    let head: CGFloat = 132
    let wing: CGFloat = 112

    let path = NSBezierPath()
    path.lineWidth = 64
    path.lineCapStyle = .round
    path.lineJoinStyle = .round

    path.move(to: NSPoint(x: x, y: pointingUp ? shaftBottom : shaftTop))
    path.line(to: NSPoint(x: x, y: pointingUp ? shaftTop : shaftBottom))

    let tipY: CGFloat = pointingUp ? shaftTop : shaftBottom
    let back: CGFloat = pointingUp ? tipY - head : tipY + head
    path.move(to: NSPoint(x: x - wing, y: back))
    path.line(to: NSPoint(x: x, y: tipY))
    path.line(to: NSPoint(x: x + wing, y: back))

    color.setStroke()
    path.stroke()
}

drawArrow(centerX: 380, pointingUp: false, color: .white)
drawArrow(centerX: 644, pointingUp: true, color: NSColor.white.withAlphaComponent(0.62))

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}
let url = URL(fileURLWithPath: "images/icon.png")
try! png.write(to: url)
print("Wrote \(url.path) (\(png.count) bytes, \(pixels)×\(pixels))")
