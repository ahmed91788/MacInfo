
import Foundation
import Combine
import Security

enum SecurityStatus: String, Sendable {
    case enabled = "Enabled"
    case disabled = "Disabled"
    case unavailable = "Unavailable"
    case unknown = "Unknown"
}

struct SecurityCheck: Identifiable, Sendable {
    let id: String
    let title: String
    let status: SecurityStatus
    let details: String
    let recommendation: String
}

struct SecuritySnapshot: Sendable {
    let checkedAt: Date
    let checks: [SecurityCheck]
    let signingIdentifier: String?
    let teamIdentifier: String?
    let hardenedRuntime: Bool?
}

private struct CommandResult {
    let exitCode: Int32
    let output: String
}

private enum SecurityCollector {
    static func run(
        _ executable: String,
        arguments: [String]
    ) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return CommandResult(
                exitCode: -1,
                output: error.localizedDescription
            )
        }

        // Read before waiting to avoid blocking if the pipe fills.
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func collect() -> SecuritySnapshot {
        var checks: [SecurityCheck] = []

        let sip = run(
            "/usr/bin/csrutil",
            arguments: ["status"]
        )

        let sipText = sip.output.lowercased()
        let sipStatus: SecurityStatus

        if sipText.contains("system integrity protection status: enabled") {
            sipStatus = .enabled
        } else if sipText.contains(
            "system integrity protection status: disabled"
        ) {
            sipStatus = .disabled
        } else {
            sipStatus = .unknown
        }

        checks.append(
            SecurityCheck(
                id: "sip",
                title: "System Integrity Protection",
                status: sipStatus,
                details: sip.output,
                recommendation:
                    "SIP should normally remain enabled to protect system files and processes."
            )
        )

        let gatekeeper = run(
            "/usr/sbin/spctl",
            arguments: ["--status"]
        )

        let gatekeeperText = gatekeeper.output.lowercased()
        let gatekeeperStatus: SecurityStatus

        if gatekeeperText.contains("assessments enabled") {
            gatekeeperStatus = .enabled
        } else if gatekeeperText.contains("assessments disabled") {
            gatekeeperStatus = .disabled
        } else {
            gatekeeperStatus = .unknown
        }

        checks.append(
            SecurityCheck(
                id: "gatekeeper",
                title: "Gatekeeper",
                status: gatekeeperStatus,
                details: gatekeeper.output,
                recommendation:
                    "Keep Gatekeeper enabled to help verify downloaded applications."
            )
        )

        let fileVault = run(
            "/usr/bin/fdesetup",
            arguments: ["status"]
        )

        let fileVaultText = fileVault.output.lowercased()
        let fileVaultStatus: SecurityStatus

        if fileVaultText.contains("filevault is on") {
            fileVaultStatus = .enabled
        } else if fileVaultText.contains("filevault is off") {
            fileVaultStatus = .disabled
        } else {
            fileVaultStatus = .unknown
        }

        checks.append(
            SecurityCheck(
                id: "filevault",
                title: "FileVault",
                status: fileVaultStatus,
                details: fileVault.output,
                recommendation:
                    "FileVault protects data at rest if your Mac is lost or stolen."
            )
        )

        let firewall = run(
            "/usr/libexec/ApplicationFirewall/socketfilterfw",
            arguments: ["--getglobalstate"]
        )

        let firewallText = firewall.output.lowercased()
        let firewallStatus: SecurityStatus

        if firewallText.contains("enabled") {
            firewallStatus = .enabled
        } else if firewallText.contains("disabled") {
            firewallStatus = .disabled
        } else {
            firewallStatus = .unknown
        }

        checks.append(
            SecurityCheck(
                id: "firewall",
                title: "Application Firewall",
                status: firewallStatus,
                details: firewall.output,
                recommendation:
                    "Enable the firewall when incoming network access is unnecessary."
            )
        )

        let signature = inspectSignature()

        checks.append(
            SecurityCheck(
                id: "signature",
                title: "Application Code Signature",
                status: signature.valid ? .enabled : .unknown,
                details: signature.details,
                recommendation:
                    "Distribute MacInfo with a valid Developer ID signature and Hardened Runtime."
            )
        )

        return SecuritySnapshot(
            checkedAt: Date(),
            checks: checks,
            signingIdentifier: signature.identifier,
            teamIdentifier: signature.teamID,
            hardenedRuntime: signature.hardenedRuntime
        )
    }

    private static func inspectSignature() -> (
        valid: Bool,
        identifier: String?,
        teamID: String?,
        hardenedRuntime: Bool?,
        details: String
    ) {
        let bundleURL = Bundle.main.bundleURL

        var staticCode: SecStaticCode?

        let createStatus = SecStaticCodeCreateWithPath(
            bundleURL as CFURL,
            SecCSFlags(),
            &staticCode
        )

        guard createStatus == errSecSuccess,
              let staticCode else {
            return (
                false, nil, nil, nil,
                "Unable to inspect the application signature."
            )
        }

        let validity = SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(),
            nil
        )

        var information: CFDictionary?

        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        )

        guard infoStatus == errSecSuccess,
              let dictionary = information as? [String: Any] else {
            return (
                validity == errSecSuccess,
                nil, nil, nil,
                "Signature validation result: \(validity)"
            )
        }

        let identifier = dictionary[
            kSecCodeInfoIdentifier as String
        ] as? String

        let teamID = dictionary[
            kSecCodeInfoTeamIdentifier as String
        ] as? String

        let flags = dictionary[
            kSecCodeInfoFlags as String
        ] as? UInt32

        // CS_RUNTIME is the Hardened Runtime flag.
        let hardened = flags.map { ($0 & 0x00010000) != 0 }

        let details = """
        Signature valid: \(validity == errSecSuccess)
        Identifier: \(identifier ?? "Unavailable")
        Team ID: \(teamID ?? "Unavailable")
        Hardened Runtime: \(hardened.map(String.init(describing:)) ?? "Unavailable")
        """

        return (
            validity == errSecSuccess,
            identifier,
            teamID,
            hardened,
            details
        )
    }
}

@MainActor
final class SecurityMonitor: ObservableObject {
    @Published private(set) var snapshot: SecuritySnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    func refresh() {
        guard !isRefreshing else { return }

        isRefreshing = true
        errorMessage = nil

        Task {
            let result = await Task.detached(
                priority: .userInitiated
            ) {
                await SecurityCollector.collect()
            }.value

            snapshot = result
            isRefreshing = false
        }
    }
}
