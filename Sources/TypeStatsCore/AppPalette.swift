import Foundation

/// Stable bundle-based colour families, shared by app tags, hourly cells and exports.
/// Neutral/monochrome apps deliberately need their name; this is not service attribution.
public enum AppPalette {
    public struct RGB: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(hex: UInt32) {
            red = Double((hex >> 16) & 255) / 255
            green = Double((hex >> 8) & 255) / 255
            blue = Double(hex & 255) / 255
        }

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public var luminance: Double {
            let v = linear
            return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]
        }

        private var linear: [Double] {
            [red, green, blue].map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        }

        fileprivate var lch: (lightness: Double, chroma: Double, hue: Double) {
            let v = linear, r = v[0], g = v[1], b = v[2]
            let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
            let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
            let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
            let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
            let bAxis = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
            return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, hypot(a, bAxis), atan2(bAxis, a))
        }

        public var perceptualLightness: Double { lch.lightness }
    }

    public enum Family: String, CaseIterable, Identifiable, Sendable {
        case claude, codex, chatgpt, teams, discord, editor, terminal, other
        public var id: String { rawValue }
        /// A non-colour cue used when Differentiate Without Color is enabled.
        public var marker: String {
            switch self {
            case .claude: "C"
            case .codex: "X"
            case .chatgpt: "G"
            case .teams: "T"
            case .discord: "D"
            case .editor: "E"
            case .terminal: "H"
            case .other: "N"
            }
        }
        public var tag: RGB {
            switch self {
            case .claude: RGB(hex: 0xC66B4E)
            case .codex, .chatgpt: RGB(hex: 0x56636B)
            case .teams: RGB(hex: 0x6264A7)
            case .discord: RGB(hex: 0x5865F2)
            case .editor: RGB(hex: 0x007ACC)
            case .terminal: RGB(hex: 0x56636B)
            case .other: RGB(hex: 0x888888)
            }
        }
    }

    public static func family(bundleID: String) -> Family {
        switch bundleID.lowercased() {
        case "com.anthropic.claudefordesktop", "com.anthropic.claude": .claude
        // Current ChatGPT and Codex share this bundle ID; keep recorded names truthful.
        case "com.openai.codex": .codex
        case "com.openai.chat": .chatgpt
        case "com.microsoft.teams", "com.microsoft.teams2": .teams
        case "com.hnc.discord": .discord
        case "com.microsoft.vscode", "com.apple.dt.xcode", "com.todesktop.230313mzl4w4u92": .editor
        case "com.mitchellh.ghostty", "com.apple.terminal", "com.googlecode.iterm2": .terminal
        default: .other
        }
    }

    public static func tag(bundleID: String) -> RGB { family(bundleID: bundleID).tag }

    /// Positive bins use equal OKLCH lightness across hues, not raw brand opacity.
    /// Dark mode reverses the ladder. Chroma reduction keeps every sample in sRGB.
    public static func heatmap(bundleID: String?, step: Int, dark: Bool, increasedContrast: Bool = false) -> RGB {
        guard step > 0 else { return lch(lightness: dark ? 0.26 : 0.92, chroma: 0, hue: 0) }
        let index = min(4, step) - 1
        let levels: [Double] = increasedContrast
            ? (dark ? [0.48, 0.60, 0.72, 0.84] : [0.78, 0.66, 0.54, 0.42])
            : (dark ? [0.40, 0.52, 0.64, 0.76] : [0.84, 0.74, 0.64, 0.54])
        let seed = bundleID.map { tag(bundleID: $0).lch }
        let strength = [0.5, 0.7, 0.85, 1.0][index]
        return lch(lightness: levels[index], chroma: min(seed?.chroma ?? 0, 0.08) * strength, hue: seed?.hue ?? 0)
    }

    static func lch(lightness: Double, chroma: Double, hue: Double) -> RGB {
        func linear(_ chroma: Double) -> [Double] {
            let a = chroma * cos(hue), b = chroma * sin(hue)
            let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
            let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
            let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
            return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s]
        }
        var c = chroma
        var values = linear(c)
        while values.contains(where: { $0 < 0 || $0 > 1 }) && c > 0.000001 {
            c *= 0.95
            values = linear(c)
        }
        let encoded = values.map { value in
            let v = min(1, max(0, value))
            return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        return RGB(red: encoded[0], green: encoded[1], blue: encoded[2])
    }
}
