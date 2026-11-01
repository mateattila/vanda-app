// Renders the app icon (light and dark) into the AppIcon asset catalog.
// Run from the repo root:
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift VandaApp/Tools/make-app-icon.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDir = "VandaApp/VandaApp/Assets.xcassets/AppIcon.appiconset"
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [Int]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors.map { rgb($0) } as CFArray, locations: nil)!
}

// A round-capped stroke instead of a glyph: matches the rounded Quicksand look without the font.
func vPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 312, y: 716))
    path.addLine(to: CGPoint(x: 512, y: 318))
    path.addLine(to: CGPoint(x: 712, y: 716))
    return path.copy(strokingWithWidth: 132, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

func sparkle(at c: CGPoint, r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let k = r * 0.22
    path.move(to: CGPoint(x: c.x, y: c.y + r))
    path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y + k))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + k, y: c.y - k))
    path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y - k))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - k, y: c.y + k))
    return path
}

struct Variant {
    let file: String
    let background: [Int]
    let glow: Int
    let letter: [Int]
    let shadow: CGColor
    let sparkle: Int
}

// Colours from the Soft Dusk palette: periwinkle accent for light, the journal's dusk for dark.
let variants = [
    Variant(file: "AppIcon.png", background: [0xB3A6F5, 0x7263D2], glow: 0xFFFFFF,
            letter: [0xFFFFFF, 0xEDE8FF], shadow: rgb(0x3A3550, 0.28), sparkle: 0xFFE7EF),
    Variant(file: "AppIcon-Dark.png", background: [0x5E4F86, 0x2E2748], glow: 0x8A7DE0,
            letter: [0xF9B9D2, 0x9C8EF0], shadow: rgb(0x000000, 0.35), sparkle: 0xFFE7EF),
]

for variant in variants {
    // Opaque context: App Store icons must not have an alpha channel.
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let full = CGFloat(size)
    ctx.drawLinearGradient(gradient(variant.background), start: CGPoint(x: 0, y: full),
                           end: CGPoint(x: full, y: 0), options: [])
    let glow = CGGradient(colorsSpace: space,
                          colors: [rgb(variant.glow, 0.38), rgb(variant.glow, 0)] as CFArray,
                          locations: nil)!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 260, y: 820), startRadius: 0,
                           endCenter: CGPoint(x: 260, y: 820), endRadius: 720, options: [])

    let letter = vPath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 48, color: variant.shadow)
    ctx.addPath(letter)
    ctx.setFillColor(rgb(variant.letter[1]))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(letter)
    ctx.clip()
    ctx.drawLinearGradient(gradient(variant.letter), start: CGPoint(x: 512, y: 790),
                           end: CGPoint(x: 512, y: 250), options: [])
    ctx.restoreGState()

    ctx.addPath(sparkle(at: CGPoint(x: 512, y: 742), r: 62))
    ctx.addPath(sparkle(at: CGPoint(x: 602, y: 836), r: 26))
    ctx.setFillColor(rgb(variant.sparkle))
    ctx.fillPath()

    let url = URL(fileURLWithPath: outputDir).appendingPathComponent(variant.file)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}
