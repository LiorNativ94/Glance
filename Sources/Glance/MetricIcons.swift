import AppKit
import SwiftUI

// CPU and RAM paths adapted from Lucide's ISC-licensed cpu and memory-stick icons.
// Draw vectors directly so the same crisp glyphs work in SwiftUI and the menu bar.
enum MetricIcons {
    static let cpu = vector(memory: false)
    static let memory = vector(memory: true)
    static let claude = providerLogo("claude")
    static let chatgpt = providerLogo("chatgpt")
    static let glance = NSImage(size: NSSize(width: 24, height: 24), flipped: true) { _ in
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 13, y: 4))
        path.line(to: NSPoint(x: 7, y: 4))
        path.curve(to: NSPoint(x: 4, y: 7), controlPoint1: NSPoint(x: 5, y: 4), controlPoint2: NSPoint(x: 4, y: 5))
        path.line(to: NSPoint(x: 4, y: 17))
        path.curve(to: NSPoint(x: 7, y: 20), controlPoint1: NSPoint(x: 4, y: 19), controlPoint2: NSPoint(x: 5, y: 20))
        path.line(to: NSPoint(x: 17, y: 20))
        path.curve(to: NSPoint(x: 20, y: 17), controlPoint1: NSPoint(x: 19, y: 20), controlPoint2: NSPoint(x: 20, y: 19))
        path.line(to: NSPoint(x: 20, y: 11))
        path.lineWidth = 3
        NSColor.black.setStroke(); path.stroke()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 17, y: 1, width: 6, height: 6), xRadius: 1.5, yRadius: 1.5).fill()
        return true
    }
    static func image(_ name: String) -> NSImage {
        if name == "cpu" { return cpu }
        if name == "memorychip" { return memory }
        if name == "glance" { glance.isTemplate = true; return glance }
        if name == "claude-usage" { return claude }
        if name == "codex-usage" { return chatgpt }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }
    private static func providerLogo(_ name: String) -> NSImage {
        let bundle = Bundle.main.url(forResource: "Glance_Glance", withExtension: "bundle")
            .flatMap(Bundle.init(url:)) ?? Bundle.module
        let image = NSImage(contentsOf: bundle.url(forResource: name, withExtension: "svg")!)!
        image.isTemplate = true
        image.accessibilityDescription = name == "chatgpt" ? "ChatGPT" : "Claude"
        return image
    }
    private static func vector(memory: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: true) { _ in
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.7
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            func segment(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
                path.move(to: NSPoint(x: x1, y: y1)); path.line(to: NSPoint(x: x2, y: y2))
            }
            if memory {
                path.appendRoundedRect(NSRect(x: 2, y: 6, width: 20, height: 10), xRadius: 2, yRadius: 2)
                for x in [8.0, 12, 16] { segment(x, 10, x, 12) }
                for x in [4.0, 8, 12, 16, 20] { segment(x, 16, x, 18) }
                segment(2, 11, 3.5, 11); segment(20.5, 11, 22, 11)
            } else {
                path.appendRoundedRect(NSRect(x: 4, y: 4, width: 16, height: 16), xRadius: 2, yRadius: 2)
                path.appendRoundedRect(NSRect(x: 8, y: 8, width: 8, height: 8), xRadius: 1, yRadius: 1)
                for pin in [7.0, 12, 17] {
                    segment(pin, 2, pin, 4); segment(pin, 20, pin, 22)
                    segment(2, pin, 4, pin); segment(20, pin, 22, pin)
                }
            }
            path.stroke(); return true
        }
        image.isTemplate = true
        return image
    }
}

struct MetricIcon: View {
    let name: String
    var body: some View {
        Image(nsImage: MetricIcons.image(name)).resizable().aspectRatio(contentMode: .fit)
    }
}
