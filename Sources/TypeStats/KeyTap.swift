import AppKit
import CoreGraphics
import TypeStatsCore

/// Listen-only CGEvent tap for keyDown and mouse-down events (needs Input Monitoring
/// permission for keys; clicks need no extra permission). It never modifies or blocks
/// events, and passes each one to the pipeline, which only counts it.
@MainActor
@Observable
final class KeyTap {
    private(set) var isRunning = false
    private(set) var permissionGranted = CGPreflightListenEventAccess()

    @ObservationIgnored private let pipeline: KeyPressPipeline
    @ObservationIgnored private var port: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var requested = false

    @ObservationIgnored nonisolated(unsafe) private static var current: KeyTap?

    init(pipeline: KeyPressPipeline) {
        self.pipeline = pipeline
    }

    func start() {
        guard port == nil else { return }
        permissionGranted = CGPreflightListenEventAccess()
        if !permissionGranted {
            // Shows the system prompt once and adds TypeStats to the Input Monitoring list.
            if !requested { requested = true; _ = CGRequestListenEventAccess() }
            return
        }
        let mask = ([.keyDown] + KeyPressPipeline.clickTypes).reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: KeyTap.callback, userInfo: nil)
        else { return }
        KeyTap.current = self
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        // Main run loop, so the callback runs on the main thread.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        isRunning = true
    }

    private func handle(type: CGEventType, isAutorepeat: Bool, location: CGPoint?, time: TimeInterval?, kind: TypingKeyKind) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
        default:
            pipeline.handle(type: type, isAutorepeat: isAutorepeat, location: location, time: time, kind: kind)
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, _ in
        // Discard key identity at this boundary. Only coarse kind and timing leave
        // the key event; Unicode text is never read.
        let isAutorepeat = type == .keyDown && KeyPressPipeline.isAutorepeat(event)
        let kind = type == .keyDown ? KeyPressPipeline.kind(of: event) : .other
        let time = type == .keyDown ? KeyPressPipeline.time(of: event) : nil
        let location = KeyPressPipeline.clickTypes.contains(type) ? event.location : nil
        MainActor.assumeIsolated {
            KeyTap.current?.handle(type: type, isAutorepeat: isAutorepeat, location: location, time: time, kind: kind)
        }
        return Unmanaged.passUnretained(event)
    }

    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
