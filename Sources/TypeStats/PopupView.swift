import Charts
import SwiftUI
import TypeStatsCore

/// Today's or the last 7/30 days' key and click totals, typing speed and top apps, with
/// Swift Charts. Used in the menu bar popup and in the `--show-window` test window.
struct PopupView: View {
    let controller: AppController
    @State var period: StatsPeriod
    @State var showExcluded: Bool
    static let width: CGFloat = 360
    static let topLimit = 8
    /// The chart and app region keeps one size across periods. The week trades part of
    /// its app-list viewport for the heatmap, so period switches never move the popup.
    static let chartHeight: CGFloat = 110
    static let noteHeight: CGFloat = 28
    static let appRowHeight: CGFloat = 28
    static let appListHeight = CGFloat(topLimit) * appRowHeight + 8
    // The week replaces the chart note slot and uses the remaining space above a scrolling list.
    static let weekAppListHeight = appListHeight - WeeklyActivityView.height - 12 + noteHeight + 6
    static let totalFont = Font.system(size: 28, weight: .bold, design: .rounded)
    static let keysColor = Color.accentColor

    init(controller: AppController, period: StatsPeriod, showExcluded: Bool = false) {
        self.controller = controller
        _period = State(initialValue: period)
        _showExcluded = State(initialValue: showExcluded)
    }

    var body: some View {
        let counter = controller.counter
        let activity = period == .week ? try? counter.weeklyActivity() : nil
        let history = period == .today ? nil : try? counter.history(days: period.days)
        let topRows = history.map { counter.markExcluded(Array($0.apps.prefix(Self.topLimit))) } ?? counter.topApps(limit: Self.topLimit)
        content(counter: counter, history: history, topRows: topRows, activity: activity)
            // The Excluded apps page covers the normal contents, which keep their size, so
            // the popup never resizes when the page opens or closes.
            .opacity(showExcluded ? 0 : 1)
            .allowsHitTesting(!showExcluded)
            .overlay {
                if showExcluded {
                    ExcludedAppsView(controller: controller, top: topRows) { showExcluded = false }
                }
            }
            .frame(width: Self.width)
            // A period switch must not animate the layout: no size or position change at all.
            .transaction { $0.animation = nil }
            .onAppear { controller.loginItem.refresh() }
            .task { if !controller.testMode { await controller.update.checkIfNeeded() } }
            .onChange(of: controller.periodRequest) { _, request in
                if let request { period = request }
            }
    }

    private func content(counter: KeyCounter, history: History?, topRows: [AppCount], activity: WeeklyActivity?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PeriodPicker(selection: $period)

            header(history)
            totals(keys: history?.totalKeys ?? counter.total,
                   clicks: history?.totalClicks ?? counter.totalClicks,
                   wpm: history.map(\.wpm) ?? counter.wpm)

            PauseRow(pause: controller.pause)

            statusBanner

            if let history {
                dayChart(history)
                if period == .week {
                    Group {
                        if let activity { WeeklyActivityView(activity: activity) }
                        else { Text("Hourly counts unavailable").font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(height: WeeklyActivityView.height, alignment: .top)
                }
                topApps(topRows, empty: "Nothing counted in the last \(period.days) days.")
            } else {
                hourChart(counter)
                topApps(topRows, empty: "No key presses or clicks counted yet today.")
            }

            Divider()
            footer
        }
        .padding(16)
    }

    // MARK: Header and totals

    @ViewBuilder private func header(_ history: History?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(history == nil ? "Today" : "Last \(period.days) days").font(.headline)
            Spacer()
            Group {
                if let first = history?.days.first.flatMap({ date(of: $0.day) }) {
                    Text("\(first, format: .dateTime.day().month()) – \(controller.counter.currentDate, format: .dateTime.day().month())")
                } else {
                    Text(controller.counter.currentDate, format: .dateTime.weekday(.wide).day().month())
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func totals(keys: Int, clicks: Int, wpm: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(keys, format: .number)
                .font(Self.totalFont).monospacedDigit()
                .accessibilityIdentifier("totalKeys")
            Text("keys").foregroundStyle(.secondary)
            Text(clicks, format: .number)
                .font(Self.totalFont).monospacedDigit()
                .padding(.leading, 10)
                .accessibilityIdentifier("totalClicks")
            Text("clicks").foregroundStyle(.secondary)
            Group {
                if let wpm { Text(wpm, format: .number.precision(.fractionLength(0))) } else { Text("–") }
            }
            .font(Self.totalFont).monospacedDigit()
            .padding(.leading, 10)
            .accessibilityIdentifier("wpm")
            Text("wpm").foregroundStyle(.secondary)
                .help("Estimated net typing speed: characters typed minus deletions, 5 to a word, per minute of steady typing (stretches of 10 seconds or more with no gap of 2 seconds).")
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    // MARK: Charts

    private func sectionTitle(_ title: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Label("keys", systemImage: "keyboard")
                .labelStyle(CompactLabelStyle())
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Today's keys per hour.
    @ViewBuilder private func hourChart(_ counter: KeyCounter) -> some View {
        let hours = (0..<24).map { counter.todayHours[$0] ?? HourCount(hour: $0) }
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("By hour")
            Chart {
                ForEach(hours) { h in
                    BarMark(x: .value("Hour", h.hour), y: .value("Keys", h.keys), width: .fixed(9))
                        .foregroundStyle(Self.keysColor)
                }
            }
            .chartXScale(domain: -0.5...23.5)
            // A fixed floor keeps the axis readable on a day with nothing counted yet.
            .chartYScale(domain: 0...max(10, hours.map(\.keys).max() ?? 0))
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18]) { value in
                    AxisGridLine()
                    AxisValueLabel { if let h = value.as(Int.self) { Text(Self.hourLabel(h)) } }
                }
            }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            .frame(height: Self.chartHeight)
            noteSlot {
                if counter.keysWithoutHour + counter.clicksWithoutHour > 0 {
                    Text("\(counter.keysWithoutHour) keys and \(counter.clicksWithoutHour) clicks today were counted before hourly tracking, so they have no hour.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Keys (bars) per day of the period.
    @ViewBuilder private func dayChart(_ history: History) -> some View {
        let days = history.days.compactMap { d in date(of: d.day).map { (date: $0, total: d) } }
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("By day")
            Chart {
                ForEach(days, id: \.total.day) { d in
                    BarMark(x: .value("Day", d.date, unit: .day), y: .value("Keys", d.total.keys), width: .ratio(0.7))
                        .foregroundStyle(Self.keysColor)
                }
            }
            .chartXAxis {
                if period == .week {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                } else {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            .frame(height: Self.chartHeight)
            if period != .week { noteSlot {} }
        }
    }

    /// The line under a chart: the same height whether or not it has text.
    private func noteSlot<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        // The clear base keeps the slot's height when there is no text (an empty frame collapses).
        ZStack(alignment: .topLeading) {
            Color.clear
            content()
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.noteHeight)
    }

    /// Apps ranked by keys. Bars show keys; each row's label gives keys, clicks and speed.
    @ViewBuilder private func topApps(_ top: [AppCount], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Top apps").font(.subheadline.weight(.semibold))
                Spacer()
                let excludedCount = controller.counter.excludedApps.count
                Button { showExcluded = true } label: {
                    Text(excludedCount == 0 ? "Excluded apps" : "Excluded apps (\(excludedCount))")
                        .font(.caption).foregroundStyle(Color.accentColor)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("excludedApps")
            }
            appList(top, empty: empty)
                .frame(height: period == .week ? Self.weekAppListHeight : Self.appListHeight, alignment: .top)
        }
    }

    @ViewBuilder private func appList(_ top: [AppCount], empty: String) -> some View {
        if period == .week {
            ScrollView { appChart(top, empty: empty) }
        } else {
            appChart(top, empty: empty)
        }
    }

    private func appChart(_ top: [AppCount], empty: String) -> some View {
        Group {
            if top.isEmpty {
                Text(empty)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(top) { row in
                    BarMark(x: .value("Keys", row.count), y: .value("App", row.name))
                        .foregroundStyle(Self.keysColor)
                        .annotation(position: .trailing, alignment: .leading) {
                            HStack(spacing: 6) {
                                Label { Text(row.count, format: .number) } icon: { Image(systemName: "keyboard") }
                                Label { Text(row.clicks, format: .number) } icon: { Image(systemName: "cursorarrow.click") }
                                if row.excluded {
                                    Text("excluded").italic()
                                } else if let wpm = row.wpm {
                                    Text("\(wpm, format: .number.precision(.fractionLength(0))) wpm")
                                }
                            }
                            .labelStyle(CompactLabelStyle())
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            .fixedSize()
                        }
                }
                .chartXAxis(.hidden)
                // Room on the right of the longest bar for its label.
                .chartXScale(domain: 0...(Double(max(top.first?.count ?? 1, 1)) * 2.3))
                // Rows keep their height; fewer apps leave the rest of the list empty.
                .frame(height: CGFloat(top.count) * Self.appRowHeight + 8)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        let login = controller.loginItem
        return VStack(alignment: .leading, spacing: 6) {
            Text("Counts and typing times only. No keys, text or click positions saved.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(controller.update.footerLabel) { controller.showUpdates() }
                .font(.caption)
                .foregroundStyle(controller.update.updateAvailable ? Color.accentColor : Color.secondary)
                .buttonStyle(.plain)
                .accessibilityIdentifier("appVersion")
            HStack {
                Toggle("Start at login", isOn: Binding(get: { login.isOn }, set: { login.set($0) }))
                    .toggleStyle(SmallSwitchStyle())
                    .font(.caption)
                    .accessibilityIdentifier("startAtLogin")
                Spacer()
                ShareButton(controller: controller, period: period).padding(.trailing, 6)
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut("q")
            }
            if login.status == .requiresApproval {
                HStack(spacing: 6) {
                    Text("Allow TypeStats in Login Items to finish.")
                    Button("Open Login Items") { MainLoginItemService.openLoginItemsSettings() }
                        .controlSize(.mini)
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            if let error = login.lastError {
                Text("Could not change login item: \(error)")
                    .font(.caption2).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var statusBanner: some View {
        if controller.testMode {
            if controller.showsTestBanner {
                Label("Key capture off (test mode)", systemImage: "testtube.2")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else if !controller.tap.permissionGranted || !controller.tap.isRunning {
            VStack(alignment: .leading, spacing: 6) {
                Label("Permission needed", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                Text("Turn on TypeStats in System Settings > Privacy & Security > Input Monitoring, then reopen TypeStats.")
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
                Button("Open Input Monitoring Settings") { KeyTap.openInputMonitoringSettings() }
                    .controlSize(.small)
            }
            .padding(10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: Helpers

    private func date(of day: String) -> Date? {
        let f = DateFormatter()
        f.calendar = controller.counter.calendar
        f.timeZone = controller.counter.calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: day)
    }

    static func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: "12a"
        case 12: "12p"
        case 1..<12: "\(hour)a"
        default: "\(hour - 12)p"
        }
    }
}

/// "Today | 7 days | 30 days". Drawn in SwiftUI (not an AppKit segmented control)
/// so `--snapshot` renders it.
private struct PeriodPicker: View {
    @Binding var selection: StatsPeriod

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StatsPeriod.allCases) { period in
                Button { selection = period } label: {
                    Text(period.title)
                        .font(.caption.weight(selection == period ? .semibold : .regular))
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .background {
                            if selection == period {
                                RoundedRectangle(cornerRadius: 6).fill(.background).shadow(radius: 0.5, y: 0.5)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == period ? .isSelected : [])
            }
        }
        .padding(2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("period")
    }
}

/// A small switch drawn in SwiftUI, so `--snapshot` renders it.
private struct SmallSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 6) {
                configuration.label
                Capsule()
                    .fill(configuration.isOn ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 26, height: 15)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white).padding(1.5).shadow(radius: 0.5)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "on" : "off")
    }
}

/// Icon then number, tightly spaced, for the per-app keys and clicks label.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// The pause control under the totals. One fixed height in both states, so the popup never
/// changes size when counting is paused or resumed. Counting: a Pause button that opens a
/// menu (15 minutes, 1 hour, Until I resume). Paused: an orange strip saying when counting
/// resumes, with a one-click Resume. Drawn in SwiftUI so `--snapshot` renders it.
private struct PauseRow: View {
    let pause: PauseControl
    static let height: CGFloat = 34

    var body: some View {
        Group {
            if let status = pause.statusText() {
                HStack(spacing: 8) {
                    Image(systemName: PauseControl.pausedSymbol).foregroundStyle(.orange)
                    Text(status).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityIdentifier("pauseStatus")
                    Spacer(minLength: 4)
                    Button { pause.resume() } label: { pill("Resume", "play.fill") }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("resume")
                }
                .padding(.horizontal, 10)
                .background(.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text("Counting").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("pauseStatus")
                    Spacer(minLength: 4)
                    Button { Self.showMenu(pause) } label: { pill("Pause", "pause.fill") }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pause")
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
    }

    private func pill(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
    }

    /// The native menu, shown at the pointer.
    @MainActor private static func showMenu(_ pause: PauseControl) {
        let menu = NSMenu()
        for choice in PauseChoice.allCases {
            let action = MenuAction { pause.pause(choice) }
            let item = NSMenuItem(title: choice.title, action: #selector(MenuAction.fire), keyEquivalent: "")
            item.target = action
            item.representedObject = action
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
