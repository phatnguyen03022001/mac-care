import SwiftUI

struct OverviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Overview").font(.largeTitle.bold())
                    Spacer()
                    Button("Refresh") { Task { await model.refreshAll() } }
                        .disabled(model.isBusy)
                }

                if let health = model.health {
                    GroupBox("System Health") {
                        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                            MetricRow("Storage used", formatBytes(health.diskTotalBytes - health.diskFreeBytes), detail: "of \(formatBytes(health.diskTotalBytes))")
                            MetricRow("Memory", formatBytes(health.memoryUsedBytes), detail: health.memoryPressure.capitalized + " pressure")
                            MetricRow("CPU", formatPercent(health.cpuUsedPercent), detail: "Current sampled utilization")
                            MetricRow("Uptime", formatDuration(health.uptimeSeconds), detail: "Since last boot")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let battery = model.health?.battery {
                    GroupBox("Battery") {
                        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                            MetricRow("Charge", formatPercent(battery.chargePercent), detail: "Current charge")
                            MetricRow("Health", formatPercent(battery.healthPercent), detail: "Estimated maximum vs design capacity")
                            MetricRow("Cycles", battery.cycleCount.map(String.init) ?? "—", detail: "Battery cycle count")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                GroupBox("Cleanup Opportunity") {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                        MetricRow("Safe reclaimable", formatBytes(model.storage?.estimatedReclaimableBytes), detail: "Regenerable data only")
                        MetricRow("Candidates", model.storage.map { String($0.candidateCount) } ?? "—", detail: "Review before execution")
                        MetricRow("Homebrew", model.brew?.available == true ? (model.brew?.version ?? "Available") : "Not found", detail: "Read-only status")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
    }
}

private struct MetricRow: View {
    let label: String
    let value: String
    let detail: String

    init(_ label: String, _ value: String, detail: String) {
        self.label = label
        self.value = value
        self.detail = detail
    }

    var body: some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold)
            Text(detail).foregroundStyle(.secondary)
        }
    }
}
