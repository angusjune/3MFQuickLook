#!/usr/bin/env swift
//
// Generates every piece of raster art the project ships:
//
//   App/Assets.xcassets/AppIcon.appiconset/*.png   the macOS app icon
//   packaging/dmg-background.png (+@2x)            the release DMG window backdrop
//
// The outputs are committed so builds stay hermetic (CI never runs this), but
// the art is defined here as code so it is reviewable in a diff and can be
// re-derived. After changing anything below:
//
//     swift scripts/generate_art.swift
//
// then rebuild. Nothing else reads this file.
//
// Design: a white magnifier over an isometric amber solid on a blue squircle —
// the Quick Look "glass" metaphor applied to a 3D model. The lens genuinely
// magnifies: the solid is redrawn scaled up, clipped to the lens, so the shape
// reads as glass rather than as a flat circle pasted on top.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Small helpers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let deviceRGB = CGColorSpaceCreateDeviceRGB()

/// Clips to `path` and fills it with a linear gradient running `start` -> `end`.
func fill(_ ctx: CGContext, _ path: CGPath, gradient colors: [CGColor], from start: CGPoint, to end: CGPoint) {
    guard let gradient = CGGradient(colorsSpace: deviceRGB, colors: colors as CFArray, locations: nil) else { return }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func fill(_ ctx: CGContext, _ path: CGPath, color: CGColor) {
    ctx.saveGState()
    ctx.setFillColor(color)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()
}

func polygon(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    return path
}

func circle(_ center: CGPoint, _ radius: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2), transform: nil)
}

/// Apple's app-icon silhouette is a superellipse, not a circularly-rounded
/// rect — n = 5 matches the macOS template closely enough that the corners
/// don't read as "off" next to system icons. Sampled as a dense polygon,
/// which is both simpler and more faithful than fitting bezier corners.
func superellipse(center: CGPoint, halfSize: CGFloat, n: CGFloat = 5, samples: Int = 1440) -> CGPath {
    let path = CGMutablePath()
    for i in 0 ..< samples {
        let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(samples)
        let c = cos(t), s = sin(t)
        let point = CGPoint(
            x: center.x + halfSize * copysign(pow(abs(c), 2 / n), c),
            y: center.y + halfSize * copysign(pow(abs(s), 2 / n), s)
        )
        i == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func makeContext(_ width: Int, _ height: Int) -> CGContext {
    guard let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0, space: deviceRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("could not create a \(width)x\(height) bitmap context") }
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

func writePNG(_ ctx: CGContext, to url: URL) {
    guard let image = ctx.makeImage() else { fatalError("could not snapshot \(url.lastPathComponent)") }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("could not open \(url.path) for writing")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not encode \(url.path)") }
    FileHandle.standardError.write("  wrote \(url.lastPathComponent)\n".data(using: .utf8)!)
}

/// Draws `text` centred on `center`, in a y-up (unflipped) CGContext.
func drawCenteredText(_ ctx: CGContext, _ text: String, center: CGPoint, font: NSFont, color: CGColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: color) ?? .black,
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let size = attributed.size()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    attributed.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Icon artwork
//
// Everything is authored in a 1024x1024 space and scaled down per size, so the
// design is resolution-independent and the numbers below stay readable.

enum Palette {
    static let backdropTop = rgb(0x6BA5FF)
    static let backdropBottom = rgb(0x1F49C4)

    static let solidTop = rgb(0xFFD166)     // lit face
    static let solidRight = rgb(0xF79024)   // mid face
    static let solidLeft = rgb(0xD96E12)    // shadowed face

    static let rimLight = rgb(0xFFFFFF)
    static let rimDark = rgb(0xB9C9E0)
    static let handleLight = rgb(0xF2F6FC)
    static let handleDark = rgb(0x9DB1CD)
}

/// An isometric cube: three rhombic faces meeting at the centre vertex.
/// Face shading alone carries the 3D read — no outlines, which would turn to
/// mud at 16pt.
func drawSolid(_ ctx: CGContext, center: CGPoint, radius r: CGFloat) {
    let dx = 0.866 * r // cos 30°
    let dy = 0.5 * r   // sin 30°

    let top = CGPoint(x: center.x, y: center.y + r)
    let upperRight = CGPoint(x: center.x + dx, y: center.y + dy)
    let lowerRight = CGPoint(x: center.x + dx, y: center.y - dy)
    let bottom = CGPoint(x: center.x, y: center.y - r)
    let lowerLeft = CGPoint(x: center.x - dx, y: center.y - dy)
    let upperLeft = CGPoint(x: center.x - dx, y: center.y + dy)

    fill(ctx, polygon([top, upperRight, center, upperLeft]), color: Palette.solidTop)
    fill(ctx, polygon([center, upperRight, lowerRight, bottom]), color: Palette.solidRight)
    fill(ctx, polygon([center, upperLeft, lowerLeft, bottom]), color: Palette.solidLeft)
}

func drawIcon(_ ctx: CGContext, pixelSize: CGFloat) {
    ctx.saveGState()
    ctx.scaleBy(x: pixelSize / 1024, y: pixelSize / 1024)

    let canvasCenter = CGPoint(x: 512, y: 512)
    let backdrop = superellipse(center: canvasCenter, halfSize: 412)

    // Contact shadow, matching the macOS icon template's grounded look.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0x0A1F4D, 0.35))
    fill(ctx, backdrop, color: Palette.backdropBottom)
    ctx.restoreGState()

    fill(
        ctx, backdrop,
        gradient: [Palette.backdropTop, Palette.backdropBottom],
        from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100)
    )

    // Keep all content inside the silhouette.
    ctx.saveGState()
    ctx.addPath(backdrop)
    ctx.clip()

    // At 16pt and 32pt the rim thins to a few pixels and the whole thing
    // smears. Below that threshold the artwork is drawn larger, with a
    // heavier rim and no sheen — the usual macOS trick of simplifying the
    // small slots rather than shipping one design scaled blindly.
    let compact = pixelSize <= 32
    if compact {
        ctx.translateBy(x: canvasCenter.x, y: canvasCenter.y)
        ctx.scaleBy(x: 1.12, y: 1.12)
        ctx.translateBy(x: -canvasCenter.x, y: -canvasCenter.y)
    }

    // Geometry note: the whole composition must clear the superellipse, which
    // cuts in hard near the corners — an earlier layout ran the handle
    // straight off the lower-right edge. The handle tip is the binding
    // constraint; everything else is sized around it.
    let solidCenter = CGPoint(x: 405, y: 608)
    let solidRadius: CGFloat = 196
    drawSolid(ctx, center: solidCenter, radius: solidRadius)

    // The lens, overlapping the solid's lower-right so the glass has something
    // to magnify rather than sitting on empty backdrop.
    let lens = CGPoint(x: 561, y: 455)
    let outerRadius: CGFloat = 179
    let rimWidth: CGFloat = compact ? 56 : 43
    let innerRadius = outerRadius - rimWidth

    // Handle first, so the rim covers the joint where it meets the lens.
    let direction = CGPoint(x: cos(-CGFloat.pi / 4), y: sin(-CGFloat.pi / 4))
    let handleStart = CGPoint(x: lens.x + direction.x * (outerRadius - 22), y: lens.y + direction.y * (outerRadius - 22))
    let handleEnd = CGPoint(x: lens.x + direction.x * (outerRadius + 112), y: lens.y + direction.y * (outerRadius + 112))
    let handle = CGMutablePath()
    handle.move(to: handleStart)
    handle.addLine(to: handleEnd)
    let handleStroked = handle.copy(strokingWithWidth: 66, lineCap: .round, lineJoin: .round, miterLimit: 10)
    fill(
        ctx, handleStroked,
        gradient: [Palette.handleLight, Palette.handleDark],
        from: CGPoint(x: lens.x, y: lens.y), to: handleEnd
    )

    // What the glass shows: the solid, redrawn magnified and clipped to the
    // lens. This is what makes it read as a lens instead of a flat disc.
    ctx.saveGState()
    ctx.addPath(circle(lens, innerRadius))
    ctx.clip()
    // The backdrop gradient behind the magnified content, so areas of the lens
    // not covered by the solid still look like glass over the icon face.
    fill(
        ctx, circle(lens, innerRadius),
        gradient: [Palette.backdropTop, Palette.backdropBottom],
        from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100)
    )
    ctx.translateBy(x: lens.x, y: lens.y)
    ctx.scaleBy(x: 1.32, y: 1.32)
    ctx.translateBy(x: -lens.x, y: -lens.y)
    drawSolid(ctx, center: solidCenter, radius: solidRadius)
    ctx.restoreGState()

    // Glass tint + specular sheen across the upper-left of the lens.
    fill(ctx, circle(lens, innerRadius), color: rgb(0xFFFFFF, 0.14))
    if !compact {
        ctx.saveGState()
        ctx.addPath(circle(lens, innerRadius))
        ctx.clip()
        let sheen = CGMutablePath()
        sheen.addEllipse(in: CGRect(x: lens.x - innerRadius * 1.05, y: lens.y - innerRadius * 0.15,
                                    width: innerRadius * 1.5, height: innerRadius * 1.35))
        fill(ctx, sheen, color: rgb(0xFFFFFF, 0.20))
        ctx.restoreGState()
    }

    // Rim: an annulus, filled with the even-odd rule.
    let rim = CGMutablePath()
    rim.addPath(circle(lens, outerRadius))
    rim.addPath(circle(lens, innerRadius))
    ctx.saveGState()
    ctx.addPath(rim)
    ctx.clip(using: .evenOdd)
    let rimBounds = CGRect(x: lens.x - outerRadius, y: lens.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2)
    if let gradient = CGGradient(colorsSpace: deviceRGB, colors: [Palette.rimLight, Palette.rimDark] as CFArray, locations: nil) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: rimBounds.minX, y: rimBounds.maxY),
            end: CGPoint(x: rimBounds.maxX, y: rimBounds.minY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
    ctx.restoreGState()

    ctx.restoreGState() // backdrop clip
    ctx.restoreGState() // scale
}

// MARK: - DMG background artwork
//
// Authored at 660x400 points (the DMG window's content size) and rendered at
// 1x and 2x. Deliberately light: Finder draws icon labels in dark text over
// this, so a dark backdrop would make "3MF QuickLook" unreadable.

func drawDMGBackground(_ ctx: CGContext, scale: CGFloat) {
    ctx.saveGState()
    ctx.scaleBy(x: scale, y: scale)

    let width: CGFloat = 660
    let height: CGFloat = 400

    fill(
        ctx, CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil),
        gradient: [rgb(0xF8FAFD), rgb(0xE3EAF6)],
        from: CGPoint(x: 0, y: height), to: CGPoint(x: 0, y: 0)
    )

    // Icon centres, mirroring packaging/dmg_settings.py. Finder measures from
    // the top-left, this context from the bottom-left.
    let iconY = height - 185
    let appX: CGFloat = 165
    let applicationsX: CGFloat = 495

    // A chevron pointing from the app toward the Applications alias.
    let arrowCenter = CGPoint(x: (appX + applicationsX) / 2, y: iconY)
    let chevron = CGMutablePath()
    chevron.move(to: CGPoint(x: arrowCenter.x - 26, y: arrowCenter.y + 30))
    chevron.addLine(to: CGPoint(x: arrowCenter.x + 20, y: arrowCenter.y))
    chevron.addLine(to: CGPoint(x: arrowCenter.x - 26, y: arrowCenter.y - 30))
    let chevronStroked = chevron.copy(strokingWithWidth: 13, lineCap: .round, lineJoin: .round, miterLimit: 10)
    fill(ctx, chevronStroked, color: rgb(0x9FB6D8))

    drawCenteredText(
        ctx, "Drag 3MF QuickLook into Applications",
        center: CGPoint(x: width / 2, y: 74),
        font: .systemFont(ofSize: 15, weight: .medium),
        color: rgb(0x5A6B85)
    )
    drawCenteredText(
        ctx, "Then launch it once to register the Quick Look extensions.",
        center: CGPoint(x: width / 2, y: 48),
        font: .systemFont(ofSize: 12, weight: .regular),
        color: rgb(0x8593A8)
    )

    ctx.restoreGState()
}

// MARK: - Asset catalog

/// (filename pixel size, catalog "size" string, catalog "scale" string)
let appIconVariants: [(pixels: Int, size: String, scale: String)] = [
    (16, "16x16", "1x"), (32, "16x16", "2x"),
    (32, "32x32", "1x"), (64, "32x32", "2x"),
    (128, "128x128", "1x"), (256, "128x128", "2x"),
    (256, "256x256", "1x"), (512, "256x256", "2x"),
    (512, "512x512", "1x"), (1024, "512x512", "2x"),
]

func appIconFilename(size: String, scale: String) -> String {
    "icon_\(size)\(scale == "2x" ? "@2x" : "").png"
}

// MARK: - Entry point

let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconSet = repoRoot.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
let packaging = repoRoot.appendingPathComponent("packaging")

FileHandle.standardError.write("Generating app icon\n".data(using: .utf8)!)

// Render each distinct pixel size once, then hard-link it into every catalog
// slot that wants it (16x16@2x and 32x32@1x are the same 32px image).
var renderedByPixelSize: [Int: URL] = [:]
for variant in appIconVariants {
    let destination = iconSet.appendingPathComponent(appIconFilename(size: variant.size, scale: variant.scale))
    if let alreadyRendered = renderedByPixelSize[variant.pixels] {
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: alreadyRendered, to: destination)
        FileHandle.standardError.write("  wrote \(destination.lastPathComponent)\n".data(using: .utf8)!)
        continue
    }
    let ctx = makeContext(variant.pixels, variant.pixels)
    drawIcon(ctx, pixelSize: CGFloat(variant.pixels))
    writePNG(ctx, to: destination)
    renderedByPixelSize[variant.pixels] = destination
}

let iconEntries = appIconVariants.map { variant in
    """
        {
          "filename" : "\(appIconFilename(size: variant.size, scale: variant.scale))",
          "idiom" : "mac",
          "scale" : "\(variant.scale)",
          "size" : "\(variant.size)"
        }
    """
}
let iconContents = """
{
  "images" : [
\(iconEntries.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try! iconContents.write(to: iconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let catalogContents = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try! catalogContents.write(
    to: repoRoot.appendingPathComponent("App/Assets.xcassets/Contents.json"),
    atomically: true, encoding: .utf8
)

FileHandle.standardError.write("Generating DMG background\n".data(using: .utf8)!)
for (scale, name) in [(CGFloat(1), "dmg-background.png"), (CGFloat(2), "dmg-background@2x.png")] {
    let ctx = makeContext(Int(660 * scale), Int(400 * scale))
    drawDMGBackground(ctx, scale: scale)
    writePNG(ctx, to: packaging.appendingPathComponent(name))
}

FileHandle.standardError.write("Done.\n".data(using: .utf8)!)
