
import SwiftUI

struct NetworkConnectionsView: View {
    @StateObject private var monitor = NetworkConnectionsMonitor()

    @State private var search = ""
    @State private var protocolFilter = "All"
    @State private var selected: NetworkConnection?

    private var filtered: [NetworkConnection] {
        monitor.connections.filter { connection in
            let matchesProtocol =
                protocolFilter == "All" ||
                connection.protocolName == protocolFilter

            let matchesSearch =
                search.isEmpty ||
                connection.processName.localizedCaseInsensitiveContains(search) ||
                String(connection.pid).contains(search) ||
                connection.localAddress.contains(search) ||
                connection.remoteAddress.contains(search) ||
                String(connection.localPort).contains(search) ||
                String(connection.remotePort).contains(search)

            return matchesProtocol && matchesSearch
        }
        .sorted {
            if $0.processName != $1.processName {
                return $0.processName < $1.processName
            }
            return $0.pid < $1.pid
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Network Connections")
                    .font(.title2.bold())

                Spacer()

                Picker("Protocol", selection: $protocolFilter) {
                    Text("All").tag("All")
                    Text("TCP").tag("TCP")
                    Text("UDP").tag("UDP")
                }
                .frame(width: 130)

                Button {
                    monitor.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }

            TextField(
                "Search process, IP address, or port",
                text: $search
            )
            .textFieldStyle(.roundedBorder)

            Table(filtered) {
                TableColumn("Process") { item in
                    Text(item.processName)
                }

                TableColumn("PID") { item in
                    Text("\(item.pid)")
                }
                .width(65)

                TableColumn("Protocol") { item in
                    Text(item.protocolName)
                }
                .width(75)

                TableColumn("Local") { item in
                    Text("\(item.localAddress):\(item.localPort)")
                        .monospaced()
                }

                TableColumn("Remote") { item in
                    Text("\(item.remoteAddress):\(item.remotePort)")
                        .monospaced()
                }

                TableColumn("State") { item in
                    Text(item.state)
                }
                .width(110)
            }
            .frame(minHeight: 400)

            HStack {
                Text("\(filtered.count) connections")

                Spacer()

                if let updated = monitor.lastUpdated {
                    Text("Updated \(updated.formatted(date: .omitted, time: .standard))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}
