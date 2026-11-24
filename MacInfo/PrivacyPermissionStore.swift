import Foundation
import Combine
import AppKit

@MainActor
final class PrivacyPermissionStore: ObservableObject {

    @Published private(set) var snapshot:
        PrivacyPermissionSnapshot?

    @Published private(set) var errorMessage: String?

    func refresh() {
        errorMessage = nil

        snapshot = PrivacyPermissionScanner.scan()
    }

    func openSettings(
        for kind: PrivacyPermissionKind
    ) {
        let base =
            "x-apple.systempreferences:" +
            "com.apple.preference.security"

        let address =
            "\(base)?\(kind.settingsAnchor)"

        if let url = URL(string: address),
           NSWorkspace.shared.open(url) {

            errorMessage = nil
            return
        }

        openPrivacySettings()
    }

    func openPrivacySettings() {
        let address =
            "x-apple.systempreferences:" +
            "com.apple.preference.security"

        guard let url = URL(string: address),
              NSWorkspace.shared.open(url) else {

            errorMessage =
                "Unable to open Privacy & Security settings."

            return
        }

        errorMessage = nil
    }
}
