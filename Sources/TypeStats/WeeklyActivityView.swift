import SwiftUI
import TypeStatsCore

/// Shared by the popup and exported image, including the palette and legend.
struct WeeklyActivityView: View {
    let activity: WeeklyActivity
    var scale: CGFloat = 1
    static let height: CGFloat = 170

    // Zero is neutral grey. Every positive step is blue, with a bright cyan peak.
    static let shades: [Color] = [
        Color(red: 0.16, green: 0.18, blue: 0.22),
        Color(red: 0.15, green: 0.32, blue: 0.51),
        Color(red: 0.16, green: 0.46, blue: 0.72),
        Color(red: 0.15, green: 0.59, blue: 0.88),
        Color(red: 0.22, green: 0.73, blue: 1.00)
    ]

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
                RoundedRectangle(cornerRadius: 2 * scale).fill(Self.shades[0])
                    .frame(width: 9 * scale, height: 9 * scale)
                Text("Less")
                ForEach(1..<5, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 2 * scale).fill(Self.shades[step])
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
            shape.fill(Self.shades[WeeklyActivity.shadeStep(keys: keys, peak: activity.peakKeys)])
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
