
import Foundation
import Combine

struct NetworkConnection: Identifiable {
    let pid: Int32
    let processName: String
    let fileDescriptor: Int32
    let protocolName: String
    let localAddress: String
    let localPort: UInt16
    let remoteAddress: String
    let remotePort: UInt16
    let state: String

    var id: String { "\(pid)-\(fileDescriptor)" }
}

@MainActor
final class NetworkConnectionsMonitor: ObservableObject {
    @Published private(set) var connections: [NetworkConnection] = []
    @Published private(set) var lastUpdated: Date?

    private var refreshTask: Task<Void, Never>?

    init() {
        refresh()

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }
                self?.refresh()
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    func refresh() {
        let capacity = 20_000

        var buffer = [MacInfoConnection](
            repeating: MacInfoConnection(),
            count: capacity
        )

        let count = buffer.withUnsafeMutableBufferPointer {
            macinfo_collect_connections(
                $0.baseAddress,
                Int32($0.count)
            )
        }

        guard count >= 0 else { return }

        connections = buffer.prefix(Int(count)).map { item in
            NetworkConnection(
                pid: item.pid,
                processName: Self.decode(item.process_name),
                fileDescriptor: item.fd,
                protocolName: Self.decode(item.protocol_name),
                localAddress: Self.decode(item.local_address),
                localPort: item.local_port,
                remoteAddress: Self.decode(item.remote_address),
                remotePort: item.remote_port,
                state: Self.decode(item.state)
            )
        }

        lastUpdated = Date()
    }

    private static func decode<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { bytes in
            let chars = bytes.prefix {
                $0 != 0
            }

            return String(
                decoding: chars,
                as: UTF8.self
            )
        }
    }
}
