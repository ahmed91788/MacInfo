
import SwiftUI

struct SecurityBaselineView: View {
    @StateObject private var store = SecurityBaselineStore()

    @State private var search = ""
    @State private var selectedType = "All"

    private var filteredChanges: [BaselineChange] {
        guard let comparison = store.comparison else {
            return []
        }

        return comparison.changes.filter { change in
            let matchesType =
                selectedType == "All" ||
                change.type.rawValue == selectedType

            let matchesSearch =
                search.isEmpty ||
                change.name.localizedCaseInsensitiveContains(search) ||
                change.details.localizedCaseInsensitiveContains(search)

            return matchesType && matchesSearch
        }
    }
    
    
    private var integrityStatistics: (
        verified: Int,
        changed: Int,
        unavailable: Int
    ) {
        guard let current = store.current else {
            return (0, 0, 0)
        }

        let verified = current.fileHashes.filter {
            $0.result.status == .success
        }.count

        let unavailable = current.fileHashes.filter {
            $0.result.status != .success
        }.count

        let changed = store.comparison?.changes.filter {
            $0.category == "File Integrity" &&
            $0.details.hasPrefix("SHA-256 changed:")
        }.count ?? 0

        return (verified, changed, unavailable)
    }


    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Security Baseline")
                        .font(.title2.bold())

                    Text("Detect changes to applications and startup services")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Create Baseline") {
                    store.createBaseline()
                }
                .disabled(store.isScanning)

                Button("Compare Now") {
                    store.compareWithBaseline()
                }
                .disabled(store.isScanning || store.baseline == nil)
            }

            if let baseline = store.baseline {
                Text(
                    "Baseline created: " +
                    baseline.createdAt.formatted(
                        date: .abbreviated,
                        time: .standard
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if store.isScanning {
                ProgressView("Scanning applications and startup services...")
            }

            if let error = store.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }

            if let comparison = store.comparison {
                HStack(spacing: 12) {
                    summaryCard(
                        "Added",
                        comparison.count(.added),
                        .orange
                    )

                    summaryCard(
                        "Modified",
                        comparison.count(.modified),
                        .yellow
                    )

                    summaryCard(
                        "Removed",
                        comparison.count(.removed),
                        .blue
                    )
                }

                HStack {
                    TextField("Search changes", text: $search)
                        .textFieldStyle(.roundedBorder)

                    Picker("Change", selection: $selectedType) {
                        Text("All").tag("All")
                        Text("Added").tag("Added")
                        Text("Modified").tag("Modified")
                        Text("Removed").tag("Removed")
                    }
                    .frame(width: 150)
                }
                
                
                HStack(spacing: 12) {
                    summaryCard(
                        "Hashed",
                        integrityStatistics.verified,
                        .green
                    )

                    summaryCard(
                        "Hash Changed",
                        integrityStatistics.changed,
                        .red
                    )

                    summaryCard(
                        "Unavailable",
                        integrityStatistics.unavailable,
                        .orange
                    )
                }


                Table(filteredChanges) {
                    TableColumn("Change") { change in
                        Text(change.type.rawValue)
                    }
                    .width(90)

                    TableColumn("Category", value: \.category)
                        .width(110)

                    TableColumn("Object", value: \.name)

                    TableColumn("Details", value: \.details)
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            } else {
                ContentUnavailableView(
                    "No Comparison",
                    systemImage: "arrow.left.arrow.right",
                    description: Text(
                        "Create a baseline, then compare it " +
                        "against a new scan."
                    )
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .padding(20)
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
}
