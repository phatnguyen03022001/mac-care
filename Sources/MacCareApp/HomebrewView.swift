import SwiftUI

struct HomebrewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Homebrew").font(.largeTitle.bold())
                    Spacer()
                    Button("Refresh") { Task { await model.refreshBrew() } }
                }

                if let brew = model.brew, brew.available {
                    GroupBox("Status") {
                        LabeledContent("Version", value: brew.version ?? "Available")
                        LabeledContent("Cache size", value: formatBytes(brew.cacheBytes))
                        LabeledContent("Outdated formulae", value: String(brew.outdatedFormulae.count))
                        LabeledContent("Outdated casks", value: String(brew.outdatedCasks.count))
                        LabeledContent("Unused dependencies", value: String(brew.unusedDependencies.count))
                    }

                    BrewNamesGroup(title: "Outdated Formulae", names: brew.outdatedFormulae)
                    BrewNamesGroup(title: "Outdated Casks", names: brew.outdatedCasks)
                    BrewNamesGroup(title: "Autoremove Preview", names: brew.unusedDependencies)

                    GroupBox("Cleanup Preview") {
                        if brew.cleanupPreview.isEmpty {
                            Text("Homebrew reports no cleanup candidates.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(brew.cleanupPreview.prefix(20), id: \.self) { line in
                                Text(line).font(.caption.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    Text("Mutations are not run from this page. Homebrew cleanup is executed only through a Mac Care cleanup plan.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView(
                        "Homebrew Not Found",
                        systemImage: "shippingbox",
                        description: Text("Mac Care checks only trusted standard Homebrew executable locations.")
                    )
                }
            }
            .padding(24)
        }
    }
}

private struct BrewNamesGroup: View {
    let title: String
    let names: [String]

    var body: some View {
        GroupBox(title) {
            if names.isEmpty {
                Text("None").foregroundStyle(.secondary)
            } else {
                FlowText(names: Array(names.prefix(40)))
            }
        }
    }
}

private struct FlowText: View {
    let names: [String]

    var body: some View {
        Text(names.joined(separator: ", "))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
