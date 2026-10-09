import AppKit
import TypeStatsCore

@MainActor
final class HomebrewUpdateService: AppUpdateService {
    static let cask = "dctmfoo/type-stats/type-stats"
    static let publishedCask = URL(string: "https://raw.githubusercontent.com/dctmfoo/homebrew-type-stats/HEAD/Casks/type-stats.rb")!
    private let options: LaunchOptions

    init(options: LaunchOptions) { self.options = options }

    func latestVersion() async throws -> AppVersion {
        let data: Data
        if options.noTap, let fixture = options.updateCask {
            data = try Data(contentsOf: fixture)
        } else {
            var request = URLRequest(url: Self.publishedCask, cachePolicy: .reloadIgnoringLocalCacheData)
            request.timeoutInterval = 30
            let (body, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateFailure("The Homebrew release could not be reached. Try again later.")
            }
            data = body
        }
        guard data.count < 64_000, let text = String(data: data, encoding: .utf8),
              let version = AppVersion.published(in: text) else {
            throw UpdateFailure("The published Homebrew version could not be read.")
        }
        return version
    }

    func upgrade(to version: AppVersion) async throws {
        let brew: URL
        if options.noTap, options.dataDir != nil, let fixture = options.updateBrew {
            brew = fixture
        } else {
            guard let path = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
                .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                throw UpdateFailure("Homebrew was not found. Install it, then try again.")
            }
            brew = URL(fileURLWithPath: path)
        }
        let before = try await installedCask(brew)
        let running = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        guard let target = before.artifacts.compactMap(\.target).first,
              URL(fileURLWithPath: target).resolvingSymlinksInPath().standardizedFileURL == running else {
            throw UpdateFailure("Run the Homebrew-installed TypeStats app to update it.")
        }
        // Refresh before upgrading even if the user's shell disables Homebrew auto-update.
        try await Self.run(brew, ["update", "--quiet"])
        try await Self.run(brew, ["upgrade", "--cask", "--no-quit", Self.cask])
        let after = try await installedCask(brew)
        guard let installed = AppVersion(after.installed ?? ""), installed >= version,
              let plist = try? Data(contentsOf: running.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let text = info["CFBundleShortVersionString"] as? String,
              let actual = AppVersion(text), actual >= version else {
            throw UpdateFailure("Homebrew has not installed version \(version.text) yet. Try checking again later.")
        }
        let controller = AppController.shared
        controller?.tap.isRelaunching = true
        do { try controller?.counter.flush() }
        catch {
            controller?.tap.isRelaunching = false
            throw UpdateFailure("Counts could not be saved before restarting. TypeStats is still running.")
        }
        // A failed launch resumes the old instance. The successful path exits below.
        defer { controller?.tap.isRelaunching = false }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        // Test relaunches keep the isolated store and never start an event tap.
        if options.noTap, let dataDir = options.dataDir {
            config.arguments = ["--no-tap", "--data-dir", dataDir.path]
            if let ready = options.updateRelaunchReady {
                config.arguments += ["--ready-file", ready.path]
            }
        }
        let replacement = try await NSWorkspace.shared.openApplication(at: running, configuration: config)
        guard replacement.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !replacement.isTerminated else {
            throw UpdateFailure("The updated app did not start. TypeStats is still running; try again.")
        }
        NSApp.terminate(nil)
    }

    private struct CaskInfo: Decodable {
        struct Cask: Decodable {
            struct Artifact: Decodable { let target: String? }
            let installed: String?
            let artifacts: [Artifact]
        }
        let casks: [Cask]
    }

    private func installedCask(_ brew: URL) async throws -> CaskInfo.Cask {
        let data = try await Self.run(brew, ["info", "--json=v2", "--cask", Self.cask])
        let info = try JSONDecoder().decode(CaskInfo.self, from: data)
        guard let cask = info.casks.first, cask.installed != nil else {
            throw UpdateFailure("TypeStats is not installed with Homebrew. Install the cask first.")
        }
        return cask
    }

    /// Drain stdout/stderr to files, so verbose Homebrew output cannot fill a pipe and hang.
    @discardableResult
    private nonisolated static func run(_ executable: URL, _ arguments: [String]) async throws -> Data {
        try await Task.detached {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typestats-update-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                  attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let outURL = directory.appendingPathComponent("stdout")
            let errURL = directory.appendingPathComponent("stderr")
            FileManager.default.createFile(atPath: outURL.path, contents: nil)
            FileManager.default.createFile(atPath: errURL.path, contents: nil)
            let output = try FileHandle(forWritingTo: outURL)
            let errors = try FileHandle(forWritingTo: errURL)
            defer { try? output.close(); try? errors.close() }
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = errors
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "\(executable.deletingLastPathComponent().path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            environment["HOMEBREW_NO_ANALYTICS"] = "1"
            environment["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
            process.environment = environment
            try process.run()
            process.waitUntilExit()
            let result = try Data(contentsOf: outURL)
            guard process.terminationStatus == 0 else {
                let stderr = try Data(contentsOf: errURL)
                let detail = String(decoding: (stderr.isEmpty ? result : stderr).suffix(1800), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw UpdateFailure(detail.isEmpty ? "Homebrew failed. Try again in Terminal." : detail)
            }
            return result
        }.value
    }
}

private struct UpdateFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
