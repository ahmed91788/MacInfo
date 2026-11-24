import SwiftUI
import UniformTypeIdentifiers
import Charts

enum MacSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case hardware = "Hardware"
    case performance = "Performance"
    case processes = "Processes"
    case network = "Network"
    case networkReputation = "Network Reputation"
    case security = "Security"
    case signatures = "Signatures"
    case applications = "Applications"
    case startup = "Startup Items"
    case persistence = "Persistence"
    case extensions = "System Extensions"
    case profiles = "Configuration Profiles"
    case privacy = "Privacy Permissions"
    case monitoring = "Security Monitoring"
    case audit = "Security Audit"
    case baseline = "Security Baseline"
    case integrity = "File Integrity"
    case malwareReputation = "Malware Reputation"
    case reports = "Reports"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .hardware: "cpu"
        case .performance: "chart.xyaxis.line"
        case .processes: "list.bullet.rectangle"
        case .network: "network"
        case .networkReputation: "network.badge.shield.half.filled"
        case .security: "shield.lefthalf.filled"
        case .signatures: "signature"
        case .applications: "square.stack.3d.up"
        case .startup: "gearshape.2"
        case .persistence: "shield.checkered"
        case .extensions: "puzzlepiece.extension"
        case .profiles: "doc.text"
        case .privacy: "hand.raised"
        case .monitoring: "shield.checkered"
        case .audit: "checkmark.shield"
        case .baseline: "clock.arrow.circlepath"
        case .integrity: "checkmark.seal"
        case .malwareReputation: "exclamationmark.shield"
        case .reports: "doc.text"
        }
    }
}

struct ContentView: View {
    @StateObject private var monitor = SystemMonitor()
    @State private var selected: MacSection? = .overview
    @State private var performanceRange: PerformanceRange = .oneMinute
    @EnvironmentObject private var appVisibility: AppVisibilityStore

    var body: some View {
        NavigationSplitView {
            List(
                MacSection.allCases,
                selection: $selected
            ) { section in
                Label(
                    section.rawValue,
                    systemImage: section.icon
                )
                .tag(section)
            }
            .navigationTitle("MacInfo")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(
                min: 180,
                ideal: 220
            )
        } detail: {
            Group {
                if let snapshot = monitor.snapshot {
                    detail(snapshot)
                } else {
                    ProgressView("Loading system information...")
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
            .navigationTitle(selected?.rawValue ?? "MacInfo")
            .toolbar {

                ToolbarItem {
                    Button {
                        monitor.refresh()
                    } label: {
                        Label(
                            "Refresh",
                            systemImage: "arrow.clockwise"
                        )
                    }
                }

                ToolbarItem {
                    Button {
                        appVisibility.hide()
                    } label: {
                        Label(
                            "Hide to Menu Bar",
                            systemImage: "eye.slash"
                        )
                    }
                    .help(
                        "Hide MacInfo while keeping monitoring active"
                    )
                    .keyboardShortcut(
                        "h",
                        modifiers: [.command, .shift]
                    )
                }
            }
        }
        .frame(minWidth: 850, minHeight: 550)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    
    @ViewBuilder
    private func detail(_ s: MacSnapshot) -> some View {
        switch selected ?? .overview {

        case .overview:
            scrollablePage {
                overview(s)
            }

        case .hardware:
            scrollablePage {
                hardware(s)
            }

        case .performance:
            scrollablePage {
                performance(s)
            }

        case .processes:
            ProcessesView()

        case .network:
            NetworkMonitorView()
            
        case .networkReputation:
            NetworkReputationView()

        case .security:
            SecurityView()

        case .signatures:
            SignatureInspectorView()

        case .applications:
            ApplicationInventoryView()

        case .startup:
            StartupItemsView()

        case .persistence:
            AdvancedPersistenceView()

        case .extensions:
            SystemExtensionsView()

        case .profiles:
            ConfigurationProfilesView()

        case .privacy:
            PrivacyPermissionsView()
            
        case .monitoring:
            SecurityMonitoringView()

        case .audit:
            SecurityAuditView()

        case .baseline:
            SecurityBaselineView()

        case .integrity:
            FileIntegrityView()

        case .malwareReputation:
            MalwareReputationView()
            
        case .reports:
            scrollablePage {
                reports(s)
            }
        }
    }
    
    private func scrollablePage<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            content()
                .padding(24)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    private func overview(_ s: MacSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(s.computerName)
                    .font(.largeTitle.bold())

                Text("\(s.model) • \(s.macOS)")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                metricCard(
                    "CPU",
                    value: String(format: "%.1f%%", s.cpuUsage),
                    icon: "cpu",
                    fraction: s.cpuUsage / 100
                )

                metricCard(
                    "Memory",
                    value: bytes(s.usedMemory),
                    icon: "memorychip",
                    fraction: ratio(
                        s.usedMemory,
                        s.totalMemory
                    )
                )

                metricCard(
                    "Storage",
                    value: bytes(
                        UInt64(max(
                            0,
                            s.totalStorage - s.freeStorage
                        ))
                    ),
                    icon: "internaldrive",
                    fraction: s.totalStorage > 0
                        ? Double(s.totalStorage - s.freeStorage) /
                          Double(s.totalStorage)
                        : 0
                )
            }

            GroupBox("System") {
                VStack(spacing: 12) {
                    infoRow("Model", s.model)
                    infoRow("Processor", s.processor)
                    infoRow("Architecture", s.architecture)
                    infoRow("Logical CPU cores", "\(s.logicalCores)")
                    infoRow("Physical memory", bytes(s.totalMemory))
                    infoRow("Uptime", uptime(s.uptime))
                }
                .padding(8)
            }

            if let percent = s.batteryPercent {
                GroupBox("Battery") {
                    VStack(spacing: 12) {
                        infoRow("Charge", "\(percent)%")
                        infoRow(
                            "Status",
                            s.isCharging == true
                                ? "Charging"
                                : "Not charging"
                        )
                    }
                    .padding(8)
                }
            }
        }
    }

    private func hardware(_ s: MacSnapshot) -> some View {
        VStack(spacing: 16) {
            GroupBox("Computer") {
                VStack(spacing: 12) {
                    infoRow("Name", s.computerName)
                    infoRow("Model", s.model)
                    infoRow("Processor", s.processor)
                    infoRow("Architecture", s.architecture)
                    infoRow("Logical cores", "\(s.logicalCores)")
                    infoRow("macOS", s.macOS)
                }
                .padding(8)
            }

            GroupBox("Memory and Storage") {
                VStack(spacing: 12) {
                    infoRow("Installed RAM", bytes(s.totalMemory))
                    infoRow(
                        "System volume capacity",
                        bytes(UInt64(max(0, s.totalStorage)))
                    )
                    infoRow(
                        "Available space",
                        bytes(UInt64(max(0, s.freeStorage)))
                    )
                }
                .padding(8)
            }
        }
    }

    
    private func performance(_ s: MacSnapshot) -> some View {
        let samples = filteredSamples

        return VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Performance Monitor")
                        .font(.title2.bold())

                    Text("CPU and memory usage over time")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Range", selection: $performanceRange) {
                    ForEach(PerformanceRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 230)

                Button {
                    monitor.toggleMonitoring()
                } label: {
                    Label(
                        monitor.isMonitoringPaused ? "Resume" : "Pause",
                        systemImage: monitor.isMonitoringPaused
                            ? "play.fill" : "pause.fill"
                    )
                }
            }

            cpuChart(samples)

            memoryChart(samples, totalMemory: s.totalMemory)

            HStack(spacing: 14) {
                statisticCard(
                    "Current CPU",
                    value: String(format: "%.1f%%", s.cpuUsage)
                )

                statisticCard(
                    "Average CPU",
                    value: String(
                        format: "%.1f%%",
                        samples.isEmpty
                            ? 0
                            : samples.map(\.cpuUsage).reduce(0, +)
                              / Double(samples.count)
                    )
                )

                statisticCard(
                    "Peak CPU",
                    value: String(
                        format: "%.1f%%",
                        samples.map(\.cpuUsage).max() ?? 0
                    )
                )
            }

            Text(
                monitor.isMonitoringPaused
                    ? "Monitoring paused"
                    : "Updating every 2 seconds"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var filteredSamples: [PerformanceSample] {
        let history = monitor.performanceHistory

        // Anchor the range to the newest sample so pausing
        // preserves the visible history.
        guard let latest = history.last?.timestamp else {
            return []
        }

        let cutoff = latest.addingTimeInterval(
            -TimeInterval(performanceRange.rawValue)
        )

        return history.filter { $0.timestamp >= cutoff }
    }

    private func cpuChart(
        _ samples: [PerformanceSample]
    ) -> some View {
        GroupBox("CPU Usage") {
            Chart(samples) { sample in
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("CPU", sample.cpuUsage)
                )
                .foregroundStyle(
                    .blue.opacity(0.12)
                )

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("CPU", sample.cpuUsage)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.linear)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)
            .padding(8)
        }
    }

    private func memoryChart(
        _ samples: [PerformanceSample],
        totalMemory: UInt64
    ) -> some View {
        GroupBox("Memory Usage") {
            Chart(samples) { sample in
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value(
                        "Memory",
                        Double(sample.memoryUsed) / 1_073_741_824
                    )
                )
                .foregroundStyle(.purple.opacity(0.12))

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value(
                        "Memory",
                        Double(sample.memoryUsed) / 1_073_741_824
                    )
                )
                .foregroundStyle(.purple)
                .interpolationMethod(.linear)
            }
            .chartYScale(
                domain: 0...max(
                    1,
                    Double(totalMemory) / 1_073_741_824
                )
            )
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)
            .padding(8)
        }
    }

    private func statisticCard(
        _ title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .quaternary.opacity(0.4),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func network(_ s: MacSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network Interfaces")
                .font(.title2.bold())

            Text("Local IP addresses detected on this Mac")
                .foregroundStyle(.secondary)

            if s.networkInterfaces.isEmpty {
                ContentUnavailableView(
                    "No Interfaces",
                    systemImage: "network.slash"
                )
            } else {
                ForEach(s.networkInterfaces) { item in
                    HStack {
                        Image(systemName: "network")
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.headline)
                            Text(item.address)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }

                        Spacer()

                        Text(item.family)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(
                        .quaternary.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
            }
        }
    }

    private func reports(_ s: MacSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("System Report")
                .font(.title2.bold())

            Text(
                "Export the current system information as a JSON file."
            )
            .foregroundStyle(.secondary)

            Button {
                exportJSON(s)
            } label: {
                Label(
                    "Export JSON Report",
                    systemImage: "square.and.arrow.up"
                )
            }
            .buttonStyle(.borderedProminent)

            Text("Captured: \(s.capturedAt.formatted())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func metricCard(
        _ title: String,
        value: String,
        icon: String,
        fraction: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.bold())
                .monospacedDigit()

            ProgressView(value: min(1, max(0, fraction)))
                .tint(.blue)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .quaternary.opacity(0.4),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func infoRow(
        _ label: String,
        _ value: String
    ) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer(minLength: 20)

            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(
                min(value, UInt64(Int64.max))
            ),
            countStyle: .binary
        )
    }

    private func ratio(
        _ used: UInt64,
        _ total: UInt64
    ) -> Double {
        guard total > 0 else { return 0 }
        return min(1, Double(used) / Double(total))
    }

    private func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        return "\(days)d \(hours)h \(minutes)m"
    }

    private func exportJSON(_ snapshot: MacSnapshot) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MacInfo-Report.json"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys
            ]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
