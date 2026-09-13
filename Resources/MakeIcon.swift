import AppKit
let destination = CommandLine.arguments[1]
let image = NSImage(size: NSSize(width: 512, height: 512))
image.lockFocus()
let rect = NSRect(x: 28, y: 28, width: 456, height: 456)
let path = NSBezierPath(roundedRect: rect, xRadius: 105, yRadius: 105)
NSGradient(starting: NSColor(red: 0.17, green: 0.59, blue: 1, alpha: 1),
           ending: NSColor(red: 0.05, green: 0.3, blue: 0.87, alpha: 1))!.draw(in: path, angle: -90)
let pulse = NSBezierPath()
pulse.move(to: NSPoint(x: 108, y: 247)); pulse.line(to: NSPoint(x: 188, y: 247))
pulse.line(to: NSPoint(x: 227, y: 356)); pulse.line(to: NSPoint(x: 282, y: 159))
pulse.line(to: NSPoint(x: 320, y: 247)); pulse.line(to: NSPoint(x: 402, y: 247))
pulse.lineWidth = 25; pulse.lineCapStyle = .round; pulse.lineJoinStyle = .round
NSColor.white.setStroke(); pulse.stroke()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = bitmap.representation(using: .png, properties: [:])!
// An icns container with one 512px PNG representation.
var icon = Data("icns".utf8)
var total = UInt32(16 + png.count).bigEndian
icon.append(Data(bytes: &total, count: 4)); icon.append(Data("ic09".utf8))
var length = UInt32(8 + png.count).bigEndian
icon.append(Data(bytes: &length, count: 4)); icon.append(png)
try icon.write(to: URL(fileURLWithPath: destination))
