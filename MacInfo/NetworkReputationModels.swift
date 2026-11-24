import Foundation

nonisolated enum NetworkReputationStatus:
    String, Codable, CaseIterable, Sendable {

    case unchecked = "Unchecked"
    case noMatch = "No Match"
    case threatMatch = "Threat Match"
    case local = "Local / Reserved"
    case stale = "Stale Database"
    case unavailable = "Unavailable"
}

nonisolated struct NetworkThreatRange:
    Codable, Sendable {

    let cidr: String
    let sblid: String?
}

nonisolated struct NetworkThreatDatabase:
    Codable, Sendable {

    let downloadedAt: Date

    let ipv4Data: Data
    let ipv6Data: Data
}

nonisolated struct NetworkASNInformation:
    Codable, Sendable {

    let asns: [String]
    let prefix: String?
}

nonisolated struct NetworkReputationItem:
    Identifiable, Sendable {

    var id: String { address }

    let address: String

    var processes: [String] = []

    var ports: [Int] = []

    var connectionCount = 0

    var status: NetworkReputationStatus = .unchecked

    var matchedRanges: [NetworkThreatRange] = []

    var networkInfo: NetworkASNInformation?

    var checkedAt: Date?

    var errorMessage: String?

    var asnDescription: String {
        guard let info = networkInfo,
              !info.asns.isEmpty else {
            return "—"
        }

        return info.asns.map {
            $0.hasPrefix("AS") ? $0 : "AS\($0)"
        }
        .joined(separator: ", ")
    }
}

nonisolated struct RIPEStatResponse:
    Decodable, Sendable {

    let data: NetworkASNInformation
}

nonisolated enum NetworkReputationError:
    LocalizedError, Sendable {

    case invalidAddress
    case invalidResponse
    case invalidFeed
    case updateTooSoon
    case databaseUnavailable
    case httpError(Int)

    var errorDescription: String? {
        switch self {

        case .invalidAddress:
            return "Invalid IP address."

        case .invalidResponse:
            return "Invalid server response."

        case .invalidFeed:
            return "Invalid threat intelligence feed."

        case .updateTooSoon:
            return "Threat feed updates must be at least one hour apart."

        case .databaseUnavailable:
            return "Download the threat database first."

        case .httpError(let code):
            return "HTTP error: \(code)"
        }
    }
}
