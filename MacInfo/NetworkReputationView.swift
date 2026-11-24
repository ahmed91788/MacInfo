import SwiftUI
import AppKit

struct NetworkReputationView: View {

    @EnvironmentObject private var store:
        NetworkReputationStore

    @State private var search = ""

    @State private var manualAddress = ""

    @State private var selectedStatus = "All"

    @State private var selectedID: String?

    @State private var detailAddress: String?

    @State private var showDetails = false

    @State private var lookupAddress: String?

    @State private var confirmLookup = false

    private var filteredItems:
        [NetworkReputationItem] {

        store.items.filter { item in

            let matchesSearch =
                search.isEmpty ||
                item.address.localizedCaseInsensitiveContains(
                    search
                ) ||
                item.processes.joined(separator: " ")
                    .localizedCaseInsensitiveContains(
                        search
                    ) ||
                item.asnDescription
                    .localizedCaseInsensitiveContains(
                        search
                    )

            let matchesStatus =
                selectedStatus == "All" ||
                item.status.rawValue == selectedStatus

            return matchesSearch && matchesStatus
        }
    }

    var body: some View {

        VStack(alignment: .leading, spacing: 12) {

            header

            summaryCards

            databasePanel

            if let error = store.errorMessage {

                Label(
                    error,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if store.isBusy {

                ProgressView()
                    .progressViewStyle(.linear)
            }

            manualLookup

            filterToolbar

            resultsTable
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .layoutPriority(1)
        }
        .padding(20)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .task {

            await store.prepare()
        }
        .sheet(isPresented: $showDetails) {

            if let item = store.items.first(
                where: {
                    $0.address == detailAddress
                }
            ) {

                detailsView(item)
            }
        }
        .confirmationDialog(
            "Look up network information?",
            isPresented: $confirmLookup
        ) {

            Button("Look Up") {

                if let address = lookupAddress {

                    store.lookupNetworkInformation(
                        address: address
                    )
                }
            }

        } message: {

            Text(
                "The selected remote IP address will be sent " +
                "to RIPEstat to retrieve ASN and routing information."
            )
        }
    }

    // MARK: - Header

    private var header: some View {

        HStack {

            VStack(alignment: .leading, spacing: 4) {

                Text("Network Reputation")
                    .font(.title2.bold())

                Text(
                    "Inspect remote network destinations"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if store.isBusy {

                Button("Cancel") {
                    store.cancel()
                }

            } else {

                Button {

                    store.updateDatabase()

                } label: {

                    Label(
                        "Update Database",
                        systemImage: "arrow.down.circle"
                    )
                }

                Button {

                    store.scanConnections()

                } label: {

                    Label(
                        "Check Connections",
                        systemImage: "shield.checkered"
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Summary cards

    private var summaryCards: some View {

        HStack(spacing: 12) {

            summaryCard(
                "Remote IPs",
                store.items.count,
                .blue
            )

            summaryCard(
                "Checked",
                store.checkedCount,
                .blue
            )

            summaryCard(
                "Threat Matches",
                store.threatCount,
                .red
            )

            summaryCard(
                "Unchecked",
                store.uncheckedCount,
                .secondary
            )
        }
    }

    private func summaryCard(
        _ title: String,
        _ value: Int,
        _ color: Color
    ) -> some View {

        VStack(alignment: .leading, spacing: 8) {

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(value)")
                .font(.title.bold())
                .foregroundStyle(color)
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color.secondary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    // MARK: - Database status

    private var databasePanel: some View {

        GroupBox {

            VStack(alignment: .leading, spacing: 8) {

                HStack {

                    Label(
                        store.databaseCount > 0
                            ? "Threat database loaded"
                            : "Threat database not downloaded",
                        systemImage: "externaldrive"
                    )
                    .fontWeight(.medium)
                    .foregroundStyle(
                        store.databaseCount > 0
                            ? Color.green
                            : Color.orange
                    )

                    Spacer()

                    Text(
                        "\(store.databaseCount) network ranges"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let date = store.databaseDate {

                    Text(
                        "Downloaded: " + date.formatted()
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                HStack {

                    Text("Threat intelligence:")

                    Link(
                        "The Spamhaus Project",
                        destination: URL(
                            string:
                                "https://www.spamhaus.org/"
                        )!
                    )

                    Spacer()

                    Link(
                        "RIPEstat",
                        destination: URL(
                            string:
                                "https://stat.ripe.net/"
                        )!
                    )
                }
                .font(.caption)

                Text(
                    "Threat matching is performed locally. " +
                    "A missing match does not guarantee an IP is safe."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let coverage = store.coverageMessage {

                    Text(coverage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Manual lookup

    private var manualLookup: some View {

        HStack {

            TextField(
                "Enter IPv4 or IPv6 address...",
                text: $manualAddress
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit {

                if !store.isBusy {

                    store.checkAddress(manualAddress)
                }
            }

            Button("Check IP") {

                store.checkAddress(
                    manualAddress
                )
            }
            .disabled(
                manualAddress.isEmpty ||
                store.isBusy
            )
        }
    }

    // MARK: - Filters

    private var filterToolbar: some View {

        HStack(spacing: 12) {

            TextField(
                "Search IP, process or ASN...",
                text: $search
            )
            .textFieldStyle(.roundedBorder)

            Picker(
                "Reputation",
                selection: $selectedStatus
            ) {

                Text("All Results")
                    .tag("All")

                ForEach(
                    NetworkReputationStatus.allCases,
                    id: \.rawValue
                ) { status in

                    Text(status.rawValue)
                        .tag(status.rawValue)
                }
            }
            .frame(width: 200)

            Text("\(filteredItems.count) IPs")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Clear") {

                store.clear()
            }
            .disabled(store.isBusy)
        }
    }

    // MARK: - Results table

    private var resultsTable: some View {

        Table(
            filteredItems,
            selection: $selectedID
        ) {

            TableColumn("Remote IP") { item in

                Text(item.address)
                    .font(.system(
                        size: 12,
                        design: .monospaced
                    ))
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 150)

            TableColumn("Processes") { item in

                Text(
                    item.processes.isEmpty
                        ? "—"
                        : item.processes.joined(
                            separator: ", "
                        )
                )
                .lineLimit(1)
            }

            TableColumn("Ports") { item in

                Text(
                    item.ports.map(String.init)
                        .joined(separator: ", ")
                )
                .lineLimit(1)
            }
            .width(min: 55, ideal: 80)

            TableColumn("ASN") { item in

                Text(item.asnDescription)
                    .lineLimit(1)
            }
            .width(min: 70, ideal: 100)

            TableColumn("Reputation") { item in

                Label(
                    item.status.rawValue,
                    systemImage: statusIcon(
                        item.status
                    )
                )
                .foregroundStyle(
                    statusColor(item.status)
                )
                .font(.caption)
            }
            .width(min: 100, ideal: 140)
        }
        .contextMenu(
            forSelectionType: String.self
        ) { ids in

            Button("View Details") {

                openDetails(ids)
            }

            Button("Look Up Network Information") {

                if let address = ids.first {

                    requestLookup(address)
                }
            }
            .disabled(
                store.isBusy ||
                ids.count != 1 ||
                ids.first.map {
                    IPAddressUtilities
                        .isLocalOrReserved($0)
                } == true
            )

            Button("Copy IP Address") {

                if let address = ids.first {

                    copy(address)
                }
            }

        } primaryAction: { ids in

            openDetails(ids)
        }
        .overlay {

            if filteredItems.isEmpty {

                ContentUnavailableView(
                    store.items.isEmpty
                        ? "No Network Results"
                        : "No Matching Results",
                    systemImage: "network",
                    description: Text(
                        store.items.isEmpty
                            ? "Check current connections or enter an IP address."
                            : "Try changing your filters."
                    )
                )
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Details

    private func detailsView(
        _ item: NetworkReputationItem
    ) -> some View {

        VStack(alignment: .leading, spacing: 16) {

            Text(item.address)
                .font(.title2.monospaced())

            Label(
                item.status.rawValue,
                systemImage: statusIcon(item.status)
            )
            .foregroundStyle(
                statusColor(item.status)
            )

            Divider()

            ScrollView {

                VStack(alignment: .leading, spacing: 16) {

                    GroupBox("Connection Information") {

                        VStack(alignment: .leading, spacing: 10) {

                            detailRow(
                                "Address",
                                item.address
                            )

                            detailRow(
                                "Connections",
                                String(item.connectionCount)
                            )

                            detailRow(
                                "Processes",
                                item.processes.joined(
                                    separator: ", "
                                )
                            )

                            detailRow(
                                "Remote Ports",
                                item.ports.map(String.init)
                                    .joined(separator: ", ")
                            )
                        }
                        .padding(8)
                    }

                    GroupBox("Network Information") {

                        VStack(alignment: .leading, spacing: 10) {

                            detailRow(
                                "ASN",
                                item.asnDescription
                            )

                            detailRow(
                                "Prefix",
                                item.networkInfo?.prefix
                                    ?? "Unavailable"
                            )

                            Button("Look Up ASN via RIPEstat") {

                                requestLookup(
                                    item.address
                                )

                                showDetails = false
                            }
                            .disabled(
                                store.isBusy ||
                                IPAddressUtilities
                                    .isLocalOrReserved(
                                        item.address
                                    )
                            )
                        }
                        .padding(8)
                    }

                    GroupBox("Threat Intelligence") {

                        VStack(alignment: .leading, spacing: 10) {

                            detailRow(
                                "Provider",
                                "Spamhaus DROP"
                            )

                            detailRow(
                                "Status",
                                item.status.rawValue
                            )

                            ForEach(
                                Array(
                                    item.matchedRanges.enumerated()
                                ),
                                id: \.offset
                            ) { entry in

                                VStack(
                                    alignment: .leading,
                                    spacing: 6
                                ) {

                                    detailRow(
                                        "Matched CIDR",
                                        entry.element.cidr
                                    )

                                    detailRow(
                                        "SBL Reference",
                                        entry.element.sblid
                                            ?? "Unknown"
                                    )
                                }

                                Divider()
                            }

                            if item.matchedRanges.isEmpty {

                                Text(
                                    "No matching ranges recorded."
                                )
                                .foregroundStyle(.secondary)
                            }

                            if let message =
                                item.errorMessage {

                                Text(message)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(8)
                    }

                    Text(
                        "Threat intelligence matches require review. " +
                        "Shared infrastructure and changing IP allocations " +
                        "can affect interpretation."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            HStack {

                Button("Copy IP") {

                    copy(item.address)
                }

                Link(
                    "Open RIPEstat",
                    destination: URL(
                        string:
                            "https://stat.ripe.net/"
                    )!
                )

                Spacer()

                Button("Close") {

                    showDetails = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 680, height: 580)
    }

    // MARK: - Helpers

    private func openDetails(
        _ ids: Set<String>
    ) {

        guard let address = ids.first else {
            return
        }

        detailAddress = address
        showDetails = true
    }

    private func requestLookup(
        _ address: String
    ) {

        lookupAddress = address

        confirmLookup = true
    }

    private func copy(
        _ value: String
    ) {

        NSPasteboard.general.clearContents()

        NSPasteboard.general.setString(
            value,
            forType: .string
        )
    }

    private func detailRow(
        _ title: String,
        _ value: String
    ) -> some View {

        HStack(alignment: .top) {

            Text(title)
                .foregroundStyle(.secondary)
                .frame(
                    width: 125,
                    alignment: .leading
                )

            Text(value.isEmpty ? "—" : value)
                .textSelection(.enabled)

            Spacer()
        }
    }

    private func statusColor(
        _ status: NetworkReputationStatus
    ) -> Color {

        switch status {

        case .threatMatch:
            return .red

        case .stale:
            return .orange

        default:
            return .secondary
        }
    }

    private func statusIcon(
        _ status: NetworkReputationStatus
    ) -> String {

        switch status {

        case .threatMatch:
            return "exclamationmark.shield.fill"

        case .noMatch:
            return "shield"

        case .local:
            return "house"

        case .stale:
            return "clock.badge.exclamationmark"

        case .unchecked:
            return "questionmark.circle"

        case .unavailable:
            return "exclamationmark.circle"
        }
    }
}
