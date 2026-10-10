import SwiftUI
import TypeStatsCore

/// The same app-hour projection, palette and named legend in the popup and export.
struct WeeklyActivityView: View {
    let activity: WeeklyActivity
    var scale: CGFloat = 1
    var interactive = true
    static let height: CGFloat = 190

    private struct Slot: Hashable { let day: String; let hour: Int }
    @State private var hovered: Slot?
    @FocusState private var focused: Slot?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    private var dark: Bool { scheme == .dark }
    private func colour(bundleID: String?, step: Int) -> Color {
        Color(AppPalette.heatmap(bundleID: bundleID, step: step, dark: dark, increasedContrast: contrast == .increased))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            Text("When you typed").font(.system(size: 12 * scale, weight: .semibold))
                .accessibilityIdentifier("weeklyActivity")
            Text(activity.peakText).font(.system(size: 10 * scale)).foregroundStyle(.secondary)
            VStack(spacing: 2 * scale) {
                ForEach(activity.rows) { row in
                    HStack(spacing: 2 * scale) {
                        Text(row.label).font(.system(size: 9 * scale))
                            .foregroundStyle(.secondary)
                            .frame(width: 42 * scale, height: 10 * scale, alignment: .leading)
                        ForEach(0..<24, id: \.self) { hour in
                            let detail = row.detail(at: hour)
                            let slot = Slot(day: row.day, hour: hour)
                            cell(detail)
                                .frame(maxWidth: .infinity)
                                .frame(height: 10 * scale)
                                .contentShape(Rectangle())
                                .focusable(interactive)
                                .focused($focused, equals: slot)
                                .onHover { inside in
                                    guard interactive else { return }
                                    if inside { hovered = slot } else if hovered == slot { hovered = nil }
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(detail.text)
                                .accessibilityIdentifier("hour-\(row.day)-\(hour)")
                        }
                    }
                }
            }
            HStack(spacing: 2 * scale) {
                Color.clear.frame(width: 42 * scale, height: 10 * scale)
                ForEach(0..<4, id: \.self) { index in
                    Text(PopupView.hourLabel(index * 6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.system(size: 9 * scale)).foregroundStyle(.secondary)
            legend
            HStack(spacing: 4 * scale) {
                Text("0")
                swatch(colour(bundleID: nil, step: 0))
                Text("Fewer keys")
                ForEach(1..<5, id: \.self) { step in swatch(colour(bundleID: nil, step: step)) }
                Text("More")
                Spacer(minLength: 4 * scale)
                RoundedRectangle(cornerRadius: 1.5 * scale)
                    .strokeBorder(.secondary, lineWidth: 0.5 * scale)
                    .frame(width: 9 * scale, height: 9 * scale)
                Text("Not yet")
            }
            .font(.system(size: 9 * scale)).foregroundStyle(.secondary)
            Text(activity.coverageText ?? " ")
                .font(.system(size: 10 * scale)).foregroundStyle(.secondary)
        }
        .frame(height: Self.height * scale, alignment: .top)
        .overlay(alignment: .bottom) {
            if interactive, let slot = hovered ?? focused,
               let row = activity.rows.first(where: { $0.day == slot.day }) {
                Text(row.detail(at: slot.hour).text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .padding(12)
                    .frame(maxWidth: 288, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(PorcelainTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary, lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("hourDetail")
            }
        }
        .zIndex(1)
        .onChange(of: activity.rows.map(\.day)) { _, _ in hovered = nil; focused = nil }
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2 * scale).fill(color)
            .frame(width: 9 * scale, height: 9 * scale)
    }

    @ViewBuilder private func cell(_ detail: WeeklyActivity.HourDetail) -> some View {
        let shape = RoundedRectangle(cornerRadius: 1.5 * scale)
        switch detail.cell {
        case .count(let keys):
            let step = WeeklyActivity.shadeStep(keys: keys, peak: activity.peakKeys)
            let soleLeader = detail.leaders.count == 1 ? detail.leaders.first?.app.bundleID : nil
            let rgb = AppPalette.heatmap(bundleID: soleLeader, step: step, dark: dark, increasedContrast: contrast == .increased)
            shape.fill(Color(rgb))
                .overlay {
                    if keys > 0 && (differentiate || detail.leaders.count > 1) {
                        Text(detail.leaders.count > 1 ? "=" : soleLeader.map { AppPalette.family(bundleID: $0).marker } ?? "?")
                            .font(.system(size: 7 * scale, weight: .bold))
                            .foregroundStyle(rgb.luminance > 0.18 ? Color.black : Color.white)
                    }
                }
                .overlay {
                    if contrast == .increased { shape.strokeBorder(.primary, lineWidth: 0.5 * scale) }
                }
        case .future:
            shape.strokeBorder(.secondary, lineWidth: (contrast == .increased ? 1 : 0.5) * scale)
        }
    }

    /// Bounded colour-family legend. Monochrome/unknown identities share a neutral family;
    /// full names remain in cell details. Export has the same named key and never uses hover.
    private var legend: some View {
        let grouped = Dictionary(grouping: activity.leadingApps) { AppPalette.family(bundleID: $0.bundleID) }
        let families = AppPalette.Family.allCases.filter { grouped[$0] != nil }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4 * scale), count: 4),
                         alignment: .leading, spacing: 2 * scale) {
            ForEach(families) { family in
                let names = (grouped[family] ?? []).map(\.name)
                HStack(spacing: 4 * scale) {
                    swatch(Color(family.tag))
                    Text((differentiate ? family.marker + " " : "") + legendName(family, names: names))
                        .lineLimit(1)
                }
                .font(.system(size: 9 * scale))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(names.joined(separator: ", "))
                .accessibilityLabel(names.joined(separator: ", "))
            }
        }
        .frame(height: 24 * scale, alignment: .top)
    }

    private func legendName(_ family: AppPalette.Family, names: [String]) -> String {
        if names == ["Visual Studio Code"] { return "VS Code" }
        if let name = names.first, names.count == 1, name.count <= 12 {
            return name == "Google Chrome" ? "Chrome" : name
        }
        switch family {
        case .claude: return "Claude"
        case .codex: return "OpenAI apps"
        case .chatgpt: return "ChatGPT"
        case .teams: return "Teams"
        case .discord: return "Discord"
        case .editor: return "Editors"
        case .terminal: return "Terminals"
        case .other: return names == ["Google Chrome"] ? "Chrome" : "Other apps"
        }
    }
}
