import AppKit

// Draws a 1024x1024 app icon: warm "Claude" squircle with a usage gauge ring.
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no ctx") }

// Background squircle with a warm gradient.
let inset = 40.0
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220)
squircle.addClip()

let colors = [
    CGColor(red: 0.87, green: 0.49, blue: 0.36, alpha: 1.0), // Claude coral
    CGColor(red: 0.79, green: 0.36, blue: 0.28, alpha: 1.0),
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Gauge ring: track + ~72% filled arc.
let center = CGPoint(x: size / 2, y: size / 2)
let radius = 280.0
let lineWidth = 90.0
ctx.setLineCap(.round)

// Track.
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.25))
ctx.setLineWidth(lineWidth)
ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()

// Filled portion, starting at top, going clockwise ~72%.
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
ctx.setLineWidth(lineWidth)
let start = CGFloat.pi / 2                 // top
let end = start - (.pi * 2 * 0.72)         // clockwise
ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
ctx.strokePath()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError("encode failed") }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
