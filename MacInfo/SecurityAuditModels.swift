
import Foundation

enum AuditSeverity: String, Codable, CaseIterable, Sendable {
    case critical = "Critical"
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    case info = "Info"

    var weight: Int {
        switch self {
        case .critical: 25
        case .high: 12
        case .medium: 5
        case .low: 1
        case .info: 0
        }
    }

    var rank: Int {
        switch self {
        case .critical: 0
        case .high: 1
        case .medium: 2
        case .low: 3
        case .info: 4
        }
    }
}

struct AuditFinding: Identifiable, Codable, Sendable {
    let id: String
    let category: String
    let title: String
    let severity: AuditSeverity
    let details: String
    let evidence: String
    let recommendation: String
}

struct AuditReport: Identifiable, Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let computerName: String
    let macOSVersion: String

    let applicationCount: Int
    let startupItemCount: Int

    let findings: [AuditFinding]

    var score: Int {
        let penalty = findings.reduce(0) {
            $0 + $1.severity.weight
        }

        return max(0, 100 - penalty)
    }

    func count(_ severity: AuditSeverity) -> Int {
        findings.filter { $0.severity == severity }.count
    }
}
