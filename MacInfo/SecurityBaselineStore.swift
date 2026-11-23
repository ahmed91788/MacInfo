
import Foundation
import Combine

@MainActor
final class SecurityBaselineStore: ObservableObject {
    @Published private(set) var baseline: SecurityBaseline?
    @Published private(set) var current: SecurityBaseline?
    @Published private(set) var comparison: BaselineComparison?
    @Published private(set) var isScanning = false
    @Published var errorMessage: String?

    private var baselineURL: URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("MacInfo", isDirectory: true)

        return directory.appendingPathComponent(
            "security-baseline.json"
        )
    }

    init() {
        loadBaseline()
    }

    func createBaseline() {
        guard !isScanning else { return }

        isScanning = true
        errorMessage = nil

        Task {
            let snapshot = await Task.detached(
                priority: .userInitiated
            ) {
                SecurityBaselineEngine.capture()
            }.value

            do {
                try save(snapshot)
                baseline = snapshot
                current = snapshot
                comparison = BaselineComparison(changes: [])
            } catch {
                errorMessage = error.localizedDescription
            }

            isScanning = false
        }
    }

    func compareWithBaseline() {
        guard !isScanning else { return }

        guard let baseline else {
            errorMessage = "Create a baseline first."
            return
        }

        isScanning = true
        errorMessage = nil

        Task {
            let snapshot = await Task.detached(
                priority: .userInitiated
            ) {
                SecurityBaselineEngine.capture()
            }.value

            current = snapshot
            comparison = SecurityBaselineEngine.compare(
                baseline: baseline,
                current: snapshot
            )

            isScanning = false
        }
    }

    private func loadBaseline() {
        guard let data = try? Data(contentsOf: baselineURL),
              let snapshot = try? JSONDecoder().decode(
                SecurityBaseline.self,
                from: data
              ) else {
            return
        }

        baseline = snapshot
    }

    private func save(_ snapshot: SecurityBaseline) throws {
        let directory = baselineURL.deletingLastPathComponent()

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(snapshot)
        try data.write(to: baselineURL, options: .atomic)
    }
}
