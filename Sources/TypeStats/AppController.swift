import AppKit
import SwiftUI
import TypeStatsCore

/// Disposable login-service failure used only by --no-tap --popup-banners.
@MainActor
private final class PopupBannerLoginItemService: LoginItemService {
    var status: LoginItemStatus { .requiresApproval }
    private struct Failure: Error, CustomStringConvertible {
        var description: String { "Fixture login registration failed. Try again after allowing TypeStats in Login Items." }
    }
    func register() throws { throw Failure() }
    func unregister() throws { throw Failure() }
}

/// Owns the store, counter, event tap and test seams for the running app.
@MainActor
@Observable
final class AppController {
    static var shared: AppController?

    let counter: KeyCounter
    let tap: KeyTap
    let loginItem: LoginItem
    let pause: PauseControl
    let update: AppUpdate
    @ObservationIgnored private var updatesWindow: NSWindow?
    let testMode: Bool
    /// Show "Key capture off (test mode)" in the popup (test mode without `--no-test-banner`).
    let showsTestBanner: Bool
    /// Test seam (`--measure-views`): the period the popup should switch to.
    var periodRequest: StatsPeriod?
    @ObservationIgnored private let pipeline: KeyPressPipeline
    @ObservationIgnored let options: LaunchOptions
    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var sigterm: DispatchSourceSignal?

    /// Batched writes: pending presses are saved this often and on quit.
    static let flushInterval: Duration = .seconds(3)

    init(options: LaunchOptions, dataDir: URL) {
        self.options = options
        update = AppUpdate(currentVersion: options.noTap ? options.updateVersion ?? Self.bundleVersion : Self.bundleVersion,
                           service: HomebrewUpdateService(options: options))
        testMode = options.noTap
        showsTestBanner = options.noTap && !options.noTestBanner
        // Test mode never touches the real login item.
        let loginService: any LoginItemService
        if options.noTap {
            if options.popupBanners { loginService = PopupBannerLoginItemService() }
            else { loginService = InMemoryLoginItemService() }
        } else { loginService = MainLoginItemService() }
        loginItem = LoginItem(service: loginService)
        if options.noTap && options.popupBanners { loginItem.set(true) }
        let at = options.at
        do {
            counter = try KeyCounter(store: try CountStore(directory: dataDir), now: { at ?? Date() })
        } catch {
            FileHandle.standardError.write(Data("TypeStats: cannot open store at \(dataDir.path): \(error)\n".utf8))
            exit(1)
        }
        let pause = PauseControl(directory: dataDir, now: { at ?? Date() })
        pause.apply(pause: options.pause, resume: options.resume)
        self.pause = pause
        pipeline = KeyPressPipeline(
            counter: counter, frontmostApp: AppController.frontmostApp, appAtPoint: AppController.app(at:),
            isPaused: { pause.isPaused })
        tap = KeyTap(pipeline: pipeline)

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { AppController.shared?.didFinishLaunching() } })
        observers.append(center.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { AppController.shared?.flush() } })
    }

    private func didFinishLaunching() {
        // SIGTERM (kill) quits through the normal path so pending counts are saved.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        source.resume()
        sigterm = source

        if let dir = options.shareCards {
            do {
                for name in try ShareRender.writeAll(to: dir) { print("wrote\t\(name)") }
                fflush(stdout)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("TypeStats: share render failed: \(error)\n".utf8))
                exit(1)
            }
        }
        applyExclusionSeams()
        runSimulation()
        if options.shareCopy != nil || options.shareSave != nil { runShareSeam() }
        if !options.noTap { tap.start() }
        if options.noTap && options.darkSnapshot { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if options.showWindow { showWindow() }
        if options.measureViews { measureViews() }
        if options.simulateSelfClicks > 0 { simulateSelfClicks(options.simulateSelfClicks) }
        if options.noTap && (options.updateCask != nil || options.updatesWindow || options.performUpdate) {
            Task { @MainActor in
                await update.check()
                if options.updatesWindow { showUpdates() }
                if options.performUpdate { await update.update() }
                finishStartupEvidence()
            }
        } else { finishStartupEvidence() }
        if let seconds = options.resumeAfter {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.pause.resume()
            }
        }
        if options.sharePanel {
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? ShareActions.savePanel(self, self.options.view)
            }
        }

        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: AppController.flushInterval)
                guard let self else { return }
                if !self.options.holdFlush { self.flush() }
                self.counter.rolloverIfNeeded()
                self.pause.refresh()
                if !self.options.noTap && !self.tap.isRunning { self.tap.start() }
            }
        }
    }

    static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private func finishStartupEvidence() {
        if let url = options.snapshot { writeSnapshot(to: url) }
        if let url = options.readyFile {
            do { try Data("ready\n".utf8).write(to: url) }
            catch {
                FileHandle.standardError.write(Data("TypeStats: ready file write failed: \(error)\n".utf8))
            }
        }
    }

    func showUpdates() {
        if updatesWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: AppUpdatesView(update: update)))
            window.title = "App Updates"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            updatesWindow = window
        }
        updatesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !options.noTap { Task { await update.checkIfNeeded() } }
    }

    /// Test seam (`--share-copy`, `--share-save`): the Share actions without the menu, for
    /// the period in `--view`. Copy goes only to the pasteboard named by `--pasteboard`.
    private func runShareSeam() {
        let summary = ShareActions.summary(self, options.view)
        do {
            if let kind = options.shareCopy {
                guard let name = options.pasteboard else {
                    FileHandle.standardError.write(Data("TypeStats: --share-copy needs --pasteboard <name>\n".utf8))
                    exit(2)
                }
                let board = NSPasteboard(name: NSPasteboard.Name(name))
                if kind == "image" { try ShareActions.copyImage(summary, to: board) } else { try ShareActions.copyText(summary, to: board) }
            }
            if let url = options.shareSave { try ShareActions.savePNG(summary, to: url) }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("TypeStats: share failed: \(error)\n".utf8))
            exit(1)
        }
    }

    /// Stops counting `app`; counts already saved for it stay. Used by the popup's Excluded apps page.
    func exclude(_ app: AppIdentity) {
        do { try counter.exclude(app) } catch {
            FileHandle.standardError.write(Data("TypeStats: cannot exclude \(app.bundleID): \(error)\n".utf8))
        }
    }

    /// Counts `bundleID` again.
    func include(bundleID: String) {
        do { try counter.include(bundleID: bundleID) } catch {
            FileHandle.standardError.write(Data("TypeStats: cannot remove exclusion \(bundleID): \(error)\n".utf8))
        }
    }

    /// Test seams `--exclude` and `--include`: the popup's own calls, before events are simulated.
    private func applyExclusionSeams() {
        for bundleID in options.exclude { exclude(AppController.identity(forBundleID: bundleID)) }
        for bundleID in options.include { include(bundleID: bundleID) }
    }

    /// Regular running apps (the ones with a Dock icon), by name, one per bundle id.
    static func runningApps() -> [AppIdentity] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map(identity(of:))
            .filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func flush() {
        do { try counter.flush() } catch {
            FileHandle.standardError.write(Data("TypeStats: save failed: \(error)\n".utf8))
        }
    }

    /// Test seams: feed synthetic key and mouse events through the same pipeline as the event tap.
    private func runSimulation() {
        for (bundleID, n) in options.simulateKeys {
            let app = AppController.identity(forBundleID: bundleID)
            for _ in 0..<n {
                if let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                    pipeline.handle(type: .keyDown, event: e, app: app)
                }
            }
        }
        if let (bundleID, text) = options.simulateText {
            let app = AppController.identity(forBundleID: bundleID)
            for ch in text {
                guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else { continue }
                let units = Array(String(ch).utf16)
                e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                pipeline.handle(type: .keyDown, event: e, app: app)
            }
        }
        // Clicks cycle through left, right and other buttons.
        let buttons: [(CGEventType, CGMouseButton)] = [(.leftMouseDown, .left), (.rightMouseDown, .right), (.otherMouseDown, .center)]
        for (bundleID, n) in options.simulateClicks {
            let app = AppController.identity(forBundleID: bundleID)
            for i in 0..<n {
                let (type, button) = buttons[i % buttons.count]
                if let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero, mouseButton: button) {
                    pipeline.handle(type: type, event: e, app: app)
                }
            }
        }
        simulateTyping(options.simulateTyping)
        let simulated = !options.simulateKeys.isEmpty || options.simulateText != nil || !options.simulateClicks.isEmpty
            || !options.simulateTyping.isEmpty
        if simulated && !options.holdFlush { flush() }
    }

    /// Pause between `--simulate-typing` segments: longer than a burst gap, so it is idle time.
    static let simulatedPause: Double = 60

    /// Test seam: timed key presses. Each segment spreads its presses evenly over its
    /// seconds; segments are separated by `simulatedPause`. The presses carry event
    /// timestamps (as real key events do), ending now, and go through the same pipeline.
    private func simulateTyping(_ segments: [LaunchOptions.TypingSegment]) {
        guard !segments.isEmpty else { return }
        let span = segments.reduce(0) { $0 + $1.seconds } + Double(segments.count - 1) * Self.simulatedPause
        var t = Double(EventClock.nowNanos()) / 1e9 - span
        for (index, segment) in segments.enumerated() {
            if index > 0 { t += Self.simulatedPause }
            let app = AppController.identity(forBundleID: segment.bundleID)
            let step = segment.seconds / Double(segment.keys)
            for i in 0..<segment.keys {
                guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else { continue }
                e.timestamp = UInt64(((t + Double(i) * step) * 1e9).rounded())
                // No modifiers: a new event can pick up keys held on the Mac right now, and a
                // held Command or Control would turn these presses into shortcuts.
                e.flags = []
                pipeline.handle(type: .keyDown, event: e, app: app)
            }
            t += segment.seconds
        }
    }

    /// Test seam: `n` left clicks at the centre of a TypeStats window, with no app given,
    /// so the real under-pointer lookup attributes them. The window is ordered front
    /// without activating TypeStats, so the frontmost-app fallback would pick another app.
    private func simulateSelfClicks(_ n: Int) {
        let w = window ?? makeWindow()
        if window == nil { w.orderFrontRegardless(); window = w }
        Task { @MainActor [weak self] in
            // Wait until the window server shows the window (up to 5 s).
            for _ in 0..<100 where !w.occlusionState.contains(.visible) {
                try? await Task.sleep(for: .milliseconds(50))
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard let self else { return }
            let screenHeight = NSScreen.screens.first?.frame.height ?? 0
            let center = CGPoint(x: w.frame.midX, y: screenHeight - w.frame.midY)
            for _ in 0..<n {
                if let e = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left) {
                    self.pipeline.handle(type: .leftMouseDown, event: e)
                }
            }
            if !self.options.holdFlush { self.flush() }
        }
    }

    /// Height of the screen area the popup can use; `--screen-height` replaces the real one.
    var visibleScreenHeight: CGFloat {
        options.screenHeight.map { CGFloat($0) } ?? NSScreen.main?.visibleFrame.height ?? .greatestFiniteMagnitude
    }

    var showsPermissionBanner: Bool {
        testMode ? options.popupBanners : !tap.permissionGranted || !tap.isRunning
    }

    /// Popup contents in a normal, capturable window (`--show-window`).
    private func showWindow() {
        let w = window ?? makeWindow()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w
    }

    private func makeWindow() -> NSWindow {
        // Follow the menu bar popup's shared preferred size and screen-capped detail viewport.
        let host = NSHostingController(rootView: PopupView(controller: self, period: options.view, showExcluded: options.excludedPage))
        host.sizingOptions = [.preferredContentSize]
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable]
        w.title = "TypeStats"
        w.isReleasedWhenClosed = false
        w.center()
        return w
    }

    /// Test seam (`--measure-views`): a window that follows the popup's content size (as the
    /// menu bar window does), switched through every period while counts change. Prints
    /// `label<TAB>fitting w<TAB>h<TAB>window x<TAB>y<TAB>w<TAB>h` per step, then quits.
    private func measureViews() {
        let host = NSHostingController(rootView: PopupView(controller: self, period: .today))
        host.sizingOptions = [.preferredContentSize]
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.borderless]
        w.isReleasedWhenClosed = false
        w.setFrameTopLeftPoint(NSPoint(x: 200, y: 900))
        w.orderFrontRegardless()
        window = w
        Task { @MainActor [weak self] in
            guard let self else { return }
            @MainActor func report(_ label: String) async {
                try? await Task.sleep(for: .milliseconds(400))
                let fit = host.view.fittingSize
                let bounds = (CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(w.windowNumber)) as? [[String: Any]])?
                    .first?[kCGWindowBounds as String] as? [String: Double] ?? [:]
                let f = ["X", "Y", "Width", "Height"].map { String(Int((bounds[$0] ?? -1).rounded())) }
                print(([label, String(Int(fit.width)), String(Int(fit.height))] + f).joined(separator: "\t"))
            }
            await report("start")
            var extra = 0
            // Every directed pair, including switches back from the weekly heatmap.
            for period in [StatsPeriod.week, .today, .month, .week, .month, .today] {
                self.periodRequest = period
                await report("switch-\(period.rawValue)")
                // Live counts arrive (a new app each time, so the app list grows past its limit).
                extra += 1
                for app in 0..<2 {
                    for _ in 0..<(40 * extra) {
                        self.counter.record(AppController.identity(forBundleID: "local.typestats.measure.\(extra).\(app)"))
                    }
                }
                await report("count-\(period.rawValue)")
            }
            fflush(stdout)
            exit(0)
        }
    }

    /// Renders the popup or App Updates into a PNG; test options are in docs/run.md.
    private func writeSnapshot(to url: URL) {
        let view = Group {
            if options.updatesWindow { AppUpdatesView(update: update) }
            else { PopupView(controller: self, period: options.view, showExcluded: options.excludedPage) }
        }
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, options.noTap && options.darkSnapshot ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("TypeStats: snapshot failed\n".utf8))
            return
        }
        do { try png.write(to: url) } catch {
            FileHandle.standardError.write(Data("TypeStats: snapshot write failed: \(error)\n".utf8))
        }
    }

    static func frontmostApp() -> AppIdentity? {
        NSWorkspace.shared.frontmostApplication.map(identity(of:))
    }

    /// The app owning the topmost window that takes a click at `point` (global display
    /// coordinates, origin top-left), or nil (then the click goes to the frontmost app).
    /// The point is used only for this lookup and never stored.
    ///
    /// First asks AppKit which window a mouse-down there would hit (about a microsecond,
    /// and it skips click-through windows such as the Dock's invisible full-screen
    /// window). If that window has no app owner (the menu bar belongs to the window
    /// server), falls back to a layer-aware scan of on-screen windows.
    static func app(at point: CGPoint) -> AppIdentity? {
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let number = NSWindow.windowNumber(at: NSPoint(x: point.x, y: screenHeight - point.y), belowWindowWithWindowNumber: 0)
        if number > 0,
           let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(number)) as? [[String: Any]])?.first,
           let pid = WindowHitTest.Window(info: info)?.pid,
           let app = NSRunningApplication(processIdentifier: pid) {
            return identity(of: app)
        }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let pid = WindowHitTest.ownerPID(at: point, windows: list.compactMap(WindowHitTest.Window.init(info:))),
              let app = NSRunningApplication(processIdentifier: pid)
        else { return nil }
        return identity(of: app)
    }

    static func identity(of app: NSRunningApplication) -> AppIdentity {
        let name = app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)"
        return AppIdentity(bundleID: app.bundleIdentifier ?? "process.\(name)", name: name)
    }

    static func identity(forBundleID bundleID: String) -> AppIdentity {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            return AppIdentity(bundleID: bundleID, name: name.replacingOccurrences(of: ".app", with: ""))
        }
        // Test seam: "sample.Name" shows as "Name" (the share prototype's sample apps).
        if bundleID.hasPrefix("sample.") {
            return AppIdentity(bundleID: bundleID, name: String(bundleID.dropFirst("sample.".count)).replacingOccurrences(of: "_", with: " "))
        }
        return AppIdentity(bundleID: bundleID, name: bundleID)
    }
}
