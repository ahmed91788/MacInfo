
import Foundation
import Combine

struct SignatureCheck: Identifiable, Sendable {
    let id: String
    let title: String
    let value: String
    let passed: Bool?
}

struct SignatureReport: Sendable {
    let path: String
    let bundleIdentifier: String
    let executableName: String
    let checkedAt: Date

    let signatureValid: Bool
    let identifier: String?
    let teamIdentifier: String?
    let authorities: [String]

    let hardenedRuntime: Bool
    let secureTimestamp: String?
    let entitlements: String

    let gatekeeperAccepted: Bool
    let staplerValidated: Bool

    let checks: [SignatureCheck]
    let rawOutput: String
}

private struct CommandOutput: Sendable {
    let exitCode: Int32
    let output: String
}

private enum SignatureCommands {
    static func run(
        _ executable: String,
        _ arguments: [String]
    ) -> CommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return CommandOutput(
                exitCode: -1,
                output: error.localizedDescription
            )
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandOutput(
            exitCode: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self)
        )
    }

    static func inspect(_ url: URL) -> SignatureReport {
        let path = url.path

        let bundle = Bundle(url: url)
        let bundleIdentifier =
            bundle?.bundleIdentifier ?? "Unavailable"

        let executableName =
            bundle?.object(forInfoDictionaryKey: "CFBundleExecutable")
                as? String ?? url.deletingPathExtension().lastPathComponent

        let verify = run(
            "/usr/bin/codesign",
            ["--verify", "--strict", "--verbose=2", path]
        )

        let details = run(
            "/usr/bin/codesign",
            ["-dv", "--verbose=4", path]
        )

        let entitlements = run(
            "/usr/bin/codesign",
            ["-d", "--entitlements", ":-", path]
        )

        let gatekeeper = run(
            "/usr/sbin/spctl",
            ["--assess", "--type", "execute", "--verbose=4", path]
        )

        let stapler = run(
            "/usr/bin/xcrun",
            ["stapler", "validate", path]
        )

        let lines = details.output.components(
            separatedBy: .newlines
        )

        func field(_ prefix: String) -> String? {
            lines.first {
                $0.hasPrefix(prefix)
            }?.dropFirst(prefix.count).trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }

        let identifier = field("Identifier=")
        let teamID = field("TeamIdentifier=")

        let authorities = lines.compactMap { line -> String? in
            guard line.hasPrefix("Authority=") else {
                return nil
            }
            return String(line.dropFirst("Authority=".count))
        }

        let flags = field("CodeDirectory v")
        let runtimeEnabled = details.output.contains("runtime")

        // A secure timestamp appears as Timestamp=...
        // Signed Time=... is not equivalent.
        let timestamp = field("Timestamp=")

        let signatureValid = verify.exitCode == 0
        let gatekeeperAccepted = gatekeeper.exitCode == 0
        let staplerValidated = stapler.exitCode == 0

        let checks = [
            SignatureCheck(
                id: "signature",
                title: "Code Signature",
                value: signatureValid ? "Valid" : "Invalid",
                passed: signatureValid
            ),
            SignatureCheck(
                id: "runtime",
                title: "Hardened Runtime",
                value: runtimeEnabled ? "Enabled" : "Disabled",
                passed: runtimeEnabled
            ),
            SignatureCheck(
                id: "timestamp",
                title: "Secure Timestamp",
                value: timestamp ?? "Missing",
                passed: timestamp != nil
            ),
            SignatureCheck(
                id: "gatekeeper",
                title: "Gatekeeper",
                value: gatekeeperAccepted ? "Accepted" : "Rejected",
                passed: gatekeeperAccepted
            ),
            SignatureCheck(
                id: "stapler",
                title: "Stapled Ticket",
                value: staplerValidated ? "Valid" : "Not found or invalid",
                passed: staplerValidated
            )
        ]

        let raw = """
        ===== SIGNATURE VERIFICATION =====
        \(verify.output)

        ===== SIGNATURE DETAILS =====
        \(details.output)

        ===== ENTITLEMENTS =====
        \(entitlements.output)

        ===== GATEKEEPER =====
        \(gatekeeper.output)

        ===== STAPLER =====
        \(stapler.output)
        """

        _ = flags

        return SignatureReport(
            path: path,
            bundleIdentifier: bundleIdentifier,
            executableName: executableName,
            checkedAt: Date(),
            signatureValid: signatureValid,
            identifier: identifier,
            teamIdentifier: teamID,
            authorities: authorities,
            hardenedRuntime: runtimeEnabled,
            secureTimestamp: timestamp,
            entitlements: entitlements.output,
            gatekeeperAccepted: gatekeeperAccepted,
            staplerValidated: staplerValidated,
            checks: checks,
            rawOutput: raw
        )
    }
}

@MainActor
final class SignatureInspector: ObservableObject {
    @Published private(set) var report: SignatureReport?
    @Published private(set) var isInspecting = false
    @Published private(set) var errorMessage: String?

    func inspect(_ url: URL) {
        guard !isInspecting else { return }

        isInspecting = true
        errorMessage = nil

        Task {
            let result = await Task.detached(
                priority: .userInitiated
            ) {
                await SignatureCommands.inspect(url)
            }.value

            report = result
            isInspecting = false
        }
    }
}
