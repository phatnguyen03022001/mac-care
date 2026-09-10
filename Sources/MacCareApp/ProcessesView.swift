import SwiftUI

struct ProcessesView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Processes").font(.largeTitle.bold())
                    Text("Inspection only. No environment, argv dump, kill, stop, or restart actions.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { Task { await model.refreshProcesses() } }
            }
            .padding(24)

            Divider()

            Table(model.processes) {
                TableColumn("PID") { process in
                    Text(String(process.pid)).monospacedDigit()
                }
                .width(70)

                TableColumn("Process") { process in
                    Text(process.name).lineLimit(1)
                }

                TableColumn("CPU") { process in
                    Text(formatPercent(process.cpuPercent)).monospacedDigit()
                }
                .width(80)

                TableColumn("Memory") { process in
                    Text(formatBytes(process.residentBytes)).monospacedDigit()
                }
                .width(100)

                TableColumn("Uptime") { process in
                    Text(formatDuration(process.uptimeSeconds.map(TimeInterval.init)))
                }
                .width(100)
            }
        }
    }
}
