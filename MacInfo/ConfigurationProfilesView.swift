import SwiftUI
import AppKit

struct ConfigurationProfilesView: View {

    @StateObject private var store =
        ConfigurationProfileStore()

    @State private var selectedTab: ProfileTab = .profiles
    @State private var search = ""
    @State private var reviewOnly = false
    @State private var selectedCategory = "All"

    @State private var selectedProfileID: String?
    @State private var selectedPayloadID: String?

    @State private var profileDetails: ConfigurationProfile?
    @State private var payloadDetails: ConfigurationPayload?

    @State private var showWarnings = false
    @State private var revealRawOutput = false

    private enum ProfileTab: String, CaseIterable {
        case profiles = "Configuration Profiles"
        case payloads = "Payloads"
        case raw = "Raw Output"
    }

    // MARK: - Filtered data

    private var profiles: [ConfigurationProfile] {
        store.snapshot?.profiles ?? []
    }

    private var filteredProfiles: [ConfigurationProfile] {
        profiles.filter { profile in

            let matchesSearch =
                search.isEmpty ||
                profile.name.localizedCaseInsensitiveContains(search) ||
                profile.identifier.localizedCaseInsensitiveContains(search) ||
                profile.organization.localizedCaseInsensitiveContains(search)

            return matchesSearch &&
                (!reviewOnly || profile.needsReview)
        }
    }

    private var filteredPayloads: [ConfigurationPayload] {
        profiles.flatMap(\.payloads).filter { payload in

            let matchesSearch =
                search.isEmpty ||
                payload.name.localizedCaseInsensitiveContains(search) ||
                payload.identifier.localizedCaseInsensitiveContains(search) ||
                payload.type.localizedCaseInsensitiveContains(search)

            let matchesCategory =
                selectedCategory == "All" ||
                payload.category.rawValue == selectedCategory

            return matchesSearch &&
                matchesCategory &&
                (!reviewOnly || payload.needsReview)
        }
    }

    private var filteredItemCount: Int {
        selectedTab == .profiles
            ? filteredProfiles.count
            : filteredPayloads.count
    }

    // MARK: - Main view

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if store.isScanning {
                ProgressView()
                    .progressViewStyle(.linear)
            }

            if let error = store.errorMessage {
                Label(
                    error,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            summaryCards

            if let enrollment = store.snapshot?.enrollment {
                enrollmentView(enrollment)
            }

            Picker("", selection: $selectedTab) {
                ForEach(
                    ProfileTab.allCases,
                    id: \.self
                ) { tab in
                    Text(tab.rawValue)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if selectedTab != .raw {
                filterToolbar
            }

            if store.snapshot == nil {
                emptyContent
            } else {
                tabContent
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .layoutPriority(1)
            }
        }
        .padding(20)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .sheet(item: $profileDetails) { profile in
            profileDetailsView(profile)
        }
        .sheet(item: $payloadDetails) { payload in
            payloadDetailsView(payload)
        }
        .sheet(isPresented: $showWarnings) {
            warningsView
        }
        .onAppear {
            if store.snapshot == nil {
                store.refresh()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Configuration Profiles")
                    .font(.title2.bold())

                Text(
                    "Inspect managed settings and device enrollment"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let snapshot = store.snapshot {
                    Text(
                        "Last scanned: " +
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

            if let snapshot = store.snapshot,
               !snapshot.warnings.isEmpty {

                Button {
                    showWarnings = true
                } label: {
                    Label(
                        "\(snapshot.warnings.count) Warnings",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
            }

            if store.isScanning {
                Button("Cancel") {
                    store.cancel()
                }
            } else {
                Button {
                    revealRawOutput = false
                    store.refresh()
                } label: {
                    Label(
                        "Refresh",
                        systemImage: "arrow.clockwise"
                    )
                }
            }
        }
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        HStack(spacing: 12) {
            summaryCard(
                "Profiles",
                value: store.snapshot.map {
                    String($0.profileCount)
                } ?? "—",
                icon: "doc.text",
                color: .blue
            )

            summaryCard(
                "Payloads",
                value: store.snapshot.map {
                    String($0.payloadCount)
                } ?? "—",
                icon: "square.stack",
                color: .blue
            )

            summaryCard(
                "MDM Enrollment",
                value: store.snapshot?
                    .enrollment.mdm.rawValue ?? "—",
                icon: "desktopcomputer",
                color: .secondary
            )

            summaryCard(
                "Needs Review",
                value: store.snapshot.map {
                    String($0.reviewCount)
                } ?? "—",
                icon: "exclamationmark.triangle",
                color: .orange
            )
        }
    }

    private func summaryCard(
        _ title: String,
        value: String,
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

            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
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

    // MARK: - Enrollment information

    private func enrollmentView(
        _ enrollment: DeviceEnrollmentInfo
    ) -> some View {

        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 26))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Device Management")
                            .font(.headline)

                        Text(enrollmentDescription(enrollment))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                Divider()

                HStack(alignment: .top, spacing: 20) {
                    enrollmentField(
                        "MDM Enrollment",
                        value: enrollment.mdm.rawValue
                    )

                    enrollmentField(
                        "Automated Enrollment",
                        value: enrollment
                            .automatedEnrollment.rawValue
                    )

                    enrollmentField(
                        "User Approved",
                        value: approvalDescription(
                            enrollment.userApproved
                        )
                    )
                }

                if let serverURL = enrollment.serverURL,
                   !serverURL.isEmpty {

                    Divider()

                    Text("MDM Server")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(serverURL)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
            .padding(6)
        }
    }

    private func enrollmentField(
        _ title: String,
        value: String
    ) -> some View {

        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.callout.weight(.medium))
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private func enrollmentDescription(
        _ enrollment: DeviceEnrollmentInfo
    ) -> String {

        switch enrollment.mdm {
        case .enrolled:
            return "This Mac is enrolled in device management."

        case .notEnrolled:
            return "No active MDM enrollment was reported."

        case .unknown:
            return "Device enrollment status is unavailable."
        }
    }

    private func approvalDescription(
        _ value: Bool?
    ) -> String {

        guard let value else {
            return "Unknown"
        }

        return value ? "Yes" : "No"
    }

    // MARK: - Filters

    private var filterToolbar: some View {
        HStack(spacing: 12) {
            TextField(
                "Search profiles and payloads...",
                text: $search
            )
            .textFieldStyle(.roundedBorder)

            if selectedTab == .payloads {
                Picker(
                    "Category",
                    selection: $selectedCategory
                ) {
                    Text("All Categories")
                        .tag("All")

                    ForEach(
                        ProfilePayloadCategory.allCases,
                        id: \.rawValue
                    ) { category in
                        Text(category.rawValue)
                            .tag(category.rawValue)
                    }
                }
                .frame(width: 200)
            }

            Toggle(
                "Needs review",
                isOn: $reviewOnly
            )
            .toggleStyle(.checkbox)

            Text("\(filteredItemCount) items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .profiles:
            profilesTable

        case .payloads:
            payloadsTable

        case .raw:
            rawOutputView
        }
    }

    private var emptyContent: some View {
        ContentUnavailableView(
            store.isScanning
                ? "Scanning Profiles"
                : "No Profile Inventory",
            systemImage: "doc.text",
            description: Text(
                store.isScanning
                    ? "Collecting configuration information..."
                    : "Click Refresh to inspect profiles."
            )
        )
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    // MARK: - Profiles table

    private var profilesTable: some View {
        Table(
            filteredProfiles,
            selection: $selectedProfileID
        ) {
            TableColumn("Profile") { profile in
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name)
                            .fontWeight(.medium)

                        Text(profile.identifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            TableColumn(
                "Organization",
                value: \.organization
            )
            .width(min: 100, ideal: 140)

            TableColumn(
                "Scope",
                value: \.scope
            )
            .width(min: 70, ideal: 100)

            TableColumn("Payloads") { profile in
                Text(profile.payloads.count.formatted())
                    .monospacedDigit()
            }
            .width(70)

            TableColumn("Removal") { profile in
                Text(
                    removalDescription(
                        profile.removalDisallowed
                    )
                )
                .foregroundStyle(.secondary)
            }
            .width(90)

            TableColumn("Review") { profile in
                if profile.needsReview {
                    Label(
                        "Review",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .width(90)
        }
        .contextMenu(
            forSelectionType: String.self
        ) { ids in
            Button("View Details") {
                openProfileDetails(ids)
            }
            .disabled(ids.isEmpty)

            Button("Copy Identifier") {
                if let profile = filteredProfiles.first(
                    where: { ids.contains($0.id) }
                ) {
                    copy(profile.identifier)
                }
            }
            .disabled(ids.isEmpty)

        } primaryAction: { ids in
            openProfileDetails(ids)
        }
        .overlay {
            if filteredProfiles.isEmpty {
                ContentUnavailableView(
                    profiles.isEmpty
                        ? "No Profiles Reported"
                        : "No Matching Profiles",
                    systemImage: "doc.text",
                    description: Text(
                        profiles.isEmpty
                            ? "No accessible configuration profiles were reported."
                            : "Try changing the search or filters."
                    )
                )
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Payloads table

    private var payloadsTable: some View {
        Table(
            filteredPayloads,
            selection: $selectedPayloadID
        ) {
            TableColumn("Payload") { payload in
                HStack(spacing: 8) {
                    Image(systemName: payload.category.icon)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(payload.name)
                            .fontWeight(.medium)

                        Text(payload.identifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            TableColumn("Category") { payload in
                Text(payload.category.rawValue)
            }
            .width(min: 100, ideal: 150)

            TableColumn(
                "Payload Type",
                value: \.type
            )

            TableColumn("Review") { payload in
                if payload.needsReview {
                    Label(
                        "Review",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .width(90)
        }
        .contextMenu(
            forSelectionType: String.self
        ) { ids in
            Button("View Details") {
                openPayloadDetails(ids)
            }
            .disabled(ids.isEmpty)

            Button("Copy Payload Type") {
                if let payload = filteredPayloads.first(
                    where: { ids.contains($0.id) }
                ) {
                    copy(payload.type)
                }
            }
            .disabled(ids.isEmpty)

        } primaryAction: { ids in
            openPayloadDetails(ids)
        }
        .overlay {
            if filteredPayloads.isEmpty {
                ContentUnavailableView(
                    "No Matching Payloads",
                    systemImage: "square.stack"
                )
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Profile details

    private func profileDetailsView(
        _ profile: ConfigurationProfile
    ) -> some View {

        VStack(alignment: .leading, spacing: 16) {
            Label(
                profile.name,
                systemImage: "doc.text"
            )
            .font(.title2.bold())

            Text(profile.identifier)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox("Profile Information") {
                        VStack(spacing: 10) {
                            detailRow(
                                "Identifier",
                                profile.identifier
                            )

                            detailRow(
                                "Organization",
                                profile.organization
                            )

                            detailRow(
                                "Scope",
                                profile.scope
                            )

                            detailRow(
                                "Installed",
                                profile.installedAt
                            )

                            detailRow(
                                "Removal",
                                removalDescription(
                                    profile.removalDisallowed
                                )
                            )
                        }
                        .padding(8)
                    }

                    GroupBox(
                        "Payloads (\(profile.payloads.count))"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(profile.payloads) { payload in
                                VStack(
                                    alignment: .leading,
                                    spacing: 5
                                ) {
                                    Label(
                                        payload.name,
                                        systemImage:
                                            payload.category.icon
                                    )
                                    .font(.callout.weight(.medium))

                                    Text(payload.type)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)

                                    if payload.needsReview {
                                        Text(
                                            payload.reviewReasons
                                                .joined(separator: "\n")
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                    }
                                }
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )

                                Divider()
                            }

                            if profile.payloads.isEmpty {
                                Text("No payload details available.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }

                    reviewSection(profile.reviewReasons)
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Button("Copy Identifier") {
                    copy(profile.identifier)
                }

                Spacer()

                Button("Close") {
                    profileDetails = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 700, height: 580)
    }

    // MARK: - Payload details

    private func payloadDetailsView(
        _ payload: ConfigurationPayload
    ) -> some View {

        VStack(alignment: .leading, spacing: 16) {
            Label(
                payload.name,
                systemImage: payload.category.icon
            )
            .font(.title2.bold())

            Text(payload.type)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox("Payload Information") {
                        VStack(spacing: 10) {
                            detailRow(
                                "Identifier",
                                payload.identifier
                            )

                            detailRow(
                                "Type",
                                payload.type
                            )

                            detailRow(
                                "Category",
                                payload.category.rawValue
                            )

                            detailRow(
                                "Organization",
                                payload.organization
                            )
                        }
                        .padding(8)
                    }

                    if !payload.details.isEmpty {
                        GroupBox("Configuration Details") {
                            VStack(spacing: 10) {
                                ForEach(
                                    payload.details.keys.sorted(),
                                    id: \.self
                                ) { key in
                                    detailRow(
                                        key,
                                        payload.details[key] ?? ""
                                    )
                                }
                            }
                            .padding(8)
                        }
                    }

                    reviewSection(payload.reviewReasons)
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Button("Copy Payload Type") {
                    copy(payload.type)
                }

                Spacer()

                Button("Close") {
                    payloadDetails = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 700, height: 550)
    }

    // MARK: - Review section

    private func reviewSection(
        _ reasons: [String]
    ) -> some View {

        GroupBox("Security Review") {
            VStack(alignment: .leading, spacing: 10) {
                if reasons.isEmpty {
                    Label(
                        "No automatic review flags",
                        systemImage: "checkmark.circle"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(reasons, id: \.self) { reason in
                        Label(
                            reason,
                            systemImage:
                                "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                Text(
                    "Managed configurations may be legitimate. " +
                    "Review flags are not evidence of malware."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding(8)
        }
    }

    // MARK: - Raw diagnostic output

    private var rawOutputView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "Raw profile output may contain sensitive settings.",
                systemImage: "exclamationmark.shield"
            )
            .font(.caption)
            .foregroundStyle(.orange)

            Toggle(
                "Reveal raw diagnostic output",
                isOn: $revealRawOutput
            )
            .toggleStyle(.checkbox)

            if revealRawOutput {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let snapshot = store.snapshot {
                            commandOutput(
                                snapshot.enrollmentCommand
                            )

                            commandOutput(
                                snapshot.profileCommand
                            )
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Diagnostic Output Hidden",
                    systemImage: "eye.slash",
                    description: Text(
                        "Enable the checkbox to inspect command output."
                    )
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            }
        }
    }

    private func commandOutput(
        _ result: ExtensionCommandResult
    ) -> some View {

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "terminal")

                Text(result.command)
                    .font(
                        .system(
                            .caption,
                            design: .monospaced
                        )
                    )

                Spacer()

                Button {
                    copy(
                        result.output +
                        "\n" +
                        result.errorOutput
                    )
                } label: {
                    Label(
                        "Copy",
                        systemImage: "doc.on.doc"
                    )
                }
            }

            Divider()

            Text(
                result.output.isEmpty
                    ? "No standard output."
                    : result.output
            )
            .font(
                .system(
                    .caption,
                    design: .monospaced
                )
            )
            .textSelection(.enabled)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )

            if !result.errorOutput.isEmpty {
                Divider()

                Text("Standard Error")
                    .font(.caption.bold())

                Text(result.errorOutput)
                    .font(
                        .system(
                            .caption,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(
            Color.secondary.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: - Warnings

    private var warningsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan Warnings")
                .font(.title2.bold())

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(
                        Array(
                            (store.snapshot?.warnings ?? [])
                                .enumerated()
                        ),
                        id: \.offset
                    ) { entry in
                        Label(
                            entry.element,
                            systemImage:
                                "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }

            HStack {
                Spacer()

                Button("Close") {
                    showWarnings = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 650, height: 400)
    }

    // MARK: - Helpers

    private func removalDescription(
        _ disallowed: Bool?
    ) -> String {

        guard let disallowed else {
            return "Unknown"
        }

        return disallowed
            ? "Restricted"
            : "Allowed"
    }

    private func detailRow(
        _ title: String,
        _ value: String
    ) -> some View {

        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(
                    width: 160,
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

    private func openProfileDetails(
        _ ids: Set<String>
    ) {
        profileDetails = filteredProfiles.first {
            ids.contains($0.id)
        }
    }

    private func openPayloadDetails(
        _ ids: Set<String>
    ) {
        payloadDetails = filteredPayloads.first {
            ids.contains($0.id)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()

        NSPasteboard.general.setString(
            text,
            forType: .string
        )
    }
}
