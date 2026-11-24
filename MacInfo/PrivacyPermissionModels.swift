import Foundation

nonisolated enum PrivacyPermissionStatus:
    String, CaseIterable, Sendable {

    case authorized = "Authorized"
    case notAuthorized = "Not Authorized"
    case denied = "Denied"
    case restricted = "Restricted"
    case notDetermined = "Not Determined"
    case limited = "Limited"
    case unknown = "Unknown"
    case manualCheck = "Manual Check"
}

nonisolated enum PrivacyPermissionCategory:
    String, CaseIterable, Sendable {

    case system = "System Access"
    case input = "Input and Monitoring"
    case media = "Media"
    case personal = "Personal Data"
    case automation = "Automation"
    case connectivity = "Connectivity"
}

nonisolated enum PrivacyPermissionKind:
    String, CaseIterable, Sendable {

    case fullDiskAccess = "Full Disk Access"
    case accessibility = "Accessibility"
    case screenRecording = "Screen Recording"
    case camera = "Camera"
    case microphone = "Microphone"
    case inputMonitoring = "Input Monitoring"
    case contacts = "Contacts"
    case calendars = "Calendars"
    case reminders = "Reminders"
    case photos = "Photos"
    case automation = "Automation"
    case location = "Location Services"
    case bluetooth = "Bluetooth"
    case filesAndFolders = "Files and Folders"

    var icon: String {
        switch self {
        case .fullDiskAccess:
            return "internaldrive"
        case .accessibility:
            return "accessibility"
        case .screenRecording:
            return "display"
        case .camera:
            return "camera"
        case .microphone:
            return "mic"
        case .inputMonitoring:
            return "keyboard"
        case .contacts:
            return "person.crop.rectangle"
        case .calendars:
            return "calendar"
        case .reminders:
            return "checklist"
        case .photos:
            return "photo"
        case .automation:
            return "gearshape.2"
        case .location:
            return "location"
        case .bluetooth:
            return "antenna.radiowaves.left.and.right"
        case .filesAndFolders:
            return "folder"
        }
    }

    var category: PrivacyPermissionCategory {
        switch self {
        case .fullDiskAccess, .filesAndFolders:
            return .system

        case .accessibility, .inputMonitoring:
            return .input

        case .screenRecording, .camera, .microphone:
            return .media

        case .contacts, .calendars, .reminders, .photos:
            return .personal

        case .automation:
            return .automation

        case .location, .bluetooth:
            return .connectivity
        }
    }

    var settingsAnchor: String {
        switch self {
        case .fullDiskAccess:
            return "Privacy_AllFiles"
        case .accessibility:
            return "Privacy_Accessibility"
        case .screenRecording:
            return "Privacy_ScreenCapture"
        case .camera:
            return "Privacy_Camera"
        case .microphone:
            return "Privacy_Microphone"
        case .inputMonitoring:
            return "Privacy_ListenEvent"
        case .contacts:
            return "Privacy_Contacts"
        case .calendars:
            return "Privacy_Calendars"
        case .reminders:
            return "Privacy_Reminders"
        case .photos:
            return "Privacy_Photos"
        case .automation:
            return "Privacy_Automation"
        case .location:
            return "Privacy_LocationServices"
        case .bluetooth:
            return "Privacy_Bluetooth"
        case .filesAndFolders:
            return "Privacy_FilesAndFolders"
        }
    }

    var description: String {
        switch self {
        case .fullDiskAccess:
            return "Access to protected files and application data."

        case .accessibility:
            return "Allows applications to interact with supported user interface elements."

        case .screenRecording:
            return "Allows applications to capture screen content."

        case .camera:
            return "Allows applications to access the camera."

        case .microphone:
            return "Allows applications to capture microphone audio."

        case .inputMonitoring:
            return "Allows applications to monitor certain keyboard and input events."

        case .contacts:
            return "Controls access to contact information."

        case .calendars:
            return "Controls access to calendar information."

        case .reminders:
            return "Controls access to reminder information."

        case .photos:
            return "Controls access to the photo library."

        case .automation:
            return "Controls permission to automate other applications."

        case .location:
            return "Controls access to device location information."

        case .bluetooth:
            return "Controls access to Bluetooth functionality."

        case .filesAndFolders:
            return "Controls access to protected user folders and volumes."
        }
    }
}

nonisolated struct PrivacyPermissionRecord:
    Identifiable, Sendable {

    let kind: PrivacyPermissionKind
    let status: PrivacyPermissionStatus
    let source: String
    let details: String

    var id: String {
        kind.rawValue
    }

    var name: String {
        kind.rawValue
    }

    var category: PrivacyPermissionCategory {
        kind.category
    }
}

nonisolated struct PrivacyPermissionSnapshot: Sendable {
    let capturedAt: Date
    let permissions: [PrivacyPermissionRecord]

    var authorizedCount: Int {
        permissions.filter {
            $0.status == .authorized
        }.count
    }

    var notAuthorizedCount: Int {
        permissions.filter {
            $0.status == .denied ||
            $0.status == .notAuthorized ||
            $0.status == .restricted
        }.count
    }

    var otherCount: Int {
        permissions.count -
        authorizedCount -
        notAuthorizedCount
    }
}
