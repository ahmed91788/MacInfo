
import Foundation

enum AuditScannerID: String, Codable, CaseIterable, Sendable {
    case systemSecurity
    case applications
    case persistence

    var title: String {
        switch self {
        case .systemSecurity: "System Security"
        case .applications: "Applications"
        case .persistence: "Startup Persistence"
        }
    }
}

enum AuditScannerState: String, Codable, Sendable {
    case pending
    case running
    case completed
    case partial
    case failed
    case cancelled
}

struct AuditScannerResult: Identifiable, Codable, Sendable {
    let scanner: AuditScannerID
    let state: AuditScannerState
    let itemCount: Int
    let message: String?

    var id: AuditScannerID { scanner }
}

struct AuditProgress: Sendable {
    let completed: Int
    let total: Int
    let currentScanner: String

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

struct AuditComparison: Sendable {
    let newFindings: [AuditFinding]
    let resolvedFindings: [AuditFinding]
    let unchangedFindings: [AuditFinding]
    let incomparableCategories: [AuditScannerID]

    static func compare(
        current: AuditReport,
        previous: AuditReport
    ) -> AuditComparison {
        func isComplete(
            _ scanner: AuditScannerID,
            in report: AuditReport
        ) -> Bool {
            report.scanners.first {
                $0.scanner == scanner
            }?.state == .completed
        }

        let comparable = AuditScannerID.allCases.filter {
            isComplete($0, in: current) &&
            isComplete($0, in: previous)
        }

        let excluded = AuditScannerID.allCases.filter {
            !comparable.contains($0)
        }

        func scanner(for finding: AuditFinding) -> AuditScannerID {
            switch finding.category {
            case "System Security": .systemSecurity
            case "Applications": .applications
            default: .persistence
            }
        }

        let currentFindings = current.findings.filter {
            comparable.contains(scanner(for: $0))
        }

        let previousFindings = previous.findings.filter {
            comparable.contains(scanner(for: $0))
        }

        let currentIDs = Set(currentFindings.map(\.id))
        let previousIDs = Set(previousFindings.map(\.id))

        return AuditComparison(
            newFindings: currentFindings.filter {
                !previousIDs.contains($0.id)
            },
            resolvedFindings: previousFindings.filter {
                !currentIDs.contains($0.id)
            },
            unchangedFindings: currentFindings.filter {
                previousIDs.contains($0.id)
            },
            incomparableCategories: excluded
        )
    }
}
