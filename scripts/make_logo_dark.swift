#!/usr/bin/env swift
// Generates Resources/logo-dark.png: the brand mark re-tinted for dark backgrounds.
//
// The original asset (Resources/logo.png) draws its back shape as brand blue at 40%
// alpha. Blended over a white page that reads as periwinkle, but over the app's dark
// sidebar (#08090E) it disappears — leaving a half-glyph. This variant keeps the brand
// silhouette and colors but makes the back shape the periwinkle it is meant to read as
// (#AEBFF7) and the front shape the exact brand blue (#0037FF), both on transparency.
//
// Usage: swift scripts/make_logo_dark.swift <logo.png> <out.png>

import Foundation
import CoreGraphics
import ImageIO
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: make_logo_dark.swift <logo.png> <out.png>\n".data(using: .utf8)!)
    exit(2)
}
let srcPath = args[1], outPath = args[2]

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: srcPath) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("cannot load \(srcPath)\n".data(using: .utf8)!)
    exit(1)
}
let w = image.width, h = image.height
var buf = [UInt8](repeating: 0, count: w * h * 4)
guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write("cannot create context\n".data(using: .utf8)!)
    exit(1)
}
ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

// Back shape (source alpha ~40%) -> periwinkle, front shape (100%) -> brand blue.
let periwinkle: (Double, Double, Double) = (0.682, 0.749, 0.969)  // #AEBFF7
let brandBlue: (Double, Double, Double) = (0.0, 0.216, 1.0)       // #0037FF
for i in stride(from: 0, to: buf.count, by: 4) {
    let a = Int(buf[i + 3])
    guard a > 4 else { buf[i] = 0; buf[i+1] = 0; buf[i+2] = 0; buf[i+3] = 0; continue }
    let isFront = a >= 190
    let alpha: Double = isFront ? Double(a) / 255.0 : min(1.0, Double(a) / 102.0)
    let c = isFront ? brandBlue : periwinkle
    buf[i]     = UInt8(max(0, min(255, (c.0 * alpha * 255.0).rounded())))
    buf[i + 1] = UInt8(max(0, min(255, (c.1 * alpha * 255.0).rounded())))
    buf[i + 2] = UInt8(max(0, min(255, (c.2 * alpha * 255.0).rounded())))
    buf[i + 3] = UInt8(max(0, min(255, (alpha * 255.0).rounded())))
}
guard let outCtx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                             bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let outImage = outCtx.makeImage() else {
    FileHandle.standardError.write("cannot build output\n".data(using: .utf8)!)
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: outImage)
guard let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("png encode failed\n".data(using: .utf8)!)
    exit(1)
}
try! data.write(to: URL(fileURLWithPath: outPath))
print("logo-dark written: \(outPath) \(w)x\(h)")
