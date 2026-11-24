import SwiftUI

struct SecurityMonitoringMenu: View {

    @EnvironmentObject private var store:
        SecurityMonitoringStore

    var body: some View {
        Text("MacInfo Security Monitoring")
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

        Button("Scan Now") {
            store.scanNow()
        }
        .disabled(store.isScanning)

        Button(
            store.settings.enabled
                ? "Pause Monitoring"
                : "Start Monitoring"
        ) {
            store.setEnabled(
                !store.settings.enabled
            )
        }

        if store.isScanning {
            Button("Cancel Scan") {
                store.cancelScan()
            }
        }
    }
}
