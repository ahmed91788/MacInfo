import Foundation

nonisolated enum MonitoringCategory:
    String, Codable, CaseIterable, Sendable {

    case applications = "Applications"
    case startup = "Startup Items"
    case extensions = "System Extensions"
    case profiles = "Configuration Profiles"
    case security = "Security Settings"
}

nonisolated enum MonitoringChangeType:
    String, Codable, CaseIterable, Sendable {

    case added = "Added"
    case removed = "Removed"
    case modified = "Modified"
}

nonisolated enum MonitoringEventLevel:
    String, Codable, CaseIterable, Sendable {

    case info = "Info"
    case review = "Review"
}

nonisolated struct MonitoringItem:
    Codable, Equatable, Sendable {

    let id: String
    let name: String
    let category: MonitoringCategory
    let attributes: [String: String]
}

nonisolated struct MonitoringEvent:
    Identifiable, Codable, Sendable {

    let id: UUID
    let timestamp: Date

    let category: MonitoringCategory
    let change: MonitoringChangeType
    let level: MonitoringEventLevel

    let name: String
    let details: [String]

    var title: String {
        "\(change.rawValue): \(name)"
    }
}

nonisolated struct MonitoringSettings:
    Codable, Sendable {

    var enabled = false

    var intervalMinutes = 15

    var notificationsEnabled = false

    var categories: Set<MonitoringCategory> =
        Set(MonitoringCategory.allCases)

    var intervalSeconds: Int {
        max(1, min(intervalMinutes, 1440)) * 60
    }
}

nonisolated struct MonitoringCategoryResult: Sendable {
    let category: MonitoringCategory
    let items: [MonitoringItem]

    let complete: Bool
    let message: String?
}

nonisolated struct MonitoringScanResult: Sendable {
    let capturedAt: Date
    let results: [MonitoringCategoryResult]
}

nonisolated struct MonitoringPersistentState:
    Codable, Sendable {

    var settings = MonitoringSettings()

    var snapshots: [
        MonitoringCategory: [MonitoringItem]
    ] = [:]

    var events: [MonitoringEvent] = []

    var totalScans = 0

    var lastScanAt: Date?

    var lastSuccessfulScanAt: Date?
}
