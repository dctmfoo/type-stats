import Foundation
import Testing
@testable import TypeStatsCore

@Suite struct ShareSummaryTests {
    private func summary(title: String = "Today", keys: Int = 7120, clicks: Int = 665, wpm: Int? = 58,
                         apps: [(String, Int)] = [("Xcode", 3840), ("Mail", 1215), ("Google Chrome", 960), ("Notes", 702)]) -> ShareSummary {
        ShareSummary(title: title, dateText: "Monday 5 October", keys: keys, clicks: clicks, wpm: wpm,
                     buckets: [], apps: apps.map { .init(name: $0.0, keys: $0.1) }, isDaily: title != "Today")
    }

    @Test func todayLineMatchesTheAgreedFormat() {
        #expect(summary().text == "Today: 7,120 keys · 665 clicks · 58 wpm. Top: Xcode 3,840 · Mail 1,215 · Chrome 960. via TypeStats")
    }

    @Test func periodTitlesLeadTheLine() {
        #expect(summary(title: "Last 7 days").text.hasPrefix("Last 7 days: 7,120 keys"))
        #expect(summary(title: "Last 30 days").text.hasPrefix("Last 30 days: 7,120 keys"))
    }

    @Test func fewerThanThreeAppsListWhatExists() {
        #expect(summary(apps: [("Xcode", 3840), ("Mail", 1215)]).text
            == "Today: 7,120 keys · 665 clicks · 58 wpm. Top: Xcode 3,840 · Mail 1,215. via TypeStats")
        #expect(summary(apps: [("Xcode", 3840)]).text.contains("Top: Xcode 3,840. via TypeStats"))
    }

    @Test func zeroDataIsStillAValidLine() {
        let line = summary(keys: 0, clicks: 0, wpm: nil, apps: []).text
        #expect(line == "Today: 0 keys · 0 clicks. via TypeStats")
    }

    @Test func largeNumbersUseThousandsCommasWhateverTheLocale() {
        #expect(ShareSummary.number(1_234_567) == "1,234,567")
        #expect(ShareSummary.number(999) == "999")
        #expect(ShareSummary.number(0) == "0")
    }

    @Test func fileNameHasPeriodAndLocalDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let date = cal.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 1))!
        #expect(ShareSummary.fileName(period: .today, date: date, calendar: cal) == "TypeStats-Today-2026-10-05.png")
        #expect(ShareSummary.fileName(period: .week, date: date, calendar: cal) == "TypeStats-7-days-2026-10-05.png")
        #expect(ShareSummary.fileName(period: .month, date: date, calendar: cal) == "TypeStats-30-days-2026-10-05.png")
    }

    @MainActor @Test func builtFromTheRealCountsOfThePeriod() throws {
        let clock = TestClock("2026-10-05 09:30")
        let counter = try KeyCounter(store: try CountStore(directory: try makeTestDirectory()),
                                     calendar: clock.calendar, now: { clock.date })
        clock.set("2026-10-03 22:10")
        for _ in 0..<3 { counter.record(claude) }
        counter.recordClick(claude)
        clock.set("2026-10-05 09:30")
        for _ in 0..<5 { counter.record(terminal) }
        for _ in 0..<2 { counter.recordClick(terminal) }
        try counter.flush()

        let today = ShareSummary.make(period: .today, counter: counter)
        #expect(today.title == "Today" && !today.isDaily)
        #expect(today.keys == 5 && today.clicks == 2)
        #expect(today.buckets.count == 24 && today.buckets[9].keys == 5 && today.buckets[9].clicks == 2)
        #expect(today.apps.map(\.name) == ["Terminal"])
        #expect(today.dateText == "Monday 5 October")

        let week = ShareSummary.make(period: .week, counter: counter)
        #expect(week.title == "Last 7 days" && week.isDaily)
        #expect(week.keys == 8 && week.clicks == 3)
        #expect(week.buckets.count == 7 && week.buckets[6].keys == 5 && week.buckets[4].keys == 3)
        #expect(week.buckets.map(\.label) == ["Tue", "Wed", "Thu", "Fri", "Sat", "Sun", "Mon"])
        #expect(week.apps.map(\.name) == ["Terminal", "Claude"])
        #expect(week.dateText == "29 Sep – 5 Oct")
        #expect(week.text.hasPrefix("Last 7 days: 8 keys · 3 clicks"))

        let month = ShareSummary.make(period: .month, counter: counter)
        #expect(month.title == "Last 30 days" && month.buckets.count == 30 && month.keys == 8)
    }
}
