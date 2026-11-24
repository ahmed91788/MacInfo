import Foundation

enum ConfigurationProfileScanner {

    // MARK: - Main scan

    nonisolated static func scan()
        -> ConfigurationProfileSnapshot {

        let profileCommand = ExtensionCommandRunner.run(
            executable: "/usr/bin/profiles",
            arguments: [
                "show",
                "-type",
                "configuration",
                "-output",
                "stdout-xml"
            ],
            timeout: 30
        )

        let enrollmentCommand = ExtensionCommandRunner.run(
            executable: "/usr/bin/profiles",
            arguments: [
                "status",
                "-type",
                "enrollment"
            ],
            timeout: 20
        )

        var warnings: [String] = []
        var profiles: [ConfigurationProfile] = []

        if profileCommand.succeeded {
            let result = parseProfiles(
                profileCommand.output
            )

            profiles = result.profiles
            warnings.append(contentsOf: result.warnings)
        } else {
            warnings.append(
                "Unable to enumerate configuration profiles. " +
                "Access may be restricted."
            )
        }

        let enrollment = parseEnrollment(
            enrollmentCommand.succeeded
                ? enrollmentCommand.output
                : ""
        )

        if !enrollmentCommand.succeeded {
            warnings.append(
                "Unable to determine device enrollment status."
            )
        } else if enrollment.mdm == .unknown {
            warnings.append(
                "MDM enrollment status was not recognized."
            )
        }

        return ConfigurationProfileSnapshot(
            capturedAt: Date(),
            profiles: profiles,
            enrollment: enrollment,
            profileCommand: profileCommand,
            enrollmentCommand: enrollmentCommand,
            warnings: warnings
        )
    }

    // MARK: - Parse property list

    nonisolated static func parseProfiles(
        _ output: String
    ) -> (
        profiles: [ConfigurationProfile],
        warnings: [String]
    ) {
        guard !output.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return (
                [],
                ["Profile command returned empty output."]
            )
        }

        var xml = output

        // Ignore informational text surrounding the plist.
        if let start = output.range(of: "<?xml"),
           let end = output.range(
               of: "</plist>",
               options: .backwards
           ),
           start.lowerBound < end.upperBound {

            xml = String(
                output[start.lowerBound..<end.upperBound]
            )
        }

        guard let data = xml.data(using: .utf8) else {
            return (
                [],
                ["Unable to decode profile output."]
            )
        }

        do {
            let plist = try PropertyListSerialization
                .propertyList(
                    from: data,
                    options: [],
                    format: nil
                )

            var profiles: [ConfigurationProfile] = []
            var warnings: [String] = []

            collectProfiles(
                from: plist,
                scope: "Unknown",
                profiles: &profiles,
                warnings: &warnings
            )

            // Deduplicate profiles within the same scope.
            var unique: [String: ConfigurationProfile] = [:]

            for profile in profiles {
                unique[profile.id] = profile
            }

            let sorted = unique.values.sorted {
                $0.name.localizedCaseInsensitiveCompare(
                    $1.name
                ) == .orderedAscending
            }

            return (sorted, warnings)

        } catch {
            return (
                [],
                [
                    "Unable to parse profile property list: " +
                    error.localizedDescription
                ]
            )
        }
    }

    // MARK: - Collect profiles

    nonisolated private static func collectProfiles(
        from value: Any,
        scope: String,
        profiles: inout [ConfigurationProfile],
        warnings: inout [String]
    ) {
        if let array = value as? [Any] {
            for entry in array {
                collectProfiles(
                    from: entry,
                    scope: scope,
                    profiles: &profiles,
                    warnings: &warnings
                )
            }

            return
        }

        guard let dictionary = value as? [String: Any] else {
            return
        }

        let isProfile =
            dictionary["ProfileIdentifier"] != nil ||
            dictionary["ProfileUUID"] != nil ||
            string(dictionary, ["PayloadType"]) == "Configuration"

        if isProfile {
            profiles.append(
                parseProfile(
                    dictionary,
                    scope: scope
                )
            )

            return
        }

        for (key, child) in dictionary {
            if child is [Any] ||
                child is [String: Any] {

                let nextScope =
                    scope == "Unknown"
                        ? normalizeScope(key)
                        : scope

                collectProfiles(
                    from: child,
                    scope: nextScope,
                    profiles: &profiles,
                    warnings: &warnings
                )
            }
        }
    }

    // MARK: - Parse individual profile

    nonisolated private static func parseProfile(
        _ dictionary: [String: Any],
        scope: String
    ) -> ConfigurationProfile {

        let identifier = string(
            dictionary,
            [
                "ProfileIdentifier",
                "PayloadIdentifier"
            ]
        ) ?? "Unknown"

        let uuid = string(
            dictionary,
            [
                "ProfileUUID",
                "PayloadUUID"
            ]
        ) ?? identifier

        let name = string(
            dictionary,
            [
                "ProfileDisplayName",
                "PayloadDisplayName",
                "ProfileName"
            ]
        ) ?? identifier

        let organization = string(
            dictionary,
            [
                "ProfileOrganization",
                "PayloadOrganization"
            ]
        ) ?? "Unknown"

        let profileScope = string(
            dictionary,
            [
                "ProfileScope",
                "PayloadScope"
            ]
        ) ?? scope

        let installedAt = string(
            dictionary,
            [
                "ProfileInstallDate",
                "ProfileInstallationDate"
            ]
        ) ?? "Unknown"

        let removalDisallowed = boolean(
            dictionary,
            [
                "ProfileRemovalDisallowed",
                "PayloadRemovalDisallowed"
            ]
        )

        let payloadDictionaries =
            dictionary["ProfileItems"]
                as? [[String: Any]]
            ?? dictionary["PayloadContent"]
                as? [[String: Any]]
            ?? []

        let profileID = "\(profileScope):\(uuid)"

        let payloads = payloadDictionaries
            .enumerated()
            .map { index, payload in
                parsePayload(
                    payload,
                    parentID: profileID,
                    index: index
                )
            }

        return ConfigurationProfile(
            id: profileID,
            name: name,
            identifier: identifier,
            organization: organization,
            scope: profileScope,
            installedAt: installedAt,
            removalDisallowed: removalDisallowed,
            payloads: payloads
        )
    }

    // MARK: - Parse payload

    nonisolated private static func parsePayload(
        _ dictionary: [String: Any],
        parentID: String,
        index: Int
    ) -> ConfigurationPayload {

        let type = string(
            dictionary,
            [
                "PayloadType",
                "ProfileItemType"
            ]
        ) ?? "Unknown"

        let identifier = string(
            dictionary,
            [
                "PayloadIdentifier",
                "ProfileItemIdentifier"
            ]
        ) ?? "Unknown"

        let name = string(
            dictionary,
            [
                "PayloadDisplayName",
                "ProfileItemDisplayName",
                "ProfileItemName"
            ]
        ) ?? type

        let uuid = string(
            dictionary,
            [
                "PayloadUUID",
                "ProfileItemUUID"
            ]
        ) ?? identifier

        let organization = string(
            dictionary,
            [
                "PayloadOrganization",
                "ProfileItemOrganization"
            ]
        ) ?? "Unknown"

        let category = classifyPayload(type)

        let details = extractDetails(dictionary)

        let reasons = reviewReasons(
            category: category
        )

        return ConfigurationPayload(
            id: "\(parentID):\(uuid):\(index)",
            name: name,
            identifier: identifier,
            type: type,
            category: category,
            organization: organization,
            details: details,
            reviewReasons: reasons
        )
    }

    // MARK: - Payload classification

    nonisolated static func classifyPayload(
        _ type: String
    ) -> ProfilePayloadCategory {

        let value = type.lowercased()

        if value.contains("security.root") ||
            value.contains("security.pem") ||
            value.contains("security.pkcs") ||
            value.contains("security.scep") ||
            value.contains("certificate") {

            return .certificate
        }

        if value.contains("vpn") {
            return .vpn
        }

        if value.contains("proxy") {
            return .proxy
        }

        if value.contains("dns") {
            return .dns
        }

        if value.contains("tcc.configuration") {
            return .privacy
        }

        if value.contains("system-extension") ||
            value.contains("systemextension") ||
            value.contains("kernel-extension") {

            return .systemExtension
        }

        if value == "com.apple.mdm" {
            return .mdm
        }

        if value.contains("applicationaccess") ||
            value.contains("restrictions") {

            return .restrictions
        }

        if value.contains("wifi") ||
            value.contains("ethernet") ||
            value.contains("network") ||
            value.contains("webcontent-filter") {

            return .network
        }

        if value.contains("security") ||
            value.contains("firewall") ||
            value.contains("filevault") ||
            value.contains("fdesetup") {

            return .security
        }

        if value.contains("application") ||
            value.contains("managedclient") {

            return .application
        }

        return .other
    }

    // MARK: - Extract selected metadata

    nonisolated private static func extractDetails(
        _ dictionary: [String: Any]
    ) -> [String: String] {

        // Deliberately exclude passwords, private keys,
        // certificate contents and authentication tokens.

        let allowedKeys: Set<String> = [
            "PayloadDescription",
            "PayloadVersion",
            "PayloadEnabled",
            "VPNType",
            "VPNSubType",
            "RemoteAddress",
            "ProxyType",
            "ProxyServer",
            "ProxyServerPort",
            "ProxyPACURL",
            "DNSProtocol",
            "ServerAddresses",
            "ServerName",
            "SSID_STR",
            "EncryptionType",
            "AutoJoin",
            "AllowedTeamIdentifiers",
            "AllowedSystemExtensions",
            "AllowedSystemExtensionTypes"
        ]

        var result: [String: String] = [:]

        var sources = [dictionary]

        for key in [
            "ProfileItemContent",
            "PayloadContent",
            "DNSSettings",
            "VPN",
            "IKEv2",
            "Proxies"
        ] {
            if let nested =
                dictionary[key] as? [String: Any] {

                sources.append(nested)
            }
        }

        for source in sources {
            for (key, value) in source {
                guard allowedKeys.contains(key) else {
                    continue
                }

                if let text = value as? String {
                    result[key] = text
                } else if let number = value as? NSNumber {
                    result[key] = number.stringValue
                } else if let array = value as? [String] {
                    result[key] = array.joined(
                        separator: ", "
                    )
                }
            }
        }

        return result
    }

    // MARK: - Security review

    nonisolated private static func reviewReasons(
        category: ProfilePayloadCategory
    ) -> [String] {

        switch category {
        case .certificate:
            return [
                "Contains managed certificate configuration. " +
                "Verify the issuer and intended trust settings."
            ]

        case .vpn:
            return [
                "Contains managed VPN settings. " +
                "Verify the provider if unexpected."
            ]

        case .proxy:
            return [
                "Contains managed proxy settings. " +
                "Network traffic may be routed through a proxy."
            ]

        case .dns:
            return [
                "Contains managed DNS settings. " +
                "Verify the configured resolver."
            ]

        case .privacy:
            return [
                "Contains managed privacy permission policies."
            ]

        case .mdm:
            return [
                "Contains device management configuration."
            ]

        case .systemExtension:
            return [
                "Contains system or kernel extension policies."
            ]

        default:
            return []
        }
    }

    // MARK: - Enrollment status

    nonisolated static func parseEnrollment(
        _ output: String
    ) -> DeviceEnrollmentInfo {

        var mdm: ProfileEnrollmentState = .unknown
        var automated: ProfileEnrollmentState = .unknown

        var userApproved: Bool?
        var serverURL: String?

        for rawLine in output.components(
            separatedBy: .newlines
        ) {
            let line = rawLine.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            let lower = line.lowercased()

            if lower.hasPrefix("mdm enrollment:") {
                let value = valueAfterColon(line)
                    .lowercased()

                if value.hasPrefix("yes") {
                    mdm = .enrolled

                    if value.contains("user approved") {
                        userApproved = true
                    }
                } else if value.hasPrefix("no") {
                    mdm = .notEnrolled
                }
            }

            if lower.hasPrefix("enrolled via dep:") ||
                lower.hasPrefix("enrolled via ade:") {

                let value = valueAfterColon(line)
                    .lowercased()

                if value.hasPrefix("yes") {
                    automated = .enrolled
                } else if value.hasPrefix("no") {
                    automated = .notEnrolled
                }
            }

            if lower.hasPrefix("mdm server:") {
                serverURL = valueAfterColon(line)
            }
        }

        return DeviceEnrollmentInfo(
            mdm: mdm,
            automatedEnrollment: automated,
            userApproved: userApproved,
            serverURL: serverURL
        )
    }

    // MARK: - Helpers

    nonisolated private static func valueAfterColon(
        _ text: String
    ) -> String {

        guard let index = text.firstIndex(of: ":") else {
            return ""
        }

        return String(
            text[text.index(after: index)...]
        )
        .trimmingCharacters(in: .whitespaces)
    }

    nonisolated private static func normalizeScope(
        _ value: String
    ) -> String {

        switch value.lowercased() {
        case "_computerlevel", "computer", "system":
            return "Computer"

        case "_userlevel", "user":
            return "User"

        default:
            return value
        }
    }

    nonisolated private static func string(
        _ dictionary: [String: Any],
        _ keys: [String]
    ) -> String? {

        for key in keys {
            if let value = dictionary[key] as? String,
               !value.isEmpty {

                return value
            }

            if let value = dictionary[key] as? Date {
                return ISO8601DateFormatter()
                    .string(from: value)
            }
        }

        return nil
    }

    nonisolated private static func boolean(
        _ dictionary: [String: Any],
        _ keys: [String]
    ) -> Bool? {

        for key in keys {
            if let value = dictionary[key] as? Bool {
                return value
            }

            if let value = dictionary[key] as? String {
                switch value.lowercased() {
                case "yes", "true", "1":
                    return true
                case "no", "false", "0":
                    return false
                default:
                    break
                }
            }
        }

        return nil
    }
}
