import Foundation
import Combine

@MainActor
final class NetworkReputationStore:
    ObservableObject {

    @Published private(set) var items:
        [NetworkReputationItem] = []

    @Published private(set) var isScanning = false

    @Published private(set) var isUpdating = false

    @Published private(set) var isLookingUp = false

    @Published private(set) var databaseCount = 0

    @Published private(set) var databaseDate: Date?

    @Published private(set) var lastScanAt: Date?

    @Published private(set) var errorMessage: String?

    @Published private(set) var coverageMessage: String?

    private let client =
        NetworkReputationClient.shared

    private var operationTask: Task<Void, Never>?

    var isBusy: Bool {
        isScanning || isUpdating || isLookingUp
    }

    var threatCount: Int {

        items.filter {
            !$0.matchedRanges.isEmpty
        }.count
    }

    var checkedCount: Int {

        items.filter {
            $0.status == .noMatch ||
            $0.status == .threatMatch
        }.count
    }

    var uncheckedCount: Int {

        items.filter {
            $0.status == .unchecked ||
            $0.status == .unavailable ||
            $0.status == .stale
        }.count
    }

    // MARK: - Load database

    func prepare() async {

        do {

            try await client.loadDatabase()

            await refreshDatabaseInformation()

        } catch {

            errorMessage = error.localizedDescription
        }
    }

    private func refreshDatabaseInformation() async {

        let info =
            await client.databaseInformation()

        databaseCount = info.count
        databaseDate = info.date
    }

    // MARK: - Update database

    func updateDatabase() {

        guard !isBusy else {
            return
        }

        isUpdating = true
        errorMessage = nil

        operationTask = Task {

            defer {
                isUpdating = false
                operationTask = nil
            }

            do {

                try await client.loadDatabase()

                try await client.updateDatabase()

                await refreshDatabaseInformation()

                try Task.checkCancellation()

                await recheckItems()

            } catch is CancellationError {

                errorMessage = "Update cancelled."

            } catch {

                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Scan current connections

    func scanConnections() {

        guard !isBusy else {
            return
        }

        isScanning = true
        errorMessage = nil

        operationTask = Task {

            defer {
                isScanning = false
                operationTask = nil
            }

            do {

                try await client.loadDatabase()

                await refreshDatabaseInformation()

                let worker = Task.detached(
                    priority: .utility
                ) {
                    try NetworkReputationCollector.scan()
                }

                let collected =
                    try await withTaskCancellationHandler {

                        try await worker.value

                    } onCancel: {

                        worker.cancel()
                    }

                try Task.checkCancellation()

                items = collected

                coverageMessage =
                    "TCP connections visible to the current user. " +
                    "Some system processes may be inaccessible."

                await recheckItems()

                lastScanAt = Date()

            } catch is CancellationError {

                errorMessage = "Scan cancelled."

            } catch {

                errorMessage = error.localizedDescription
            }
        }
    }

    private func recheckItems() async {

        for index in items.indices {

            guard !Task.isCancelled else {
                return
            }

            let result = await client.check(
                items[index]
            )

            items[index] = result
        }

        items.sort {

            let left = !$0.matchedRanges.isEmpty
            let right = !$1.matchedRanges.isEmpty

            if left != right {
                return left
            }

            return $0.address < $1.address
        }
    }

    // MARK: - Manual IP check

    func checkAddress(_ address: String) {

        guard !isBusy else {
            return
        }

        let input = address.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard let normalized =
            IPAddressUtilities.normalized(input) else {

            errorMessage = "Enter a valid IPv4 or IPv6 address."

            return
        }

        isScanning = true
        errorMessage = nil

        operationTask = Task {

            defer {
                isScanning = false
                operationTask = nil
            }

            do {

                try await client.loadDatabase()

                await refreshDatabaseInformation()

                let existing = items.first {
                    $0.address == normalized
                }

                let item = existing ??
                    NetworkReputationItem(
                        address: normalized
                    )

                let checked = await client.check(item)

                if let index = items.firstIndex(
                    where: {
                        $0.address == normalized
                    }
                ) {

                    items[index] = checked

                } else {

                    items.append(checked)
                }

            } catch {

                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Network information

    func lookupNetworkInformation(
        address: String
    ) {

        guard !isBusy else {
            return
        }

        isLookingUp = true
        errorMessage = nil

        operationTask = Task {

            defer {
                isLookingUp = false
                operationTask = nil
            }

            do {

                let information =
                    try await client.lookupASN(
                        address: address
                    )

                try Task.checkCancellation()

                if let index = items.firstIndex(
                    where: {
                        $0.address == address
                    }
                ) {

                    items[index].networkInfo =
                        information
                }

            } catch {

                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        operationTask?.cancel()
    }

    func clear() {

        guard !isBusy else {
            return
        }

        items.removeAll()
        errorMessage = nil
    }
}
