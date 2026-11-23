
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SignatureInspectorView: View {
    @StateObject private var inspector = SignatureInspector()
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Developer Signature Inspector")
                        .font(.title2.bold())

                    Text("Inspect macOS application signatures and notarization")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    chooseApplication()
                } label: {
                    Label("Open Application", systemImage: "folder")
                }
            }

            if inspector.isInspecting {
                ProgressView("Inspecting application...")
            }

            if let error = inspector.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }

            if let report = inspector.report {
                HStack(spacing: 12) {
                    Image(systemName: "app.badge.checkmark")
                        .font(.largeTitle)
                        .foregroundStyle(
                            report.signatureValid ? .green : .orange
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.executableName)
                            .font(.title3.bold())

                        Text(report.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer()
                }
                .padding(14)
                .background(
                    .quaternary.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 12)
                )

                Picker("Details", selection: $selectedTab) {
                    Text("Overview").tag(0)
                    Text("Entitlements").tag(1)
                    Text("Raw Output").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 350)

                switch selectedTab {
                case 0:
                    overview(report)
                case 1:
                    outputView(report.entitlements)
                default:
                    outputView(report.rawOutput)
                }
            } else if !inspector.isInspecting {
                ContentUnavailableView(
                    "No Application Selected",
                    systemImage: "app.dashed",
                    description: Text(
                        "Choose a .app bundle to inspect its signature."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func overview(_ report: SignatureReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: 12
                ) {
                    ForEach(report.checks) { check in
                        HStack(spacing: 12) {
                            Image(
                                systemName: check.passed == true
                                    ? "checkmark.circle.fill"
                                    : "exclamationmark.circle.fill"
                            )
                            .foregroundStyle(
                                check.passed == true ? .green : .orange
                            )

                            VStack(alignment: .leading, spacing: 5) {
                                Text(check.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(check.value)
                                    .fontWeight(.medium)
                                    .lineLimit(2)
                            }

                            Spacer()
                        }
                        .padding(14)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .background(
                            .quaternary.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                }

                GroupBox("Signing Identity") {
                    VStack(spacing: 12) {
                        row(
                            "Bundle Identifier",
                            report.bundleIdentifier
                        )

                        row(
                            "Signing Identifier",
                            report.identifier ?? "Unavailable"
                        )

                        row(
                            "Team Identifier",
                            report.teamIdentifier ?? "Unavailable"
                        )

                        ForEach(
                            Array(report.authorities.enumerated()),
                            id: \.offset
                        ) { index, authority in
                            row(
                                "Authority \(index + 1)",
                                authority
                            )
                        }
                    }
                    .padding(10)
                }

                if let timestamp = report.secureTimestamp {
                    GroupBox("Secure Timestamp") {
                        Text(timestamp)
                            .textSelection(.enabled)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                            .padding(10)
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }

    private func outputView(_ text: String) -> some View {
        ScrollView {
            Text(text.isEmpty ? "No output available." : text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding(14)
        }
        .background(
            .quaternary.opacity(0.3),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    
    private func chooseApplication() {
        let panel = NSOpenPanel()

        panel.title = "Choose a macOS Application"
        panel.prompt = "Inspect"

        // Allow application bundles to be selected.
        panel.canChooseFiles = true
        panel.canChooseDirectories = true

        // Treat .app bundles as selectable packages,
        // not directories to navigate into.
        panel.treatsFilePackagesAsDirectories = false

        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        // Don't restrict allowedContentTypes here.
        // Validate the selected URL instead.
        panel.allowedContentTypes = []

        if panel.runModal() == .OK,
           let url = panel.url {

            guard url.pathExtension.lowercased() == "app" else {
                return
            }

            selectedTab = 0
            inspector.inspect(url)
        }
    }

}
