
import SwiftUI

enum ProcessSort: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"
    case name = "Name"
    case pid = "PID"

    var id: String { rawValue }
}

struct ProcessesView: View {
    @StateObject private var monitor = ProcessMonitor()

    @State private var search = ""
    @State private var sort: ProcessSort = .cpu
    @State private var selectedProcess: ProcessRecord?

    private var filteredProcesses: [ProcessRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)

        let filtered = monitor.processes.filter { process in
            query.isEmpty
                || process.name.localizedCaseInsensitiveContains(query)
                || process.path.localizedCaseInsensitiveContains(query)
                || String(process.pid).contains(query)
        }

        switch sort {
        case .cpu:
            return filtered.sorted { $0.cpuPercent > $1.cpuPercent }
        case .memory:
            return filtered.sorted { $0.memoryBytes > $1.memoryBytes }
        case .name:
            return filtered.sorted {
                $0.name.localizedStandardCompare($1.name)
                    == .orderedAscending
            }
        case .pid:
            return filtered.sorted { $0.pid < $1.pid }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Process Explorer")
                        .font(.title2.bold())

                    Text("\(filteredProcesses.count) visible processes")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Sort", selection: $sort) {
                    ForEach(ProcessSort.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .frame(width: 155)

                Button {
                    monitor.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh processes")
            }

            TextField("Search processes, PID or path", text: $search)
                .textFieldStyle(.roundedBorder)

            Table(filteredProcesses, selection: $selectedPID) {
                TableColumn("Name") { process in
                    HStack(spacing: 8) {
                        Image(systemName: "app")
                            .foregroundStyle(.secondary)

                        Text(process.name)
                            .lineLimit(1)
                    }
                }

                TableColumn("PID") { process in
                    Text("\(process.pid)")
                        .monospacedDigit()
                }
                .width(65)

                TableColumn("CPU") { process in
                    Text(
                        String(format: "%.1f%%", process.cpuPercent)
                    )
                    .monospacedDigit()
                }
                .width(85)

                TableColumn("Memory") { process in
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: Int64(
                                min(
                                    process.memoryBytes,
                                    UInt64(Int64.max)
                                )
                            ),
                            countStyle: .memory
                        )
                    )
                    .monospacedDigit()
                }
                .width(110)

                TableColumn("User ID") { process in
                    Text("\(process.userID)")
                        .monospacedDigit()
                }
                .width(80)
            }
            .contextMenu(forSelectionType: Int32.self) { pids in
                Button("View Details") {
                    if let pid = pids.first {
                        selectedProcess = monitor.processes.first {
                            $0.pid == pid
                        }
                    }
                }
            } primaryAction: { pids in
                if let pid = pids.first {
                    selectedProcess = monitor.processes.first {
                        $0.pid == pid
                    }
                }
            }

            HStack {
                if let updated = monitor.lastUpdated {
                    Text("Updated: \(updated.formatted(date: .omitted, time: .standard))")
                }

                Spacer()

                Text("Refreshes every 2 seconds")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .sheet(item: $selectedProcess) { process in
            ProcessDetailsView(process: process)
        }
    }

    @State private var selectedPID: Int32?
}

private struct ProcessDetailsView: View {
    let process: ProcessRecord

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(process.name)
                    .font(.title2.bold())

                Spacer()

                Button("Close") {
                    dismiss()
                }
            }

            detail("PID", "\(process.pid)")
            detail("Parent PID", "\(process.parentPID)")
            detail("User ID", "\(process.userID)")
            detail(
                "CPU",
                String(format: "%.2f%%", process.cpuPercent)
            )
            detail(
                "Memory",
                ByteCountFormatter.string(
                    fromByteCount: Int64(
                        min(
                            process.memoryBytes,
                            UInt64(Int64.max)
                        )
                    ),
                    countStyle: .memory
                )
            )

            VStack(alignment: .leading, spacing: 5) {
                Text("Executable Path")
                    .foregroundStyle(.secondary)

                Text(
                    process.path.isEmpty
                        ? "Unavailable"
                        : process.path
                )
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 560, height: 350)
    }

    private func detail(
        _ label: String,
        _ value: String
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .textSelection(.enabled)
        }
    }
}
