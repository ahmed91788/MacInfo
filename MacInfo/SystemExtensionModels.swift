
import Foundation

enum MacExtensionType: String, CaseIterable, Sendable {
    case network = "Network Extension"
    case endpointSecurity = "Endpoint Security"
    case driverKit = "DriverKit"
    case unknown = "Other"

    var icon: String {
        switch self {
        case .network:
            return "network"
        case .endpointSecurity:
            return "shield.lefthalf.filled"
        case .driverKit:
            return "cpu"
        case .unknown:
            return "puzzlepiece.extension"
        }
    }
}

enum MacExtensionState: String, CaseIterable, Sendable {
    case activated = "Activated"
    case inactive = "Inactive"
    case pendingApproval = "Pending Approval"
    case pendingRemoval = "Pending Removal"
    case unknown = "Unknown"
}

struct MacSystemExtension: Identifiable, Sendable {
    let type: MacExtensionType
    let name: String
    let bundleIdentifier: String
    let teamIdentifier: String
    let version: String

    let enabled: Bool
    let active: Bool
    let state: MacExtensionState
    let rawState: String

    let reviewReasons: [String]

    var id: String {
        "\(type.rawValue):\(teamIdentifier):\(bundleIdentifier):\(version)"
    }

    var needsReview: Bool {
        !reviewReasons.isEmpty
    }
}

struct MacKernelExtension: Identifiable, Sendable {
    let index: Int
    let referenceCount: Int
    let address: String
    let size: String

    let bundleIdentifier: String
    let version: String
    let uuid: String?
    let rawLine: String

    var id: String {
        "\(index):\(bundleIdentifier)"
    }

    var isAppleIdentifier: Bool {
        bundleIdentifier.hasPrefix("com.apple.")
    }

    var needsReview: Bool {
        !isAppleIdentifier
    }
}

nonisolated struct ExtensionCommandResult: Sendable {
    let executable: String
    let arguments: [String]

    let output: String
    let errorOutput: String

    let exitCode: Int32?
    let timedOut: Bool

    var succeeded: Bool {
        exitCode == 0 && !timedOut
    }

    var command: String {
        ([executable] + arguments).joined(separator: " ")
    }
}

struct SystemExtensionSnapshot: Sendable {
    let capturedAt: Date

    let systemExtensions: [MacSystemExtension]
    let kernelExtensions: [MacKernelExtension]

    let systemCommand: ExtensionCommandResult
    let kernelCommand: ExtensionCommandResult

    let warnings: [String]

    var totalCount: Int {
        systemExtensions.count + kernelExtensions.count
    }

    var activeCount: Int {
        systemExtensions.filter(\.active).count
            + kernelExtensions.count
    }

    var inactiveCount: Int {
        systemExtensions.filter { !$0.active }.count
    }

    var reviewCount: Int {
        systemExtensions.filter(\.needsReview).count
            + kernelExtensions.filter(\.needsReview).count
    }

    var isComplete: Bool {
        systemCommand.succeeded &&
        kernelCommand.succeeded &&
        warnings.isEmpty
    }
}
