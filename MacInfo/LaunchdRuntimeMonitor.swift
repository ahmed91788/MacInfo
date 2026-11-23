
import Foundation
import Combine

struct LaunchdRuntimeEntry: Identifiable, Sendable {
    let label: String
    let pid: Int?
    let lastExitStatus: Int?

    var id: String { label }
}

private enum LaunchdRuntimeScanner {
    static func scan() -> [LaunchdRuntimeEntry] {
        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: "/bin/launchctl"
        )
        process.arguments = ["list"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return []
        }

        let output = String(decoding: data, as: UTF8.self)

        return output
            .components(separatedBy: .newlines)
            .dropFirst()
            .compactMap { line -> LaunchdRuntimeEntry? in
                let fields = line.split(
                    whereSeparator: { $0.isWhitespace }
                )

                guard fields.count >= 3 else {
                    return nil
                }

                let pid = Int(fields[0])
                let exitStatus = Int(fields[1])
                let label = fields.dropFirst(2)
                    .joined(separator: " ")

                return LaunchdRuntimeEntry(
                    label: label,
                    pid: pid,
                    lastExitStatus: exitStatus
                )
            }
    }
}

@MainActor
final class LaunchdRuntimeMonitor: ObservableObject {
    @Published private(set) var entries: [LaunchdRuntimeEntry] = []
    @Published private(set) var isLoading = false

    func refresh() {
        guard !isLoading else { return }

        isLoading = true

        Task {
            let result = await Task.detached(
                priority: .utility
            ) {
                await LaunchdRuntimeScanner.scan()
            }.value

            entries = result
            isLoading = false
        }
    }
}
