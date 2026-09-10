import SwiftUI

enum MacCareSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case cleanup = "Cleanup"
    case applications = "Applications"
    case processes = "Processes"
    case homebrew = "Homebrew"
    case privacy = "Privacy"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .cleanup: "trash"
        case .applications: "app.dashed"
        case .processes: "waveform.path.ecg"
        case .homebrew: "shippingbox"
        case .privacy: "hand.raised"
        }
    }
}

struct RootView: View {
    @StateObject private var model = AppModel()
    @State private var selection: MacCareSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(MacCareSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Mac Care")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            Group {
                switch selection ?? .overview {
                case .overview: OverviewView(model: model)
                case .cleanup: CleanupView(model: model)
                case .applications: ApplicationsView(model: model)
                case .processes: ProcessesView(model: model)
                case .homebrew: HomebrewView(model: model)
                case .privacy: PrivacyView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await model.refreshAll() }
        .alert("Mac Care", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
