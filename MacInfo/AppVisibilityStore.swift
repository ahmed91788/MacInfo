import Foundation
import AppKit
import Combine

@MainActor
final class AppVisibilityStore: ObservableObject {

    @Published private(set) var isHidden = false

    // MARK: - Hide

    func hide() {
        NSApp.hide(nil)

        NSApp.setActivationPolicy(.accessory)

        isHidden = true
    }

    // MARK: - Show

    func show() {
        NSApp.setActivationPolicy(.regular)

        NSApp.unhide(nil)

        NSApp.activate(ignoringOtherApps: true)

        isHidden = false
    }

    // MARK: - Toggle

    func toggle() {
        if isHidden {
            show()
        } else {
            hide()
        }
    }

    // MARK: - Quit

    func quit() {
        NSApp.terminate(nil)
    }
}
