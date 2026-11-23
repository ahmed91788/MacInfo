
import SwiftUI

struct SecurityView: View {
    @StateObject private var monitor = SecurityMonitor()
    @State private var selectedCheck: SecurityCheck?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Security Inspector")
                        .font(.title2.bold())

                    Text("macOS security configuration and code signing")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    monitor.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(monitor.isRefreshing)
            }

            if monitor.isRefreshing && monitor.snapshot == nil {
                ProgressView("Checking security settings...")
                    .frame(maxWidth: .infinity, minHeight: 180)
            }

            if let snapshot = monitor.snapshot {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: 14
                ) {
                    ForEach(snapshot.checks) { check in
                        Button {
                            selectedCheck = check
                        } label: {
                            securityCard(check)
                        }
                        .buttonStyle(.plain)
                    }
                }

                GroupBox("Application Signing") {
                    VStack(alignment: .leading, spacing: 12) {
                        detail(
                            "Bundle Identifier",
                            snapshot.signingIdentifier ?? "Unavailable"
                        )

                        detail(
                            "Team Identifier",
                            snapshot.teamIdentifier ?? "Unavailable"
                        )

                        detail(
                            "Hardened Runtime",
                            snapshot.hardenedRuntime.map {
                                $0 ? "Enabled" : "Disabled"
                            } ?? "Unavailable"
                        )
                    }
                    .padding(10)
                }

                Text(
                    "Last checked: " +
                    snapshot.checkedAt.formatted(
                        date: .abbreviated,
                        time: .standard
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .onAppear {
            if monitor.snapshot == nil {
                monitor.refresh()
            }
        }
        .sheet(item: $selectedCheck) { check in
            SecurityCheckDetailsView(check: check)
        }
    }

    private func securityCard(_ check: SecurityCheck) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon(for: check.status))
                .font(.title2)
                .foregroundStyle(color(for: check.status))

            VStack(alignment: .leading, spacing: 5) {
                Text(check.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(check.status.rawValue)
                    .foregroundStyle(color(for: check.status))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .quaternary.opacity(0.4),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func detail(
        _ title: String,
        _ value: String
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .textSelection(.enabled)
        }
    }

    private func icon(for status: SecurityStatus) -> String {
        switch status {
        case .enabled: "checkmark.shield.fill"
        case .disabled: "exclamationmark.shield.fill"
        case .unavailable, .unknown: "questionmark.shield"
        }
    }

    private func color(for status: SecurityStatus) -> Color {
        switch status {
        case .enabled: .green
        case .disabled: .orange
        case .unavailable, .unknown: .secondary
        }
    }
}

private struct SecurityCheckDetailsView: View {
    let check: SecurityCheck

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(check.title)
                    .font(.title2.bold())

                Spacer()

                Button("Close") {
                    dismiss()
                }
            }

            LabeledContent("Status", value: check.status.rawValue)

            Text("Diagnostic Output")
                .font(.headline)

            ScrollView {
                Text(check.details)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                .quaternary.opacity(0.4),
                in: RoundedRectangle(cornerRadius: 8)
            )

            Text("Recommendation")
                .font(.headline)

            Text(check.recommendation)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 580, height: 420)
    }
}
