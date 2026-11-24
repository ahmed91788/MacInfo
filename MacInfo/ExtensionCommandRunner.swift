
import Foundation
import Darwin

enum ExtensionCommandRunner {

    nonisolated static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 20
    ) -> ExtensionCommandResult {

        let fm = FileManager.default

        let directory = fm.temporaryDirectory
            .appendingPathComponent(
                "MacInfoExtensions-\(UUID().uuidString)",
                isDirectory: true
            )

        let stdoutURL = directory
            .appendingPathComponent("stdout.txt")

        let stderrURL = directory
            .appendingPathComponent("stderr.txt")

        defer {
            try? fm.removeItem(at: directory)
        }

        func failure(
            _ message: String
        ) -> ExtensionCommandResult {
            ExtensionCommandResult(
                executable: executable,
                arguments: arguments,
                output: "",
                errorOutput: message,
                exitCode: nil,
                timedOut: false
            )
        }

        do {
            try fm.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [
                    .posixPermissions: 0o700
                ]
            )

            try Data().write(to: stdoutURL)
            try Data().write(to: stderrURL)

            let stdout = try FileHandle(
                forWritingTo: stdoutURL
            )

            defer {
                try? stdout.close()
            }

            let stderr = try FileHandle(
                forWritingTo: stderrURL
            )

            defer {
                try? stderr.close()
            }

            let process = Process()

            process.executableURL = URL(
                fileURLWithPath: executable
            )

            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = FileHandle.nullDevice

            var environment =
                ProcessInfo.processInfo.environment

            environment["LANG"] = "C"
            environment["LC_ALL"] = "C"

            process.environment = environment

            try process.run()

            let deadline = ProcessInfo.processInfo
                .systemUptime + timeout

            var timedOut = false

            while process.isRunning {
                if ProcessInfo.processInfo.systemUptime
                    >= deadline ||
                    Task<Never, Never>.isCancelled {

                    timedOut =
                        !Task<Never, Never>.isCancelled

                    process.terminate()

                    let terminationDeadline =
                        ProcessInfo.processInfo.systemUptime + 1

                    while process.isRunning &&
                        ProcessInfo.processInfo.systemUptime
                        < terminationDeadline {

                        Thread.sleep(
                            forTimeInterval: 0.05
                        )
                    }

                    if process.isRunning {
                        Darwin.kill(
                            process.processIdentifier,
                            SIGKILL
                        )
                    }

                    break
                }

                Thread.sleep(forTimeInterval: 0.05)
            }

            process.waitUntilExit()

            try? stdout.synchronize()
            try? stderr.synchronize()

            let outputData =
                (try? Data(contentsOf: stdoutURL)) ?? Data()

            let errorData =
                (try? Data(contentsOf: stderrURL)) ?? Data()

            let output = String(
                decoding: outputData,
                as: UTF8.self
            )

            let errorOutput = String(
                decoding: errorData,
                as: UTF8.self
            )

            return ExtensionCommandResult(
                executable: executable,
                arguments: arguments,
                output: output,
                errorOutput: errorOutput,
                exitCode: process.terminationStatus,
                timedOut: timedOut
            )

        } catch {
            return failure(error.localizedDescription)
        }
    }
}
