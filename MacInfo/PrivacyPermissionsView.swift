import SwiftUI
import AppKit
import Combine

struct PrivacyPermissionsView: View {

    @StateObject private var store =
        PrivacyPermissionStore()

    @State private var search = ""

    @State private var selectedCategory = "All"
    @State private var selectedStatus = "All"

    @State private var selectedID: String?

    @State private var selectedDetails:
        PrivacyPermissionRecord?

    // MARK: - Filtered records

    private var filteredPermissions:
        [PrivacyPermissionRecord] {

        (store.snapshot?.permissions ?? [])
            .filter { permission in

                let matchesSearch =
                    search.isEmpty ||
                    permission.name
                        .localizedCaseInsensitiveContains(search) ||
                    permission.details
                        .localizedCaseInsensitiveContains(search)

                let matchesCategory =
                    selectedCategory == "All" ||
                    permission.category.rawValue ==
                        selectedCategory

                let matchesStatus =
                    selectedStatus == "All" ||
                    permission.status.rawValue ==
                        selectedStatus

                return matchesSearch &&
                    matchesCategory &&
                    matchesStatus
            }
    }

    // MARK: - Main view

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            header

            if let error = store.errorMessage {
                Label(
                    error,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            summaryCards

            informationBanner

            filterToolbar

            permissionsTable
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
        .sheet(item: $selectedDetails) { permission in
            permissionDetails(permission)
        }
        .onAppear {
            store.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            store.refresh()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Privacy Permissions")
                    .font(.title2.bold())

                Text("Inspect MacInfo privacy authorization")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let snapshot = store.snapshot {
                    Text(
                        "Last checked: " +
                        snapshot.capturedAt.formatted(
                            date: .abbreviated,
                            time: .standard
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                store.openPrivacySettings()
            } label: {
                Label(
                    "Privacy Settings",
                    systemImage: "gearshape"
                )
            }

            Button {
                store.refresh()
            } label: {
                Label(
                    "Refresh",
                    systemImage: "arrow.clockwise"
                )
            }
        }
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                "Permissions",
                value: store.snapshot?.permissions.count,
                icon: "hand.raised",
                color: .blue
            )

            summaryCard(
                "Authorized",
                value: store.snapshot?.authorizedCount,
                icon: "checkmark.circle",
                color: .green
            )

            summaryCard(
                "Not Authorized",
                value: store.snapshot?.notAuthorizedCount,
                icon: "lock",
                color: .secondary
            )

            summaryCard(
                "Other / Unknown",
                value: store.snapshot?.otherCount,
                icon: "questionmark.circle",
                color: .secondary
            )
        }
    }

    private func summaryCard(
        _ title: String,
        value: Int?,
        icon: String,
        color: Color
    ) -> some View {

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: icon)
                    .foregroundStyle(color)
            }

            Text(value.map { String($0) } ?? "—")
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

    // MARK: - Information banner

    private var informationBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 24))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 5) {
                Text("MacInfo Authorization")
                    .font(.headline)

                Text("""
                These results describe permissions available \
                to MacInfo. To review permissions granted to \
                other applications, open the corresponding \
                Privacy & Security settings.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)

                Text("""
                Denied or undetermined permissions are not \
                security vulnerabilities.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color.blue.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    // MARK: - Filter toolbar

    private var filterToolbar: some View {
        HStack(spacing: 12) {
            TextField(
                "Search permissions...",
                text: $search
            )
            .textFieldStyle(.roundedBorder)

            Picker(
                "Category",
                selection: $selectedCategory
            ) {
                Text("All Categories")
                    .tag("All")

                ForEach(
                    PrivacyPermissionCategory.allCases,
                    id: \.rawValue
                ) { category in
                    Text(category.rawValue)
                        .tag(category.rawValue)
                }
            }
            .frame(width: 190)

            Picker(
                "Status",
                selection: $selectedStatus
            ) {
                Text("All Statuses")
                    .tag("All")

                ForEach(
                    PrivacyPermissionStatus.allCases,
                    id: \.rawValue
                ) { status in
                    Text(status.rawValue)
                        .tag(status.rawValue)
                }
            }
            .frame(width: 180)

            Text("\(filteredPermissions.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Permissions table

    private var permissionsTable: some View {
        Table(
            filteredPermissions,
            selection: $selectedID
        ) {
            TableColumn("Permission") { permission in
                HStack(spacing: 8) {
                    Image(systemName: permission.kind.icon)
                        .foregroundStyle(.blue)
                        .frame(width: 20)

                    Text(permission.name)
                        .fontWeight(.medium)
                }
            }
            .width(min: 150, ideal: 190)

            TableColumn("Category") { permission in
                Text(permission.category.rawValue)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 140)

            TableColumn("Status") { permission in
                HStack(spacing: 6) {
                    Image(
                        systemName: statusIcon(
                            permission.status
                        )
                    )

                    Text(permission.status.rawValue)
                }
                .foregroundStyle(
                    statusColor(permission.status)
                )
            }
            .width(min: 110, ideal: 140)

            TableColumn(
                "Source",
                value: \.source
            )
            .width(min: 100, ideal: 130)

            TableColumn("Settings") { permission in
                Button {
                    store.openSettings(
                        for: permission.kind
                    )
                } label: {
                    Label(
                        "Open Settings",
                        systemImage: "arrow.up.right.square"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .width(110)
        }
        .contextMenu(
            forSelectionType: String.self
        ) { ids in

            Button("View Details") {
                openDetails(ids)
            }
            .disabled(ids.isEmpty)

            Button("Open Privacy Settings") {
                if let permission =
                    filteredPermissions.first(
                        where: { ids.contains($0.id) }
                    ) {

                    store.openSettings(
                        for: permission.kind
                    )
                }
            }
            .disabled(ids.isEmpty)

        } primaryAction: { ids in
            openDetails(ids)
        }
        .overlay {
            if filteredPermissions.isEmpty {
                ContentUnavailableView(
                    "No Matching Permissions",
                    systemImage: "hand.raised",
                    description: Text(
                        "Try changing the search or filters."
                    )
                )
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Permission details

    private func permissionDetails(
        _ permission: PrivacyPermissionRecord
    ) -> some View {

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: permission.kind.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 5) {
                    Text(permission.name)
                        .font(.title2.bold())

                    Text(permission.category.rawValue)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    GroupBox("Authorization") {
                        VStack(spacing: 10) {
                            detailRow(
                                "Application",
                                "MacInfo"
                            )

                            detailRow(
                                "Permission",
                                permission.name
                            )

                            detailRow(
                                "Status",
                                permission.status.rawValue
                            )

                            detailRow(
                                "Source",
                                permission.source
                            )
                        }
                        .padding(8)
                    }

                    GroupBox("Permission Description") {
                        Text(permission.kind.description)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                            .padding(8)
                    }

                    GroupBox("Diagnostic Information") {
                        Text(permission.details)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                            .padding(8)
                            .textSelection(.enabled)
                    }

                    GroupBox("Security Considerations") {
                        Text("""
                        Grant this permission only to \
                        applications that require it for \
                        their intended functionality. \
                        MacInfo does not require every \
                        permission to perform diagnostics.
                        """)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .padding(8)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Button {
                    store.openSettings(
                        for: permission.kind
                    )
                } label: {
                    Label(
                        "Open Settings",
                        systemImage: "arrow.up.right.square"
                    )
                }

                Spacer()

                Button("Close") {
                    selectedDetails = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 650, height: 520)
    }

    // MARK: - Status appearance

    private func statusColor(
        _ status: PrivacyPermissionStatus
    ) -> Color {

        switch status {
        case .authorized:
            return .green

        case .limited:
            return .blue

        case .denied, .notAuthorized, .restricted:
            return .secondary

        case .notDetermined, .unknown, .manualCheck:
            return .secondary
        }
    }

    private func statusIcon(
        _ status: PrivacyPermissionStatus
    ) -> String {

        switch status {
        case .authorized:
            return "checkmark.circle.fill"

        case .denied, .notAuthorized:
            return "lock.circle"

        case .restricted:
            return "lock.shield"

        case .limited:
            return "circle.lefthalf.filled"

        case .notDetermined:
            return "minus.circle"

        case .unknown:
            return "questionmark.circle"

        case .manualCheck:
            return "gearshape"
        }
    }

    // MARK: - Helpers

    private func detailRow(
        _ title: String,
        _ value: String
    ) -> some View {

        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(
                    width: 140,
                    alignment: .leading
                )

            Text(value)
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
        }
        .font(.callout)
    }

    private func openDetails(
        _ ids: Set<String>
    ) {
        selectedDetails = filteredPermissions.first {
            ids.contains($0.id)
        }
    }
}
