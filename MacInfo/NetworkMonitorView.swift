
import SwiftUI
import Charts

struct NetworkMonitorView: View {
    @StateObject private var monitor = NetworkMonitor()
    @State private var selectedRange = 60
    @State private var selectedNetworkTab = 0

    private var visibleHistory: [NetworkSpeedSample] {
        guard let latest = monitor.history.last?.timestamp else {
            return []
        }

        let cutoff = latest.addingTimeInterval(
            -Double(selectedRange)
        )

        return monitor.history.filter {
            $0.timestamp >= cutoff
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack {
                Picker("Network View", selection: $selectedNetworkTab) {
                    Text("Traffic").tag(0)
                    Text("Connections").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                if selectedNetworkTab == 0 {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Network Monitor")
                                .font(.title2.bold())

                            Text("Live interface traffic and throughput")
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Picker("History", selection: $selectedRange) {
                            Text("1 min").tag(60)
                            Text("5 min").tag(300)
                            Text("10 min").tag(600)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 230)

                        Button {
                            monitor.refresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Refresh network statistics")
                    }

                    HStack(spacing: 14) {
                        speedCard(
                            title: "Download",
                            speed: monitor.totalDownloadSpeed,
                            icon: "arrow.down.circle.fill",
                            color: .blue
                        )

                        speedCard(
                            title: "Upload",
                            speed: monitor.totalUploadSpeed,
                            icon: "arrow.up.circle.fill",
                            color: .green
                        )
                    }

                    GroupBox("Network Traffic") {
                        Chart {
                            ForEach(visibleHistory) { sample in
                                LineMark(
                                    x: .value("Time", sample.timestamp),
                                    y: .value(
                                        "Speed",
                                        sample.downloadBytesPerSecond / 1_048_576
                                    ),
                                    series: .value("Direction", "Download")
                                )
                                .foregroundStyle(.blue)

                                LineMark(
                                    x: .value("Time", sample.timestamp),
                                    y: .value(
                                        "Speed",
                                        sample.uploadBytesPerSecond / 1_048_576
                                    ),
                                    series: .value("Direction", "Upload")
                                )
                                .foregroundStyle(.green)
                            }
                        }
                        .chartYAxisLabel("MiB/s")
                        .frame(height: 240)
                        .padding(8)
                    }

                    Text("Network Interfaces")
                        .font(.headline)

                    Table(monitor.interfaces) {
                        TableColumn("Interface") { item in
                            Text(item.name)
                                .fontWeight(.medium)
                        }

                        TableColumn("IP Address") { item in
                            Text(item.address.isEmpty ? "—" : item.address)
                                .monospaced()
                        }

                        TableColumn("Status") { item in
                            Label(
                                item.isUp ? "Up" : "Down",
                                systemImage: item.isUp
                                    ? "checkmark.circle.fill"
                                    : "xmark.circle"
                            )
                            .foregroundStyle(
                                item.isUp ? .green : .secondary
                            )
                        }

                        TableColumn("Download") { item in
                            Text(formatSpeed(item.downloadSpeed))
                                .monospacedDigit()
                        }

                        TableColumn("Upload") { item in
                            Text(formatSpeed(item.uploadSpeed))
                                .monospacedDigit()
                        }
                    }
                    .frame(minHeight: 220)

                    if let updated = monitor.lastUpdated {
                        Text(
                            "Last updated: " +
                            updated.formatted(date: .omitted, time: .standard)
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    NetworkConnectionsView()
                }
            }
        }
        .padding(20)
    }

    private func speedCard(
        title: String,
        speed: Double,
        icon: String,
        color: Color
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .foregroundStyle(.secondary)

                Text(formatSpeed(speed))
                    .font(.title2.bold())
                    .monospacedDigit()
            }

            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            .quaternary.opacity(0.4),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_048_576 {
            return String(
                format: "%.2f MiB/s",
                bytesPerSecond / 1_048_576
            )
        }

        if bytesPerSecond >= 1024 {
            return String(
                format: "%.1f KiB/s",
                bytesPerSecond / 1024
            )
        }

        return String(
            format: "%.0f B/s",
            bytesPerSecond
        )
    }
}
