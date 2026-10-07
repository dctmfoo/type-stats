import AppKit
import SwiftUI
import TypeStatsCore

/// The popup's Excluded apps page: the apps whose key presses and clicks are never counted
/// (for example a password manager), with a button to remove each, and lists of the current
/// top apps and the running apps to exclude from. It is drawn over the popup's normal
/// contents, so the popup keeps its size.
struct ExcludedAppsView: View {
    let controller: AppController
    /// The top apps of the period being viewed.
    let top: [AppCount]
    let close: () -> Void
    @State private var running: [AppIdentity] = []

    var body: some View {
        let counter = controller.counter
        let excluded = Set(counter.excludedApps.map(\.bundleID))
        let topCandidates = top.filter { !excluded.contains($0.bundleID) }.map { AppIdentity(bundleID: $0.bundleID, name: $0.name) }
        let shown = Set(topCandidates.map(\.bundleID))
        let runningCandidates = running.filter { !excluded.contains($0.bundleID) && !shown.contains($0.bundleID) }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { close() } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
                    .accessibilityIdentifier("excludedBack")
                Spacer()
                Text("Excluded apps").font(.headline)
                Spacer()
                Label("Back", systemImage: "chevron.left").font(.caption).hidden()
            }
            Text("Key presses and clicks in these apps are never counted. What was counted before stays in your history, marked excluded.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("Excluded") {
                        if counter.excludedApps.isEmpty {
                            Text("No apps excluded.").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(counter.excludedApps, id: \.bundleID) { app in
                            row(app, action: "Remove") { controller.include(bundleID: app.bundleID) }
                        }
                    }
                    if !topCandidates.isEmpty {
                        section("Top apps now") {
                            ForEach(topCandidates, id: \.bundleID) { app in
                                row(app, action: "Exclude") { controller.exclude(app) }
                            }
                        }
                    }
                    if !runningCandidates.isEmpty {
                        section("Running apps") {
                            ForEach(runningCandidates, id: \.bundleID) { app in
                                row(app, action: "Exclude") { controller.exclude(app) }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { running = controller.testMode ? [] : AppController.runningApps() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func row(_ app: AppIdentity, action: String, perform: @escaping () -> Void) -> some View {
        HStack {
            Text(app.name).lineLimit(1).truncationMode(.tail)
            Spacer()
            Button(action: perform) {
                Text(action)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(action) \(app.name)")
        }
    }
}
