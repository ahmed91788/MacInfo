import Foundation
import Combine
import UserNotifications

@MainActor
final class SecurityMonitoringStore: ObservableObject {

    @Published private(set) var state =
        MonitoringPersistentState()

    @Published private(set) var isScanning = false

    @Published private(set) var nextScanAt: Date?

    @Published private(set) var errorMessage: String?

    @Published private(set) var scanWarnings: [String] = []

    private var schedulerTask: Task<Void, Never>?

    private var workerTask:
        Task<MonitoringScanResult, Never>?

    private let maximumEvents = 5000

    private var storageURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/MacInfo",
                isDirectory: true
            )
            .appendingPathComponent(
                "security-monitoring.json"
            )
    }

    // MARK: - Initialization

    init() {
        load()

        if state.settings.enabled {
            restartScheduler()
        }
    }

    // MARK: - Public properties

    var settings: MonitoringSettings {
        state.settings
    }

    var events: [MonitoringEvent] {
        state.events
    }

    var reviewCount: Int {
        state.events.filter {
            $0.level == .review
        }.count
    }

    var statusText: String {
        if isScanning {
            return "Scanning"
        }

        return settings.enabled
            ? "Monitoring Active"
            : "Monitoring Paused"
    }

    // MARK: - Settings

    func updateSettings(
        _ settings: MonitoringSettings
    ) {
        let scheduleChanged =
            state.settings.enabled != settings.enabled ||
            state.settings.intervalMinutes !=
                settings.intervalMinutes

        state.settings = settings

        save()

        if scheduleChanged {
            restartScheduler()
        }
    }

    func setEnabled(_ enabled: Bool) {
        var settings = state.settings
        settings.enabled = enabled

        updateSettings(settings)
    }

    func setInterval(_ minutes: Int) {
        var settings = state.settings
        settings.intervalMinutes = minutes

        updateSettings(settings)
    }

    func setCategory(
        _ category: MonitoringCategory,
        enabled: Bool
    ) {
        var settings = state.settings

        if enabled {
            settings.categories.insert(category)
        } else {
            settings.categories.remove(category)
        }

        updateSettings(settings)
    }

    // MARK: - Scheduler

    private func restartScheduler() {
        schedulerTask?.cancel()
        schedulerTask = nil

        nextScanAt = nil

        guard state.settings.enabled else {
            return
        }

        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {

                guard let interval = self?
                    .settings.intervalSeconds else {
                    return
                }

                self?.nextScanAt = Date()
                    .addingTimeInterval(
                        TimeInterval(interval)
                    )

                do {
                    try await Task.sleep(
                        for: .seconds(interval)
                    )
                } catch {
                    return
                }

                guard !Task.isCancelled else {
                    return
                }

                self?.scanNow()
            }
        }
    }

    // MARK: - Scan

    func scanNow() {
        guard !isScanning else {
            return
        }

        guard !state.settings.categories.isEmpty else {
            errorMessage = "Select at least one monitoring category."
            return
        }

        isScanning = true
        errorMessage = nil
        scanWarnings = []

        let currentSettings = state.settings

        let worker = Task.detached(
            priority: .utility
        ) {
            await SecurityMonitoringEngine.scan(
                settings: currentSettings
            )
        }

        workerTask = worker

        Task { [weak self] in
            let result = await worker.value

            guard let self else {
                return
            }

            if !worker.isCancelled {
                self.processResult(result)
            } else {
                self.errorMessage = "Scan cancelled."
            }

            self.isScanning = false
            self.workerTask = nil
        }
    }

    func cancelScan() {
        workerTask?.cancel()
    }

    // MARK: - Process scan result

    private func processResult(
        _ result: MonitoringScanResult
    ) {
        var newEvents: [MonitoringEvent] = []

        var nextState = state

        for categoryResult in result.results {
            let category = categoryResult.category

            if let message = categoryResult.message {
                scanWarnings.append(
                    "\(category.rawValue): \(message)"
                )
            }

            guard nextState.settings.categories
                .contains(category) else {
                continue
            }

            // Do not establish an empty baseline
            // from an incomplete scan.
            if categoryResult.items.isEmpty &&
                !categoryResult.complete {

                continue
            }

            if let previous = nextState.snapshots[category] {

                let changes = SecurityMonitoringEngine.compare(
                    previous: previous,
                    current: categoryResult.items,
                    allowRemovals: categoryResult.complete
                )

                newEvents.append(contentsOf: changes)

                if categoryResult.complete {
                    nextState.snapshots[category] =
                        categoryResult.items
                } else {
                    nextState.snapshots[category] =
                        SecurityMonitoringEngine.merge(
                            previous: previous,
                            current: categoryResult.items
                        )
                }

            } else {
                // First observation establishes a baseline.
                // It does not generate hundreds of alerts.

                nextState.snapshots[category] =
                    categoryResult.items
            }
        }

        nextState.totalScans += 1
        nextState.lastScanAt = result.capturedAt

        if !result.results.isEmpty &&
            result.results.allSatisfy(\.complete) {

            nextState.lastSuccessfulScanAt =
                result.capturedAt
        }

        nextState.events.insert(
            contentsOf: newEvents.reversed(),
            at: 0
        )

        if nextState.events.count > maximumEvents {
            nextState.events = Array(
                nextState.events.prefix(maximumEvents)
            )
        }

        state = nextState

        save()

        if state.settings.notificationsEnabled {
            notify(events: newEvents)
        }
    }

    // MARK: - Notifications

    func setNotificationsEnabled(
        _ enabled: Bool
    ) {
        if !enabled {
            var settings = state.settings
            settings.notificationsEnabled = false
            updateSettings(settings)
            return
        }

        Task {
            do {
                let granted = try await
                    UNUserNotificationCenter.current()
                    .requestAuthorization(
                        options: [.alert, .sound]
                    )

                var settings = state.settings
                settings.notificationsEnabled = granted

                updateSettings(settings)

                if !granted {
                    errorMessage =
                        "Notification permission was not granted."
                }

            } catch {
                errorMessage =
                    error.localizedDescription
            }
        }
    }

    private func notify(
        events: [MonitoringEvent]
    ) {
        let reviewEvents = events.filter {
            $0.level == .review
        }

        guard !reviewEvents.isEmpty else {
            return
        }

        let content = UNMutableNotificationContent()

        content.title = "MacInfo Security Monitoring"

        if reviewEvents.count == 1,
           let event = reviewEvents.first {

            content.body = event.title

        } else {
            content.body =
                "\(reviewEvents.count) security-related changes detected."
        }

        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        Task {
            do {
                try await UNUserNotificationCenter
                    .current()
                    .add(request)
            } catch {
                errorMessage =
                    "Unable to deliver notification: " +
                    error.localizedDescription
            }
        }
    }

    // MARK: - History management

    func clearHistory() {
        state.events.removeAll()
        save()
    }

    func resetMonitoringBaseline() {
        guard !isScanning else {
            return
        }

        state.snapshots.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(
            atPath: storageURL.path
        ) else {
            return
        }

        do {
            let data = try Data(
                contentsOf: storageURL
            )

            state = try JSONDecoder().decode(
                MonitoringPersistentState.self,
                from: data
            )

        } catch {
            errorMessage =
                "Unable to load monitoring history: " +
                error.localizedDescription
        }
    }

    private func save() {
        do {
            let directory = storageURL
                .deletingLastPathComponent()

            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [
                    .posixPermissions: 0o700
                ]
            )

            let encoder = JSONEncoder()

            encoder.outputFormatting = [
                .prettyPrinted,
                .sortedKeys
            ]

            let data = try encoder.encode(state)

            try data.write(
                to: storageURL,
                options: .atomic
            )

            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: storageURL.path
            )

        } catch {
            errorMessage =
                "Unable to save monitoring history: " +
                error.localizedDescription
        }
    }

    deinit {
        schedulerTask?.cancel()
        workerTask?.cancel()
    }
}
