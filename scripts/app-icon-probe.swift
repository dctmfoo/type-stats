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
                                "source": "NSWorkspace original application icon"])
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
