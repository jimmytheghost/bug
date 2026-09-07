import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = root.appendingPathComponent("Bug.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.05, y: p * 0.05, width: p * 0.9, height: p * 0.9), xRadius: p * 0.2, yRadius: p * 0.2).fill()
        if let symbol = NSImage(systemSymbolName: "ladybug.fill", accessibilityDescription: "Bug") {
            let config = NSImage.SymbolConfiguration(pointSize: p * 0.57, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.systemMint]))
            let configured = symbol.withSymbolConfiguration(config)!
            configured.draw(in: NSRect(x: p * 0.20, y: p * 0.20, width: p * 0.60, height: p * 0.60))
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(filename))
    }
}
