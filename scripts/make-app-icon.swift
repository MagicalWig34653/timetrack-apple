#!/usr/bin/env swift
// Generates the Timetrack app icon PNGs and the three AppIcon.appiconset folders.
// usage: swift scripts/make-app-icon.swift   (run from the repository root)
// Motif: open time arc in the accent blue with a clock hand on a calm dark tile (same as BrandMark in TimetrackDesign).
import AppKit
import CoreGraphics

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Draws the mark into a square canvas of `size` points. `inset` shrinks the tile (macOS keeps transparent margin and rounded corners itself).
func render(size: Int, tile: Bool) -> Data {
    let s = CGFloat(size)
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let rect: CGRect
    if tile {
        // macOS: 824/1024 tile with rounded corners and a soft shadow.
        let side = s * 824 / 1024
        rect = CGRect(x: (s - side) / 2, y: (s - side) / 2 + s * 0.008, width: side, height: side)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: color(0x000000, 0.35))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: side * 0.225, cornerHeight: side * 0.225, transform: nil))
        context.setFillColor(color(0x0B0F1E))
        context.fillPath()
        context.restoreGState()
        context.addPath(CGPath(roundedRect: rect, cornerWidth: side * 0.225, cornerHeight: side * 0.225, transform: nil))
        context.clip()
    } else {
        rect = CGRect(x: 0, y: 0, width: s, height: s)
    }
    // Background: calm dark gradient with a faint accent glow at the top.
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(colorsSpace: space, colors: [color(0x1E2A4A), color(0x0A0D1A)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [color(0x2563EB, 0.30), color(0x2563EB, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: rect.midX, y: rect.maxY), startRadius: 0, endCenter: CGPoint(x: rect.midX, y: rect.maxY), endRadius: rect.width * 0.8, options: [])

    // Arc: 300 degrees open at the bottom-left, round caps, accent gradient.
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = rect.width * 0.28
    let lineWidth = rect.width * 0.085
    context.saveGState()
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.addArc(center: center, radius: radius, startAngle: -CGFloat.pi * 0.75, endAngle: CGFloat.pi, clockwise: false)
    context.replacePathWithStrokedPath()
    context.clip()
    let arcGradient = CGGradient(colorsSpace: space, colors: [color(0x93C5FD), color(0x2563EB)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(arcGradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    context.restoreGState()

    // Hands: minute hand up, hour hand to the right.
    context.setLineCap(.round)
    context.setStrokeColor(color(0xFFFFFF))
    context.setLineWidth(rect.width * 0.05)
    context.move(to: center)
    context.addLine(to: CGPoint(x: center.x, y: center.y + radius * 0.62))
    context.strokePath()
    context.setStrokeColor(color(0xFFFFFF, 0.85))
    context.setLineWidth(rect.width * 0.05)
    context.move(to: center)
    context.addLine(to: CGPoint(x: center.x + radius * 0.42, y: center.y))
    context.strokePath()
    context.setFillColor(color(0xFFFFFF))
    context.fillEllipse(in: CGRect(x: center.x - rect.width * 0.03, y: center.y - rect.width * 0.03, width: rect.width * 0.06, height: rect.width * 0.06))

    let image = context.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ path: String) throws {
    try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try data.write(to: URL(fileURLWithPath: path))
}

func contents(_ images: [[String: String]], extra: [String: Any] = [:]) -> Data {
    var json: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    json.merge(extra) { $1 }
    return try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
}

let fullBleed = render(size: 1024, tile: false)
// iOS / iPadOS: one 1024 image (system applies the mask).
try write(fullBleed, "Sources/iOS/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
try write(contents([["filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]]), "Sources/iOS/Assets.xcassets/AppIcon.appiconset/Contents.json")
// watchOS: one 1024 image.
try write(fullBleed, "Sources/Watch/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
try write(contents([["filename": "icon-1024.png", "idiom": "universal", "platform": "watchos", "size": "1024x1024"]]), "Sources/Watch/Assets.xcassets/AppIcon.appiconset/Contents.json")
// macOS: explicit sizes with built-in tile.
var macImages: [[String: String]] = []
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "mac-\(points)@\(scale)x.png"
    try write(render(size: points * scale, tile: true), "Sources/Mac/Assets.xcassets/AppIcon.appiconset/\(name)")
    macImages.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
}
try write(contents(macImages), "Sources/Mac/Assets.xcassets/AppIcon.appiconset/Contents.json")
// Accent + launch background colors per target.
func colorset(_ light: String, _ dark: String) -> Data {
    func comps(_ hex: String) -> [String: Any] {
        let value = UInt32(hex, radix: 16)!
        return ["color-space": "srgb", "components": ["red": String(format: "0x%02X", (value >> 16) & 0xFF), "green": String(format: "0x%02X", (value >> 8) & 0xFF), "blue": String(format: "0x%02X", value & 0xFF), "alpha": "1.000"]]
    }
    let entries: [[String: Any]] = [
        ["idiom": "universal", "color": comps(light)],
        ["idiom": "universal", "appearances": [["appearance": "luminosity", "value": "dark"]], "color": comps(dark)],
    ]
    return try! JSONSerialization.data(withJSONObject: ["colors": entries, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys])
}
for target in ["iOS", "Mac", "Watch"] {
    try write(colorset("2563EB", "60A5FA"), "Sources/\(target)/Assets.xcassets/AccentColor.colorset/Contents.json")
    try write(Data("{\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n".utf8), "Sources/\(target)/Assets.xcassets/Contents.json")
}
try write(colorset("F4F4F5", "0C0C0E"), "Sources/iOS/Assets.xcassets/LaunchBackground.colorset/Contents.json")
print("icons written")
