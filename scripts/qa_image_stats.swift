#!/usr/bin/env swift
// QA helper: prints objective stats about a snapshot PNG so scripts can tell a real
// rendered screen from a blank/black window.
//
// Output (one line, space-separated key=value):
//   width=2640 height=1720 bytes=812345 uniqueColors=48213 meanLuma=0.183 nonBg=0.94 verdict=ok
//
// `uniqueColors` is sampled on a grid of at most 400x260 pixels (fast, deterministic);
// `nonBg` is the fraction of sampled pixels that differ from the most common color.
// verdict: ok | blank (almost no colour variety) | dark (nearly all one colour).
//
// Usage: swift scripts/qa_image_stats.swift <file.png> [--verbose]

import Foundation
import CoreGraphics
import ImageIO

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: qa_image_stats.swift <file.png>\n".data(using: .utf8)!)
    exit(2)
}
let path = args[1]
let verbose = args.contains("--verbose")

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("width=0 height=0 bytes=0 uniqueColors=0 meanLuma=0 nonBg=0 verdict=missing")
    exit(1)
}
let w = img.width, h = img.height
let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0

// Draw into a small RGBA buffer (nearest-ish scaling is fine: we sample a grid anyway).
let sw = min(w, 400), sh = min(h, 260)
var buf = [UInt8](repeating: 0, count: sw * sh * 4)
guard let ctx = CGContext(data: &buf, width: sw, height: sh, bitsPerComponent: 8,
                          bytesPerRow: sw * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    print("width=\(w) height=\(h) bytes=\(bytes) uniqueColors=0 meanLuma=0 nonBg=0 verdict=ctxfail")
    exit(1)
}
ctx.interpolationQuality = .none
ctx.draw(img, in: CGRect(x: 0, y: 0, width: sw, height: sh))

var counts: [UInt32: Int] = [:]
var lumaSum = 0.0
for y in 0..<sh {
    for x in 0..<sw {
        let i = (y * sw + x) * 4
        let r = UInt32(buf[i]), g = UInt32(buf[i + 1]), b = UInt32(buf[i + 2])
        counts[(r << 16) | (g << 8) | b, default: 0] += 1
        lumaSum += 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }
}
let samples = sw * sh
let unique = counts.count
let meanLuma = lumaSum / Double(samples) / 255.0
let mostCommon = counts.values.max() ?? 0
let nonBg = 1.0 - Double(mostCommon) / Double(samples)

var verdict = "ok"
if unique < 200 || nonBg < 0.05 { verdict = "blank" }
else if unique < 1500 { verdict = "dark" }

print(String(format: "width=%d height=%d bytes=%d uniqueColors=%d meanLuma=%.3f nonBg=%.2f verdict=%@",
             w, h, bytes, unique, meanLuma, nonBg, verdict))
if verbose {
    let top = counts.sorted { $0.value > $1.value }.prefix(5).map { String(format: "#%06X:%d", $0.key, $0.value) }
    print("topColors=\(top.joined(separator: ","))")
}
