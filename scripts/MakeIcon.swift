import AppKit
import Foundation

guard let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Icon canvas unavailable") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.065, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
let accent = NSColor(calibratedRed: 0.80, green: 0.91, blue: 0.66, alpha: 1)
let text = NSAttributedString(string: "B", attributes: [.font: NSFont(name: "Baskerville", size: 570) ?? NSFont.systemFont(ofSize: 570), .foregroundColor: accent])
text.draw(at: NSPoint(x: (1024 - text.size().width) / 2, y: 170))
accent.setStroke()
for (x, y, dx, dy) in [(150.0,150.0,1.0,1.0), (874,150,-1,1), (150,874,1,-1), (874,874,-1,-1)] {
    let path = NSBezierPath()
    path.lineWidth = 6
    path.move(to: NSPoint(x: x + dx * 85, y: y))
    path.line(to: NSPoint(x: x, y: y))
    path.line(to: NSPoint(x: x, y: y + dy * 85))
    path.stroke()
}
NSGraphicsContext.restoreGraphicsState()
guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("Icon generation failed") }
let path = CommandLine.arguments[1]
try png.write(to: URL(fileURLWithPath: path))
