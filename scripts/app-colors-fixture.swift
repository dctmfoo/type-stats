// Compiled alongside TypeStatsCore (same module identity) by app-colors-check.sh.
// Writes only illustrative counts through the real store interface; no input tap or UI.
import Foundation

@main
struct AppColorsFixture {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw CocoaError(.fileWriteInvalidFileName) }
        let data = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard data.standardizedFileURL != CountStore.defaultDirectory().standardizedFileURL else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let store = try CountStore(directory: data)
        let claude = AppIdentity(bundleID: "com.anthropic.claudefordesktop", name: "Claude")
        // Current Homebrew ChatGPT uses this identifier; legacy ChatGPT uses com.openai.chat.
        // These are illustrative rows, not renamed Codex history.
        let chatgpt = AppIdentity(bundleID: "com.openai.codex", name: "ChatGPT")
        let teams = AppIdentity(bundleID: "com.microsoft.teams2", name: "Teams")
        let discord = AppIdentity(bundleID: "com.hnc.Discord", name: "Discord")
        let ghostty = AppIdentity(bundleID: "com.mitchellh.ghostty", name: "Ghostty")
        let chrome = AppIdentity(bundleID: "com.google.Chrome", name: "Google Chrome")
        let rows: [(String, Int, [(AppIdentity, Int)])] = [
            ("2026-09-29", 9, [(claude, 257), (chatgpt, 252), (teams, 16)]),
            ("2026-09-30", 13, [(teams, 264), (chatgpt, 245), (discord, 226)]),
            ("2026-10-01", 9, [(claude, 210), (chatgpt, 210)]),
            ("2026-10-02", 9, [(chatgpt, 400), (claude, 100)]),
            ("2026-10-03", 9, [(ghostty, 140), (claude, 70)]),
            ("2026-10-04", 10, [(chrome, 15)]),
            ("2026-10-04", 11, [(discord, 200), (claude, 100)]),
            ("2026-10-05", 12, [(claude, 200), (chatgpt, 50)]),
            ("2026-10-05", 13, [(claude, 600), (chatgpt, 200), (teams, 100), (discord, 57)])
        ]
        for (day, hour, apps) in rows {
            for (app, keys) in apps {
                try store.add(day: day, hour: hour, app: app, keys: keys,
                              burstCount: keys, activeSeconds: Double(keys) / 5)
            }
        }
        try store.add(day: "2026-10-05", hour: 14, app: chrome, keys: 0, clicks: 137)
        try store.add(day: "2026-09-29", app: claude, keys: 50)
        try store.save()
    }
}
