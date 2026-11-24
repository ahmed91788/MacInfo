
import Foundation

enum SystemExtensionScanner {

    // MARK: - Main scan

    nonisolated static func scan() -> SystemExtensionSnapshot {

        let systemCommand = ExtensionCommandRunner.run(
            executable: "/usr/bin/systemextensionsctl",
            arguments: ["list"],
            timeout: 20
        )

        let kernelCommand = ExtensionCommandRunner.run(
            executable: "/usr/bin/kmutil",
            arguments: ["showloaded"],
            timeout: 30
        )

        let systemResult = parseSystemExtensions(
            systemCommand.output
        )

        let kernelResult = parseKernelExtensions(
            kernelCommand.output
        )

        var warnings =
            systemResult.warnings + kernelResult.warnings

        if !systemCommand.succeeded {
            warnings.append(
                "System extension enumeration failed."
            )
        }

        if !kernelCommand.succeeded {
            warnings.append(
                "Kernel extension enumeration failed."
            )
        }

        return SystemExtensionSnapshot(
            capturedAt: Date(),
            systemExtensions: systemResult.items,
            kernelExtensions: kernelResult.items,
            systemCommand: systemCommand,
            kernelCommand: kernelCommand,
            warnings: warnings
        )
    }

    // MARK: - System extensions

    nonisolated static func parseSystemExtensions(
        _ output: String
    ) -> (
        items: [MacSystemExtension],
        warnings: [String]
    ) {
        var items: [MacSystemExtension] = []
        var warnings: [String] = []

        var currentType: MacExtensionType = .unknown
        var expectedCount: Int?

        let pattern =
            #"^\s*([*\s]*)\s*([A-Z0-9]{10}|-)\s+(\S+)\s+\(([^)]*)\)\s+(.*?)\s+\[([^\]]+)\]\s*$"#

        guard let regex = try? NSRegularExpression(
            pattern: pattern
        ) else {
            return (
                [],
                ["Unable to initialize system extension parser."]
            )
        }

        let countRegex = try? NSRegularExpression(
            pattern: #"^\s*(\d+)\s+extension"#
        )

        for rawLine in output.components(
            separatedBy: .newlines
        ) {
            let line = rawLine.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !line.isEmpty else {
                continue
            }

            if let countRegex,
               let match = countRegex.firstMatch(
                   in: line,
                   range: NSRange(
                       line.startIndex...,
                       in: line
                   )
               ),
               let range = Range(
                   match.range(at: 1),
                   in: line
               ) {

                expectedCount = Int(line[range])
                continue
            }

            if line.hasPrefix("---") {
                currentType = extensionType(
                    from: line
                )

                continue
            }

            if line.lowercased().hasPrefix("enabled") {
                continue
            }

            let range = NSRange(
                rawLine.startIndex...,
                in: rawLine
            )

            guard let match = regex.firstMatch(
                in: rawLine,
                range: range
            ) else {
                warnings.append(
                    "Unrecognized system extension row: \(line)"
                )
                continue
            }

            func value(_ index: Int) -> String {
                guard let range = Range(
                    match.range(at: index),
                    in: rawLine
                ) else {
                    return ""
                }

                return String(rawLine[range])
            }

            let markers = value(1)
            let teamID = value(2)
            let bundleID = value(3)
            let version = value(4)
            let name = value(5)
            let rawState = value(6)

            let state = extensionState(
                from: rawState
            )

            let starCount = markers.filter {
                $0 == "*"
            }.count

            // State text is preferred when a single
            // marker is ambiguous in CLI output.

            let active = state == .activated

            let enabled =
                starCount >= 2 ||
                state == .activated

            let reasons = reviewReasons(
                type: currentType,
                teamID: teamID,
                state: state
            )

            let item = MacSystemExtension(
                type: currentType,
                name: name.isEmpty ? bundleID : name,
                bundleIdentifier: bundleID,
                teamIdentifier: teamID,
                version: version,
                enabled: enabled,
                active: active,
                state: state,
                rawState: rawState,
                reviewReasons: reasons
            )

            items.append(item)
        }

        if let expectedCount,
           expectedCount != items.count {

            warnings.append(
                "Reported \(expectedCount) system extensions, " +
                "but parsed \(items.count)."
            )
        }

        if expectedCount == nil && items.isEmpty {
            warnings.append(
                "No recognized system extension inventory."
            )
        }

        items.sort {
            $0.name.localizedCaseInsensitiveCompare(
                $1.name
            ) == .orderedAscending
        }

        return (items, warnings)
    }

    // MARK: - Extension type

    nonisolated private static func extensionType(
        from header: String
    ) -> MacExtensionType {

        let value = header.lowercased()

        if value.contains("network_extension") {
            return .network
        }

        if value.contains("endpoint_security") {
            return .endpointSecurity
        }

        if value.contains("driver_extension") ||
            value.contains("driverkit") {

            return .driverKit
        }

        return .unknown
    }

    // MARK: - Activation state

    nonisolated private static func extensionState(
        from rawState: String
    ) -> MacExtensionState {

        let value = rawState.lowercased()

        if value.contains("waiting for user") ||
            value.contains("pending approval") {

            return .pendingApproval
        }

        if value.contains("uninstall") ||
            value.contains("terminated") ||
            value.contains("waiting to uninstall") {

            return .pendingRemoval
        }

        if value.contains("disabled") ||
            value.contains("inactive") ||
            value.contains("deactivated") {

            return .inactive
        }

        if value.contains("activated enabled") {
            return .activated
        }

        return .unknown
    }

    // MARK: - Review reasons

    nonisolated private static func reviewReasons(
        type: MacExtensionType,
        teamID: String,
        state: MacExtensionState
    ) -> [String] {

        var reasons: [String] = []

        if teamID.isEmpty || teamID == "-" {
            reasons.append(
                "Developer Team ID is unavailable."
            )
        }

        switch state {
        case .pendingApproval:
            reasons.append(
                "Extension is waiting for user approval."
            )

        case .pendingRemoval:
            reasons.append(
                "Extension is pending removal."
            )

        case .unknown:
            reasons.append(
                "Activation state could not be determined."
            )

        default:
            break
        }

        if type == .unknown {
            reasons.append(
                "Extension category is unrecognized."
            )
        }

        return reasons
    }

    // MARK: - Kernel extensions

    nonisolated static func parseKernelExtensions(
        _ output: String
    ) -> (
        items: [MacKernelExtension],
        warnings: [String]
    ) {
        var items: [MacKernelExtension] = []
        var warnings: [String] = []

        let pattern =
            #"^\s*(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+\S+\s+(\S+)\s+\(([^)]*)\)(?:\s+([A-Fa-f0-9-]{36}))?.*$"#

        guard let regex = try? NSRegularExpression(
            pattern: pattern
        ) else {
            return (
                [],
                ["Unable to initialize kernel extension parser."]
            )
        }

        for rawLine in output.components(
            separatedBy: .newlines
        ) {
            let line = rawLine.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !line.isEmpty else {
                continue
            }

            let range = NSRange(
                rawLine.startIndex...,
                in: rawLine
            )

            guard let match = regex.firstMatch(
                in: rawLine,
                range: range
            ) else {
                if line.first?.isNumber == true {
                    warnings.append(
                        "Unrecognized kernel extension row: \(line)"
                    )
                }

                continue
            }

            func value(_ index: Int) -> String {
                guard let range = Range(
                    match.range(at: index),
                    in: rawLine
                ) else {
                    return ""
                }

                return String(rawLine[range])
            }

            let uuid = value(7)

            let item = MacKernelExtension(
                index: Int(value(1)) ?? 0,
                referenceCount: Int(value(2)) ?? 0,
                address: value(3),
                size: value(4),
                bundleIdentifier: value(5),
                version: value(6),
                uuid: uuid.isEmpty ? nil : uuid,
                rawLine: rawLine
            )

            items.append(item)
        }

        if items.isEmpty {
            warnings.append(
                "No recognized loaded kernel extension rows."
            )
        }

        items.sort {
            $0.bundleIdentifier <
            $1.bundleIdentifier
        }

        return (items, warnings)
    }
}
