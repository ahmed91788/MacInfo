
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SecurityAuditView: View {
    @StateObject private var store = SecurityAuditStore()

    @State private var selectedSeverity = "All"
    @State private var search = ""
    @State private var selectedFinding: AuditFinding?
    @State private var selectedFindingID: String?

    private var filteredFindings: [AuditFinding] {
        guard let report = store.currentReport else {
            return []
        }

        return report.findings.filter { finding in
            let matchesSeverity =
                selectedSeverity == "All" ||
                finding.severity.rawValue == selectedSeverity

            let matchesSearch =
                search.isEmpty ||
                finding.title.localizedCaseInsensitiveContains(search) ||
                finding.details.localizedCaseInsensitiveContains(search) ||
                finding.evidence.localizedCaseInsensitiveContains(search)

            return matchesSeverity && matchesSearch
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Security Audit")
                        .font(.title2.bold())

                    Text("System security and persistence assessment")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let report = store.currentReport {
                    Menu("Export") {
                        Button("Export JSON") {
                            export(report, asHTML: false)
                        }

                        Button("Export HTML") {
                            export(report, asHTML: true)
                        }
                    }
                }

                if store.isScanning {
                    Button {
                        store.cancelScan()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                } else {
                    Button {
                        store.scan()
                    } label: {
                        Label("Run Audit", systemImage: "shield.checkered")
                    }
                }

            }
            
            if store.isScanning {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: store.progress.fraction)

                    HStack {
                        Text(store.progress.currentScanner)

                        Spacer()

                        Text(
                            "\(store.progress.completed) / \(store.progress.total)"
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }


            if store.isScanning {
                ProgressView("Running security audit...")
            }

            if let error = store.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }

            if let report = store.currentReport {
                reportContent(report)
            } else if !store.isScanning {
                ContentUnavailableView(
                    "No Security Audit",
                    systemImage: "shield",
                    description: Text(
                        "Run an audit to inspect security settings, " +
                        "applications and startup persistence."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .sheet(item: $selectedFinding) { finding in
            findingDetails(finding)
        }
    }

    private func reportContent(_ report: AuditReport) -> some View {
        let previous = store.history.first {
            $0.id != report.id
        }

        let comparison = previous.map {
            AuditComparison.compare(
                current: report,
                previous: $0
            )
        }
        
        return VStack(alignment: .leading, spacing: 12) {
            
            GroupBox("Scanner Coverage") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(report.scanners) { scanner in
                        HStack {
                            Image(
                                systemName: scanner.state == .completed
                                    ? "checkmark.circle.fill"
                                    : "exclamationmark.circle.fill"
                            )
                            .foregroundStyle(
                                scanner.state == .completed
                                    ? .green
                                    : .orange
                            )

                            Text(scanner.scanner.title)

                            Spacer()

                            Text(scanner.state.rawValue.capitalized)
                                .foregroundStyle(.secondary)

                            Text("\(scanner.itemCount)")
                                .monospacedDigit()
                        }
                    }
                }
                .padding(8)
            }

            HStack(spacing: 12) {
                ForEach(
                    [
                        AuditSeverity.critical,
                        .high,
                        .medium,
                        .low
                    ],
                    id: \.rawValue
                ) { severity in
                    summaryCard(
                        severity.rawValue,
                        report.count(severity),
                        severityColor(severity)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Heuristic Security Score")
                        .fontWeight(.medium)

                    Spacer()

                    Text(
                        report.score.map { "\($0) / 100" }
                        ?? "N/A — Incomplete Scan"
                    )
                        .font(.title3.bold())
                }

                if let score = report.score {
                    ProgressView(value: Double(score), total: 100)
                        .tint(scoreColor(score))
                }

                Text(
                    "\(report.applicationCount) applications · " +
                    "\(report.startupItemCount) startup items · " +
                    "\(report.findings.count) findings"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                TextField("Search findings", text: $search)
                    .textFieldStyle(.roundedBorder)

                Picker("Severity", selection: $selectedSeverity) {
                    Text("All").tag("All")

                    ForEach(
                        AuditSeverity.allCases,
                        id: \.rawValue
                    ) { severity in
                        Text(severity.rawValue)
                            .tag(severity.rawValue)
                    }
                }
                .frame(width: 150)

                Menu("History") {
                    ForEach(store.history) { previous in
                        Button {
                            store.selectReport(previous)
                        } label: {
                            Text(
                                previous.createdAt.formatted(
                                    date: .abbreviated,
                                    time: .standard
                                )
                            )
                        }
                    }
                }
            }

            Table(filteredFindings, selection: $selectedFindingID) {
                TableColumn("Severity") { finding in
                    Text(finding.severity.rawValue)
                        .foregroundStyle(
                            severityColor(finding.severity)
                        )
                        .fontWeight(.medium)
                }
                .width(90)

                TableColumn("Category", value: \.category)
                    .width(130)

                TableColumn("Finding") { finding in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(finding.title)
                            .fontWeight(.medium)

                        Text(finding.details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contextMenu(forSelectionType: String.self) { ids in
                Button("View Details") {
                    guard let id = ids.first else { return }
                    selectedFinding = filteredFindings.first { $0.id == id }
                }
            } primaryAction: { ids in
                guard let id = ids.first else { return }
                selectedFinding = filteredFindings.first { $0.id == id }
            }
            
            if let comparison {
                HStack(spacing: 12) {
                    summaryCard(
                        "New",
                        comparison.newFindings.count,
                        .orange
                    )

                    summaryCard(
                        "Resolved",
                        comparison.resolvedFindings.count,
                        .green
                    )

                    summaryCard(
                        "Unchanged",
                        comparison.unchangedFindings.count,
                        .secondary
                    )
                }

                if !comparison.incomparableCategories.isEmpty {
                    Text(
                        "Some categories could not be compared " +
                        "because scanner coverage was incomplete."
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summaryCard(
        _ title: String,
        _ count: Int,
        _ color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(count.formatted())
                .font(.title.bold())
                .foregroundStyle(color)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .quaternary.opacity(0.4),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func severityColor(_ severity: AuditSeverity) -> Color {
        switch severity {
        case .critical: .red
        case .high: .orange
        case .medium: .yellow
        case .low: .blue
        case .info: .secondary
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 85 { return .green }
        if score >= 60 { return .orange }
        return .red
    }

    private func findingDetails(_ finding: AuditFinding) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(finding.title)
                    .font(.title2.bold())

                LabeledContent(
                    "Severity",
                    value: finding.severity.rawValue
                )

                LabeledContent(
                    "Category",
                    value: finding.category
                )

                Divider()

                Text("Details")
                    .font(.headline)

                Text(finding.details)
                    .textSelection(.enabled)

                Text("Evidence")
                    .font(.headline)

                Text(finding.evidence)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)

                Text("Recommendation")
                    .font(.headline)

                Text(finding.recommendation)
                    .textSelection(.enabled)
            }
            .padding(24)
        }
        .frame(width: 650, height: 460)
    }

    private func export(_ report: AuditReport, asHTML: Bool) {
        let panel = NSSavePanel()

        panel.nameFieldStringValue = asHTML
            ? "MacInfo-Security-Audit.html"
            : "MacInfo-Security-Audit.json"

        panel.allowedContentTypes = asHTML
            ? [.html]
            : [.json]

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            let data = try asHTML
                ? SecurityAuditExporter.html(report)
                : SecurityAuditExporter.json(report)

            try data.write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
