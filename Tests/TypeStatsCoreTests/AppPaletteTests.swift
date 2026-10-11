import XCTest
@testable import TypeStatsCore

final class AppPaletteTests: XCTestCase {
    func testStableBundleAssignmentsAndNeutralHostFallback() {
        XCTAssertEqual(AppPalette.tag(bundleID: "com.anthropic.claudefordesktop"), .init(hex: 0xC66B4E))
        XCTAssertEqual(AppPalette.tag(bundleID: "com.openai.codex"), .init(hex: 0x218358))
        XCTAssertEqual(AppPalette.family(bundleID: "com.openai.chat"), .chatgpt)
        XCTAssertEqual(AppPalette.family(bundleID: "com.openai.codex"), .codex)
        XCTAssertEqual(AppPalette.tag(bundleID: "com.openai.chat"), .init(hex: 0x218358))
        XCTAssertEqual(AppPalette.tag(bundleID: "com.microsoft.teams2"), .init(hex: 0x6264A7))
        XCTAssertEqual(AppPalette.tag(bundleID: "com.hnc.Discord"), .init(hex: 0x5865F2))
        XCTAssertEqual(AppPalette.tag(bundleID: "com.microsoft.VSCode"), AppPalette.tag(bundleID: "com.microsoft.vscode"))
        XCTAssertEqual(AppPalette.tag(bundleID: "com.mitchellh.ghostty"), .init(hex: 0x56636B))
        XCTAssertEqual(AppPalette.family(bundleID: "com.google.Chrome"), .other)
        XCTAssertEqual(AppPalette.family(bundleID: "a.new.app"), .other)
        XCTAssertEqual(AppPalette.family(bundleID: "not.an.actual.claude.service"), .other)
        XCTAssertEqual(Set(AppPalette.Family.allCases.map(\.marker)).count, AppPalette.Family.allCases.count)
    }

    func testOpenAIHueIsDistinctFromTerminalAtEveryPositiveIntensity() {
        let terminal = "com.apple.Terminal"
        XCTAssertEqual(AppPalette.tag(bundleID: terminal), .init(hex: 0x56636B))
        XCTAssertEqual(AppPalette.tag(bundleID: "unknown"), .init(hex: 0x888888))
        for id in ["com.openai.chat", "com.openai.codex"] {
            XCTAssertNotEqual(AppPalette.tag(bundleID: id), AppPalette.tag(bundleID: terminal))
            for dark in [false, true] {
                for contrast in [false, true] {
                    for step in 1...4 {
                        let app = AppPalette.heatmap(bundleID: id, step: step, dark: dark, increasedContrast: contrast)
                        let host = AppPalette.heatmap(bundleID: terminal, step: step, dark: dark, increasedContrast: contrast)
                        // A visible channel separation, not merely unequal floating-point samples.
                        XCTAssertGreaterThan(abs(app.red - host.red), 0.04)
                        XCTAssertGreaterThan(abs(app.blue - host.blue), 0.04)
                        XCTAssertEqual(app.perceptualLightness, host.perceptualLightness, accuracy: 0.00001)
                    }
                }
            }
        }
    }

    func testEqualActivityHasEqualPerceptualLightnessAcrossEveryHueAndAppearance() {
        let ids = ["com.anthropic.claudefordesktop", "com.openai.codex", "com.openai.chat", "com.microsoft.teams2", "com.hnc.Discord",
                   "com.microsoft.VSCode", "com.mitchellh.ghostty", "com.google.Chrome", "unknown"]
        for dark in [false, true] {
            for contrast in [false, true] {
                var previousBand: [Double] = []
                for step in 1...4 {
                    let colors = ids.map { AppPalette.heatmap(bundleID: $0, step: step, dark: dark, increasedContrast: contrast) }
                    let lightness = colors.map(\.perceptualLightness)
                    XCTAssertLessThan(lightness.max()! - lightness.min()!, 0.00001)
                    for color in colors {
                        XCTAssertTrue([color.red, color.green, color.blue].allSatisfy { (0...1).contains($0) })
                    }
                    let band = colors.map(\.luminance)
                    if !previousBand.isEmpty {
                        if dark { XCTAssertGreaterThan(band.min()!, previousBand.max()!) }
                        else { XCTAssertLessThan(band.max()!, previousBand.min()!) }
                    }
                    previousBand = band
                }
                let zero = AppPalette.heatmap(bundleID: nil, step: 0, dark: dark, increasedContrast: contrast)
                let positive = AppPalette.heatmap(bundleID: nil, step: 1, dark: dark, increasedContrast: contrast)
                XCTAssertNotEqual(zero, positive)
                XCTAssertEqual(AppPalette.heatmap(bundleID: ids[0], step: 0, dark: dark), zero)
            }
        }
    }

    func testIntensityUsesTotalNotLeadingShare() {
        XCTAssertEqual(WeeklyActivity.shadeStep(keys: 735, peak: 957), 4)
        XCTAssertEqual(WeeklyActivity.shadeStep(keys: 15, peak: 957), 1)
        let lowShareLeader = AppPalette.heatmap(bundleID: "com.microsoft.teams2", step: 4, dark: false)
        let exclusiveButQuiet = AppPalette.heatmap(bundleID: "com.google.Chrome", step: 1, dark: false)
        XCTAssertLessThan(lowShareLeader.luminance, exclusiveButQuiet.luminance)
    }
}
