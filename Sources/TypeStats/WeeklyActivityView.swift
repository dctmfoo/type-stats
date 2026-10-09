import SwiftUI
import TypeStatsCore

/// Shared by the popup and exported image, including the palette and legend.
struct WeeklyActivityView: View {
    let activity: WeeklyActivity
    var scale: CGFloat = 1
    static let height: CGFloat = 170

    @Environment(\.colorScheme) private var scheme

    // Zero is neutral grey and every positive step is blue. Dark mode brightens toward the
    // peak; light mode darkens toward it, so the busiest hour always stands out most.
    static let darkShades: [Color] = [
        Color(red: 0.16, green: 0.18, blue: 0.22),
        Color(red: 0.15, green: 0.32, blue: 0.51),
        Color(red: 0.16, green: 0.46, blue: 0.72),
        Color(red: 0.15, green: 0.59, blue: 0.88),
        Color(red: 0.22, green: 0.73, blue: 1.00)
    ]
    static let lightShades: [Color] = [
        Color(red: 0.86, green: 0.87, blue: 0.90),
        Color(red: 0.74, green: 0.85, blue: 0.97),
        Color(red: 0.50, green: 0.72, blue: 0.93),
        Color(red: 0.25, green: 0.52, blue: 0.86),
        Color(red: 0.08, green: 0.33, blue: 0.68)
    ]

    private var shades: [Color] { scheme == .dark ? Self.darkShades : Self.lightShades }

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            Text("When you typed").font(.system(size: 12 * scale, weight: .semibold))
            Text(activity.peakText).font(.system(size: 10 * scale)).foregroundStyle(.secondary)
            VStack(spacing: 2 * scale) {
                ForEach(activity.rows) { row in
                    HStack(spacing: 2 * scale) {
                        Text(row.label).font(.system(size: 9 * scale))
                            .foregroundStyle(.secondary)
                            .frame(width: 42 * scale, height: 10 * scale, alignment: .leading)
                        ForEach(0..<24, id: \.self) { hour in
                            cell(row.cells[hour])
                                .frame(maxWidth: .infinity)
                                .frame(height: 10 * scale)
                                .accessibilityLabel("\(row.label), \(WeeklyActivity.hourRange(hour))")
                                .accessibilityValue(value(row.cells[hour]))
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
            HStack(spacing: 4 * scale) {
                Text("0")
                RoundedRectangle(cornerRadius: 2 * scale).fill(shades[0])
                    .frame(width: 9 * scale, height: 9 * scale)
                Text("Less")
                ForEach(1..<5, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 2 * scale).fill(shades[step])
                        .frame(width: 9 * scale, height: 9 * scale)
                }
                Text("More")
                Spacer(minLength: 4 * scale)
                cell(.future).frame(width: 9 * scale, height: 9 * scale)
                Text("Not yet")
            }
            .font(.system(size: 9 * scale)).foregroundStyle(.secondary)
            Text(activity.coverageText ?? " ")
                .font(.system(size: 10 * scale)).foregroundStyle(.secondary)
        }
        .frame(height: Self.height * scale, alignment: .top)
        .accessibilityIdentifier("weeklyActivity")
    }

    @ViewBuilder private func cell(_ cell: WeeklyActivity.Cell) -> some View {
        let shape = RoundedRectangle(cornerRadius: 1.5 * scale)
        switch cell {
        case .count(let keys):
            shape.fill(shades[WeeklyActivity.shadeStep(keys: keys, peak: activity.peakKeys)])
        case .future:
            shape.strokeBorder(.secondary.opacity(0.45), lineWidth: 0.5 * scale)
        }
    }

    private func value(_ cell: WeeklyActivity.Cell) -> String {
        switch cell {
        case .count(let keys): "\(ShareSummary.number(keys)) keys"
        case .future: "Not yet counted"
        }
    }
}
