import SwiftUI
import AppKit

struct SecurityMonitoringMenu: View {

    @EnvironmentObject private var store:
        SecurityMonitoringStore

    @EnvironmentObject private var appVisibility:
        AppVisibilityStore

    @Environment(\.openWindow)
    private var openWindow

    var body: some View {

        Text("MacInfo")
            .font(.headline)

        Text(store.statusText)

        if let lastScan = store.state.lastScanAt {
            Text(
                "Last scan: " +
                lastScan.formatted(
                    date: .omitted,
                    time: .shortened
                )
            )
        }

        Text("\(store.reviewCount) review events")

        Divider()

        // MARK: - Window visibility

        Button {
            showMacInfo()
        } label: {
            Label(
                "Show MacInfo",
                systemImage: "macwindow"
            )
        }

        Button {
            appVisibility.hide()
        } label: {
            Label(
                "Hide MacInfo",
                systemImage: "eye.slash"
            )
        }
        .disabled(appVisibility.isHidden)

        Divider()

        // MARK: - Monitoring

        Button {
            store.scanNow()
        } label: {
            Label(
                "Scan Now",
                systemImage: "arrow.clockwise"
            )
        }
        .disabled(store.isScanning)

        Button {
            store.setEnabled(
                !store.settings.enabled
            )
        } label: {
            Label(
                store.settings.enabled
                    ? "Pause Monitoring"
                    : "Start Monitoring",
                systemImage: store.settings.enabled
                    ? "pause.fill"
                    : "play.fill"
            )
        }

        if store.isScanning {
            Button("Cancel Scan") {
                store.cancelScan()
            }
        }

        Divider()

        Button {
            appVisibility.quit()
        } label: {
            Label(
                "Quit MacInfo",
                systemImage: "power"
            )
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    // MARK: - Show main window

    private func showMacInfo() {
        appVisibility.show()
    }
}
