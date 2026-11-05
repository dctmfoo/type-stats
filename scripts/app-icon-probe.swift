// Execute the actual icon resolver against public installed-bundle metadata.
import AppKit

@main
struct AppIconProbe {
    @MainActor static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let apps = [("com.anthropic.claudefordesktop", "Claude"), ("com.openai.codex", "ChatGPT"),
                    ("com.microsoft.teams2", "Teams"), ("com.hnc.Discord", "Discord"),
                    ("com.mitchellh.ghostty", "Ghostty"), ("com.google.Chrome", "Google Chrome"),
                    ("com.apple.Terminal", "Terminal"), ("local.typestats.unavailable-icon-fixture", "Unavailable app")]
        var sources: [[String: String]] = []
        // Verify real resolver pixels against the declared resource, not just provenance.
        for (id, name) in [("com.anthropic.claudefordesktop", "Claude"),
                           ("com.microsoft.teams2", "Teams"), ("com.google.Chrome", "Google Chrome")] {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
                  let bundle = Bundle(url: url),
                  let declaration = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String else { continue }
            let file = (declaration as NSString).pathExtension.isEmpty ? declaration + ".icns" : declaration
            guard let resource = bundle.url(forResource: file, withExtension: nil),
                  let declared = NSImage(contentsOf: resource),
                  let actual = AppIconStore.icon(bundleID: id, expectedName: name) else { continue }
            func raster(_ image: NSImage) -> Data? {
                var rect = CGRect(x: 0, y: 0, width: 64, height: 64)
                guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
                      let bitmap = StandardBitmap.make(cg) else { return nil }
                return bitmap.representation(using: .png, properties: [:])
            }
            guard raster(actual.image) == raster(declared) else {
                fatalError("FAIL declared artwork pixels: " + id)
            }
        }
        for (id, name) in apps {
            if let icon = AppIconStore.resolve(bundleID: id, expectedName: name) {
                guard icon.bundleID.caseInsensitiveCompare(id) == .orderedSame,
                      let data = icon.image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: data),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try png.write(to: directory.appendingPathComponent(id + ".png"))
                sources.append(["requestedID": id, "actualID": icon.bundleID, "bundleURL": icon.bundleURL.path,
                                "source": "validated declared bundle artwork, with native workspace fallback"])
            } else {
                sources.append(["requestedID": id, "expectedName": name,
                                "source": "neutral system app symbol; exact bundle/product artwork unavailable or ambiguous"])
            }
        }
        guard AppIconStore.icon(bundleID: "local.typestats.unavailable-icon-fixture") == nil,
              AppIconStore.icon(bundleID: "") == nil,
              AppIconStore.resolve(bundleID: "com.google.Chrome", expectedName: "Wrong product") == nil else { throw CocoaError(.fileReadCorruptFile) }
        try JSONSerialization.data(withJSONObject: sources, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("sources.json"))
        print("PASS exact bundle icon provenance and unavailable/empty identity fallback")
    }
}
