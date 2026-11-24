import Foundation

enum ProfileEnrollmentState: String, Sendable {
    case enrolled = "Enrolled"
    case notEnrolled = "Not Enrolled"
    case unknown = "Unknown"
}

enum ProfilePayloadCategory: String, CaseIterable, Sendable {
    case certificate = "Certificate"
    case vpn = "VPN"
    case proxy = "Proxy"
    case dns = "DNS"
    case network = "Network"
    case privacy = "Privacy Permissions"
    case restrictions = "Restrictions"
    case mdm = "Device Management"
    case security = "Security"
    case systemExtension = "System Extensions"
    case application = "Application"
    case other = "Other"

    var icon: String {
        switch self {
        case .certificate:
            return "checkmark.seal"
        case .vpn:
            return "lock.shield"
        case .proxy:
            return "arrow.left.arrow.right"
        case .dns:
            return "globe"
        case .network:
            return "network"
        case .privacy:
            return "hand.raised"
        case .restrictions:
            return "lock"
        case .mdm:
            return "desktopcomputer"
        case .security:
            return "shield"
        case .systemExtension:
            return "puzzlepiece.extension"
        case .application:
            return "app"
        case .other:
            return "gearshape"
        }
    }
}

struct ConfigurationPayload: Identifiable, Sendable {
    let id: String
    let name: String
    let identifier: String
    let type: String
    let category: ProfilePayloadCategory
    let organization: String
    let details: [String: String]
    let reviewReasons: [String]

    var needsReview: Bool {
        !reviewReasons.isEmpty
    }
}

struct ConfigurationProfile: Identifiable, Sendable {
    let id: String
    let name: String
    let identifier: String
    let organization: String
    let scope: String
    let installedAt: String
    let removalDisallowed: Bool?
    let payloads: [ConfigurationPayload]

    var reviewReasons: [String] {
        var reasons = payloads.flatMap(\.reviewReasons)

        if removalDisallowed == true {
            reasons.append(
                "Profile removal is restricted."
            )
        }

        return Array(Set(reasons)).sorted()
    }

    var needsReview: Bool {
        !reviewReasons.isEmpty
    }
}

struct DeviceEnrollmentInfo: Sendable {
    let mdm: ProfileEnrollmentState
    let automatedEnrollment: ProfileEnrollmentState
    let userApproved: Bool?
    let serverURL: String?
}

struct ConfigurationProfileSnapshot: Sendable {
    let capturedAt: Date

    let profiles: [ConfigurationProfile]
    let enrollment: DeviceEnrollmentInfo

    let profileCommand: ExtensionCommandResult
    let enrollmentCommand: ExtensionCommandResult

    let warnings: [String]

    var profileCount: Int {
        profiles.count
    }

    var payloadCount: Int {
        profiles.reduce(0) {
            $0 + $1.payloads.count
        }
    }

    var reviewCount: Int {
        profiles.filter(\.needsReview).count
    }

    var isComplete: Bool {
        profileCommand.succeeded &&
        enrollmentCommand.succeeded &&
        warnings.isEmpty
    }
}
