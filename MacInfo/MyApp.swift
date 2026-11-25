import SwiftUI
import AppKit

@main
struct MacInfoApp: App {
    @NSApplicationDelegateAdaptor(MacInfoAppDelegate.self)
    private var appDelegate

    @StateObject private var securityMonitoring =
        SecurityMonitoringStore()

    @StateObject private var appVisibility =
        AppVisibilityStore()

    @StateObject private var malwareReputation =
        MalwareReputationStore()

    @StateObject private var networkReputation =
        NetworkReputationStore()

    var body: some Scene {
        Window("MacInfo", id: "main") {
            MacInfoRootView()
                .environmentObject(securityMonitoring)
                .environmentObject(appVisibility)
                .environmentObject(malwareReputation)
                .environmentObject(networkReputation)
        }
        .defaultSize(width: 1100, height: 720)

        MenuBarExtra(
            isInserted: Binding(
                get: {
                    appVisibility.isMenuBarVisible
                },
                set: { visible in
                    appVisibility.setMenuBarVisible(visible)
                }
            )
        ) {
            SecurityMonitoringMenu()
                .environmentObject(securityMonitoring)
                .environmentObject(appVisibility)

            Divider()

            Button("Hide Completely — ⌃⌥⌘M") {
                appVisibility.hideCompletely()
            }
            .disabled(!appVisibility.isHotKeyRegistered)

            if let error = appVisibility.hotKeyError {
                Text(error)
            }
        } label: {
            Image(
                systemName: securityMonitoring.settings.enabled
                    ? "shield.checkered"
                    : "shield"
            )
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MacInfoRootView: View {
    @EnvironmentObject private var appVisibility:
        AppVisibilityStore

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView()
            .safeAreaInset(edge: .bottom) {
                if let error = appVisibility.hotKeyError {
                    Label(
                        error,
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .task { @MainActor in
                let open = openWindow

                appVisibility.reopenMainWindow = {
                    open(id: "main")
                }

                appVisibility.registerGlobalHotKey()
            }
    }
}

@MainActor
final class MacInfoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }
}
