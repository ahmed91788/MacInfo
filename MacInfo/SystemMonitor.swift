
import Foundation
import Combine
import Darwin
import IOKit.ps

struct MacSnapshot: Codable {
    let capturedAt: Date
    let computerName: String
    let model: String
    let processor: String
    let macOS: String
    let architecture: String
    let logicalCores: Int
    let uptime: TimeInterval

    let cpuUsage: Double
    let totalMemory: UInt64
    let usedMemory: UInt64
    let totalStorage: Int64
    let freeStorage: Int64

    let batteryPercent: Int?
    let isCharging: Bool?
    let networkInterfaces: [NetworkInterface]
}

struct NetworkInterface: Codable, Identifiable {
    let name: String
    let address: String
    let family: String

    var id: String { "\(name)-\(family)-\(address)" }
}

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot: MacSnapshot?

    private var refreshTask: Task<Void, Never>?
    private var previousCPU: (used: UInt64, total: UInt64)?
    
    @Published private(set) var performanceHistory: [PerformanceSample] = []
    @Published private(set) var isMonitoringPaused = false

    private let maximumHistoryDuration: TimeInterval = 600
    private let maximumSamples = 301

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
    
    func toggleMonitoring() {
        isMonitoringPaused.toggle()

        // Reset the CPU baseline when resuming so the next
        // reading doesn't average across the paused interval.
        if !isMonitoringPaused {
            previousCPU = nil
        }
    }

    
    func refresh() {
        guard !isMonitoringPaused else { return }

        let now = Date()
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = Self.memoryUsage()
        let disk = Self.diskUsage()
        let battery = Self.batteryInfo()
        let cpu = cpuUsage()

        let newSnapshot = MacSnapshot(
            capturedAt: now,
            computerName: Host.current().localizedName ?? "Mac",
            model: Self.sysctlString("hw.model"),
            processor: Self.processorName(),
            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.architecture(),
            logicalCores: ProcessInfo.processInfo.activeProcessorCount,
            uptime: ProcessInfo.processInfo.systemUptime,
            cpuUsage: cpu,
            totalMemory: totalMemory,
            usedMemory: usedMemory,
            totalStorage: disk.total,
            freeStorage: disk.free,
            batteryPercent: battery.percent,
            isCharging: battery.charging,
            networkInterfaces: Self.networkAddresses()
        )

        snapshot = newSnapshot

        performanceHistory.append(
            PerformanceSample(
                timestamp: now,
                cpuUsage: cpu,
                memoryUsed: usedMemory
            )
        )

        let cutoff = now.addingTimeInterval(-maximumHistoryDuration)

        performanceHistory.removeAll {
            $0.timestamp < cutoff
        }

        if performanceHistory.count > maximumSamples {
            performanceHistory.removeFirst(
                performanceHistory.count - maximumSamples
            )
        }
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0,
              size > 0 else {
            return "Unknown"
        }

        var data = [CChar](repeating: 0, count: size)

        guard sysctlbyname(name, &data, &size, nil, 0) == 0 else {
            return "Unknown"
        }

        return data.withUnsafeBufferPointer {
            guard let base = $0.baseAddress else {
                return "Unknown"
            }
            return String(cString: base)
        }
    }

    private static func processorName() -> String {
        let name = sysctlString("machdep.cpu.brand_string")
        if name != "Unknown" { return name }

        #if arch(arm64)
        return "Apple Silicon"
        #elseif arch(x86_64)
        return "Intel"
        #else
        return "Unknown"
        #endif
    }

    private static func architecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "Unknown"
        #endif
    }

    private func cpuUsage() -> Double {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size /
            MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) {
                host_statistics(
                    mach_host_self(),
                    HOST_CPU_LOAD_INFO,
                    $0,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let ticks = info.cpu_ticks
        let user = UInt64(ticks.0)
        let system = UInt64(ticks.1)
        let idle = UInt64(ticks.2)
        let nice = UInt64(ticks.3)

        let used = user + system + nice
        let total = used + idle

        defer { previousCPU = (used, total) }

        guard let previous = previousCPU,
              total > previous.total,
              used >= previous.used else {
            return 0
        }

        return Double(used - previous.used) /
               Double(total - previous.total) * 100
    }

    private static func memoryUsage() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size /
            MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) {
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    $0,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let pages = UInt64(stats.active_count)
                  + UInt64(stats.wire_count)
                  + UInt64(stats.compressor_page_count)

        return pages * UInt64(vm_kernel_page_size)
    }

    private static func diskUsage() -> (total: Int64, free: Int64) {
        let url = URL(fileURLWithPath: "/")

        guard let values = try? url.resourceValues(
            forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ]
        ) else {
            return (0, 0)
        }

        return (
            Int64(values.volumeTotalCapacity ?? 0),
            Int64(values.volumeAvailableCapacity ?? 0)
        )
    }

    private static func batteryInfo() -> (
        percent: Int?,
        charging: Bool?
    ) {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info)
            .takeRetainedValue() as [CFTypeRef]

        for source in sources {
            guard let raw = IOPSGetPowerSourceDescription(
                info, source
            )?.takeUnretainedValue(),
                  let description = raw as? [String: Any] else {
                continue
            }

            let current = description[
                kIOPSCurrentCapacityKey
            ] as? Int

            let maximum = description[
                kIOPSMaxCapacityKey
            ] as? Int

            let charging = description[
                kIOPSIsChargingKey
            ] as? Bool

            let percent: Int?
            if let current, let maximum, maximum > 0 {
                percent = Int(
                    Double(current) / Double(maximum) * 100
                )
            } else {
                percent = nil
            }

            return (percent, charging)
        }

        return (nil, nil)
    }

    private static func networkAddresses() -> [NetworkInterface] {
        var pointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&pointer) == 0,
              let first = pointer else {
            return []
        }

        defer { freeifaddrs(pointer) }

        var results: [NetworkInterface] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first

        while let node = current {
            let item = node.pointee

            if let address = item.ifa_addr {
                let family = Int32(address.pointee.sa_family)

                if family == AF_INET || family == AF_INET6 {
                    var buffer = [CChar](
                        repeating: 0,
                        count: Int(NI_MAXHOST)
                    )

                    let length: socklen_t = family == AF_INET
                        ? socklen_t(MemoryLayout<sockaddr_in>.size)
                        : socklen_t(MemoryLayout<sockaddr_in6>.size)

                    let result = getnameinfo(
                        address,
                        length,
                        &buffer,
                        socklen_t(buffer.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )

                    if result == 0 {
                        results.append(
                            NetworkInterface(
                                name: String(cString: item.ifa_name),
                                address: String(cString: buffer),
                                family: family == AF_INET
                                    ? "IPv4" : "IPv6"
                            )
                        )
                    }
                }
            }

            current = item.ifa_next
        }

        return results.sorted {
            ($0.name, $0.family, $0.address) <
            ($1.name, $1.family, $1.address)
        }
    }
}
