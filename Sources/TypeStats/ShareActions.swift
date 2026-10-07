import AppKit
import SwiftUI
import TypeStatsCore

/// Copy image, Copy text and Save image... for the period the popup is showing.
/// The card is card A from `ShareCardView.swift`, rendered at 2x (2400x1260 pixels for
/// the 1200x630 card).
@MainActor
enum ShareActions {
    enum Failure: Error { case render, pasteboard }

    static func summary(_ controller: AppController, _ period: StatsPeriod) -> ShareSummary {
        ShareSummary.make(period: period, counter: controller.counter)
    }

    /// Card A as a PNG (and a TIFF for apps that only read that), or nil if rendering fails.
    static func render(_ summary: ShareSummary) -> (png: Data, tiff: Data, pixelWidth: Int, pixelHeight: Int)? {
        let renderer = ImageRenderer(content: ShareCardA(sample: summary))
        renderer.scale = ShareRender.shareScale
        guard let image = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]),
              let tiff = rep.tiffRepresentation(using: .lzw, factor: 0)
        else { return nil }
        return (png, tiff, image.width, image.height)
    }

    static func copyImage(_ summary: ShareSummary, to pasteboard: NSPasteboard) throws {
        guard let card = render(summary) else { throw Failure.render }
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        guard pasteboard.setData(card.png, forType: .png), pasteboard.setData(card.tiff, forType: .tiff)
        else { throw Failure.pasteboard }
    }

    static func copyText(_ summary: ShareSummary, to pasteboard: NSPasteboard) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(summary.text, forType: .string) else { throw Failure.pasteboard }
    }

    static func savePNG(_ summary: ShareSummary, to url: URL) throws {
        guard let card = render(summary) else { throw Failure.render }
        try card.png.write(to: url, options: .atomic)
    }

    /// Opens the save dialog in Downloads with `TypeStats-<period>-<date>.png` and writes the
    /// card if the person confirms. The app is activated first: a menu bar app is not
    /// frontmost, and without that the dialog opens behind other windows.
    static func savePanel(_ controller: AppController, _ period: StatsPeriod) throws {
        let summary = summary(controller, period)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.nameFieldStringValue = ShareSummary.fileName(
            period: period, date: controller.counter.currentDate, calendar: controller.counter.calendar)
        panel.canCreateDirectories = true
        panel.title = "Save image"
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .modalPanel
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try savePNG(summary, to: url)
    }

    /// The native Share menu, shown at the pointer. `done` gets a short note ("Image copied")
    /// to show on the Share button, or the error text.
    static func showMenu(_ controller: AppController, period: StatsPeriod, done: @escaping (String) -> Void) {
        func item(_ title: String, _ symbol: String, _ run: @escaping () throws -> String?) -> NSMenuItem {
            let action = MenuAction {
                do { if let note = try run() { done(note) } } catch { done("Share failed") }
            }
            let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            item.target = action
            item.representedObject = action
            return item
        }
        let menu = NSMenu()
        menu.addItem(item("Copy image", "photo.on.rectangle") {
            try copyImage(summary(controller, period), to: .general); return "Image copied"
        })
        menu.addItem(item("Copy text", "text.quote") {
            try copyText(summary(controller, period), to: .general); return "Text copied"
        })
        menu.addItem(.separator())
        menu.addItem(item("Save image...", "square.and.arrow.down") {
            try savePanel(controller, period); return nil
        })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

final class MenuAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}

/// The Share control in the popup footer, next to Quit. Drawn in SwiftUI so `--snapshot`
/// renders it; a click opens the native menu.
struct ShareButton: View {
    let controller: AppController
    let period: StatsPeriod
    @State private var note: String?

    var body: some View {
        Button {
            ShareActions.showMenu(controller, period: period) { text in
                note = text
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    note = nil
                }
            }
        } label: {
            Label(note ?? "Share", systemImage: note == nil ? "square.and.arrow.up" : "checkmark")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 7)
                .background(Color.accentColor.opacity(0.14), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("share")
    }
}
