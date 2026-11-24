
import Foundation

struct IntegrityScanOptions: Sendable {
    var includeApplications = true
    var includeStartupItems = true
    var includeSystemFiles = true
    var maximumFileSizeMB = 512

    var maximumFileSize: UInt64 {
        UInt64(max(1, maximumFileSizeMB)) * 1024 * 1024
    }
}

struct IntegrityScanProgress: Sendable {
    let completed: Int
    let total: Int
    let currentPath: String

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

enum IntegrityVerificationStatus: String, CaseIterable, Sendable {
    case matched = "Matched"
    case changed = "Changed"
    case missing = "Missing"
    case unverified = "Unverified"
    case newFile = "New File"
    case skipped = "Skipped"
    case cancelled = "Cancelled"
}

struct IntegrityVerificationResult: Identifiable, Sendable {
    let path: String
    let name: String
    let category: String
    let status: IntegrityVerificationStatus

    let baselineHash: String?
    let currentHash: String?
    let size: UInt64?
    let message: String?

    var id: String { path }
}

struct IntegrityTarget: Sendable {
    let path: String
    let name: String
    let category: String
}
