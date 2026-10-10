import AppKit

/// Reads public bundle artwork only. Never substitutes a service/parent-brand logo.
@MainActor
enum AppIconStore {
    struct Icon {
        let image: NSImage
        let bundleURL: URL
        let bundleID: String
    }
    private final class Entry {
        let icon: Icon?
        let resolvedAt = Date()
        init(_ icon: Icon?) { self.icon = icon }
    }
    private static let cache = NSCache<NSString, Entry>()

    static func icon(bundleID: String, expectedName: String? = nil) -> Icon? {
        let key = (bundleID.lowercased() + "|" + (expectedName ?? "").lowercased()) as NSString
        if let entry = cache.object(forKey: key), entry.icon != nil || Date().timeIntervalSince(entry.resolvedAt) < 60 {
            return entry.icon
        }
        let icon = resolve(bundleID: bundleID, expectedName: expectedName)
        cache.setObject(Entry(icon), forKey: key)
        return icon
    }

    static func resolve(bundleID: String, expectedName: String? = nil) -> Icon? {
        guard !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url), let actualID = bundle.bundleIdentifier,
              actualID.caseInsensitiveCompare(bundleID) == .orderedSame else { return nil }
        // A fixture must not label another product's artwork as its own. Some installed
        // bundles share an identifier, so verify public declared names as well.
        if let expectedName {
            func canonical(_ name: String) -> String {
                let normalized = name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
                let value = String(String.UnicodeScalarView(normalized))
                switch value {
                case "teams", "microsoftteams": return "teams"
                case "chrome", "googlechrome": return "chrome"
                default: return value
                }
            }
            let names = ["CFBundleName", "CFBundleDisplayName"].compactMap {
                (bundle.localizedInfoDictionary?[$0] ?? bundle.infoDictionary?[$0]) as? String
            }
            guard names.contains(where: { canonical($0) == canonical(expectedName) }) else { return nil }
        }
        let original = NSWorkspace.shared.icon(forFile: url.path)
        guard let image = original.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let standard = StandardBitmap.make(image) else { return nil }
        let artwork = NSImage(size: original.size)
        artwork.addRepresentation(standard)
        return Icon(image: artwork, bundleURL: url, bundleID: actualID)
    }
}
