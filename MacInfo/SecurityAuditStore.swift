
import Foundation
import Combine

@MainActor
final class SecurityAuditStore: ObservableObject {
    @Published private(set) var currentReport: AuditReport?
    @Published private(set) var history: [AuditReport] = []
    @Published private(set) var isScanning = false
    @Published private(set) var errorMessage: String?
    
    @Published private(set) var progress = AuditProgress(
        completed: 0,
        total: AuditScannerID.allCases.count,
        currentScanner: ""
    )

    private var scanTask: Task<Void, Never>?

    private let maxHistory = 20

    private var historyURL: URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent(
            "MacInfo",
            isDirectory: true
        )

        return directory.appendingPathComponent(
            "security-audit-history.json"
        )
    }

    init() {
        loadHistory()
    }

    
    func scan() {
        guard !isScanning else { return }

        isScanning = true
        errorMessage = nil

        progress = AuditProgress(
            completed: 0,
            total: AuditScannerID.allCases.count,
            currentScanner: "Starting"
        )

        scanTask = Task {
            let report = await Task.detached(
                priority: .userInitiated
            ) {
                await SecurityAuditEngine.scan { update in
                    Task { @MainActor in
                        self.progress = update
                    }
                }
            }.value

            currentReport = report
            history.insert(report, at: 0)

            if history.count > maxHistory {
                history = Array(history.prefix(maxHistory))
            }

            saveHistory()

            isScanning = false
            scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func selectReport(_ report: AuditReport) {
        currentReport = report
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let reports = try? JSONDecoder().decode(
                [AuditReport].self,
                from: data
              ) else {
            return
        }

        history = reports
        currentReport = reports.first
    }

    private func saveHistory() {
        do {
            let directory = historyURL.deletingLastPathComponent()

            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let data = try JSONEncoder().encode(history)
            try data.write(to: historyURL, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
