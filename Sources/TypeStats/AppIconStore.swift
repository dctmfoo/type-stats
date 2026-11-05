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
    // One resolver and cache serve popup and export alike. Providers let the pixel probe
    // exercise real bundle validation/fallbacks without registering fake installed apps.
    static let shared = Resolver()

    static func icon(bundleID: String, expectedName: String? = nil) -> Icon? {
        shared.icon(bundleID: bundleID, expectedName: expectedName)
    }

    static func resolve(bundleID: String, expectedName: String? = nil) -> Icon? {
        shared.resolve(bundleID: bundleID, expectedName: expectedName)
    }

    @MainActor final class Resolver {
        private let cache = NSCache<NSString, Entry>()
        private let applicationURL: (String) -> URL?
        private let nativeIcon: (URL) -> NSImage?

        init(applicationURL: @escaping (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }, nativeIcon: @escaping (URL) -> NSImage? = {
            NSWorkspace.shared.icon(forFile: $0.path)
        }) {
            self.applicationURL = applicationURL
            self.nativeIcon = nativeIcon
        }

        func icon(bundleID: String, expectedName: String? = nil) -> Icon? {
            let key = (bundleID.lowercased() + "|" + (expectedName ?? "").lowercased()) as NSString
            if let entry = cache.object(forKey: key), entry.icon != nil || Date().timeIntervalSince(entry.resolvedAt) < 60 {
                return entry.icon
            }
            let icon = resolve(bundleID: bundleID, expectedName: expectedName)
            cache.setObject(Entry(icon), forKey: key)
            return icon
        }

        func resolve(bundleID: String, expectedName: String? = nil) -> Icon? {
            guard !bundleID.isEmpty,
                  let url = applicationURL(bundleID),
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
            // Prefer declared public artwork over appearance-dependent workspace variants.
            // An absent, unreadable or undecodable resource still uses the native icon.
            let artwork = AppIconStore.declaredArtwork(bundle).flatMap(AppIconStore.standardArtwork)
                ?? nativeIcon(url).flatMap(AppIconStore.standardArtwork)
            guard let artwork else { return nil }
            return Icon(image: artwork, bundleURL: url, bundleID: actualID)
        }
    }

    private static func declaredArtwork(_ bundle: Bundle) -> NSImage? {
        guard let name = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
              !name.isEmpty else { return nil }
        let file = (name as NSString).pathExtension.isEmpty ? name + ".icns" : name
        guard let url = bundle.url(forResource: file, withExtension: nil) else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func standardArtwork(_ original: NSImage) -> NSImage? {
        // 64 pixels covers the largest current exported app icon (24pt at 2x).
        var rect = CGRect(x: 0, y: 0, width: 64, height: 64)
        guard let image = original.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let standard = StandardBitmap.make(image) else { return nil }
        let artwork = NSImage(size: original.size)
        artwork.addRepresentation(standard)
        return artwork
    }
}
