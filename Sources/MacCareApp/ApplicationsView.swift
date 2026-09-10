import SwiftUI

struct ApplicationsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Applications").font(.largeTitle.bold())
                    Text("Installed app metadata only. Old usage is a signal, never an uninstall decision.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { Task { await model.refreshApplications() } }
            }
            .padding(24)

            Divider()

            Table(model.applications) {
                TableColumn("Application") { app in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).fontWeight(.medium)
                        Text(app.bundleIdentifier ?? app.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                TableColumn("Version") { app in
                    Text(app.version ?? "—")
                }
                .width(min: 80, ideal: 110)

                TableColumn("Size") { app in
                    Text(formatBytes(app.approximateBytes))
                        .monospacedDigit()
                }
                .width(min: 90, ideal: 110)

                TableColumn("Last used") { app in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatDate(app.lastUsedAt))
                        Text(app.usageSignal)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .width(min: 140, ideal: 220)
            }
        }
    }
}
