
import Foundation

enum SecurityAuditEngine {
    static func securityFindings(
        from snapshot: SecuritySnapshot
    ) -> [AuditFinding] {
        var findings: [AuditFinding] = []

        for check in snapshot.checks {
            guard check.status == .disabled else {
                continue
            }

            let severity: AuditSeverity

            switch check.id {
            case "sip", "filevault", "gatekeeper":
                severity = .high
            case "firewall":
                severity = .medium
            default:
                severity = .low
            }

            findings.append(
                AuditFinding(
                    id: "security.\(check.id)",
                    category: "System Security",
                    title: "\(check.title) disabled",
                    severity: severity,
                    details: check.details,
                    evidence: check.status.rawValue,
                    recommendation: check.recommendation
                )
            )
        }

        return findings
    }

    static func applicationFindings(
        from applications: [InstalledApplication]
    ) -> [AuditFinding] {
        var findings: [AuditFinding] = []

        for app in applications {
            let severity: AuditSeverity
            let title: String

            switch app.signature {
            case .invalid:
                severity = .high
                title = "Invalid application signature"

            case .unsigned:
                severity = .medium
                title = "Unsigned application"

            case .adHoc:
                severity = .low
                title = "Ad-hoc signed application"

            default:
                continue
            }

            findings.append(
                AuditFinding(
                    id: "application.\(app.path)",
                    category: "Applications",
                    title: title,
                    severity: severity,
                    details: app.name,
                    evidence: app.path,
                    recommendation:
                        "Verify the application's origin and integrity."
                )
            )
        }

        return findings
    }

    static func persistenceFindings(
        from items: [StartupItem]
    ) -> [AuditFinding] {
        var findings: [AuditFinding] = []

        for item in items {
            for reason in item.reviewReasons {
                let normalized = reason.lowercased()
                let severity: AuditSeverity

                if normalized.contains("invalid") {
                    severity = .high
                } else if normalized.contains("temporary") {
                    severity = .medium
                } else if normalized.contains("unsigned") {
                    severity = .medium
                } else {
                    severity = .low
                }

                findings.append(
                    AuditFinding(
                        id: "startup.\(item.id).\(reason)",
                        category: "Persistence",
                        title: reason,
                        severity: severity,
                        details: item.label,
                        evidence:
                            "\(item.plistPath)\n\(item.executablePath)",
                        recommendation:
                            "Review the startup configuration and " +
                            "confirm that the executable is expected."
                    )
                )
            }
        }

        return findings
    }

    static func scan(
        progress: @Sendable @escaping (AuditProgress) -> Void
    ) -> AuditReport {
        var findings: [AuditFinding] = []
        var scannerResults: [AuditScannerResult] = []

        var applicationCount = 0
        var startupCount = 0
        var completed = 0

        let total = AuditScannerID.allCases.count

        func notify(_ name: String) {
            progress(
                AuditProgress(
                    completed: completed,
                    total: total,
                    currentScanner: name
                )
            )
        }

        func record(
            _ scanner: AuditScannerID,
            state: AuditScannerState,
            count: Int,
            message: String? = nil
        ) {
            scannerResults.append(
                AuditScannerResult(
                    scanner: scanner,
                    state: state,
                    itemCount: count,
                    message: message
                )
            )

            completed += 1
            notify(scanner.title)
        }

        // MARK: System security

        notify("System Security")

        if Task<Never, Never>.isCancelled {
            record(
                .systemSecurity,
                state: .cancelled,
                count: 0
            )
        } else {
            let snapshot = SecurityCollector.collect()

            findings += securityFindings(from: snapshot)

            record(
                .systemSecurity,
                state: .completed,
                count: snapshot.checks.count
            )
        }

        // MARK: Applications

        if Task<Never, Never>.isCancelled {
            record(
                .applications,
                state: .cancelled,
                count: 0
            )
        } else {
            notify("Applications")

            let applications = ApplicationScanner.scan()
            applicationCount = applications.count

            findings += applicationFindings(
                from: applications
            )

            record(
                .applications,
                state: .completed,
                count: applications.count
            )
        }

        // MARK: Persistence

        if Task<Never, Never>.isCancelled {
            record(
                .persistence,
                state: .cancelled,
                count: 0
            )
        } else {
            notify("Startup Persistence")

            let items = StartupScanner.scan()
            startupCount = items.count

            findings += persistenceFindings(
                from: items
            )

            record(
                .persistence,
                state: .completed,
                count: items.count
            )
        }

        findings.sort {
            if $0.severity.rank != $1.severity.rank {
                return $0.severity.rank < $1.severity.rank
            }

            return $0.title < $1.title
        }

        return AuditReport(
            id: UUID(),
            createdAt: Date(),
            computerName: Host.current().localizedName ?? "Mac",
            macOSVersion:
                ProcessInfo.processInfo.operatingSystemVersionString,
            applicationCount: applicationCount,
            startupItemCount: startupCount,
            findings: findings,
            scanners: scannerResults
        )
    }
}
