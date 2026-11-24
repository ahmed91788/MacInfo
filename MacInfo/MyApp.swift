
import SwiftUI

@main
struct MacInfoApp: App {
    @StateObject private var securityMonitoring =
        SecurityMonitoringStore()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(securityMonitoring)
        }
        .defaultSize(width: 1100, height: 720)
        MenuBarExtra {
            SecurityMonitoringMenu()
                .environmentObject(securityMonitoring)
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
