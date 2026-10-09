import SwiftUI
import TypeStatsCore

struct AppUpdatesView: View {
    let update: AppUpdate

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("App Updates").font(.title2.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow { Text("Current version").foregroundStyle(.secondary); Text(update.currentVersion) }
                GridRow { Text("Latest version").foregroundStyle(.secondary); Text(update.latest?.text ?? "Not checked") }
            }
            .font(.body).monospacedDigit()
            Text(update.status).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("updateStatus")
            if let error = update.error {
                Text(error).font(.callout).foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("updateError")
            }
            HStack {
                if update.isChecking || update.isUpdating { ProgressView().controlSize(.small) }
                Spacer()
                Button {
                    Task {
                        if update.updateAvailable { await update.update() }
                        else { await update.check() }
                    }
                } label: {
                    Text(update.buttonLabel)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(update.isChecking || update.isUpdating)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("updateAction")
            }
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
    }
}
