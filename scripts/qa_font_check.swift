#!/usr/bin/env swift
// QA helper: proves the bundled Vazirmatn fonts are valid and registerable through the
// exact CoreText API the app uses (CTFontManagerRegisterFontsForURL), then lists the
// PostScript names the app can ask for.
//
// Usage: swift scripts/qa_font_check.swift <Fonts-dir>
// Exit 0 only if every .ttf registers and a "Vazirmatn" family is present.

import Foundation
import CoreGraphics
import CoreText

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: qa_font_check.swift <Fonts-dir>\n".data(using: .utf8)!)
    exit(2)
}
let dir = args[1]
let fm = FileManager.default
guard let files = try? fm.contentsOfDirectory(atPath: dir) else {
    print("FAIL: cannot list \(dir)")
    exit(1)
}
let fonts = files.filter { $0.lowercased().hasSuffix(".ttf") }.sorted()
guard !fonts.isEmpty else {
    print("FAIL: no .ttf files in \(dir)")
    exit(1)
}

var failures = 0
var registered: [String] = []
for name in fonts {
    let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
    var error: Unmanaged<CFError>?
    let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
    if !ok {
        let message = error?.takeRetainedValue().localizedDescription ?? "unknown error"
        print("FAIL: \(name): \(message)")
        failures += 1
        continue
    }
    // Read the names back out via the registered font.
    guard let descriptor = CTFontDescriptorCreateWithAttributes(
            [kCTFontURLAttribute: url] as CFDictionary) as CTFontDescriptor?,
          CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) != nil else {
        print("FAIL: \(name): cannot create descriptor")
        failures += 1
        continue
    }
    let list = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
    let psNames = list.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
    let families = list.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String }
    _ = descriptor
    let ps = psNames.first ?? "?"
    let family = families.first ?? "?"
    registered.append("\(name) -> family=\(family) postscript=\(ps)")
    print("OK: \(name) family=\(family) postscript=\(ps)")
}

let hasVazir = registered.contains { $0.lowercased().contains("vazir") }
if !hasVazir {
    print("FAIL: no registered font reports a Vazirmatn family")
    failures += 1
}
if failures > 0 {
    print("RESULT: FAIL (\(failures) problem(s), \(fonts.count) fonts)")
    exit(1)
}
print("RESULT: OK (\(fonts.count) fonts registered, Vazirmatn family present)")
