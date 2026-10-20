// Renders one alternate app icon per palette: the white halo and horns of the primary icon
// on the palette's gradient. Run from the repository root after changing a palette or the icon:
//
//     swift Tools/make-app-icons.swift
//
// The colours mirror `Palette.stops(for:)` in MisbehaveKit/Look.swift.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

typealias RGB = (Double, Double, Double)

/// Top-left, middle and bottom-right of the icon gradient.
let palettes: [(name: String, colors: [RGB])] = [
    ("peach", [(1.0, 0.68, 0.52), (0.95, 0.43, 0.38), (0.80, 0.30, 0.26)]),
    ("cherry", [(0.95, 0.33, 0.42), (0.78, 0.10, 0.25), (0.55, 0.06, 0.16)]),
    ("sunset", [(0.98, 0.60, 0.25), (0.97, 0.42, 0.25), (0.75, 0.22, 0.55)]),
    ("lemon", [(0.99, 0.82, 0.30), (0.92, 0.60, 0.08), (0.80, 0.42, 0.04)]),
    ("matcha", [(0.62, 0.80, 0.45), (0.30, 0.58, 0.33), (0.18, 0.42, 0.32)]),
    ("ocean", [(0.36, 0.82, 0.86), (0.07, 0.52, 0.72), (0.05, 0.32, 0.60)]),
    ("lavender", [(0.85, 0.62, 0.98), (0.58, 0.38, 0.90), (0.40, 0.28, 0.75)]),
    ("unicorn", [(0.98, 0.55, 0.75), (0.68, 0.48, 0.98), (0.38, 0.76, 0.93)]),
    ("midnight", [(0.55, 0.30, 0.75), (0.20, 0.16, 0.45), (0.08, 0.08, 0.25)]),
    ("cocoa", [(0.78, 0.56, 0.42), (0.45, 0.28, 0.22), (0.28, 0.17, 0.13)]),
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("misbehave/Resources/Assets.xcassets")
let source = catalog.appendingPathComponent("AppIcon.appiconset/AppIcon.png")

guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
      let icon = CGImageSourceCreateImageAtIndex(input, 0, nil) else {
    fatalError("Cannot read \(source.path)")
}
let size = icon.width
let space = CGColorSpace(name: CGColorSpace.sRGB)!

// The glyph: how white each pixel of the primary icon is. The gradient behind it never gets close.
var pixels = [UInt8](repeating: 0, count: size * size * 4)
let reader = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                       space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
reader.draw(icon, in: CGRect(x: 0, y: 0, width: size, height: size))
var mask = [UInt8](repeating: 0, count: size * size * 4)
for index in 0..<(size * size) {
    let minimum = Double(min(pixels[index * 4], pixels[index * 4 + 1], pixels[index * 4 + 2])) / 255
    let alpha = UInt8(max(0, min(1, (minimum - 0.55) / 0.40)) * 255)
    mask[index * 4] = alpha
    mask[index * 4 + 1] = alpha
    mask[index * 4 + 2] = alpha
    mask[index * 4 + 3] = alpha
}
let glyphContext = CGContext(data: &mask, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let glyph = glyphContext.makeImage()!

for palette in palettes {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let colors = palette.colors.map { CGColor(colorSpace: space, components: [$0.0, $0.1, $0.2, 1])! }
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 0.5, 1])!
    let side = CGFloat(size)
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: side, y: 0), options: [])
    context.setShadow(offset: CGSize(width: 0, height: -side * 0.012), blur: side * 0.03,
                      color: CGColor(colorSpace: space, components: [0, 0, 0, 0.18]))
    context.draw(glyph, in: CGRect(x: 0, y: 0, width: side, height: side))

    let folder = catalog.appendingPathComponent("AppIcon-\(palette.name).appiconset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let png = folder.appendingPathComponent("AppIcon.png")
    let destination = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    let contents = """
    {
      "images" : [
        { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }

    """
    try contents.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("Wrote \(folder.lastPathComponent)")
}
