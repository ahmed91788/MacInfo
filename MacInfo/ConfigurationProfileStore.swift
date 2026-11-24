import Foundation
import Combine

@MainActor
final class ConfigurationProfileStore: ObservableObject {

    @Published private(set) var snapshot:
        ConfigurationProfileSnapshot?

    @Published private(set) var isScanning = false

    @Published private(set) var errorMessage: String?

    private var workerTask:
        Task<ConfigurationProfileSnapshot, Never>?

    private var activeScanID: UUID?

    func refresh() {
        guard !isScanning else {
            return
        }

        isScanning = true
        errorMessage = nil

        let scanID = UUID()
        activeScanID = scanID

        let worker = Task.detached(
            priority: .utility
        ) {
            ConfigurationProfileScanner.scan()
        }

        workerTask = worker

        Task { [weak self] in
            let result = await worker.value

            guard let self,
                  self.activeScanID == scanID else {
                return
            }

            if worker.isCancelled {
                self.errorMessage = "Scan cancelled."
            } else {
                self.snapshot = result

                if !result.isComplete {
                    self.errorMessage =
                        "Some configuration information " +
                        "could not be collected."
                }
            }

            self.isScanning = false
            self.workerTask = nil
            self.activeScanID = nil
        }
    }

    func cancel() {
        workerTask?.cancel()
    }

    deinit {
        workerTask?.cancel()
    }
}
