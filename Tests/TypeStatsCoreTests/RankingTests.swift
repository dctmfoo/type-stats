import Testing
@testable import TypeStatsCore

// Swift Testing suite (the XCTest suites cover the store and pipeline).
@Suite struct RankingTests {
    @Test func highestCountFirstThenNameThenBundleID() {
        let rows = [
            AppCount(bundleID: "b.two", name: "Beta", count: 4),
            AppCount(bundleID: "a.one", name: "alpha", count: 4),
            AppCount(bundleID: "z.big", name: "Zed", count: 9),
            AppCount(bundleID: "c.dup2", name: "Same", count: 1),
            AppCount(bundleID: "c.dup1", name: "Same", count: 1),
        ]
        #expect(rows.rankedByCount().map(\.bundleID) == ["z.big", "a.one", "b.two", "c.dup1", "c.dup2"])
    }

    @Test func equalKeysRankedByClicks() {
        let rows = [
            AppCount(bundleID: "a.few", name: "Alpha", count: 4, clicks: 1),
            AppCount(bundleID: "b.many", name: "Beta", count: 4, clicks: 9),
            AppCount(bundleID: "c.keys", name: "Gamma", count: 5, clicks: 0),
        ]
        #expect(rows.rankedByCount().map(\.bundleID) == ["c.keys", "b.many", "a.few"])
    }

    @Test func emptyListStaysEmpty() {
        #expect([AppCount]().rankedByCount().isEmpty)
    }
}
