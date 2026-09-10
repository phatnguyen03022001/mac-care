import SwiftUI

struct PrivacyView: View {
    @ObservedObject var model: AppModel

    private let protectedGroups = [
        "Photos and every *.photoslibrary package",
        "Keychains and password-manager stores",
        "SSH, GPG, cloud, Kubernetes, and registry credentials",
        "Browser cookies, sessions, authentication databases, and credential stores",
        "Personal document roots such as Pictures, Documents, Desktop, Downloads, Movies, and Music",
        "Clipboard, shell history, process environments, and secret/token discovery"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Privacy").font(.largeTitle.bold())
                    Spacer()
                    Button("Run Self-Test") { Task { await model.refreshPrivacy() } }
                }

                GroupBox("Hard Boundary") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Protected data is denied in MacCareCore before filesystem traversal. There is no override in v0.1.0.")
                        ForEach(protectedGroups, id: \.self) { item in
                            Label(item, systemImage: "lock.fill")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Privacy Self-Test") {
                    if let report = model.privacyReport {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(
                                report.passed ? "All synthetic privacy checks passed" : "Privacy self-test failed",
                                systemImage: report.passed ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
                            )
                            .fontWeight(.semibold)

                            ForEach(report.checks) { check in
                                HStack {
                                    Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    Text(check.name)
                                    Spacer()
                                    Text(check.passed ? "PASS" : "FAIL")
                                        .font(.caption.monospaced())
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Self-test has not run yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("MCP Safety") {
                    Text("The MCP executable exposes only narrow semantic tools. It does not expose shell, arbitrary file reading, arbitrary deletion, clipboard access, credential lookup, or process control.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
    }
}
