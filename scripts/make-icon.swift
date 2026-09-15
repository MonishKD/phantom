// Draws Phantom's ghost mark and writes the app iconset plus the README image.
// Run from the repo root:  swift scripts/make-icon.swift
// Then:                    iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
//
// The artwork is an original sleek, swept-tail ghost — not any company's emblem.

import AppKit
import CoreGraphics
import Foundation

let canvas: CGFloat = 1024

// MARK: - Shapes

/// The ghost: domed head, flanks, a tail trailing off to the left, scalloped hem.
func ghostPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 762, y: 500))
    path.addCurve(to: CGPoint(x: 556, y: 812), control1: CGPoint(x: 762, y: 722), control2: CGPoint(x: 676, y: 812))
    path.addCurve(to: CGPoint(x: 356, y: 520), control1: CGPoint(x: 436, y: 812), control2: CGPoint(x: 356, y: 716))
    // tail: long, tapering, streaming away to the left
    path.addCurve(to: CGPoint(x: 116, y: 332), control1: CGPoint(x: 356, y: 436), control2: CGPoint(x: 296, y: 388))
    path.addCurve(to: CGPoint(x: 372, y: 322), control1: CGPoint(x: 236, y: 330), control2: CGPoint(x: 300, y: 298))
    // hem, flowing back to the right flank
    path.addCurve(to: CGPoint(x: 548, y: 300), control1: CGPoint(x: 452, y: 346), control2: CGPoint(x: 470, y: 300))
    path.addCurve(to: CGPoint(x: 722, y: 330), control1: CGPoint(x: 626, y: 300), control2: CGPoint(x: 652, y: 352))
    path.addCurve(to: CGPoint(x: 762, y: 500), control1: CGPoint(x: 752, y: 320), control2: CGPoint(x: 762, y: 404))
    path.closeSubpath()
    return path
}

func eyePath(center: CGPoint, width: CGFloat, height: CGFloat, angle: CGFloat) -> CGPath {
    var transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
    return CGPath(
        ellipseIn: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
        transform: &transform
    )
}

// MARK: - Drawing

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// Draws the icon at `size` points, optionally without the rounded-square plate.
func draw(into ctx: CGContext, size: CGFloat, plate: Bool) {
    ctx.scaleBy(x: size / canvas, y: size / canvas)
    let space = CGColorSpaceCreateDeviceRGB()

    if plate {
        let inset: CGFloat = 100
        let plateRect = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: plateRect, cornerWidth: 190, cornerHeight: 190, transform: nil))
        ctx.clip()

        let backdrop = CGGradient(
            colorsSpace: space,
            colors: [color(0.13, 0.15, 0.30), color(0.03, 0.04, 0.09)] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(
            backdrop,
            start: CGPoint(x: 0, y: canvas),
            end: CGPoint(x: 0, y: 0),
            options: []
        )

        // cool glow behind the ghost, so the white shape sits in light rather than on flat colour
        let glow = CGGradient(
            colorsSpace: space,
            colors: [color(0.36, 0.47, 1.0, 0.55), color(0.36, 0.47, 1.0, 0)] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawRadialGradient(
            glow,
            startCenter: CGPoint(x: 512, y: 580), startRadius: 0,
            endCenter: CGPoint(x: 512, y: 580), endRadius: 430,
            options: []
        )
        ctx.restoreGState()
    }

    // Ghost and eyes share a slight forward lean, so the whole mark reads as moving.
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 550)
    ctx.rotate(by: -0.07)
    ctx.translateBy(x: -512, y: -550)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 46, color: color(0, 0, 0, 0.45))
    ctx.addPath(ghostPath())
    ctx.setFillColor(color(0.97, 0.98, 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // eyes, slanted for a bit of intent
    ctx.setFillColor(color(0.05, 0.06, 0.13))
    ctx.addPath(eyePath(center: CGPoint(x: 486, y: 648), width: 72, height: 104, angle: -0.22))
    ctx.fillPath()
    ctx.addPath(eyePath(center: CGPoint(x: 628, y: 648), width: 72, height: 104, angle: 0.22))
    ctx.fillPath()

    ctx.restoreGState()
}

func render(size: CGFloat, plate: Bool) -> CGImage {
    let pixels = Int(size)
    let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    draw(into: ctx, size: size, plate: plate)
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) throws {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

// MARK: - Output

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")

// (file name, pixel size) pairs iconutil expects
let variants: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, size) in variants {
    try write(render(size: size, plate: true), to: iconset.appendingPathComponent(name))
}
try write(render(size: 512, plate: true), to: root.appendingPathComponent("docs/phantom-mark.png"))

print("wrote \(variants.count) iconset images and docs/phantom-mark.png")
