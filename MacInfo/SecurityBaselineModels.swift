
import Foundation

struct BaselineApplication: Codable, Sendable, Identifiable {
    let path: String
    let name: String
    let bundleIdentifier: String?
    let version: String?
    let signature: String
    let teamIdentifier: String?

    var id: String { path }
}

struct BaselineStartupItem: Codable, Sendable, Identifiable {
    let plistPath: String
    let label: String
    let executablePath: String
    let arguments: [String]
    let signingStatus: String
    let teamIdentifier: String?
    let runAtLoad: Bool
    let keepAlive: Bool
    let disabledInPlist: Bool

    var id: String { plistPath }
}

struct SecurityBaseline: Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let applications: [BaselineApplication]
    let startupItems: [BaselineStartupItem]
    let fileHashes: [BaselineFileHash]

    init(
        id: UUID,
        createdAt: Date,
        applications: [BaselineApplication],
        startupItems: [BaselineStartupItem],
        fileHashes: [BaselineFileHash]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.applications = applications
        self.startupItems = startupItems
        self.fileHashes = fileHashes
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case applications
        case startupItems
        case fileHashes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        applications = try container.decode(
            [BaselineApplication].self,
            forKey: .applications
        )

        startupItems = try container.decode(
            [BaselineStartupItem].self,
            forKey: .startupItems
        )

        fileHashes = try container.decodeIfPresent(
            [BaselineFileHash].self,
            forKey: .fileHashes
        ) ?? []
    }
}

enum BaselineChangeType: String, Sendable {
    case added = "Added"
    case removed = "Removed"
    case modified = "Modified"
}


struct BaselineChange: Identifiable, Sendable {
    let id: String
    let type: BaselineChangeType
    let category: String
    let name: String
    let details: String

    var oldHash: String? = nil
    var newHash: String? = nil
}


struct BaselineComparison: Sendable {
    let changes: [BaselineChange]

    func count(_ type: BaselineChangeType) -> Int {
        changes.filter { $0.type == type }.count
    }
}

struct BaselineFileHash: Codable, Sendable, Identifiable {
    let path: String
    let category: String
    let name: String
    let result: FileHashResult

    var id: String { path }
}
