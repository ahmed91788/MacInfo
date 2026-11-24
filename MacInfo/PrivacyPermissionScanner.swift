import Foundation
import ApplicationServices
import CoreGraphics
import AVFoundation
import Contacts
import EventKit
import Photos
import CoreLocation

@MainActor
enum PrivacyPermissionScanner {

    static func scan() -> PrivacyPermissionSnapshot {

        let permissions = PrivacyPermissionKind
            .allCases
            .map { kind in
                inspect(kind)
            }

        return PrivacyPermissionSnapshot(
            capturedAt: Date(),
            permissions: permissions
        )
    }

    // MARK: - Inspect individual permission

    static func inspect(
        _ kind: PrivacyPermissionKind
    ) -> PrivacyPermissionRecord {

        switch kind {

        case .fullDiskAccess:
            return record(
                kind,
                status: .manualCheck,
                source: "System Settings",
                details: """
                macOS does not provide a public API for \
                definitively checking Full Disk Access. \
                Review the permission in System Settings.
                """
            )

        case .accessibility:
            return record(
                kind,
                status: AXIsProcessTrusted()
                    ? .authorized
                    : .notAuthorized,
                source: "ApplicationServices",
                details: "Authorization for the current process."
            )

        case .screenRecording:
            return record(
                kind,
                status: CGPreflightScreenCaptureAccess()
                    ? .authorized
                    : .notAuthorized,
                source: "CoreGraphics",
                details: "Screen capture preflight authorization."
            )

        case .inputMonitoring:
            return record(
                kind,
                status: CGPreflightListenEventAccess()
                    ? .authorized
                    : .notAuthorized,
                source: "CoreGraphics",
                details: "Input monitoring preflight authorization."
            )

        case .camera:
            return record(
                kind,
                status: mediaStatus(
                    AVCaptureDevice.authorizationStatus(
                        for: .video
                    )
                ),
                source: "AVFoundation",
                details: "Camera authorization for MacInfo."
            )

        case .microphone:
            return record(
                kind,
                status: mediaStatus(
                    AVCaptureDevice.authorizationStatus(
                        for: .audio
                    )
                ),
                source: "AVFoundation",
                details: "Microphone authorization for MacInfo."
            )

        case .contacts:
            return record(
                kind,
                status: contactsStatus(),
                source: "Contacts",
                details: "Contacts authorization for MacInfo."
            )

        case .calendars:
            return record(
                kind,
                status: eventStatus(
                    EKEventStore.authorizationStatus(
                        for: .event
                    )
                ),
                source: "EventKit",
                details: "Calendar authorization for MacInfo."
            )

        case .reminders:
            return record(
                kind,
                status: eventStatus(
                    EKEventStore.authorizationStatus(
                        for: .reminder
                    )
                ),
                source: "EventKit",
                details: "Reminders authorization for MacInfo."
            )

        case .photos:
            return record(
                kind,
                status: photosStatus(),
                source: "Photos",
                details: "Photo library read/write authorization."
            )

        case .location:
            return record(
                kind,
                status: locationStatus(),
                source: "CoreLocation",
                details: "Location authorization for MacInfo."
            )

        case .automation:
            return record(
                kind,
                status: .manualCheck,
                source: "System Settings",
                details: """
                Automation authorization is specific to \
                the application being controlled. There \
                is no single global authorization state.
                """
            )

        case .bluetooth:
            return record(
                kind,
                status: .manualCheck,
                source: "System Settings",
                details: """
                Bluetooth permission can be reviewed \
                without initializing Bluetooth services.
                """
            )

        case .filesAndFolders:
            return record(
                kind,
                status: .manualCheck,
                source: "System Settings",
                details: """
                File and folder permissions are specific \
                to protected locations and volumes.
                """
            )
        }
    }

    // MARK: - AVFoundation

    private static func mediaStatus(
        _ status: AVAuthorizationStatus
    ) -> PrivacyPermissionStatus {

        switch status {
        case .authorized:
            return .authorized

        case .denied:
            return .denied

        case .restricted:
            return .restricted

        case .notDetermined:
            return .notDetermined

        @unknown default:
            return .unknown
        }
    }

    // MARK: - Contacts

    private static func contactsStatus()
        -> PrivacyPermissionStatus {

        let status = CNContactStore.authorizationStatus(
            for: .contacts
        )

        switch status {
        case .authorized:
            return .authorized

        case .denied:
            return .denied

        case .restricted:
            return .restricted

        case .notDetermined:
            return .notDetermined

        default:
            return .unknown
        }
    }

    // MARK: - EventKit

    private static func eventStatus(
        _ status: EKAuthorizationStatus
    ) -> PrivacyPermissionStatus {

        if #available(macOS 14.0, *) {
            if status == .fullAccess {
                return .authorized
            }

            if status == .writeOnly {
                return .limited
            }
        }

        switch status {
        case .authorized:
            return .authorized

        case .denied:
            return .denied

        case .restricted:
            return .restricted

        case .notDetermined:
            return .notDetermined

        default:
            return .unknown
        }
    }

    // MARK: - Photos

    private static func photosStatus()
        -> PrivacyPermissionStatus {

        let status = PHPhotoLibrary.authorizationStatus(
            for: .readWrite
        )

        switch status {
        case .authorized:
            return .authorized

        case .limited:
            return .limited

        case .denied:
            return .denied

        case .restricted:
            return .restricted

        case .notDetermined:
            return .notDetermined

        @unknown default:
            return .unknown
        }
    }

    // MARK: - Location

    private static func locationStatus()
        -> PrivacyPermissionStatus {

        let manager = CLLocationManager()

        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return .authorized

        case .denied:
            return .denied

        case .restricted:
            return .restricted

        case .notDetermined:
            return .notDetermined

        @unknown default:
            return .unknown
        }
    }

    // MARK: - Record helper

    private static func record(
        _ kind: PrivacyPermissionKind,
        status: PrivacyPermissionStatus,
        source: String,
        details: String
    ) -> PrivacyPermissionRecord {

        PrivacyPermissionRecord(
            kind: kind,
            status: status,
            source: source,
            details: details
        )
    }
}
