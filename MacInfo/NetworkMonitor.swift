
import Foundation
import Combine
import Darwin

struct NetworkInterfaceStats: Identifiable {
    let name: String
    let address: String
    let isUp: Bool
    let bytesReceived: UInt64
    let bytesSent: UInt64
    let downloadSpeed: Double
    let uploadSpeed: Double

    var id: String { name }
}

struct NetworkSpeedSample: Identifiable {
    let timestamp: Date
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double

    var id: Date { timestamp }
}

private struct NetworkCounters {
    var received: UInt64
    var sent: UInt64
}

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var interfaces: [NetworkInterfaceStats] = []
    @Published private(set) var history: [NetworkSpeedSample] = []
    @Published private(set) var totalDownloadSpeed = 0.0
    @Published private(set) var totalUploadSpeed = 0.0
    @Published private(set) var lastUpdated: Date?

    private var refreshTask: Task<Void, Never>?
    private var previousCounters: [String: NetworkCounters] = [:]
    private var previousSampleTime: UInt64?

    init() {
        refresh()

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
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
        let now = DispatchTime.now().uptimeNanoseconds

        let elapsed: Double
        if let previousSampleTime, now > previousSampleTime {
            elapsed = Double(now - previousSampleTime) / 1_000_000_000
        } else {
            elapsed = 0
        }

        var addresses: [String: String] = [:]
        var counters: [String: NetworkCounters] = [:]
        var interfaceStates: [String: Bool] = [:]

        var pointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&pointer) == 0,
              let first = pointer else {
            return
        }

        defer { freeifaddrs(pointer) }

        var current: UnsafeMutablePointer<ifaddrs>? = first

        while let node = current {
            let item = node.pointee
            current = item.ifa_next

            let name = String(cString: item.ifa_name)
            let flags = Int32(item.ifa_flags)

            let isUp = (flags & Int32(IFF_UP)) != 0
            interfaceStates[name] = isUp

            guard let address = item.ifa_addr else {
                continue
            }

            let family = Int32(address.pointee.sa_family)

            if family == AF_INET || family == AF_INET6 {
                var host = [CChar](
                    repeating: 0,
                    count: Int(NI_MAXHOST)
                )

                let length: socklen_t = family == AF_INET
                    ? socklen_t(MemoryLayout<sockaddr_in>.size)
                    : socklen_t(MemoryLayout<sockaddr_in6>.size)

                let result = host.withUnsafeMutableBufferPointer {
                    getnameinfo(
                        address,
                        length,
                        $0.baseAddress,
                        socklen_t($0.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                }

                if result == 0 {
                    let ip = String(cString: host)

                    if addresses[name] == nil || family == AF_INET {
                        addresses[name] = ip
                    }
                }
            }

            if family == AF_LINK,
               let data = item.ifa_data {
                let stats = data.assumingMemoryBound(
                    to: if_data.self
                ).pointee

                counters[name] = NetworkCounters(
                    received: UInt64(stats.ifi_ibytes),
                    sent: UInt64(stats.ifi_obytes)
                )
            }
        }

        var results: [NetworkInterfaceStats] = []

        for (name, value) in counters {
            let previous = previousCounters[name]

            var download = 0.0
            var upload = 0.0

            if elapsed > 0, let previous {
                if value.received >= previous.received {
                    download = Double(
                        value.received - previous.received
                    ) / elapsed
                }

                if value.sent >= previous.sent {
                    upload = Double(
                        value.sent - previous.sent
                    ) / elapsed
                }
            }

            results.append(
                NetworkInterfaceStats(
                    name: name,
                    address: addresses[name] ?? "",
                    isUp: interfaceStates[name] ?? false,
                    bytesReceived: value.received,
                    bytesSent: value.sent,
                    downloadSpeed: download,
                    uploadSpeed: upload
                )
            )
        }

        results.sort { $0.name < $1.name }

        // Exclude loopback from aggregate network throughput.
        let active = results.filter {
            $0.isUp && !$0.name.hasPrefix("lo")
        }

        totalDownloadSpeed = active.reduce(0) {
            $0 + $1.downloadSpeed
        }

        totalUploadSpeed = active.reduce(0) {
            $0 + $1.uploadSpeed
        }

        interfaces = results
        previousCounters = counters
        previousSampleTime = now
        lastUpdated = Date()

        history.append(
            NetworkSpeedSample(
                timestamp: Date(),
                downloadBytesPerSecond: totalDownloadSpeed,
                uploadBytesPerSecond: totalUploadSpeed
            )
        )

        let cutoff = Date().addingTimeInterval(-600)
        history.removeAll { $0.timestamp < cutoff }

        if history.count > 301 {
            history.removeFirst(history.count - 301)
        }
    }
}
