import AppKit

let destination = CommandLine.arguments[1]
var representations = Data()

// Include native sizes for Finder, Spotlight, and Retina displays.
for (type, size) in [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128),
                     ("ic08", 256), ("ic09", 512), ("ic10", 1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(size) / 512)
    scale.concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    if size == 1024 {
        try png.write(to: URL(fileURLWithPath: destination).deletingPathExtension().appendingPathExtension("png"))
    }
    representations.append(Data(type.utf8))
    var length = UInt32(8 + png.count).bigEndian
    representations.append(Data(bytes: &length, count: 4))
    representations.append(png)
}

var icon = Data("icns".utf8)
var total = UInt32(8 + representations.count).bigEndian
icon.append(Data(bytes: &total, count: 4))
icon.append(representations)
try icon.write(to: URL(fileURLWithPath: destination))

func drawIcon() {
    NSColor(calibratedWhite: 0.90, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 51, y: 47, width: 410, height: 410), xRadius: 92, yRadius: 92).fill()
    NSColor(calibratedWhite: 0.975, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 51, y: 51, width: 410, height: 410), xRadius: 92, yRadius: 92).fill()
    let frame = NSBezierPath()
    frame.move(to: NSPoint(x: 270, y: 348))
    frame.line(to: NSPoint(x: 188, y: 348))
    frame.curve(to: NSPoint(x: 164, y: 324), controlPoint1: NSPoint(x: 175, y: 348), controlPoint2: NSPoint(x: 164, y: 337))
    frame.line(to: NSPoint(x: 164, y: 188))
    frame.curve(to: NSPoint(x: 188, y: 164), controlPoint1: NSPoint(x: 164, y: 175), controlPoint2: NSPoint(x: 175, y: 164))
    frame.line(to: NSPoint(x: 324, y: 164))
    frame.curve(to: NSPoint(x: 348, y: 188), controlPoint1: NSPoint(x: 337, y: 164), controlPoint2: NSPoint(x: 348, y: 175))
    frame.line(to: NSPoint(x: 348, y: 270))
    frame.lineWidth = 39
    frame.lineCapStyle = .butt
    NSColor(red: 0.09, green: 0.13, blue: 0.22, alpha: 1).setStroke()
    frame.stroke()
    NSColor(red: 0.16, green: 0.36, blue: 0.98, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 317, y: 317, width: 62, height: 62), xRadius: 14, yRadius: 14).fill()
}
