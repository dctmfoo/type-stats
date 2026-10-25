import SwiftUI
import TypeStatsCore

/// Porcelain's surfaces and text remain system semantic colours in every appearance.
enum PorcelainTheme {
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.70, green: 0.62, blue: 0.82) : Color(red: 0.45, green: 0.39, blue: 0.56)
    }

    static func magnitude(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.67, green: 0.66, blue: 0.72) : Color(red: 0.46, green: 0.45, blue: 0.51)
    }

    static let surface = Color(nsColor: .controlBackgroundColor)
    static let background = Color(nsColor: .windowBackgroundColor)
}

extension Color {
    init(_ rgb: AppPalette.RGB) { self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1) }
}

/// Unmodified bundle artwork and a separate small colour cue, beside the app name.
struct AppTag: View {
    let bundleID: String
    let name: String
    var size: CGFloat = 16
    var showsColourCue = true
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    var body: some View {
        let rgb = AppPalette.tag(bundleID: bundleID)
        HStack(spacing: 3) {
            Group {
                if let icon = AppIconStore.icon(bundleID: bundleID, expectedName: name) {
                    Image(nsImage: icon.image).resizable().renderingMode(.original)
                        .allowedDynamicRange(.standard).scaledToFit()
                } else {
                    Image(systemName: "app").resizable().scaledToFit().foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            if showsColourCue {
                if differentiate {
                    Text(AppPalette.family(bundleID: bundleID).marker)
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(rgb.luminance > 0.18 ? Color.black : Color.white)
                        .frame(width: 10, height: size * 0.75)
                        .background(Color(rgb), in: RoundedRectangle(cornerRadius: 2))
                } else {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color(rgb))
                        .frame(width: 3, height: size * 0.75)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
