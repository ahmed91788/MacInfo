
import SwiftUI

struct AdvancedPersistenceView: View {
    @StateObject private var startup = StartupMonitor()
    @StateObject private var runtime = LaunchdRuntimeMonitor()
    @StateObject private var background = BackgroundTaskMonitor()

    @State private var selectedTab = 0
    @State private var search = ""
    @State private var reviewOnly = false
    @State private var selectedItem: StartupItem?
    @State private var selectedStartupPath: String?

    private var filteredItems: [StartupItem] {
        startup.items.filter { item in
            let matchesSearch =
                search.isEmpty ||
                item.label.localizedCaseInsensitiveContains(search) ||
                item.executablePath.localizedCaseInsensitiveContains(search) ||
                item.plistPath.localizedCaseInsensitiveContains(search)

            return matchesSearch &&
                (!reviewOnly || item.needsReview)
        }
    }

    private var reviewCount: Int {
        startup.items.filter(\.needsReview).count
    }

    private var missingCount: Int {
        startup.items.filter {
            $0.programExists == false
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Advanced Persistence Inspector")
                        .font(.title2.bold())

                    Text("Read-only startup and background service audit")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    refreshAll()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            HStack(spacing: 12) {
                summaryCard(
                    "Startup Entries",
                    startup.items.count,
                    "list.bullet"
                )

                summaryCard(
                    "Needs Review",
                    reviewCount,
                    "exclamationmark.triangle"
                )

                summaryCard(
                    "Missing Targets",
                    missingCount,
                    "questionmark.folder"
                )
            }

            Picker("Inspector", selection: $selectedTab) {
                Text("Startup Items").tag(0)
                Text("Launchd Runtime").tag(1)
                Text("Background Tasks").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 500)

            switch selectedTab {
            case 0:
                startupContent
            case 1:
                runtimeContent
            default:
                backgroundContent
            }
        }
        .padding(20)
        .onAppear {
            if startup.items.isEmpty {
                refreshAll()
            }
        }
        .sheet(item: $selectedItem) { item in
            persistenceDetails(item)
        }
    }

    private var startupContent: some View {
        VStack(spacing: 12) {
            HStack {
                TextField(
                    "Search label, executable or configuration",
                    text: $search
                )
                .textFieldStyle(.roundedBorder)

                Toggle("Needs Review", isOn: $reviewOnly)
                    .toggleStyle(.checkbox)
            }

            Table(filteredItems, selection: $selectedStartupPath) {
                TableColumn("Service") { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.label)
                            .fontWeight(.medium)

                        Text(item.executablePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                TableColumn("Type") { item in
                    Text(item.type.rawValue)
                }
                .width(120)

                TableColumn("Signature") { item in
                    Text(item.signingStatus)
                }
                .width(120)

                TableColumn("Review") { item in
                    if item.needsReview {
                        Label(
                            "\(item.reviewReasons.count) flags",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(100)
            }
            .contextMenu(forSelectionType: String.self) { paths in
                Button("View Details") {
                    guard let path = paths.first else { return }
                    selectedItem = startup.items.first { $0.id == path }
                }
            } primaryAction: { paths in
                guard let path = paths.first else { return }
                selectedItem = startup.items.first { $0.id == path }
            }

        }
    }

    private var runtimeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                "\(runtime.entries.count) jobs visible in the current launchd context"
            )
            .foregroundStyle(.secondary)

            Table(runtime.entries) {
                TableColumn("Label", value: \.label)

                TableColumn("PID") { entry in
                    Text(entry.pid.map(String.init) ?? "—")
                }
                .width(90)

                TableColumn("Last Exit") { entry in
                    Text(entry.lastExitStatus.map(String.init) ?? "—")
                }
                .width(100)
            }
        }
    }

    private var backgroundContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Service Management background-task diagnostics")
                .foregroundStyle(.secondary)

            ScrollView {
                Text(background.output.isEmpty
                     ? "No diagnostic output loaded."
                     : background.output)
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
    }

    private func summaryCard(
        _ title: String,
        _ count: Int,
        _ icon: String
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(count.formatted())
                    .font(.title2.bold())
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            .quaternary.opacity(0.4),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func persistenceDetails(
        _ item: StartupItem
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.label)
                    .font(.title2.bold())

                LabeledContent("Type", value: item.type.rawValue)
                LabeledContent("Signature", value: item.signingStatus)
                LabeledContent(
                    "Team ID",
                    value: item.teamIdentifier ?? "Unavailable"
                )

                if let modifiedAt = item.modifiedAt {
                    LabeledContent(
                        "Modified",
                        value: modifiedAt.formatted(
                            date: .abbreviated,
                            time: .standard
                        )
                    )
                }

                Divider()

                Text("Executable")
                    .font(.headline)

                Text(item.executablePath)
                    .textSelection(.enabled)

                Text("Configuration")
                    .font(.headline)

                Text(item.plistPath)
                    .textSelection(.enabled)

                Divider()

                Text("Review Findings")
                    .font(.headline)

                if item.reviewReasons.isEmpty {
                    Text("No heuristic review flags.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(item.reviewReasons, id: \.self) { reason in
                        Label(
                            reason,
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 650, height: 480)
    }

    private func refreshAll() {
        startup.scan()
        runtime.refresh()
        background.refresh()
    }
}
