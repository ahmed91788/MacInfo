
import SwiftUI

struct FileIntegrityView: View {
    @StateObject private var store = FileIntegrityStore()

    @State private var search = ""
    @State private var selectedStatus = "All"
    @State private var selectedID: String?
    @State private var selectedResult:
        IntegrityVerificationResult?

    @State private var showSettings = false

    private var filteredResults:
        [IntegrityVerificationResult] {

        store.results.filter { result in
            let matchesStatus =
                selectedStatus == "All" ||
                result.status.rawValue == selectedStatus

            let matchesSearch =
                search.isEmpty ||
                result.name.localizedCaseInsensitiveContains(search) ||
                result.path.localizedCaseInsensitiveContains(search)

            return matchesStatus && matchesSearch
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let baseline = store.baseline {
                Text(
                    "Baseline: " +
                    baseline.createdAt.formatted(
                        date: .abbreviated,
                        time: .standard
                    ) +
                    " · \(baseline.fileHashes.count) recorded files"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if store.isScanning {
                progressContent
            }

            if store.wasCancelled {
                Label(
                    "Scan cancelled. Results are incomplete.",
                    systemImage: "exclamationmark.circle"
                )
                .foregroundStyle(.orange)
                .font(.caption)
            }

            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            summaryCards

            toolbar

            if store.results.isEmpty && !store.isScanning {
                ContentUnavailableView(
                    store.hasScanned
                        ? "No Verification Results"
                        : "No Integrity Scan",
                    systemImage: "checkmark.shield",
                    description: Text(
                        store.hasScanned
                            ? "No files were verified."
                            : "Run a scan to compare files against your baseline."
                    )
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            } else {
                resultsTable
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .layoutPriority(1)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .padding(20)
        .sheet(isPresented: $showSettings) {
            settingsView
        }
        .sheet(item: $selectedResult) { result in
            detailsView(result)
        }
        .onAppear {
            store.reloadBaseline()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("File Integrity")
                    .font(.title2.bold())

                Text("SHA-256 executable verification")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.reloadBaseline()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload baseline")
            .disabled(store.isScanning)

            Button {
                showSettings = true
            } label: {
                Label(
                    "Settings",
                    systemImage: "gearshape"
                )
            }
            .disabled(store.isScanning)

            if store.isScanning {
                Button("Cancel") {
                    store.cancel()
                }
            } else {
                Button {
                    store.scan()
                } label: {
                    Label(
                        "Scan Now",
                        systemImage: "checkmark.shield"
                    )
                }
                .disabled(store.baseline == nil)
            }
        }
    }

    // MARK: Progress

    private var progressContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.progress.total > 0 {
                ProgressView(
                    value: store.progress.fraction
                )
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            HStack {
                Text(store.progress.currentPath)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(
                    "\(store.progress.completed) / " +
                    "\(store.progress.total)"
                )
                .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Summary

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                "Matched",
                store.count(.matched),
                .green
            )

            summaryCard(
                "Changed",
                store.count(.changed),
                .red
            )

            summaryCard(
                "Missing",
                store.count(.missing),
                .orange
            )

            summaryCard(
                "Unverified",
                store.count(.unverified) +
                store.count(.skipped) +
                store.count(.cancelled) +
                store.count(.newFile),
                .secondary
            )
        }
    }

    private func summaryCard(
        _ title: String,
        _ count: Int,
        _ color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(count.formatted())
                .font(.title.bold())
                .foregroundStyle(color)
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            .quaternary.opacity(0.4),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack {
            TextField("Search files", text: $search)
                .textFieldStyle(.roundedBorder)

            Picker("Status", selection: $selectedStatus) {
                Text("All").tag("All")

                ForEach(
                    IntegrityVerificationStatus.allCases,
                    id: \.rawValue
                ) { status in
                    Text(status.rawValue)
                        .tag(status.rawValue)
                }
            }
            .frame(width: 180)

            Text("\(filteredResults.count) files")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Results table

    private var resultsTable: some View {
        Table(
            filteredResults,
            selection: $selectedID
        ) {
            TableColumn("File") { result in
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.name)
                        .fontWeight(.medium)

                    Text(result.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            TableColumn("Category", value: \.category)
                .width(100)

            TableColumn("Status") { result in
                Text(result.status.rawValue)
                    .foregroundStyle(
                        statusColor(result.status)
                    )
            }
            .width(100)

            TableColumn("Size") { result in
                if let size = result.size {
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: Int64(clamping: size),
                            countStyle: .file
                        )
                    )
                } else {
                    Text("—")
                }
            }
            .width(90)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("View Details") {
                openDetails(ids)
            }
            .disabled(ids.isEmpty)
        } primaryAction: { ids in
            openDetails(ids)
        }
    }

    private func openDetails(_ ids: Set<String>) {
        guard let id = ids.first else {
            return
        }

        selectedResult = store.results.first {
            $0.id == id
        }
    }

    private func statusColor(
        _ status: IntegrityVerificationStatus
    ) -> Color {
        switch status {
        case .matched:
            .green
        case .changed:
            .red
        case .missing:
            .orange
        case .newFile:
            .blue
        default:
            .secondary
        }
    }

    // MARK: Settings

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Integrity Scan Settings")
                .font(.title2.bold())

            GroupBox("Scan Scope") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        "Installed applications",
                        isOn: $store.options.includeApplications
                    )

                    Toggle(
                        "Startup executables",
                        isOn: $store.options.includeStartupItems
                    )

                    Toggle(
                        "Include system executables",
                        isOn: $store.options.includeSystemFiles
                    )
                }
                .padding(8)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }

            GroupBox("File Size Limit") {
                HStack {
                    Text("Maximum file size")

                    Spacer()

                    Picker(
                        "",
                        selection: $store.options.maximumFileSizeMB
                    ) {
                        Text("64 MB").tag(64)
                        Text("128 MB").tag(128)
                        Text("256 MB").tag(256)
                        Text("512 MB").tag(512)
                        Text("1 GB").tag(1024)
                        Text("2 GB").tag(2048)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                .padding(8)
            }

            Text(
                "Files exceeding the limit are skipped, " +
                "not marked as verified."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            HStack {
                Spacer()

                Button("Done") {
                    showSettings = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 360)
    }

    // MARK: Details

    private func detailsView(
        _ result: IntegrityVerificationResult
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(result.name)
                .font(.title2.bold())

            LabeledContent(
                "Status",
                value: result.status.rawValue
            )

            LabeledContent(
                "Category",
                value: result.category
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("File Path")
                        .font(.headline)

                    Text(result.path)
                        .textSelection(.enabled)

                    hashSection(
                        "Baseline SHA-256",
                        result.baselineHash
                    )

                    hashSection(
                        "Current SHA-256",
                        result.currentHash
                    )

                    if let message = result.message {
                        Text("Details")
                            .font(.headline)

                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }
            .frame(maxHeight: .infinity)

            HStack {
                Spacer()

                Button("Close") {
                    selectedResult = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 650, height: 420)
    }

    private func hashSection(
        _ title: String,
        _ hash: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)

            Text(hash ?? "Unavailable")
                .font(
                    .system(
                        .body,
                        design: .monospaced
                    )
                )
                .textSelection(.enabled)
                .padding(10)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .background(
                    .quaternary.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
    }
}
