
import SwiftUI
import AppKit

struct SystemExtensionsView: View {

    @StateObject private var store =
        SystemExtensionStore()

    @State private var selectedTab: ExtensionTab = .system
    @State private var search = ""
    @State private var reviewOnly = false
    @State private var selectedType = "All"

    @State private var selectedSystemID: String?
    @State private var selectedKernelID: String?

    @State private var systemDetails:
        MacSystemExtension?

    @State private var kernelDetails:
        MacKernelExtension?

    @State private var showWarnings = false

    private enum ExtensionTab: String, CaseIterable {
        case system = "System Extensions"
        case kernel = "Kernel Extensions"
        case raw = "Raw Output"
    }

    // MARK: - Filtered data

    private var systemItems: [MacSystemExtension] {
        (store.snapshot?.systemExtensions ?? [])
            .filter { item in

                let matchesSearch =
                    search.isEmpty ||
                    item.name.localizedCaseInsensitiveContains(search) ||
                    item.bundleIdentifier.localizedCaseInsensitiveContains(search) ||
                    item.teamIdentifier.localizedCaseInsensitiveContains(search)

                let matchesType =
                    selectedType == "All" ||
                    item.type.rawValue == selectedType

                return matchesSearch &&
                    matchesType &&
                    (!reviewOnly || item.needsReview)
            }
    }

    private var kernelItems: [MacKernelExtension] {
        (store.snapshot?.kernelExtensions ?? [])
            .filter { item in

                let matchesSearch =
                    search.isEmpty ||
                    item.bundleIdentifier
                        .localizedCaseInsensitiveContains(search)

                return matchesSearch &&
                    (!reviewOnly || item.needsReview)
            }
    }

    // MARK: - Main view

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if store.isScanning {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            if let error = store.errorMessage {
                Label(
                    error,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            summaryCards

            Picker("", selection: $selectedTab) {
                ForEach(
                    ExtensionTab.allCases,
                    id: \.self
                ) { tab in
                    Text(tab.rawValue)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if selectedTab != .raw {
                filterToolbar
            }

            if store.snapshot == nil {
                emptyContent
            } else {
                tabContent
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .layoutPriority(1)
            }
        }
        .padding(20)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .sheet(item: $systemDetails) { item in
            systemDetailsView(item)
        }
        .sheet(item: $kernelDetails) { item in
            kernelDetailsView(item)
        }
        .sheet(isPresented: $showWarnings) {
            warningsView
        }
        .onAppear {
            if store.snapshot == nil {
                store.refresh()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("System Extensions")
                    .font(.title2.bold())

                Text("Inspect system-level extensions and drivers")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let snapshot = store.snapshot {
                    Text(
                        "Last scanned: " +
                        snapshot.capturedAt.formatted(
                            date: .abbreviated,
                            time: .standard
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let snapshot = store.snapshot,
               !snapshot.warnings.isEmpty {

                Button {
                    showWarnings = true
                } label: {
                    Label(
                        "\(snapshot.warnings.count) Warnings",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
            }

            if store.isScanning {
                Button("Cancel") {
                    store.cancel()
                }
            } else {
                Button {
                    store.refresh()
                } label: {
                    Label(
                        "Refresh",
                        systemImage: "arrow.clockwise"
                    )
                }
            }
        }
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                title: "Total Extensions",
                value: store.snapshot?.totalCount,
                icon: "puzzlepiece.extension",
                color: .blue
            )

            summaryCard(
                title: "Active",
                value: store.snapshot?.activeCount,
                icon: "checkmark.circle",
                color: .green
            )

            summaryCard(
                title: "Not Confirmed Active",
                value: store.snapshot?.inactiveCount,
                icon: "pause.circle",
                color: .secondary
            )

            summaryCard(
                title: "Needs Review",
                value: store.snapshot?.reviewCount,
                icon: "exclamationmark.triangle",
                color: .orange
            )
        }
    }

    private func summaryCard(
        title: String,
        value: Int?,
        icon: String,
        color: Color
    ) -> some View {

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: icon)
                    .foregroundStyle(color)
            }

            Text(value.map { $0.formatted() } ?? "—")
                .font(.title.bold())
                .foregroundStyle(color)
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color.secondary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    // MARK: - Filters

    private var filterToolbar: some View {
        HStack(spacing: 12) {
            TextField(
                "Search extensions...",
                text: $search
            )
            .textFieldStyle(.roundedBorder)

            if selectedTab == .system {
                Picker("Type", selection: $selectedType) {
                    Text("All Types")
                        .tag("All")

                    ForEach(
                        MacExtensionType.allCases,
                        id: \.rawValue
                    ) { type in
                        Text(type.rawValue)
                            .tag(type.rawValue)
                    }
                }
                .frame(width: 200)
            }

            Toggle(
                "Needs review",
                isOn: $reviewOnly
            )
            .toggleStyle(.checkbox)

            Text("\(selectedTab == .system ? systemItems.count : kernelItems.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .system:
            systemTable

        case .kernel:
            kernelTable

        case .raw:
            rawOutputView
        }
    }

    private var emptyContent: some View {
        ContentUnavailableView(
            store.isScanning
                ? "Scanning Extensions"
                : "No Extension Inventory",
            systemImage: "puzzlepiece.extension",
            description: Text(
                store.isScanning
                    ? "Collecting system extension information..."
                    : "Click Refresh to inspect extensions."
            )
        )
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    // MARK: - System extensions table

    private var systemTable: some View {
        Table(
            systemItems,
            selection: $selectedSystemID
        ) {
            TableColumn("Extension") { item in
                HStack(spacing: 8) {
                    Image(systemName: item.type.icon)
                        .foregroundStyle(.blue)
                        .frame(width: 20)

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(item.name)
                            .fontWeight(.medium)

                        Text(item.bundleIdentifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            TableColumn("Type") { item in
                Text(item.type.rawValue)
            }
            .width(min: 90, ideal: 130)

            TableColumn(
                "Team ID",
                value: \.teamIdentifier
            )
            .width(100)

            TableColumn(
                "Version",
                value: \.version
            )
            .width(90)

            TableColumn("Status") { item in
                HStack(spacing: 5) {
                    Circle()
                        .fill(stateColor(item.state))
                        .frame(width: 7, height: 7)

                    Text(item.state.rawValue)
                        .foregroundStyle(
                            stateColor(item.state)
                        )
                }
            }
            .width(min: 100, ideal: 140)
        }
        .contextMenu(
            forSelectionType: String.self
        ) { ids in
            Button("View Details") {
                openSystemDetails(ids)
            }
            .disabled(ids.isEmpty)

            Button("Copy Bundle Identifier") {
                if let item = systemItems.first(
                    where: { ids.contains($0.id) }
                ) {
                    copy(item.bundleIdentifier)
                }
            }
            .disabled(ids.isEmpty)

        } primaryAction: { ids in
            openSystemDetails(ids)
        }
    }

    // MARK: - Kernel extensions table

    private var kernelTable: some View {
        Table(
            kernelItems,
            selection: $selectedKernelID
        ) {
            TableColumn("Bundle Identifier") { item in
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .foregroundStyle(
                            item.needsReview
                                ? Color.orange
                                : Color.secondary
                        )

                    Text(item.bundleIdentifier)
                        .lineLimit(1)
                }
            }

            TableColumn(
                "Version",
                value: \.version
            )
            .width(100)

            TableColumn("Identifier Type") { item in
                Text(
                    item.isAppleIdentifier
                        ? "Apple Namespace"
                        : "Third-party / Other"
                )
                .foregroundStyle(
                    item.needsReview
                        ? Color.orange
                        : Color.secondary
                )
            }
            .width(min: 100, ideal: 140)

            TableColumn("References") { item in
                Text(item.referenceCount.formatted())
                    .monospacedDigit()
            }
            .width(80)

            TableColumn("Status") { _ in
                Label(
                    "Loaded",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            }
            .width(90)
        }
        .contextMenu(
            forSelectionType: String.self
        ) { ids in
            Button("View Details") {
                openKernelDetails(ids)
            }
            .disabled(ids.isEmpty)

            Button("Copy Bundle Identifier") {
                if let item = kernelItems.first(
                    where: { ids.contains($0.id) }
                ) {
                    copy(item.bundleIdentifier)
                }
            }
            .disabled(ids.isEmpty)

        } primaryAction: { ids in
            openKernelDetails(ids)
        }
    }

    // MARK: - Raw output

    private var rawOutputView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let snapshot = store.snapshot {
                    commandOutput(snapshot.systemCommand)
                    commandOutput(snapshot.kernelCommand)
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
    }

    private func commandOutput(
        _ result: ExtensionCommandResult
    ) -> some View {

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "terminal")

                Text(result.command)
                    .font(
                        .system(
                            .caption,
                            design: .monospaced
                        )
                    )

                Spacer()

                Text(
                    result.timedOut
                        ? "Timed Out"
                        : "Exit: \(result.exitCode.map { String($0) } ?? "N/A")"
                )
                .font(.caption)
                .foregroundStyle(
                    result.succeeded
                        ? Color.green
                        : Color.orange
                )

                Button {
                    copy(
                        result.output +
                        "\n" +
                        result.errorOutput
                    )
                } label: {
                    Label(
                        "Copy",
                        systemImage: "doc.on.doc"
                    )
                }
            }

            Divider()

            Text(
                result.output.isEmpty
                    ? "No standard output."
                    : result.output
            )
            .font(
                .system(
                    .caption,
                    design: .monospaced
                )
            )
            .textSelection(.enabled)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )

            if !result.errorOutput.isEmpty {
                Divider()

                Text("Standard Error")
                    .font(.caption.bold())

                Text(result.errorOutput)
                    .font(
                        .system(
                            .caption,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(
            Color.secondary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: - System extension details

    private func systemDetailsView(
        _ item: MacSystemExtension
    ) -> some View {

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: item.type.icon)
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.title2.bold())

                    Text(item.bundleIdentifier)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox("Extension Information") {
                        VStack(spacing: 10) {
                            detailRow(
                                "Type",
                                item.type.rawValue
                            )

                            detailRow(
                                "Bundle Identifier",
                                item.bundleIdentifier
                            )

                            detailRow(
                                "Team Identifier",
                                item.teamIdentifier
                            )

                            detailRow(
                                "Version",
                                item.version
                            )

                            detailRow(
                                "Status",
                                item.state.rawValue
                            )

                            detailRow(
                                "Raw State",
                                item.rawState
                            )
                        }
                        .padding(8)
                    }

                    GroupBox("Security Review") {
                        VStack(
                            alignment: .leading,
                            spacing: 10
                        ) {
                            if item.reviewReasons.isEmpty {
                                Label(
                                    "No registration-state warnings",
                                    systemImage: "checkmark.circle"
                                )
                                .foregroundStyle(.green)
                            } else {
                                ForEach(
                                    item.reviewReasons,
                                    id: \.self
                                ) { reason in
                                    Label(
                                        reason,
                                        systemImage:
                                            "exclamationmark.triangle"
                                    )
                                    .foregroundStyle(.orange)
                                }
                            }

                            Text(
                                "Registration metadata does not " +
                                "independently verify the extension's " +
                                "code signature or safety."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .padding(8)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Button("Copy Bundle ID") {
                    copy(item.bundleIdentifier)
                }

                Spacer()

                Button("Close") {
                    systemDetails = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 650, height: 480)
    }

    // MARK: - Kernel extension details

    private func kernelDetailsView(
        _ item: MacKernelExtension
    ) -> some View {

        VStack(alignment: .leading, spacing: 16) {
            Label(
                "Kernel Extension",
                systemImage: "cpu"
            )
            .font(.title2.bold())

            Text(item.bundleIdentifier)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox("Extension Information") {
                        VStack(spacing: 10) {
                            detailRow(
                                "Bundle Identifier",
                                item.bundleIdentifier
                            )

                            detailRow(
                                "Version",
                                item.version
                            )

                            detailRow(
                                "Index",
                                String(item.index)
                            )

                            detailRow(
                                "Reference Count",
                                String(item.referenceCount)
                            )

                            detailRow(
                                "Address",
                                item.address
                            )

                            detailRow(
                                "Size",
                                item.size
                            )

                            detailRow(
                                "UUID",
                                item.uuid ?? "Unavailable"
                            )

                            detailRow(
                                "Status",
                                "Loaded"
                            )
                        }
                        .padding(8)
                    }

                    if item.needsReview {
                        GroupBox("Security Review") {
                            Label(
                                "Loaded extension outside the Apple " +
                                "bundle identifier namespace. " +
                                "Verify its origin if unexpected.",
                                systemImage:
                                    "exclamationmark.triangle"
                            )
                            .foregroundStyle(.orange)
                            .padding(8)
                        }
                    }

                    GroupBox("Raw Information") {
                        Text(item.rawLine)
                            .font(
                                .system(
                                    .caption,
                                    design: .monospaced
                                )
                            )
                            .textSelection(.enabled)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                            .padding(8)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Button("Copy Bundle ID") {
                    copy(item.bundleIdentifier)
                }

                Spacer()

                Button("Close") {
                    kernelDetails = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 650, height: 520)
    }

    // MARK: - Warnings

    private var warningsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan Warnings")
                .font(.title2.bold())

            Text(
                "Some diagnostic information may be incomplete."
            )
            .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(
                        Array(
                            (store.snapshot?.warnings ?? [])
                                .enumerated()
                        ),
                        id: \.offset
                    ) { entry in
                        Label(
                            entry.element,
                            systemImage:
                                "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }

            HStack {
                Spacer()

                Button("Close") {
                    showWarnings = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 650, height: 420)
    }

    // MARK: - Helpers

    private func detailRow(
        _ title: String,
        _ value: String
    ) -> some View {

        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(
                    width: 140,
                    alignment: .leading
                )

            Text(value)
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
        }
        .font(.callout)
    }

    private func stateColor(
        _ state: MacExtensionState
    ) -> Color {

        switch state {
        case .activated:
            return .green

        case .pendingApproval:
            return .orange

        case .pendingRemoval:
            return .orange

        case .inactive:
            return .secondary

        case .unknown:
            return .secondary
        }
    }

    private func openSystemDetails(
        _ ids: Set<String>
    ) {
        systemDetails = systemItems.first {
            ids.contains($0.id)
        }
    }

    private func openKernelDetails(
        _ ids: Set<String>
    ) {
        kernelDetails = kernelItems.first {
            ids.contains($0.id)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()

        NSPasteboard.general.setString(
            text,
            forType: .string
        )
    }
}
