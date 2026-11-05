// Deterministic public-bundle fixtures exercise the actual shared resolver and cache.
import AppKit

@main struct AppIconFixtureProbe {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func require(_ value: Bool, _ label: String) throws {
            guard value else { throw NSError(domain: "AppIconFixture", code: 1,
                                             userInfo: [NSLocalizedDescriptionKey: label]) }
        }
        func bitmap(_ size: Int, native: Bool = false) -> NSBitmapImageRep {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
            for y in 0..<size { for x in 0..<size {
                let u = Double(x) / Double(size), v = Double(y) / Double(size)
                let rgba: [UInt8]
                if native { rgba = [0, 0, 255, 255] }
                else if u < 0.125 || v < 0.125 || u > 0.875 || v > 0.875 { rgba = [0, 0, 0, 0] }
                else if u > 0.4 && u < 0.6 && v > 0.4 && v < 0.6 { rgba = [0, 0, 0, 255] }
                else { rgba = [51, 204, 77, 255] }
                for c in 0..<4 { rep.bitmapData![(y * size + x) * 4 + c] = rgba[c] }
            }}
            return rep
        }
        let iconset = root.appendingPathComponent("Fixture.iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for n in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let suffix = scale == 2 ? "@2x" : ""
                try bitmap(n * scale).representation(using: .png, properties: [:])!
                    .write(to: iconset.appendingPathComponent("icon_\(n)x\(n)\(suffix).png"))
            }
        }
        let icns = root.appendingPathComponent("Fixture.icns")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
        try process.run(); process.waitUntilExit()
        try require(process.terminationStatus == 0, "create genuine multi-resolution ICNS")
        let native = NSImage(size: NSSize(width: 64, height: 64)); native.addRepresentation(bitmap(64, native: true))
        func fixture(_ declaration: String?, assetOnly: Bool = false, corrupt: Bool = false) throws -> (String, URL) {
            let id = "local.typestats.fixture." + UUID().uuidString
            let url = root.appendingPathComponent(id + ".app")
            let resources = url.appendingPathComponent("Contents/Resources")
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            var info = ["CFBundleIdentifier": id, "CFBundleName": "Pixel fixture", "CFBundlePackageType": "APPL"]
            if let declaration { info["CFBundleIconFile"] = declaration }
            if assetOnly { info["CFBundleIconName"] = "CatalogIcon" }
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: url.appendingPathComponent("Contents/Info.plist"))
            if declaration == "Fixture" || declaration == "Fixture.icns" {
                try FileManager.default.copyItem(at: icns, to: resources.appendingPathComponent("Fixture.icns"))
            }
            if corrupt { try Data("broken".utf8).write(to: resources.appendingPathComponent("Broken.icns")) }
            return (id, url)
        }
        func pixels(_ icon: AppIconStore.Icon?) throws -> NSBitmapImageRep {
            try require(icon != nil, "resolved fixture")
            let cg = icon!.image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            try require(cg.width >= 48 && cg.height >= 48, "export resolution")
            return NSBitmapImageRep(cgImage: cg)
        }
        func checkDeclared(_ icon: AppIconStore.Icon?) throws {
            let rep = try pixels(icon)
            func color(_ u: Double, _ v: Double) -> NSColor {
                rep.colorAt(x: Int(Double(rep.pixelsWide) * u), y: Int(Double(rep.pixelsHigh) * v))!.usingColorSpace(.sRGB)!
            }
            try require(color(0.02, 0.02).alphaComponent == 0, "transparent corners preserved")
            let green = color(0.25, 0.5), black = color(0.5, 0.5)
            try require(abs(green.greenComponent - 0.8) < 0.03 && abs(green.redComponent - 0.2) < 0.03,
                        "declared colour selected instead of native blue: \(green) at \(rep.pixelsWide)px")
            try require(black.alphaComponent == 1 && black.redComponent < 0.01 && black.greenComponent < 0.01,
                        "legitimate opaque black detail preserved")
        }
        for declaration in ["Fixture.icns", "Fixture"] {
            let (id, url) = try fixture(declaration)
            for order in [["popup", "export"], ["export", "popup"]] {
                var lookups = 0, nativeCalls = 0
                let resolver = AppIconStore.Resolver(applicationURL: { _ in lookups += 1; return url },
                    nativeIcon: { _ in nativeCalls += 1; return native })
                for _ in order { try checkDeclared(resolver.icon(bundleID: id, expectedName: "Pixel fixture")) }
                try require(lookups == 1 && nativeCalls == 0, "both cache orders reuse declared artwork")
                try require(resolver.icon(bundleID: id, expectedName: "Wrong product") == nil, "name remains part of cache identity")
                try require(resolver.icon(bundleID: "wrong.identifier") == nil, "bundle ID mismatch rejected")
                try require(resolver.icon(bundleID: "") == nil, "empty ID rejected")
            }
        }
        for (declaration, assetOnly, corrupt) in [("Missing.icns", false, false),
            ("Broken.icns", false, true), (nil, true, false), (nil, false, false)] as [(String?, Bool, Bool)] {
            let (id, url) = try fixture(declaration, assetOnly: assetOnly, corrupt: corrupt)
            let resolver = AppIconStore.Resolver(applicationURL: { _ in url }, nativeIcon: { _ in native })
            let rep = try pixels(resolver.icon(bundleID: id, expectedName: "Pixel fixture"))
            let color = rep.colorAt(x: 0, y: 0)!.usingColorSpace(.sRGB)!
            try require(color.blueComponent > 0.99 && color.alphaComponent == 1, "native fallback pixels")
            let unavailable = AppIconStore.Resolver(applicationURL: { _ in url }, nativeIcon: { _ in nil })
            try require(unavailable.icon(bundleID: id) == nil, "neutral fallback when no artwork decodes")
        }
        let absent = AppIconStore.Resolver(applicationURL: { _ in nil })
        try require(absent.icon(bundleID: "unavailable") == nil, "uninstalled identity is neutral")
        print("PASS declared ICNS/extensionless pixels, alpha, black detail, both cache orders, identity gates and native/neutral fallbacks")
    }
}
