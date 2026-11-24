// Draws the app icon: a sheet of paper with a Latin Modern "M" between two
// booktabs rules. Usage: swift make-icon.swift <font.ttf> <out.png>
import Cocoa

let args = CommandLine.arguments
let fontURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])

CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor] ?? []

let side = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// The standard macOS icon shape: an 824pt rounded square inside a 1024pt canvas.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor(calibratedRed: 0.99, green: 0.985, blue: 0.965, alpha: 1).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSColor.black.withAlphaComponent(0.12).setStroke()
shape.lineWidth = 2
shape.stroke()

let ink = NSColor(calibratedWhite: 0.1, alpha: 1)
ink.setFill()
NSRect(x: 270, y: 742, width: 484, height: 14).fill()
NSRect(x: 270, y: 270, width: 484, height: 14).fill()

let font: NSFont = descriptors.first.map { CTFontCreateWithFontDescriptor($0, 500, nil) as NSFont }
    ?? NSFont(name: "Times New Roman", size: 500)!
let glyph = NSAttributedString(string: "M", attributes: [.font: font, .foregroundColor: ink])
let size = glyph.size()
let capHeight = font.capHeight
// Centre the capital optically between the two rules.
let baseline = 512 - capHeight / 2
glyph.draw(at: NSPoint(x: 512 - size.width / 2, y: baseline + font.descender))

NSGraphicsContext.current?.flushGraphics()
try rep.representation(using: .png, properties: [:])!.write(to: outURL)
