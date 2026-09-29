// Renders Resources/claude-logo.svg into an .iconset for iconutil.
// AppKit rasterizes SVG natively, so this needs no external tooling.
import AppKit

let repo = FileManager.default.currentDirectoryPath
let svg = "\(repo)/Resources/claude-logo.svg"
let outDir = "\(repo)/.build/AppIcon.iconset"

guard let art = NSImage(contentsOfFile: svg) else {
    FileHandle.standardError.write("failed to load \(svg)\n".data(using: .utf8)!)
    exit(1)
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// macOS icons inset their art inside a transparent margin (~82% of the canvas)
// so the squircle matches the size of native icons in Finder and the Dock.
let inset: CGFloat = 0.82

// (pixel size, filename)
let variants: [(Int, String)] = [
    (16, "icon_16x16.png"),     (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),     (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),  (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),  (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),  (1024, "icon_512x512@2x.png"),
]

for (px, name) in variants {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let side = CGFloat(px) * inset
    let origin = (CGFloat(px) - side) / 2
    art.draw(in: NSRect(x: origin, y: origin, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

print("wrote \(variants.count) variants to \(outDir)")
