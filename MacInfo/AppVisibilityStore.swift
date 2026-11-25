import Foundation
import AppKit
import Combine
import Carbon.HIToolbox

@MainActor
final class AppVisibilityStore: ObservableObject {
    @Published private(set) var isHidden = false
    @Published private(set) var isFullyHidden = false
    @Published private(set) var isMenuBarVisible = true
    @Published private(set) var isHotKeyRegistered = false
    @Published private(set) var hotKeyError: String?

    var reopenMainWindow: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // MARK: - Menu bar binding

    func setMenuBarVisible(_ visible: Bool) {
        // Avoid publishing the same value during SwiftUI scene updates.
        guard isMenuBarVisible != visible else { return }
        isMenuBarVisible = visible
    }

    // MARK: - Hide to menu bar

    func hide() {
        setMenuBarVisible(true)
        isFullyHidden = false
        isHidden = true

        NSApp.hide(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Hide everything

    func hideCompletely() {
        // Keep a way to restore the app if registration failed.
        guard isHotKeyRegistered else { return }

        isHidden = true
        isFullyHidden = true

        NSApp.hide(nil)
        NSApp.setActivationPolicy(.accessory)

        setMenuBarVisible(false)
    }

    // MARK: - Show

    func show() {
        isHidden = false
        isFullyHidden = false

        NSApp.setActivationPolicy(.regular)
        setMenuBarVisible(true)
        NSApp.unhide(nil)

        Task { @MainActor [weak self] in
            await Task.yield()

            guard let self, !self.isHidden else { return }

            if let window = NSApp.windows.first(where: {
                $0.canBecomeMain &&
                ($0.isVisible || $0.isMiniaturized)
            }) {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }

                window.makeKeyAndOrderFront(nil)
            } else {
                self.reopenMainWindow?()
            }

            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func toggle() {
        if isHidden {
            show()
        } else {
            hide()
        }
    }

    func toggleFullVisibility() {
        if isHidden {
            show()
        } else {
            hideCompletely()
        }
    }

    // MARK: - Global hotkey

    func registerGlobalHotKey() {
        guard !isHotKeyRegistered else { return }

        unregisterGlobalHotKey()
        hotKeyError = nil

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let context = Unmanaged
            .passUnretained(self)
            .toOpaque()

        var installedHandler: EventHandlerRef?

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.makeHotKeyHandler(),
            1,
            &eventType,
            context,
            &installedHandler
        )

        eventHandlerRef = installedHandler

        guard handlerStatus == noErr else {
            unregisterGlobalHotKey()
            hotKeyError =
                "Cannot install global hotkey handler: \(handlerStatus)"
            return
        }

        let identifier = EventHotKeyID(
            signature: OSType(0x4D414349),
            id: 1
        )

        var registeredHotKey: EventHotKeyRef?

        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            UInt32(controlKey | optionKey | cmdKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &registeredHotKey
        )

        hotKeyRef = registeredHotKey

        guard registrationStatus == noErr else {
            unregisterGlobalHotKey()
            hotKeyError =
                "Cannot register ⌃⌥⌘M: \(registrationStatus). " +
                "The shortcut may already be in use."
            return
        }

        isHotKeyRegistered = true
    }

    // A capture-free literal closure can be converted to a C callback.
    // The nonisolated factory prevents MainActor inference here.
    nonisolated private static func makeHotKeyHandler() -> EventHandlerUPP {
        return { _, event, userData in
            guard let event, let userData else {
                return OSStatus(eventNotHandledErr)
            }

            var identifier = EventHotKeyID(
                signature: 0,
                id: 0
            )

            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &identifier
            )

            guard status == noErr,
                  identifier.signature == OSType(0x4D414349),
                  identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }

            let store = Unmanaged<AppVisibilityStore>
                .fromOpaque(userData)
                .takeUnretainedValue()

            Task { @MainActor in
                store.toggleFullVisibility()
            }

            return noErr
        }
    }

    private func unregisterGlobalHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        isHotKeyRegistered = false
    }

    // MARK: - Quit

    func quit() {
        unregisterGlobalHotKey()
        NSApp.terminate(nil)
    }
}
