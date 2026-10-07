import AppKit
import TypeStatsCore

// Entry point. The `--dump-*` and `--login-status` options print and exit without any
// UI (see docs/run.md for their formats); otherwise the menu bar app starts.
let options: LaunchOptions
do {
    options = try LaunchOptions.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("TypeStats: bad arguments: \(error)\n".utf8))
    exit(2)
}
// The share prototype uses sample data only, so it never opens the real store.
let dataDir = options.dataDir
    ?? (options.shareCards != nil
        ? FileManager.default.temporaryDirectory.appendingPathComponent("typestats-share-\(getpid())", isDirectory: true)
        : CountStore.defaultDirectory())

if options.loginStatus {
    print(MainLoginItemService().status.rawValue)
    exit(0)
}

// Test seam: read back what a named pasteboard holds. No UI and no store.
if let name = options.pasteboardRead {
    let board = NSPasteboard(name: NSPasteboard.Name(name))
    if let text = board.string(forType: .string) { print("text\t\(text)") }
    for (label, type) in [("png", NSPasteboard.PasteboardType.png), ("tiff", .tiff)] {
        guard let data = board.data(forType: type), let rep = NSBitmapImageRep(data: data) else { continue }
        print("\(label)\t\(rep.pixelsWide)x\(rep.pixelsHigh)\t\(data.count)")
        if label == "png", let url = options.pasteboardPNG { try? data.write(to: url) }
    }
    board.releaseGlobally()
    exit(0)
}

// Test seam: apply --pause / --resume, then print the pause state. No UI and no store.
if options.dumpPause {
    let at = options.at
    let pause = PauseControl(directory: dataDir, now: { at ?? Date() })
    pause.apply(pause: options.pause, resume: options.resume)
    let format = DateFormatter()
    format.locale = Locale(identifier: "en_US_POSIX")
    format.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    let until = pause.state?.until.map(format.string(from:)) ?? "-"
    print("\(pause.isPaused ? "paused" : "running")\t\(until)\t\(pause.menuBarSymbol)\t\(pause.statusText() ?? "-")")
    exit(0)
}

if options.dumpCounts || options.dumpHours || options.dumpExcluded || options.dumpHistory != nil || options.dumpWPM {
    do {
        let at = options.at
        let counter = try KeyCounter(store: try CountStore(directory: dataDir), now: { at ?? Date() })
        if options.dumpCounts {
            for row in counter.topApps(limit: .max) {
                print("\(row.bundleID)\t\(row.count)\t\(row.clicks)")
            }
        }
        if options.dumpExcluded {
            for app in counter.excludedApps { print("\(app.bundleID)\t\(app.name)") }
        }
        if options.dumpHours {
            for hour in counter.todayHours.values.sorted(by: { $0.hour < $1.hour }) where hour.keys + hour.clicks > 0 {
                print("\(hour.hour)\t\(hour.keys)\t\(hour.clicks)")
            }
            if counter.keysWithoutHour + counter.clicksWithoutHour > 0 {
                print("nohour\t\(counter.keysWithoutHour)\t\(counter.clicksWithoutHour)")
            }
        }
        if let n = options.dumpHistory {
            let history = try counter.history(days: n)
            for day in history.days { print("day\t\(day.day)\t\(day.keys)\t\(day.clicks)") }
            for app in history.apps { print("app\t\(app.bundleID)\t\(app.count)\t\(app.clicks)") }
            print("total\t\(history.totalKeys)\t\(history.totalClicks)")
        }
        if options.dumpWPM {
            func format(_ wpm: Double?) -> String { wpm.map { String(format: "%.1f", $0) } ?? "-" }
            print("overall\t\(format(counter.wpm))")
            for app in counter.todayCounts.values.sorted(by: { $0.bundleID < $1.bundleID }) where app.wpm != nil {
                print("\(app.bundleID)\t\(format(app.wpm))")
            }
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("TypeStats: cannot read counts: \(error)\n".utf8))
        exit(1)
    }
}

// Test seam: counts with no hour, written before the app opens the store.
if !options.seedNoHour.isEmpty {
    do {
        let store = try CountStore(directory: dataDir)
        let day = DayKey.string(for: options.at ?? Date(), calendar: .current)
        for (bundleID, n) in options.seedNoHour {
            try store.add(day: day, app: AppController.identity(forBundleID: bundleID), keys: n, clicks: n)
        }
        try store.save()
    } catch {
        FileHandle.standardError.write(Data("TypeStats: cannot seed counts: \(error)\n".utf8))
        exit(1)
    }
}

AppController.shared = AppController(options: options, dataDir: dataDir)
TypeStatsApp.main()
