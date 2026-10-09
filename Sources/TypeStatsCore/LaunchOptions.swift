import Foundation

/// Command line options. All but `dataDir` are test seams.
public struct LaunchOptions: Equatable, Sendable {
    public var dataDir: URL?
    public var showWindow = false
    public var dumpCounts = false
    public var noTap = false
    /// Keep simulated presses unsaved until quit (no immediate or timed flush),
    /// so a check can prove that quitting saves pending counts.
    public var holdFlush = false
    /// `--snapshot <png>`: render the popup view to a PNG after launch (for checks
    /// on machines where the terminal cannot record the screen).
    public var snapshot: URL?
    /// `--simulate-keys "bundleId:n,bundleId:n"`
    public var simulateKeys: [(bundleID: String, count: Int)] = []
    /// `--simulate-text "bundleId:text"`: one key press per character.
    public var simulateText: (bundleID: String, text: String)?
    /// `--simulate-clicks "bundleId:n,bundleId:n"`
    public var simulateClicks: [(bundleID: String, count: Int)] = []
    /// `--simulate-self-clicks n`: n clicks at the centre of a TypeStats window,
    /// attributed by the real under-pointer lookup (no app given).
    public var simulateSelfClicks = 0
    /// `--simulate-typing "bundleId:keys:seconds,..."`: per segment, `keys` timed key
    /// presses spread evenly over `seconds`; segments are separated by an idle pause.
    public var simulateTyping: [TypingSegment] = []
    /// `--at yyyy-MM-ddTHH:mm`: freeze the app's clock at this local time, so counts
    /// land on that day and hour and "today" is that day.
    public var at: Date?
    /// `--dump-hours`: print today's keys and clicks per hour and exit.
    public var dumpHours = false
    /// `--dump-history n`: print the last n days (daily totals, per-app totals) and exit.
    public var dumpHistory: Int?
    /// `--dump-wpm`: print today's estimated typing speed, overall and per app, and exit.
    public var dumpWPM = false
    /// `--login-status`: print the real login item status (read only) and exit.
    public var loginStatus = false
    /// `--view today|week|month`: which period the popup opens on.
    public var view: StatsPeriod = .today
    /// `--seed-nohour "bundleId:n,..."`: before launch, add n keys and n clicks to today for
    /// each app with no hour, as counts saved before hourly tracking look (today's view then
    /// shows the "no hour" note).
    public var seedNoHour: [(bundleID: String, count: Int)] = []
    /// `--measure-views`: open the popup in a window that follows its content size (as the
    /// menu bar window does), switch through every period while counts change, print each
    /// size and window frame, and exit.
    public var measureViews = false
    /// `--share-cards <dir>`: render the share prototype images and text from fixed sample
    /// data into that folder and exit (never reads the store).
    public var shareCards: URL?
    /// `--share-copy image|text`: after simulating, copy the card or the text line for
    /// `--view` to the pasteboard named by `--pasteboard` (never the general one), then exit.
    public var shareCopy: String?
    /// `--pasteboard <name>`: the named pasteboard `--share-copy` writes to.
    public var pasteboard: String?
    /// `--share-save <path>`: after simulating, write the card for `--view` to that path as a
    /// PNG (no dialog) and exit.
    public var shareSave: URL?
    /// `--pasteboard-read <name>`: print what a named pasteboard holds (`text`, `png`,
    /// `tiff` lines), then release it and exit. Never reads the store or the general pasteboard.
    public var pasteboardRead: String?
    /// `--pasteboard-png <path>`: with `--pasteboard-read`, also write the PNG found there.
    public var pasteboardPNG: URL?
    /// `--share-panel`: open the Save image dialog at launch (as the Share menu does), for
    /// checking that it appears in front.
    public var sharePanel = false
    /// `--ready-file <path>`: write this file once startup and the simulated presses and
    /// clicks are done (and any `--snapshot` is written), so a check can wait on it
    /// instead of sleeping.
    public var readyFile: URL?

    /// `--exclude "bundleId,..."`: before the simulated events, add these apps to the
    /// exclusion list (the same call the popup's Exclude button makes).
    public var exclude: [String] = []
    /// `--include "bundleId,..."`: remove these apps from the exclusion list.
    public var include: [String] = []
    /// `--dump-excluded`: print the exclusion list as `bundleId<TAB>name` and exit.
    public var dumpExcluded = false
    /// `--excluded-page`: open the popup on its Excluded apps page.
    public var excludedPage = false
    /// `--pause 15m|1h|until-resumed`: start the app (or `--dump-pause`) with counting paused.
    public var pause: PauseChoice?
    /// `--resume`: clear any pause at launch (before `--pause`, if both are given).
    public var resume = false
    /// `--dump-pause`: print the pause state and exit.
    public var dumpPause = false
    /// `--resume-after n`: n seconds after launch, resume as a click on Resume would, so a check
    /// can watch the menu bar icon change while the app runs.
    public var resumeAfter: Double?
    /// `--no-test-banner`: in test mode, leave the "Key capture off (test mode)" line out of the
    /// popup (for screenshots).
    public var noTestBanner = false
    /// Update verification seams. Overrides and actions are accepted only with --no-tap.
    public var updateVersion: String?
    public var updateCask: URL?
    public var updateBrew: URL?
    public var updatesWindow = false
    public var performUpdate = false
    public var updateRelaunchReady: URL?

    public struct TypingSegment: Equatable, Sendable {
        public let bundleID: String
        public let keys: Int
        public let seconds: Double

        public init(bundleID: String, keys: Int, seconds: Double) {
            self.bundleID = bundleID
            self.keys = keys
            self.seconds = seconds
        }
    }

    public init() {}

    public enum ParseError: Error, Equatable {
        case missingValue(String)
        case badSpec(String)
    }

    public static func parse(_ args: [String], timeZone: TimeZone = .current) throws -> LaunchOptions {
        var o = LaunchOptions()
        var i = 0
        func value(_ flag: String) throws -> String {
            i += 1
            guard i < args.count else { throw ParseError.missingValue(flag) }
            return args[i]
        }
        while i < args.count {
            switch args[i] {
            case "--data-dir": o.dataDir = URL(fileURLWithPath: try value("--data-dir"), isDirectory: true)
            case "--show-window": o.showWindow = true
            case "--dump-counts": o.dumpCounts = true
            case "--no-tap": o.noTap = true
            case "--hold-flush": o.holdFlush = true
            case "--snapshot": o.snapshot = URL(fileURLWithPath: try value("--snapshot"))
            case "--simulate-keys": o.simulateKeys = try parseKeys(try value("--simulate-keys"))
            case "--simulate-clicks": o.simulateClicks = try parseKeys(try value("--simulate-clicks"))
            case "--simulate-self-clicks":
                let spec = try value("--simulate-self-clicks")
                guard let n = Int(spec), n >= 0 else { throw ParseError.badSpec(spec) }
                o.simulateSelfClicks = n
            case "--simulate-typing": o.simulateTyping = try parseTyping(try value("--simulate-typing"))
            case "--at":
                let spec = try value("--at")
                guard let date = parseDate(spec, timeZone: timeZone) else { throw ParseError.badSpec(spec) }
                o.at = date
            case "--dump-hours": o.dumpHours = true
            case "--dump-wpm": o.dumpWPM = true
            case "--login-status": o.loginStatus = true
            case "--dump-history":
                let spec = try value("--dump-history")
                guard let n = Int(spec), n > 0 else { throw ParseError.badSpec(spec) }
                o.dumpHistory = n
            case "--seed-nohour": o.seedNoHour = try parseKeys(try value("--seed-nohour"))
            case "--measure-views": o.measureViews = true
            case "--share-cards": o.shareCards = URL(fileURLWithPath: try value("--share-cards"), isDirectory: true)
            case "--share-copy":
                let spec = try value("--share-copy")
                guard ["image", "text"].contains(spec) else { throw ParseError.badSpec(spec) }
                o.shareCopy = spec
            case "--pasteboard":
                let spec = try value("--pasteboard")
                guard !spec.isEmpty, spec != "Apple CFPasteboard general" else { throw ParseError.badSpec(spec) }
                o.pasteboard = spec
            case "--share-save": o.shareSave = URL(fileURLWithPath: try value("--share-save"))
            case "--pasteboard-read":
                let spec = try value("--pasteboard-read")
                guard !spec.isEmpty, spec != "Apple CFPasteboard general" else { throw ParseError.badSpec(spec) }
                o.pasteboardRead = spec
            case "--pasteboard-png": o.pasteboardPNG = URL(fileURLWithPath: try value("--pasteboard-png"))
            case "--share-panel": o.sharePanel = true
            case "--exclude": o.exclude = try parseIDs(try value("--exclude"))
            case "--include": o.include = try parseIDs(try value("--include"))
            case "--dump-excluded": o.dumpExcluded = true
            case "--excluded-page": o.excludedPage = true
            case "--pause":
                let spec = try value("--pause")
                switch spec {
                case "15m": o.pause = .fifteenMinutes
                case "1h": o.pause = .oneHour
                case "until-resumed": o.pause = .untilResumed
                default: throw ParseError.badSpec(spec)
                }
            case "--resume": o.resume = true
            case "--resume-after":
                let spec = try value("--resume-after")
                guard let n = Double(spec), n >= 0 else { throw ParseError.badSpec(spec) }
                o.resumeAfter = n
            case "--dump-pause": o.dumpPause = true
            case "--update-version": o.updateVersion = try value("--update-version")
            case "--update-cask": o.updateCask = URL(fileURLWithPath: try value("--update-cask"))
            case "--update-brew": o.updateBrew = URL(fileURLWithPath: try value("--update-brew"))
            case "--updates-window": o.updatesWindow = true
            case "--perform-update": o.performUpdate = true
            case "--update-relaunch-ready": o.updateRelaunchReady = URL(fileURLWithPath: try value("--update-relaunch-ready"))
            case "--no-test-banner": o.noTestBanner = true
            case "--ready-file": o.readyFile = URL(fileURLWithPath: try value("--ready-file"))
            case "--view":
                let spec = try value("--view")
                guard let view = StatsPeriod(rawValue: spec) else { throw ParseError.badSpec(spec) }
                o.view = view
            case "--simulate-text":
                let spec = try value("--simulate-text")
                guard let colon = spec.firstIndex(of: ":"), colon != spec.startIndex else {
                    throw ParseError.badSpec(spec)
                }
                o.simulateText = (String(spec[..<colon]), String(spec[spec.index(after: colon)...]))
            default: break  // ignore system arguments such as -NSDocumentRevisionsDebugMode
            }
            i += 1
        }
        return o
    }

    static func parseKeys(_ spec: String) throws -> [(bundleID: String, count: Int)] {
        try spec.split(separator: ",").map { part in
            guard let colon = part.lastIndex(of: ":"), colon != part.startIndex,
                  let n = Int(part[part.index(after: colon)...]), n >= 0
            else { throw ParseError.badSpec(String(part)) }
            return (String(part[..<colon]).trimmingCharacters(in: .whitespaces), n)
        }
    }

    static func parseIDs(_ spec: String) throws -> [String] {
        let ids = spec.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !ids.isEmpty, !ids.contains("") else { throw ParseError.badSpec(spec) }
        return ids
    }

    static func parseTyping(_ spec: String) throws -> [TypingSegment] {
        try spec.split(separator: ",").map { part in
            let fields = part.split(separator: ":", omittingEmptySubsequences: false)
            guard fields.count >= 3,
                  let seconds = Double(fields[fields.count - 1]), seconds > 0,
                  let keys = Int(fields[fields.count - 2]), keys > 0
            else { throw ParseError.badSpec(String(part)) }
            let bundleID = fields.dropLast(2).joined(separator: ":").trimmingCharacters(in: .whitespaces)
            guard !bundleID.isEmpty else { throw ParseError.badSpec(String(part)) }
            return TypingSegment(bundleID: bundleID, keys: keys, seconds: seconds)
        }
    }

    /// Local time "yyyy-MM-ddTHH:mm" or "yyyy-MM-ddTHH:mm:ss".
    static func parseDate(_ spec: String, timeZone: TimeZone) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            f.dateFormat = format
            if let date = f.date(from: spec) { return date }
        }
        return nil
    }

    public static func == (a: LaunchOptions, b: LaunchOptions) -> Bool {
        a.dataDir == b.dataDir && a.showWindow == b.showWindow && a.dumpCounts == b.dumpCounts
            && a.noTap == b.noTap && a.holdFlush == b.holdFlush && a.snapshot == b.snapshot
            && a.simulateKeys.map { "\($0.bundleID):\($0.count)" } == b.simulateKeys.map { "\($0.bundleID):\($0.count)" }
            && a.simulateText?.bundleID == b.simulateText?.bundleID && a.simulateText?.text == b.simulateText?.text
            && a.simulateClicks.map { "\($0.bundleID):\($0.count)" } == b.simulateClicks.map { "\($0.bundleID):\($0.count)" }
            && a.simulateSelfClicks == b.simulateSelfClicks && a.simulateTyping == b.simulateTyping
            && a.at == b.at && a.dumpHours == b.dumpHours && a.dumpHistory == b.dumpHistory
            && a.dumpWPM == b.dumpWPM && a.loginStatus == b.loginStatus && a.view == b.view
            && a.seedNoHour.map { "\($0.bundleID):\($0.count)" } == b.seedNoHour.map { "\($0.bundleID):\($0.count)" }
            && a.measureViews == b.measureViews && a.shareCards == b.shareCards
            && a.shareCopy == b.shareCopy && a.pasteboard == b.pasteboard && a.shareSave == b.shareSave
            && a.pasteboardRead == b.pasteboardRead && a.pasteboardPNG == b.pasteboardPNG
            && a.sharePanel == b.sharePanel && a.exclude == b.exclude && a.include == b.include
            && a.dumpExcluded == b.dumpExcluded && a.excludedPage == b.excludedPage
            && a.pause == b.pause && a.resume == b.resume && a.dumpPause == b.dumpPause
            && a.updateVersion == b.updateVersion && a.updateCask == b.updateCask && a.updateBrew == b.updateBrew
            && a.updatesWindow == b.updatesWindow && a.performUpdate == b.performUpdate
            && a.updateRelaunchReady == b.updateRelaunchReady
            && a.resumeAfter == b.resumeAfter && a.readyFile == b.readyFile && a.noTestBanner == b.noTestBanner
    }
}

/// The period the popup shows.
public enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case today, week, month

    public var id: String { rawValue }

    /// Number of days shown, ending today.
    public var days: Int {
        switch self {
        case .today: 1
        case .week: 7
        case .month: 30
        }
    }

    public var title: String {
        switch self {
        case .today: "Today"
        case .week: "7 days"
        case .month: "30 days"
        }
    }
}
