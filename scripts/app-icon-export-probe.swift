// Real AppTag and ShareActions, in a fresh process per cache order/appearance.
import AppKit
import SwiftUI
import TypeStatsCore

@main struct AppIconExportProbe {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let popupFirst = CommandLine.arguments[2] == "popup-first"
        let dark = CommandLine.arguments[3] == "dark"
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let apps = [AppIdentity(bundleID: "com.anthropic.claudefordesktop", name: "Claude"),
                    AppIdentity(bundleID: "com.microsoft.teams2", name: "Teams"),
                    AppIdentity(bundleID: "com.google.Chrome", name: "Google Chrome")]
        let store = try CountStore(directory: dir.appendingPathComponent("data"))
        for day in ["2026-10-04", "2026-10-05"] {
            for (i, app) in apps.enumerated() {
                try store.add(day: day, hour: 13, app: app, keys: 600 - i * 150,
                              clicks: 60 - i * 10, burstCount: 300, activeSeconds: 60)
            }
        }
        try store.save()
        let options = try LaunchOptions.parse(["--at", "2026-10-05T14:30"])
        let counter = try KeyCounter(store: store, now: { options.at! })
        func popupRows() throws {
            let rows = HStack {
                ForEach(apps, id: \.bundleID) { app in
                    AppTag(bundleID: app.bundleID, name: app.name)
                }
            }.padding(10).background(dark ? Color.black : Color.white)
                .environment(\.colorScheme, dark ? .dark : .light)
            guard let png = ShareRender.png(rows, scale: 2) else { throw ShareActions.Failure.render }
            try png.write(to: dir.appendingPathComponent("popup-tags.png"))
        }
        // Independent declared-resource templates verify final card pixels, not just a
        // successful resolver lookup or nonempty clipboard data.
        for (index, app) in apps.enumerated() {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID),
                  let bundle = Bundle(url: url),
                  let name = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String else { continue }
            let file = (name as NSString).pathExtension.isEmpty ? name + ".icns" : name
            guard let resource = bundle.url(forResource: file, withExtension: nil),
                  let original = NSImage(contentsOf: resource) else { continue }
            var rect = CGRect(x: 0, y: 0, width: 64, height: 64)
            guard let cg = original.cgImage(forProposedRect: &rect, context: nil, hints: nil),
                  let bitmap = StandardBitmap.make(cg) else { throw ShareActions.Failure.render }
            let image = NSImage(size: original.size); image.addRepresentation(bitmap)
            for size in [20, 24] {
                let view = Image(nsImage: image).resizable().renderingMode(.original)
                    .allowedDynamicRange(.standard).scaledToFit()
                    .frame(width: CGFloat(size), height: CGFloat(size))
                    .background(SharePalette.background).environment(\.colorScheme, .light)
                try ShareRender.png(view, scale: 2)!.write(to: dir.appendingPathComponent("declared-\(index)-\(size).png"))
            }
        }
        if popupFirst { try popupRows() }
        for (label, period) in [("today", StatsPeriod.today), ("week", .week), ("month", .month)] {
            let summary = ShareSummary.make(period: period, counter: counter)
            let pasteboard = NSPasteboard(name: .init("typestats-icons-" + UUID().uuidString))
            defer { pasteboard.releaseGlobally() }
            try ShareActions.copyImage(summary, to: pasteboard)
            for (type, suffix) in [(NSPasteboard.PasteboardType.png, "png"), (.tiff, "tiff")] {
                guard let data = pasteboard.data(forType: type), let rep = NSBitmapImageRep(data: data),
                      rep.pixelsWide == 2400, rep.pixelsHigh == 1260 else { throw ShareActions.Failure.pasteboard }
                try data.write(to: dir.appendingPathComponent("copy-\(label).\(suffix)"))
            }
            try ShareActions.savePNG(summary, to: dir.appendingPathComponent("save-\(label).png"))
        }
        if !popupFirst { try popupRows() }
        print("PASS real AppTag/Copy PNG+TIFF/Save PNG: today, weekly, month; \(CommandLine.arguments[2]); \(CommandLine.arguments[3]) context; 2400x1260")
    }
}
