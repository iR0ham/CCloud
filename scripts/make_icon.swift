#!/usr/bin/env swift
// Renders the CCloud app icon (macOS "squircle" style) at every size required by an
// .iconset, from the original brand mark (Resources/logo.png, transparent 3200px).
//
// Usage: swift scripts/make_icon.swift <brand-mark.png> <iconset-dir> [master.png]
//
// The master brand mark is two shapes, both brand blue #0037FF: a 40%-opacity back
// shape and a solid front shape. On the dark squircle we re-tint them into a
// light-periwinkle / vivid-blue pair so the two-tone design survives on dark
// backgrounds (the app is dark-first). Everything is drawn in normalized coordinates
// so every size is crisp instead of a bitmap downscale.

import Foundation
import CoreGraphics
import ImageIO
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: make_icon.swift <brand-mark.png> <iconset-dir> [master.png]\n".data(using: .utf8)!)
    exit(2)
}
let sourcePath = args[1]
let iconsetDir = args[2]
let masterPath: String? = args.count > 3 ? args[3] : nil

// MARK: - Load the brand mark

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: sourcePath) as CFURL, nil),
      let srcImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write("cannot load \(sourcePath)\n".data(using: .utf8)!)
    exit(1)
}

let srcW = srcImage.width
let srcH = srcImage.height
var srcBuf = [UInt8](repeating: 0, count: srcW * srcH * 4)
guard let srcCtx = CGContext(data: &srcBuf, width: srcW, height: srcH,
                             bitsPerComponent: 8, bytesPerRow: srcW * 4,
                             space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write("cannot create source context\n".data(using: .utf8)!)
    exit(1)
}
srcCtx.draw(srcImage, in: CGRect(x: 0, y: 0, width: srcW, height: srcH))

// Re-tint: separate the two shapes by their source alpha (40% = back, 100% = front),
// make both opaque, and give each a color that reads well on the dark squircle.
// The output stays premultiplied RGBA.
var markBuf = [UInt8](repeating: 0, count: srcW * srcH * 4)
let light: (Double, Double, Double) = (0.79, 0.85, 1.00)   // #C9D9FF light periwinkle
let vivid: (Double, Double, Double) = (0.21, 0.41, 1.00)   // #3669FF vivid brand blue
for i in stride(from: 0, to: srcBuf.count, by: 4) {
    let a = Int(srcBuf[i + 3])
    guard a > 4 else { continue }
    // Shape membership from the source alpha ramp (back shape is ~0.4, front is 1.0).
    let isFront = a >= 190
    let alpha: Double = isFront ? Double(a) / 255.0 : min(1.0, Double(a) / 102.0)
    let c = isFront ? vivid : light
    let pa = alpha
    markBuf[i]     = UInt8(max(0, min(255, (c.0 * pa * 255.0).rounded())))
    markBuf[i + 1] = UInt8(max(0, min(255, (c.1 * pa * 255.0).rounded())))
    markBuf[i + 2] = UInt8(max(0, min(255, (c.2 * pa * 255.0).rounded())))
    markBuf[i + 3] = UInt8(max(0, min(255, (pa * 255.0).rounded())))
}
guard let markCtx = CGContext(data: &markBuf, width: srcW, height: srcH,
                              bitsPerComponent: 8, bytesPerRow: srcW * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let markImage = markCtx.makeImage() else {
    FileHandle.standardError.write("cannot build tinted mark\n".data(using: .utf8)!)
    exit(1)
}

// Tight bounding box of the mark so it can be centered regardless of source padding.
var minX = srcW, maxX = -1, minY = srcH, maxY = -1
for y in 0..<srcH {
    for x in 0..<srcW {
        if srcBuf[(y * srcW + x) * 4 + 3] > 8 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
guard maxX > minX, maxY > minY else {
    FileHandle.standardError.write("brand mark is fully transparent\n".data(using: .utf8)!)
    exit(1)
}
let markRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
guard let markCrop = markImage.cropping(to: markRect) else {
    FileHandle.standardError.write("cannot crop mark\n".data(using: .utf8)!)
    exit(1)
}
let cropAspect = CGFloat(markCrop.width) / CGFloat(markCrop.height)

// MARK: - Icon renderer

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1.0) -> CGColor {
    CGColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
}

let deviceRGB = CGColorSpaceCreateDeviceRGB()

/// Apple-style continuous rounded square ("squircle", superellipse n=5).
/// A plain rounded rect reads boxier than real macOS icons at large sizes.
func squirclePath(_ rect: CGRect, n: Double = 5.0, samples: Int = 1024) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2
    let b = rect.height / 2
    let e = 2.0 / n
    for i in 0...samples {
        let t = 2.0 * Double.pi * Double(i) / Double(samples)
        let ct = cos(t), st = sin(t)
        let x = rect.midX + CGFloat(copysign(pow(abs(ct), e), ct)) * a
        let y = rect.midY + CGFloat(copysign(pow(abs(st), e), st)) * b
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func drawIcon(size: Int) -> CGImage {
    let S = CGFloat(size)
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: deviceRGB,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("cannot create context \(size)")
    }
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)

    // Apple-style icon grid: 824/1024 content box, ~22.5% corner radius.
    let inset = S * 0.0977
    let box = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
    let squircle = squirclePath(box)

    // 1. Floating shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.010),
                  blur: S * 0.028,
                  color: rgb(0, 0, 0, 0.42))
    ctx.addPath(squircle)
    ctx.setFillColor(rgb(0.055, 0.065, 0.10))
    ctx.fillPath()
    ctx.restoreGState()

    // 2. Tile background (clipped).
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // base vertical gradient: dark navy -> near black
    let base = CGGradient(colorsSpace: deviceRGB,
                          colors: [rgb(0.115, 0.135, 0.225), rgb(0.026, 0.032, 0.060)] as CFArray,
                          locations: [0.0, 1.0])!
    ctx.drawLinearGradient(base,
                           start: CGPoint(x: 0, y: box.maxY),
                           end: CGPoint(x: 0, y: box.minY),
                           options: [])

    // soft blue glow behind the mark
    let glowCenter = CGPoint(x: box.midX, y: box.midY - box.height * 0.04)
    let glow = CGGradient(colorsSpace: deviceRGB,
                          colors: [rgb(0.20, 0.36, 1.0, 0.62), rgb(0.20, 0.36, 1.0, 0.14), rgb(0.20, 0.36, 1.0, 0.0)] as CFArray,
                          locations: [0.0, 0.55, 1.0])!
    ctx.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0,
                           endCenter: glowCenter, endRadius: box.width * 0.66, options: [])

    // top sheen (glass highlight)
    let sheen = CGGradient(colorsSpace: deviceRGB,
                           colors: [rgb(1, 1, 1, 0.09), rgb(1, 1, 1, 0.0)] as CFArray,
                           locations: [0.0, 0.55])!
    ctx.drawLinearGradient(sheen,
                           start: CGPoint(x: 0, y: box.maxY),
                           end: CGPoint(x: 0, y: box.midY),
                           options: [])
    ctx.restoreGState()

    // 3. Hairline inner border + top edge light.
    ctx.saveGState()
    ctx.addPath(squirclePath(box.insetBy(dx: S * 0.0016, dy: S * 0.0016)))
    ctx.setLineWidth(max(1.0, S * 0.0024))
    ctx.setStrokeColor(rgb(1, 1, 1, 0.22))
    ctx.strokePath()
    ctx.restoreGState()

    // 4. Brand mark, centered, with a soft drop shadow.
    let markH = box.height * 0.615
    let markW = markH * cropAspect
    let markDst = CGRect(x: box.midX - markW / 2,
                         y: box.midY - markH / 2 - box.height * 0.015,
                         width: markW, height: markH)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.008),
                  blur: S * 0.022,
                  color: rgb(0.02, 0.05, 0.20, 0.55))
    ctx.draw(markCrop, in: markDst)
    ctx.restoreGState()

    return ctx.makeImage()!
}

// MARK: - Write iconset

let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let entries: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

var cache: [Int: CGImage] = [:]
for entry in entries {
    let image = cache[entry.px] ?? drawIcon(size: entry.px)
    cache[entry.px] = image
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: entry.px, height: entry.px)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("png encode failed for \(entry.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let out = (iconsetDir as NSString).appendingPathComponent(entry.name)
    try! data.write(to: URL(fileURLWithPath: out))
}

if let masterPath {
    let image = cache[1024] ?? drawIcon(size: 1024)
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: masterPath))
    FileHandle.standardError.write("master: \(masterPath)\n".data(using: .utf8)!)
}

print("iconset written: \(iconsetDir) (\(entries.count) entries)")
