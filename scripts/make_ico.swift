#!/usr/bin/env swift
// Builds a multi-size Windows .ico from a PNG source.
//
//   swift scripts/make_ico.swift <source.png> <output.ico> [roundtrip.png]
//
// Every entry is a 32-bpp DIB (bottom-up BGRA plus a 1-bpp AND mask), which
// Windows 10 renders at all sizes without relying on PNG-compressed entries.
// The optional third argument re-decodes the largest entry back into a PNG, so
// the committed icon can be verified instead of trusted.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(
        "usage: make_ico.swift <source.png> <output.ico> [roundtrip.png]\n"
            .data(using: .utf8)!)
    exit(2)
}
let sourcePath = args[1]
let outputPath = args[2]
let roundtripPath: String? = args.count > 3 ? args[3] : nil
let sizes = [16, 24, 32, 48, 64, 128, 256]

guard let source = CGImageSourceCreateWithURL(
    URL(fileURLWithPath: sourcePath) as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write("cannot load \(sourcePath)\n".data(using: .utf8)!)
    exit(1)
}

func le16(_ value: UInt16) -> [UInt8] {
    [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)]
}
func le32(_ value: UInt32) -> [UInt8] {
    [UInt8(value & 0xff), UInt8((value >> 8) & 0xff),
     UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)]
}

/// Renders the source at |size| and returns a 32-bpp bottom-up DIB entry.
func dibEntry(size: Int) -> [UInt8] {
    let bytesPerRow = size * 4
    var rgba = [UInt8](repeating: 0, count: bytesPerRow * size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: &rgba, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: bytesPerRow, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        FileHandle.standardError.write("cannot create \(size)px context\n".data(using: .utf8)!)
        exit(1)
    }
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

    var out = [UInt8]()
    out.reserveCapacity(40 + bytesPerRow * size + ((size + 31) / 32) * 4 * size)
    // BITMAPINFOHEADER: height is doubled because the AND mask follows.
    out += le32(40)
    out += le32(UInt32(size))
    out += le32(UInt32(size * 2))
    out += le16(1)
    out += le16(32)
    out += le32(0)              // BI_RGB
    out += le32(UInt32(bytesPerRow * size))
    out += le32(0) + le32(0)    // pixels per metre
    out += le32(0) + le32(0)    // palette

    // DIB rows are bottom-up; the CG buffer is top-up. Reorder RGBA to BGRA.
    for row in 0..<size {
        let sourceRow = size - 1 - row
        let base = sourceRow * bytesPerRow
        for column in 0..<size {
            let index = base + column * 4
            out.append(rgba[index + 2])  // B
            out.append(rgba[index + 1])  // G
            out.append(rgba[index])      // R
            out.append(rgba[index + 3])  // A
        }
    }

    // 1-bpp AND mask, zeroed: transparency comes from the alpha channel.
    let maskRowBytes = ((size + 31) / 32) * 4
    out += [UInt8](repeating: 0, count: maskRowBytes * size)
    return out
}

let entries = sizes.map { dibEntry(size: $0) }

var header: [UInt8] = []
header += le16(0)                  // reserved
header += le16(1)                  // type: icon
header += le16(UInt16(sizes.count))
var offset = 6 + 16 * sizes.count
for (index, size) in sizes.enumerated() {
    let byteCount = entries[index].count
    header.append(size >= 256 ? 0 : UInt8(size))   // 0 means 256
    header.append(size >= 256 ? 0 : UInt8(size))
    header.append(0)               // palette colour count
    header.append(0)               // reserved
    header += le16(1)              // planes
    header += le16(32)             // bits per pixel
    header += le32(UInt32(byteCount))
    header += le32(UInt32(offset))
    offset += byteCount
}

var file = Data(header)
for entry in entries { file.append(contentsOf: entry) }
try file.write(to: URL(fileURLWithPath: outputPath))
FileHandle.standardError.write(
    "wrote \(outputPath) with sizes \(sizes.map(String.init).joined(separator: "/"))\n"
        .data(using: .utf8)!)

if let roundtripPath {
    // Decode the 256px entry back and write it as PNG, proving the container.
    let largestIndex = sizes.count - 1
    let entry = entries[largestIndex]
    let pixelBytes = 256 * 256 * 4
    let dib = [UInt8](entry[40..<(40 + pixelBytes)])
    var rgba = [UInt8](repeating: 0, count: pixelBytes)
    for row in 0..<256 {
        let dibRow = 255 - row
        for column in 0..<256 {
            let src = dibRow * 1024 + column * 4
            let dst = row * 1024 + column * 4
            rgba[dst] = dib[src + 2]      // R
            rgba[dst + 1] = dib[src + 1]  // G
            rgba[dst + 2] = dib[src]      // B
            rgba[dst + 3] = dib[src + 3]  // A
        }
    }
    let provider = CGDataProvider(data: Data(rgba) as CFData)!
    let decoded = CGImage(
        width: 256, height: 256, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: 1024, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: true,
        intent: .defaultIntent)!
    let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: roundtripPath) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, decoded, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write("cannot write \(roundtripPath)\n".data(using: .utf8)!)
        exit(1)
    }
    FileHandle.standardError.write("round-trip PNG: \(roundtripPath)\n".data(using: .utf8)!)
}
