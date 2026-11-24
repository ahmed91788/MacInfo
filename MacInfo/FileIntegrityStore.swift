
import Foundation
import Combine

@MainActor
final class FileIntegrityStore: ObservableObject {
    @Published private(set) var baseline: SecurityBaseline?

    @Published private(set) var results:
        [IntegrityVerificationResult] = []

    @Published private(set) var isScanning = false
    @Published private(set) var wasCancelled = false
    @Published private(set) var hasScanned = false

    @Published private(set) var progress =
        IntegrityScanProgress(
            completed: 0,
            total: 0,
            currentPath: ""
        )

    @Published var options = IntegrityScanOptions()
    @Published var errorMessage: String?

    private var workerTask:
        Task<[IntegrityVerificationResult], Never>?

    private var activeScanID: UUID?

    private var baselineURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent(
            "MacInfo",
            isDirectory: true
        )
        .appendingPathComponent(
            "security-baseline.json"
        )
    }

    init() {
        reloadBaseline()
    }

    func reloadBaseline() {
        guard !isScanning else { return }

        baseline = nil
        errorMessage = nil
        results = []
        hasScanned = false
        wasCancelled = false

        do {
            let data = try Data(contentsOf: baselineURL)

            baseline = try JSONDecoder().decode(
                SecurityBaseline.self,
                from: data
            )
        } catch {
            errorMessage =
                "Unable to load baseline: " +
                error.localizedDescription
        }
    }

    func scan() {
        guard !isScanning else { return }

        guard let baseline else {
            errorMessage = "Create a security baseline first."
            return
        }

        guard !baseline.fileHashes.isEmpty else {
            errorMessage =
                "The baseline contains no file hashes. " +
                "Create a new baseline using MacInfo 2.3 or later."
            return
        }

        let scanID = UUID()
        let scanOptions = options

        activeScanID = scanID
        isScanning = true
        wasCancelled = false
        hasScanned = false
        errorMessage = nil
        results = []

        progress = IntegrityScanProgress(
            completed: 0,
            total: 0,
            currentPath: "Collecting file targets..."
        )

        let worker = Task.detached(
            priority: .utility
        ) { [weak self] in

            await IntegrityVerificationEngine.verify(
                baseline: baseline,
                options: scanOptions
            ) { update in

                Task { @MainActor [weak self] in
                    guard let self,
                          self.activeScanID == scanID else {
                        return
                    }

                    self.progress = update
                }
            }
        }

        workerTask = worker

        Task {
            let output = await worker.value

            guard activeScanID == scanID else {
                return
            }

            results = output
            wasCancelled = worker.isCancelled
            hasScanned = true
            isScanning = false

            workerTask = nil
            activeScanID = nil
        }
    }

    func cancel() {
        workerTask?.cancel()
    }

    func count(
        _ status: IntegrityVerificationStatus
    ) -> Int {
        results.filter {
            $0.status == status
        }.count
    }
}
