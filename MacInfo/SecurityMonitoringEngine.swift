import Foundation

nonisolated enum SecurityMonitoringEngine {

    @MainActor static func scan(
        settings: MonitoringSettings
    ) -> MonitoringScanResult {

        var results: [MonitoringCategoryResult] = []

        for category in MonitoringCategory.allCases {
            guard !Task<Never, Never>.isCancelled else {
                break
            }

            guard settings.categories.contains(category) else {
                continue
            }

            switch category {
            case .applications:
                results.append(scanApplications())

            case .startup:
                results.append(scanStartupItems())

            case .extensions:
                results.append(scanExtensions())

            case .profiles:
                results.append(scanProfiles())

            case .security:
                results.append(scanSecuritySettings())
            }
        }

        return MonitoringScanResult(
            capturedAt: Date(),
            results: results
        )
    }

    // MARK: - Applications

    @MainActor private static func scanApplications()
        -> MonitoringCategoryResult {

        let applications = ApplicationScanner.scan()

        let items = applications.map { app in
            MonitoringItem(
                id: app.path,
                name: app.name,
                category: .applications,
                attributes: [
                    "Path": app.path,
                    "Version": app.version,
                    "Bundle ID": app.bundleIdentifier,
                    "Signature": app.signature.rawValue,
                    "Team ID": app.teamIdentifier ?? "Unknown"
                ]
            )
        }

        return MonitoringCategoryResult(
            category: .applications,
            items: items,
            complete: false,
            message: """
            Application inventory does not report \
            enumeration coverage. Removal detection \
            is disabled for this category.
            """
        )
    }

    // MARK: - Startup items

    @MainActor private static func scanStartupItems()
        -> MonitoringCategoryResult {

        let startupItems = StartupScanner.scan()

        let items = startupItems.map { item in
            MonitoringItem(
                id: item.plistPath,
                name: item.label,
                category: .startup,
                attributes: [
                    "Type": item.type.rawValue,
                    "Plist": item.plistPath,
                    "Executable": item.executablePath,
                    "Arguments": item.arguments.joined(
                        separator: "\n"
                    ),
                    "Run At Load": String(item.runAtLoad),
                    "Keep Alive": String(item.keepAlive),
                    "Disabled": String(item.disabledInPlist),
                    "Signature": item.signingStatus,
                    "Team ID": item.teamIdentifier ?? "Unknown"
                ]
            )
        }

        return MonitoringCategoryResult(
            category: .startup,
            items: items,
            complete: false,
            message: """
            Startup inventory does not report \
            enumeration coverage. Removal detection \
            is disabled for this category.
            """
        )
    }

    // MARK: - System extensions

    @MainActor private static func scanExtensions()
        -> MonitoringCategoryResult {

        let snapshot = SystemExtensionScanner.scan()

        let items = snapshot.systemExtensions.map { item in
            MonitoringItem(
                id: [
                    item.type.rawValue,
                    item.teamIdentifier,
                    item.bundleIdentifier
                ].joined(separator: ":"),
                name: item.name,
                category: .extensions,
                attributes: [
                    "Type": item.type.rawValue,
                    "Bundle ID": item.bundleIdentifier,
                    "Team ID": item.teamIdentifier,
                    "Version": item.version,
                    "State": item.rawState
                ]
            )
        }

        return MonitoringCategoryResult(
            category: .extensions,
            items: items,
            complete: snapshot.isComplete,
            message: snapshot.isComplete
                ? nil
                : "Extension inventory may be incomplete."
        )
    }

    // MARK: - Configuration profiles

    private static func scanProfiles()
        -> MonitoringCategoryResult {

        let snapshot = ConfigurationProfileScanner.scan()

        var items: [MonitoringItem] = []

        for profile in snapshot.profiles {
            let payloadTypes = profile.payloads
                .map(\.type)
                .sorted()
                .joined(separator: ", ")

            items.append(
                MonitoringItem(
                    id: profile.id,
                    name: profile.name,
                    category: .profiles,
                    attributes: [
                        "Identifier": profile.identifier,
                        "Organization": profile.organization,
                        "Scope": profile.scope,
                        "Payload Types": payloadTypes,
                        "Payload Count": String(
                            profile.payloads.count
                        ),
                        "Installed": profile.installedAt
                    ]
                )
            )
        }

        return MonitoringCategoryResult(
            category: .profiles,
            items: items,
            complete: false,
            message: """
            Profile visibility depends on current \
            privileges. Removal detection is disabled.
            """
        )
    }

    // MARK: - Security settings

    @MainActor private static func scanSecuritySettings()
        -> MonitoringCategoryResult {

        let snapshot = SecurityCollector.collect()

        let availableChecks = snapshot.checks.filter {
            $0.status != .unknown &&
            $0.status != .unavailable
        }

        let items = availableChecks.map { check in
            MonitoringItem(
                id: check.id,
                name: check.title,
                category: .security,
                attributes: [
                    "Status": check.status.rawValue
                ]
            )
        }

        return MonitoringCategoryResult(
            category: .security,
            items: items,
            complete: false,
            message: availableChecks.count == snapshot.checks.count
                ? nil
                : "Some security settings were unavailable."
        )
    }

    // MARK: - Change detection

    static func compare(
        previous: [MonitoringItem],
        current: [MonitoringItem],
        allowRemovals: Bool
    ) -> [MonitoringEvent] {

        let oldItems = index(previous)
        let newItems = index(current)

        var events: [MonitoringEvent] = []

        for id in newItems.keys.sorted() {
            guard let newItem = newItems[id] else {
                continue
            }

            if let oldItem = oldItems[id] {
                if oldItem.attributes != newItem.attributes {
                    let differences = attributeChanges(
                        previous: oldItem.attributes,
                        current: newItem.attributes
                    )

                    events.append(
                        makeEvent(
                            item: newItem,
                            change: .modified,
                            details: differences
                        )
                    )
                }
            } else {
                events.append(
                    makeEvent(
                        item: newItem,
                        change: .added,
                        details: ["New inventory item detected."]
                    )
                )
            }
        }

        if allowRemovals {
            for id in oldItems.keys.sorted() {
                guard newItems[id] == nil,
                      let oldItem = oldItems[id] else {
                    continue
                }

                events.append(
                    makeEvent(
                        item: oldItem,
                        change: .removed,
                        details: [
                            "Item is no longer present in the inventory."
                        ]
                    )
                )
            }
        }

        return events
    }

    // MARK: - Snapshot merging

    static func merge(
        previous: [MonitoringItem],
        current: [MonitoringItem]
    ) -> [MonitoringItem] {

        var items = index(previous)

        for item in current {
            items[item.id] = item
        }

        return items.values.sorted {
            $0.id < $1.id
        }
    }

    private static func index(
        _ items: [MonitoringItem]
    ) -> [String: MonitoringItem] {

        var result: [String: MonitoringItem] = [:]

        for item in items {
            result[item.id] = item
        }

        return result
    }

    private static func attributeChanges(
        previous: [String: String],
        current: [String: String]
    ) -> [String] {

        let keys = Set(previous.keys)
            .union(current.keys)
            .sorted()

        return keys.compactMap { key in
            let oldValue = previous[key] ?? "Unavailable"
            let newValue = current[key] ?? "Unavailable"

            guard oldValue != newValue else {
                return nil
            }

            return "\(key): \(oldValue) → \(newValue)"
        }
    }

    private static func makeEvent(
        item: MonitoringItem,
        change: MonitoringChangeType,
        details: [String]
    ) -> MonitoringEvent {

        let level: MonitoringEventLevel

        switch item.category {
        case .startup, .extensions, .profiles, .security:
            level = .review

        case .applications:
            level = .info
        }

        return MonitoringEvent(
            id: UUID(),
            timestamp: Date(),
            category: item.category,
            change: change,
            level: level,
            name: item.name,
            details: details
        )
    }
}
