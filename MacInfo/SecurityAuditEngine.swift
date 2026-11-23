
import Foundation

enum SecurityAuditEngine {
    static func scan() -> AuditReport {
        let security = SecurityCollector.collect()
        let applications = ApplicationScanner.scan()
        let startupItems = StartupScanner.scan()

        var findings: [AuditFinding] = []

        // MARK: System security checks

        for check in security.checks {
            guard check.status == .disabled else {
                continue
            }

            let severity: AuditSeverity

            switch check.id.lowercased() {
            case "sip":
                severity = .high
            case "filevault":
                severity = .high
            case "gatekeeper":
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

        // MARK: Application signatures

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

        // MARK: Startup persistence

        for item in startupItems {
            for reason in item.reviewReasons {
                let severity: AuditSeverity

                if reason.contains("invalid") {
                    severity = .high
                } else if reason.contains("temporary") {
                    severity = .medium
                } else if reason.contains("unsigned") {
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
            applicationCount: applications.count,
            startupItemCount: startupItems.count,
            findings: findings
        )
    }
}
