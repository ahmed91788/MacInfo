
import SwiftUI

struct StartupItemsView: View {
    @StateObject private var monitor = StartupMonitor()

    @State private var search = ""
    @State private var selectedType = "All"
    @State private var selectedItem: StartupItem?
    @State private var selectedPath: String?

    private var filteredItems: [StartupItem] {
        monitor.items.filter { item in
            let matchesType =
                selectedType == "All" ||
                item.type.rawValue == selectedType

            let matchesSearch =
                search.isEmpty ||
                item.label.localizedCaseInsensitiveContains(search) ||
                item.executablePath.localizedCaseInsensitiveContains(search) ||
                item.plistPath.localizedCaseInsensitiveContains(search)

            return matchesType && matchesSearch
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Startup & Background Services")
                        .font(.title2.bold())

                    Text("\(filteredItems.count) configured services")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    monitor.scan()
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .disabled(monitor.isScanning)
            }

            HStack {
                TextField(
                    "Search service, executable or plist path",
                    text: $search
                )
                .textFieldStyle(.roundedBorder)

                Picker("Type", selection: $selectedType) {
                    Text("All").tag("All")

                    ForEach(
                        StartupItemType.allCases,
                        id: \.rawValue
                    ) { type in
                        Text(type.rawValue).tag(type.rawValue)
                    }
                }
                .frame(width: 180)
            }

            if monitor.isScanning {
                ProgressView("Scanning startup services...")
            }

            Table(filteredItems, selection: $selectedPath) {
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
                .width(130)

                TableColumn("Run at Load") { item in
                    Text(item.runAtLoad ? "Yes" : "No")
                }
                .width(90)

                TableColumn("Keep Alive") { item in
                    Text(item.keepAlive ? "Configured" : "No")
                }
                .width(100)

                TableColumn("Executable") { item in
                    switch item.programExists {
                    case .some(true):
                        Label("Found", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    case .some(false):
                        Label("Missing", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    case .none:
                        Text("Unresolved")
                            .foregroundStyle(.secondary)
                    }
                }
                .width(110)
            }
            .contextMenu(forSelectionType: String.self) { paths in
                Button("View Details") {
                    if let path = paths.first {
                        selectedItem = monitor.items.first {
                            $0.id == path
                        }
                    }
                }
            } primaryAction: { paths in
                if let path = paths.first {
                    selectedItem = monitor.items.first {
                        $0.id == path
                    }
                }
            }

            if let date = monitor.lastScanned {
                Text(
                    "Last scanned: " +
                    date.formatted(
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
            if monitor.items.isEmpty {
                monitor.scan()
            }
        }
        .sheet(item: $selectedItem) { item in
            StartupItemDetailsView(item: item)
        }
    }
}

private struct StartupItemDetailsView: View {
    let item: StartupItem

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(item.label)
                    .font(.title2.bold())
                    .lineLimit(2)

                Spacer()

                Button("Close") {
                    dismiss()
                }
            }

            LabeledContent("Type", value: item.type.rawValue)
            LabeledContent("Run at Load", value: item.runAtLoad ? "Yes" : "No")
            LabeledContent("Keep Alive", value: item.keepAlive ? "Configured" : "No")
            LabeledContent(
                "Disabled in plist",
                value: item.disabledInPlist ? "Yes" : "No"
            )

            Divider()

            Text("Executable Path")
                .font(.headline)

            Text(item.executablePath.isEmpty ? "Unavailable" : item.executablePath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            Text("Configuration File")
                .font(.headline)

            Text(item.plistPath)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            if !item.arguments.isEmpty {
                Text("Program Arguments")
                    .font(.headline)

                ScrollView {
                    Text(item.arguments.joined(separator: "\n"))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 650, height: 520)
    }
}
