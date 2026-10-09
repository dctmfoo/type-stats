import AppKit
import Charts
import SwiftUI
import TypeStatsCore

// Share cards (tasks 05 and 06): the image card A and its variants, drawn from a
// ShareSummary. The real popup feeds them its own counts; the fixed samples below are
// only for the `--share-cards` prototype path and never read the store.

typealias ShareSample = ShareSummary

extension ShareSummary {
    /// A made-up working day: 7,120 keys, 665 clicks, 58 wpm, busy 8a-6p.
    static let today: ShareSummary = {
        let keys = [0, 0, 0, 0, 0, 0, 0, 0, 420, 1310, 1180, 640, 210, 380, 950, 1120, 730, 180]
        let clicks = [0, 0, 0, 0, 0, 0, 0, 0, 40, 120, 110, 60, 20, 35, 90, 105, 70, 15]
        let buckets = (0..<24).map { h in
            Bucket(label: "\(h)", keys: h < keys.count ? keys[h] : 0, clicks: h < clicks.count ? clicks[h] : 0, index: h)
        }
        return ShareSummary(
            title: "Today", dateText: "Monday 5 October",
            keys: buckets.reduce(0) { $0 + $1.keys }, clicks: buckets.reduce(0) { $0 + $1.clicks }, wpm: 58,
            buckets: buckets,
            apps: [.init(name: "Xcode", keys: 3840), .init(name: "Mail", keys: 1215),
                   .init(name: "Google Chrome", keys: 960), .init(name: "Notes", keys: 702),
                   .init(name: "Terminal", keys: 85)],
            isDaily: false)
    }()

    static let week: ShareSummary = {
        let keys = [6120, 7340, 5210, 9080, 8120, 4300, 7120]
        let clicks = [610, 702, 488, 950, 801, 390, 665]
        let names = ["Tue", "Wed", "Thu", "Fri", "Sat", "Sun", "Mon"]
        let buckets = (0..<7).map { Bucket(label: names[$0], keys: keys[$0], clicks: clicks[$0], index: $0) }
        return ShareSummary(
            title: "Last 7 days", dateText: "29 Sep – 5 Oct",
            keys: keys.reduce(0, +), clicks: clicks.reduce(0, +), wpm: 56,
            buckets: buckets,
            apps: [.init(name: "Xcode", keys: 21450), .init(name: "Mail", keys: 7020),
                   .init(name: "Google Chrome", keys: 6310), .init(name: "Notes", keys: 4880),
                   .init(name: "Terminal", keys: 590)],
            isDaily: true)
    }()
}

enum SharePalette {
    static let background = LinearGradient(
        colors: [Color(red: 0.10, green: 0.10, blue: 0.13), Color(red: 0.05, green: 0.05, blue: 0.07)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let keys = Color(red: 0.25, green: 0.55, blue: 1.0)
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.58)
}

/// The three big numbers in one row (variant A). Starts at `size` and steps down until the
/// row fits, so a six-digit total shrinks the whole row evenly instead of squeezing a number
/// against its unit or the next stat.
private struct BigNumbers: View {
    let sample: ShareSample
    let size: CGFloat

    private var sizes: [CGFloat] { [1, 0.88, 0.76, 0.66, 0.56, 0.48].map { size * $0 } }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(sizes, id: \.self) { row($0) }
        }
    }

    private func row(_ size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.5) {
            stat(ShareSummary.number(sample.keys), "keys", size)
            stat(ShareSummary.number(sample.clicks), "clicks", size)
            stat(sample.wpm.map { "\($0)" } ?? "–", "wpm", size)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func stat(_ value: String, _ unit: String, _ size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.2) {
            Text(value).font(.system(size: size, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(SharePalette.primary)
            Text(unit).font(.system(size: size * 0.36, weight: .medium, design: .rounded))
                .foregroundStyle(SharePalette.secondary)
        }
    }
}

private struct Footer: View {
    let size: CGFloat
    var body: some View {
        HStack(spacing: size * 0.35) {
            Image(systemName: "keyboard")
            Text("TypeStats")
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .foregroundStyle(SharePalette.secondary)
    }
}

private struct ActivityChart: View {
    let sample: ShareSample
    let axisSize: CGFloat

    /// Which buckets get an x label: every hour mark of today, every day of a week, and
    /// every 7th day ending with the last day for a month.
    private var labelIndices: [Int] {
        let n = sample.buckets.count
        if !sample.isDaily { return [0, 6, 12, 18] }
        return n <= 7 ? Array(0..<n) : (0..<n).filter { (n - 1 - $0) % 7 == 0 }
    }

    var body: some View {
        Chart {
            ForEach(sample.buckets) { b in
                BarMark(x: .value("When", b.index), y: .value("Keys", b.keys),
                        width: .fixed(sample.isDaily ? (sample.buckets.count > 7 ? 14 : 56) : 18))
                    .foregroundStyle(SharePalette.keys).cornerRadius(3)
            }
        }
        .chartXScale(domain: -0.5...(Double(sample.buckets.count) - 0.5))
        // A fixed floor keeps the axis readable on a day with nothing counted.
        .chartYScale(domain: 0...max(10, sample.buckets.map(\.keys).max() ?? 0))
        .chartXAxis {
            AxisMarks(values: labelIndices) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(.white.opacity(0.1))
                AxisValueLabel {
                    if let i = value.as(Int.self) {
                        Text(sample.isDaily ? sample.buckets[i].label : PopupHour.label(i))
                            .font(.system(size: axisSize)).foregroundStyle(SharePalette.secondary)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
    }
}

@MainActor enum PopupHour {
    static func label(_ hour: Int) -> String { PopupView.hourLabel(hour) }
}

/// A: 1200x630, the full card.
struct ShareCardA: View {
    static let size = CGSize(width: 1200, height: 630)
    let sample: ShareSample

    var body: some View {
        if let activity = sample.activity {
            weeklyCard(activity)
        } else {
            standardCard
        }
    }

    private var standardCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text(sample.title).font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(SharePalette.primary)
                Spacer()
                Text(sample.dateText).font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(SharePalette.secondary)
            }
            BigNumbers(sample: sample, size: 84)
            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(sample.isDaily ? "By day" : "By hour")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(SharePalette.secondary)
                    ActivityChart(sample: sample, axisSize: 20)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Top apps").font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(SharePalette.secondary)
                    if sample.topThree.isEmpty {
                        Text("Nothing counted yet").font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundStyle(SharePalette.secondary)
                    }
                    ForEach(sample.topThree) { app in
                        HStack {
                            Text(app.name).lineLimit(1)
                            Spacer(minLength: 12)
                            Text(ShareSummary.number(app.keys)).monospacedDigit().foregroundStyle(SharePalette.keys)
                        }
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(SharePalette.primary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 360)
            }
            HStack { Spacer(); Footer(size: 22) }
        }
        .padding(48)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(SharePalette.background)
        .environment(\.colorScheme, .dark)
    }

    private func weeklyCard(_ activity: WeeklyActivity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(sample.title).font(.system(size: 34, weight: .bold, design: .rounded))
                Spacer()
                Text(sample.dateText).font(.system(size: 22)).foregroundStyle(SharePalette.secondary)
            }
            BigNumbers(sample: sample, size: 70).frame(height: 84, alignment: .leading)
            HStack(alignment: .top, spacing: 48) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("By day").font(.system(size: 20, weight: .semibold))
                    ActivityChart(sample: sample, axisSize: 16)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Top apps").font(.system(size: 20, weight: .semibold))
                    ForEach(sample.topThree) { app in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(app.name).lineLimit(1)
                                Spacer()
                                Text(ShareSummary.number(app.keys)).monospacedDigit().foregroundStyle(SharePalette.keys)
                            }
                            GeometryReader { geometry in
                                Capsule().fill(.white.opacity(0.08))
                                Capsule().fill(SharePalette.keys)
                                    .frame(width: geometry.size.width * Double(app.keys) / Double(max(1, sample.topThree.first?.keys ?? 1)))
                            }
                            .frame(height: 7)
                        }
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    }
                    if sample.topThree.isEmpty { Text("Nothing counted yet").foregroundStyle(.secondary) }
                }
                .frame(width: 360)
            }
            .frame(height: 130)
            WeeklyActivityView(activity: activity, scale: 1.2)
            HStack { Spacer(); Footer(size: 20) }
        }
        .foregroundStyle(SharePalette.primary)
        .padding(36)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(SharePalette.background)
        .environment(\.colorScheme, .dark)
    }
}

/// B: 1080x1080, numbers and a sparkline only (no app names).
struct ShareCardB: View {
    static let size = CGSize(width: 1080, height: 1080)
    let sample: ShareSample

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(sample.title).font(.system(size: 52, weight: .bold, design: .rounded))
                Spacer()
                Text(sample.dateText).font(.system(size: 30, weight: .medium, design: .rounded))
                    .foregroundStyle(SharePalette.secondary)
            }
            .foregroundStyle(SharePalette.primary)
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 8) {
                bigStat(ShareSummary.number(sample.keys), "keys")
                bigStat(ShareSummary.number(sample.clicks), "clicks")
                bigStat(sample.wpm.map { "\($0)" } ?? "–", "wpm")
            }
            Spacer(minLength: 24)
            Chart(sample.buckets) { b in
                AreaMark(x: .value("When", b.index), y: .value("Keys", b.keys))
                    .foregroundStyle(LinearGradient(colors: [SharePalette.keys.opacity(0.45), SharePalette.keys.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("When", b.index), y: .value("Keys", b.keys))
                    .foregroundStyle(SharePalette.keys).lineStyle(StrokeStyle(lineWidth: 5))
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .frame(height: 170)
            Spacer(minLength: 28)
            HStack { Spacer(); Footer(size: 28) }
        }
        .padding(72)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(SharePalette.background)
        .environment(\.colorScheme, .dark)
    }

    private func bigStat(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 22) {
            Text(value).font(.system(size: 150, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(SharePalette.primary)
            Text(unit).font(.system(size: 56, weight: .medium, design: .rounded))
                .foregroundStyle(SharePalette.secondary)
        }
        .lineLimit(1).minimumScaleFactor(0.5)
    }
}

/// C: the pasteable text, shown as it would look in a post. 1200x630.
struct ShareCardC: View {
    static let size = CGSize(width: 1200, height: 630)
    let sample: ShareSample

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Copy text").font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(SharePalette.secondary)
            Text(sample.text)
                .font(.system(size: 40, weight: .regular, design: .monospaced))
                .foregroundStyle(SharePalette.primary)
                .padding(36)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
            Spacer(minLength: 0)
        }
        .padding(56)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(SharePalette.background)
        .environment(\.colorScheme, .dark)
    }
}

enum ShareRender {
    /// Pixel scale of the shared card: 2x its logical 1200x630, so 2400x1260.
    static let shareScale: CGFloat = 2

    @MainActor static func png<V: View>(_ view: V, scale: CGFloat = 1) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Writes every variant into `dir` and returns the file names written.
    @MainActor static func writeAll(to dir: URL) throws -> [String] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var written: [String] = []
        func write(_ name: String, _ data: Data?) throws {
            guard let data else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: dir.appendingPathComponent(name))
            written.append(name)
        }
        try write("share-a-full.png", png(ShareCardA(sample: .today)))
        try write("share-a-week.png", png(ShareCardA(sample: .week)))
        try write("share-b-numbers.png", png(ShareCardB(sample: .today)))
        try write("share-c-text.png", png(ShareCardC(sample: .today)))
        try write("share-c-text.txt", Data((ShareSummary.today.text + "\n").utf8))
        return written
    }
}
