
import SwiftUI

struct ApplicationInventoryView: View {
    @StateObject private var inventory = ApplicationInventory()

    @State private var search = ""
    @State private var signatureFilter = "All"
    @State private var selectedApplication: InstalledApplication?
    @State private var selectedPath: String?

    private var filteredApplications: [InstalledApplication] {
        inventory.applications.filter { app in
            let matchesSearch =
                search.isEmpty ||
                app.name.localizedCaseInsensitiveContains(search) ||
                app.bundleIdentifier.localizedCaseInsensitiveContains(search) ||
                app.path.localizedCaseInsensitiveContains(search)

            let matchesSignature =
                signatureFilter == "All" ||
                app.signature.rawValue == signatureFilter

            return matchesSearch && matchesSignature
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Application Inventory")
                        .font(.title2.bold())

                    Text("\(filteredApplications.count) applications")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    inventory.scan()
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .disabled(inventory.isScanning)
            }

            HStack {
                TextField(
                    "Search applications, bundle ID or path",
                    text: $search
                )
                .textFieldStyle(.roundedBorder)

                Picker("Signature", selection: $signatureFilter) {
                    Text("All").tag("All")

                    ForEach(ApplicationSignature.allCases, id: \.rawValue) {
                        signature in
                        Text(signature.rawValue)
                            .tag(signature.rawValue)
                    }
                }
                .frame(width: 180)
            }

            if inventory.isScanning {
                ProgressView("Scanning applications...")
            }

            Table(filteredApplications, selection: $selectedPath) {
                TableColumn("Application") { app in
                    HStack(spacing: 10) {
                        Image(systemName: "app")
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name)
                                .fontWeight(.medium)

                            Text(app.bundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                TableColumn("Version") { app in
                    Text(app.version)
                }
                .width(90)

                TableColumn("Signature") { app in
                    Text(app.signature.rawValue)
                }
                .width(130)

                TableColumn("Team ID") { app in
                    Text(app.teamIdentifier ?? "—")
                        .monospaced()
                }
                .width(115)
            }
            .contextMenu(forSelectionType: String.self) { paths in
                Button("Inspect Signature") {
                    if let path = paths.first {
                        selectedApplication = inventory.applications.first {
                            $0.path == path
                        }
                    }
                }
            } primaryAction: { paths in
                if let path = paths.first {
                    selectedApplication = inventory.applications.first {
                        $0.path == path
                    }
                }
            }

            if let lastScanned = inventory.lastScanned {
                Text(
                    "Last scanned: " +
                    lastScanned.formatted(
                        date: .abbreviated,
                        time: .standard
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .onAppear {
            if inventory.applications.isEmpty {
                inventory.scan()
            }
        }
        .sheet(item: $selectedApplication) { app in
            ApplicationSignatureSheet(app: app)
        }
    }
}

private struct ApplicationSignatureSheet: View {
    let app: InstalledApplication

    @StateObject private var inspector = SignatureInspector()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(app.name)
                    .font(.title2.bold())

                Spacer()

                Button("Close") {
                    dismiss()
                }
            }

            LabeledContent("Bundle ID", value: app.bundleIdentifier)
            LabeledContent("Version", value: app.version)
            LabeledContent("Signature", value: app.signature.rawValue)
            LabeledContent("Team ID", value: app.teamIdentifier ?? "—")

            Text("Application Path")
                .font(.headline)

            Text(app.path)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            Divider()

            if inspector.isInspecting {
                ProgressView("Inspecting signature...")
            }

            if let report = inspector.report {
                LabeledContent(
                    "Signature Valid",
                    value: report.signatureValid ? "Yes" : "No"
                )

                LabeledContent(
                    "Hardened Runtime",
                    value: report.hardenedRuntime ? "Enabled" : "Disabled"
                )

                LabeledContent(
                    "Secure Timestamp",
                    value: report.secureTimestamp ?? "Missing"
                )

                LabeledContent(
                    "Gatekeeper",
                    value: report.gatekeeperAccepted
                        ? "Accepted" : "Rejected / Unavailable"
                )

                LabeledContent(
                    "Stapled Ticket",
                    value: report.staplerValidated
                        ? "Valid" : "Not found / Invalid"
                )
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 620, height: 460)
        .task {
            inspector.inspect(URL(fileURLWithPath: app.path))
        }
    }
}
