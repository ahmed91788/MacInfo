import SwiftUI
import AppKit

struct SecurityMonitoringView: View {

    @EnvironmentObject private var store:
        SecurityMonitoringStore

    @State private var search = ""
    @State private var selectedCategory = "All"
    @State private var selectedLevel = "All"

    @State private var selectedID: UUID?
    @State private var selectedEvent: MonitoringEvent?

    @State private var showClearConfirmation = false
    @State private var showResetConfirmation = false
    @State private var showWarnings = false

    private let intervals = [
        1, 5, 10, 15, 30, 60, 120, 360, 1440
    ]

    // MARK: - Filtered events

    private var filteredEvents: [MonitoringEvent] {
        store.events.filter { event in

            let matchesSearch =
                search.isEmpty ||
                event.name.localizedCaseInsensitiveContains(search) ||
                event.title.localizedCaseInsensitiveContains(search) ||
                event.details.joined(separator: " ")
                    .localizedCaseInsensitiveContains(search)

            let matchesCategory =
                selectedCategory == "All" ||
                event.category.rawValue == selectedCategory

            let matchesLevel =
                selectedLevel == "All" ||
                event.level.rawValue == selectedLevel

            return matchesSearch &&
                matchesCategory &&
                matchesLevel
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

            settingsPanel

            filterToolbar

            eventsTable
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .layoutPriority(1)
        }
        .padding(20)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .sheet(item: $selectedEvent) { event in
            eventDetails(event)
        }
        .sheet(isPresented: $showWarnings) {
            warningsView
        }
        .confirmationDialog(
            "Clear monitoring history?",
            isPresented: $showClearConfirmation
        ) {
            Button(
                "Clear History",
                role: .destructive
            ) {
                store.clearHistory()
            }
        } message: {
            Text(
                "Recorded events will be removed. " +
                "Monitoring snapshots will be preserved."
            )
        }
        .confirmationDialog(
            "Reset monitoring baseline?",
            isPresented: $showResetConfirmation
        ) {
            Button(
                "Reset Baseline",
                role: .destructive
            ) {
                store.resetMonitoringBaseline()
            }
        } message: {
            Text(
                "The next scan will establish a new " +
                "monitoring baseline. Event history " +
                "will be preserved."
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Security Monitoring")
                    .font(.title2.bold())

                Text(
                    "Automatically monitor security-related system changes"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(
                            store.settings.enabled
                                ? Color.green
                                : Color.secondary
                        )
                        .frame(width: 7, height: 7)

                    Text(store.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !store.scanWarnings.isEmpty {
                Button {
                    showWarnings = true
                } label: {
                    Label(
                        "Scan Coverage",
                        systemImage: "info.circle"
                    )
                }
            }

            if store.isScanning {
                Button("Cancel") {
                    store.cancelScan()
                }
            } else {
                Button {
                    store.scanNow()
                } label: {
                    Label(
                        "Scan Now",
                        systemImage: "arrow.clockwise"
                    )
                }
            }

            Button {
                store.setEnabled(
                    !store.settings.enabled
                )
            } label: {
                Label(
                    store.settings.enabled
                        ? "Pause"
                        : "Start",
                    systemImage: store.settings.enabled
                        ? "pause.fill"
                        : "play.fill"
                )
            }
        }
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                "Total Scans",
                value: String(store.state.totalScans),
                icon: "arrow.trianglehead.clockwise",
                color: .blue
            )

            summaryCard(
                "Recorded Changes",
                value: String(store.events.count),
                icon: "clock.arrow.circlepath",
                color: .blue
            )

            summaryCard(
                "Review Events",
                value: String(store.reviewCount),
                icon: "exclamationmark.triangle",
                color: .orange
            )

            summaryCard(
                "Last Scan",
                value: lastScanDescription,
                icon: "clock",
                color: .secondary
            )
        }
    }

    private var lastScanDescription: String {
        guard let date = store.state.lastScanAt else {
            return "Never"
        }

        return date.formatted(
            .relative(presentation: .named)
        )
    }

    private func summaryCard(
        _ title: String,
        value: String,
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

            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
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

    // MARK: - Settings

    private var settingsPanel: some View {
        GroupBox("Monitoring Settings") {
            VStack(alignment: .leading, spacing: 12) {

                HStack {
                    Toggle(
                        "Automatic monitoring",
                        isOn: Binding(
                            get: {
                                store.settings.enabled
                            },
                            set: {
                                store.setEnabled($0)
                            }
                        )
                    )
                    .toggleStyle(.switch)

                    Spacer()

                    Picker(
                        "Scan interval",
                        selection: Binding(
                            get: {
                                store.settings.intervalMinutes
                            },
                            set: {
                                store.setInterval($0)
                            }
                        )
                    ) {
                        ForEach(
                            intervals,
                            id: \.self
                        ) { minutes in
                            Text(intervalDescription(minutes))
                                .tag(minutes)
                        }
                    }
                    .frame(width: 230)
                }

                Divider()

                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(
                        MonitoringCategory.allCases,
                        id: \.self
                    ) { category in
                        categoryToggle(category)
                    }

                    Toggle(
                        "Desktop Notifications",
                        isOn: Binding(
                            get: {
                                store.settings.notificationsEnabled
                            },
                            set: {
                                store.setNotificationsEnabled($0)
                            }
                        )
                    )
                    .toggleStyle(.checkbox)
                }

                Divider()

                HStack {
                    if let nextScan = store.nextScanAt {
                        Label(
                            "Next scan: " +
                            nextScan.formatted(
                                date: .omitted,
                                time: .shortened
                            ),
                            systemImage: "clock"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Automatic monitoring is paused.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Reset Baseline") {
                        showResetConfirmation = true
                    }
                    .disabled(store.isScanning)

                    Button("Clear History") {
                        showClearConfirmation = true
                    }
                    .disabled(store.events.isEmpty)
                }
            }
            .padding(8)
        }
    }

    private func categoryToggle(
        _ category: MonitoringCategory
    ) -> some View {

        Toggle(
            category.rawValue,
            isOn: Binding(
                get: {
                    store.settings.categories
                        .contains(category)
                },
                set: {
                    store.setCategory(
                        category,
                        enabled: $0
                    )
                }
            )
        )
        .toggleStyle(.checkbox)
    }

    private func intervalDescription(
        _ minutes: Int
    ) -> String {

        if minutes == 1 {
            return "Every minute"
        }

        if minutes < 60 {
            return "Every \(minutes) minutes"
        }

        if minutes == 60 {
            return "Every hour"
        }

        if minutes == 1440 {
            return "Every day"
        }

        return "Every \(minutes / 60) hours"
    }

    // MARK: - Filters

    private var filterToolbar: some View {
        HStack(spacing: 12) {
            TextField(
                "Search security events...",
                text: $search
            )
            .textFieldStyle(.roundedBorder)

            Picker(
                "Category",
                selection: $selectedCategory
            ) {
                Text("All Categories")
                    .tag("All")

                ForEach(
                    MonitoringCategory.allCases,
                    id: \.rawValue
                ) { category in
                    Text(category.rawValue)
                        .tag(category.rawValue)
                }
            }
            .frame(width: 200)

            Picker(
                "Level",
                selection: $selectedLevel
            ) {
                Text("All Levels")
                    .tag("All")

                ForEach(
                    MonitoringEventLevel.allCases,
                    id: \.rawValue
                ) { level in
                    Text(level.rawValue)
                        .tag(level.rawValue)
                }
            }
            .frame(width: 130)

            Text("\(filteredEvents.count) events")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Events table

    private var eventsTable: some View {
        Table(
            filteredEvents,
            selection: $selectedID
        ) {
            TableColumn("Time") { event in
                Text(
                    event.timestamp.formatted(
                        date: .abbreviated,
                        time: .standard
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .width(min: 130, ideal: 170)

            TableColumn("Event") { event in
                HStack(spacing: 8) {
                    Image(
                        systemName: changeIcon(
                            event.change
                        )
                    )
                    .foregroundStyle(
                        changeColor(event.change)
                    )

                    Text(event.name)
                        .lineLimit(1)
                }
            }

            TableColumn("Category") { event in
                Text(event.category.rawValue)
            }
            .width(min: 100, ideal: 140)

            TableColumn("Change") { event in
                Text(event.change.rawValue)
                    .foregroundStyle(
                        changeColor(event.change)
                    )
            }
            .width(85)

            TableColumn("Level") { event in
                Text(event.level.rawValue)
                    .foregroundStyle(
                        event.level == .review
                            ? Color.orange
                            : Color.secondary
                    )
            }
            .width(75)
        }
        .contextMenu(
            forSelectionType: UUID.self
        ) { ids in
            Button("View Details") {
                openEvent(ids)
            }
            .disabled(ids.isEmpty)

        } primaryAction: { ids in
            openEvent(ids)
        }
        .overlay {
            if filteredEvents.isEmpty {
                ContentUnavailableView(
                    store.events.isEmpty
                        ? "No Security Events"
                        : "No Matching Events",
                    systemImage: "shield.checkered",
                    description: Text(
                        store.events.isEmpty
                            ? "Run a scan to establish the monitoring baseline."
                            : "Try changing the search or filters."
                    )
                )
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Event details

    private func eventDetails(
        _ event: MonitoringEvent
    ) -> some View {

        VStack(alignment: .leading, spacing: 16) {
            Label(
                event.title,
                systemImage: changeIcon(event.change)
            )
            .font(.title2.bold())

            Text(
                event.timestamp.formatted(
                    date: .abbreviated,
                    time: .standard
                )
            )
            .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox("Event Information") {
                        VStack(alignment: .leading, spacing: 10) {
                            detailRow(
                                "Name",
                                event.name
                            )

                            detailRow(
                                "Category",
                                event.category.rawValue
                            )

                            detailRow(
                                "Change",
                                event.change.rawValue
                            )

                            detailRow(
                                "Level",
                                event.level.rawValue
                            )
                        }
                        .padding(8)
                    }

                    GroupBox("Detected Changes") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(
                                Array(event.details.enumerated()),
                                id: \.offset
                            ) { entry in
                                Text(entry.element)
                                    .textSelection(.enabled)

                                Divider()
                            }
                        }
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .padding(8)
                    }

                    Text(
                        "Detected changes may be legitimate " +
                        "application updates or system changes. " +
                        "Review unexpected changes before taking action."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Button("Copy Details") {
                    let text = (
                        [event.title] + event.details
                    ).joined(separator: "\n")

                    NSPasteboard.general.clearContents()

                    NSPasteboard.general.setString(
                        text,
                        forType: .string
                    )
                }

                Spacer()

                Button("Close") {
                    selectedEvent = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 700, height: 500)
    }

    // MARK: - Scan warnings

    private var warningsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Monitoring Scan Coverage")
                .font(.title2.bold())

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(
                        Array(store.scanWarnings.enumerated()),
                        id: \.offset
                    ) { entry in
                        Label(
                            entry.element,
                            systemImage: "info.circle"
                        )
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
        .frame(width: 650, height: 400)
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
                    width: 110,
                    alignment: .leading
                )

            Text(value)
                .textSelection(.enabled)

            Spacer()
        }
    }

    private func openEvent(
        _ ids: Set<UUID>
    ) {
        selectedEvent = filteredEvents.first {
            ids.contains($0.id)
        }
    }

    private func changeIcon(
        _ change: MonitoringChangeType
    ) -> String {

        switch change {
        case .added:
            return "plus.circle"

        case .removed:
            return "minus.circle"

        case .modified:
            return "pencil.circle"
        }
    }

    private func changeColor(
        _ change: MonitoringChangeType
    ) -> Color {

        switch change {
        case .added:
            return .blue

        case .removed:
            return .secondary

        case .modified:
            return .orange
        }
    }
}
