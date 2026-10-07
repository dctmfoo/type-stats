import Foundation
@testable import TypeStatsCore

/// Fresh on-disk store directory under .po/tmp/smoke-fixtures/tests/ in this project.
func makeTestDirectory(_ name: String = #function) throws -> URL {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let safe = name.filter { $0.isLetter || $0.isNumber }
    let dir = root.appendingPathComponent(".po/tmp/smoke-fixtures/tests/\(safe)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// A clock tests can move, in a fixed time zone so day bucketing is deterministic.
final class TestClock: @unchecked Sendable {
    var date: Date
    let calendar: Calendar

    init(_ iso: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = cal
        date = TestClock.parse(iso, cal)
    }

    func set(_ iso: String) { date = TestClock.parse(iso, calendar) }

    private static func parse(_ iso: String, _ cal: Calendar) -> Date {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: iso)!
    }
}

let terminal = AppIdentity(bundleID: "com.apple.Terminal", name: "Terminal")
let chatgpt = AppIdentity(bundleID: "com.openai.chat", name: "ChatGPT")
let claude = AppIdentity(bundleID: "com.anthropic.claudefordesktop", name: "Claude")
