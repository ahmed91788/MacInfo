import SwiftUI

@main
struct MacInfoApp: App {

    @StateObject private var securityMonitoring =
        SecurityMonitoringStore()

    @StateObject private var appVisibility =
        AppVisibilityStore()
    
    @NSApplicationDelegateAdaptor(MacInfoAppDelegate.self)
    private var appDelegate

    var body: some Scene {

        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(securityMonitoring)
                .environmentObject(appVisibility)
        }
        .defaultSize(
            width: 1100,
            height: 720
        )

        MenuBarExtra {
            SecurityMonitoringMenu()
                .environmentObject(securityMonitoring)
                .environmentObject(appVisibility)
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
