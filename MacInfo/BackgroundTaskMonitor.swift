
import Foundation
import Combine

private enum BackgroundTaskCollector {
    static func collect() -> String {
        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: "/usr/bin/sfltool"
        )
        process.arguments = ["dumpbtm"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return "Unable to run sfltool: \(error.localizedDescription)"
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(decoding: data, as: UTF8.self)

        return output.isEmpty
            ? "No background task information returned."
            : output
    }
}

@MainActor
final class BackgroundTaskMonitor: ObservableObject {
    @Published private(set) var output = ""
    @Published private(set) var isLoading = false

    func refresh() {
        guard !isLoading else { return }

        isLoading = true

        Task {
            let result = await Task.detached(
                priority: .utility
            ) {
                await BackgroundTaskCollector.collect()
            }.value

            output = result
            isLoading = false
        }
    }
}
