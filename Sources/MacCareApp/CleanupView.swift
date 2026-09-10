import SwiftUI
import MacCareCore

struct CleanupView: View {
    @ObservedObject var model: AppModel
    @State private var selected: Set<String> = []
    @State private var confirmReview = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cleanup").font(.largeTitle.bold())
                    Text("Scan → classify → plan → approve → execute → verify")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh Plan") {
                    selected.removeAll()
                    Task { await model.refreshCleanup() }
                }
                .disabled(model.isBusy)
            }
            .padding(24)

            Divider()

            if let plan = model.cleanupPlan {
                List {
                    ForEach(CleanupRisk.allCases, id: \.self) { risk in
                        let candidates = plan.candidates.filter { $0.risk == risk }
                        if !candidates.isEmpty {
                            Section(risk.rawValue) {
                                ForEach(candidates) { candidate in
                                    HStack(alignment: .top, spacing: 12) {
                                        if candidate.risk == .protected {
                                            Image(systemName: "lock.fill")
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Toggle("", isOn: selectionBinding(candidate.candidateID))
                                                .labelsHidden()
                                        }
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(candidate.category).fontWeight(.medium)
                                            Text(candidate.displayPath)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                            Text(candidate.reason)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(formatBytes(candidate.estimatedBytes))
                                            .monospacedDigit()
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }

                HStack {
                    Button("Select SAFE") {
                        selected = Set(plan.candidates.filter { $0.risk == .safe }.map(\.candidateID))
                    }
                    Button("Clear") { selected.removeAll() }
                    Spacer()
                    Text("\(selected.count) selected")
                        .foregroundStyle(.secondary)
                    Button("Execute Selected") { prepareExecution(plan) }
                        .buttonStyle(.borderedProminent)
                        .disabled(selected.isEmpty || model.isBusy)
                }
                .padding(16)
            } else {
                ContentUnavailableView(
                    "No Cleanup Plan",
                    systemImage: "trash",
                    description: Text("Refresh to scan supported safe categories.")
                )
            }
        }
        .alert("Review cleanup items?", isPresented: $confirmReview) {
            Button("Cancel", role: .cancel) {}
            Button("Move REVIEW Items to Trash", role: .destructive) {
                Task {
                    await model.execute(candidateIDs: selected, allowReview: true)
                    selected.removeAll()
                }
            }
        } message: {
            Text("REVIEW items may contain user-significant data. Mac Care will move filesystem REVIEW items to Trash where supported.")
        }
    }
}

private extension CleanupView {
    func selectionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { enabled in
                if enabled { selected.insert(id) } else { selected.remove(id) }
            }
        )
    }

    func prepareExecution(_ plan: CleanupPlan) {
        let chosen = plan.candidates.filter { selected.contains($0.candidateID) }
        if chosen.contains(where: { $0.risk == .review }) {
            confirmReview = true
        } else {
            Task {
                await model.execute(candidateIDs: selected, allowReview: false)
                selected.removeAll()
            }
        }
    }
}
