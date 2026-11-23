
import Foundation
import Combine
import Darwin

struct ProcessRecord: Identifiable {
    let pid: Int32
    let parentPID: Int32
    let name: String
    let path: String
    let userID: UInt32
    let cpuPercent: Double
    let memoryBytes: UInt64

    var id: Int32 { pid }
}

@MainActor
final class ProcessMonitor: ObservableObject {
    @Published private(set) var processes: [ProcessRecord] = []
    @Published private(set) var lastUpdated: Date?

    private var refreshTask: Task<Void, Never>?
    private var previousCPU: [Int32: (start: UInt64, time: UInt64)] = [:]
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
        let elapsed = previousSampleTime.map {
            Double(now - $0) / 1_000_000_000
        } ?? 0

        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return }

        var pids = [pid_t](
            repeating: 0,
            count: Int(count) + 256
        )

        let bytes = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(
                buffer.baseAddress,
                Int32(buffer.count * MemoryLayout<pid_t>.size)
            )
        }

        guard bytes > 0 else { return }

        let numberOfPIDs = min(
            Int(bytes),
            pids.count
        )

        var records: [ProcessRecord] = []
        var nextCPU: [Int32: (start: UInt64, time: UInt64)] = [:]

        for pid in pids.prefix(numberOfPIDs) where pid > 0 {
            var info = proc_taskallinfo()

            let result = withUnsafeMutablePointer(to: &info) {
                proc_pidinfo(
                    pid,
                    PROC_PIDTASKALLINFO,
                    0,
                    $0,
                    Int32(MemoryLayout<proc_taskallinfo>.size)
                )
            }

            guard result == MemoryLayout<proc_taskallinfo>.size else {
                continue
            }

            let bsd = info.pbsd
            let task = info.ptinfo

            let start = UInt64(bsd.pbi_start_tvsec) * 1_000_000
                + UInt64(bsd.pbi_start_tvusec)

            let cpuTime = task.pti_total_user
                + task.pti_total_system

            nextCPU[pid] = (start, cpuTime)

            var cpu = 0.0

            if elapsed > 0,
               let previous = previousCPU[pid],
               previous.start == start,
               cpuTime >= previous.time {
                cpu = Double(cpuTime - previous.time)
                    / (elapsed * 1_000_000_000)
                    * 100
            }

            var nameBuffer = [CChar](
                repeating: 0,
                count: Int(MAXPATHLEN)
            )

            let nameLength = nameBuffer.withUnsafeMutableBufferPointer {
                proc_name(pid, $0.baseAddress, UInt32($0.count))
            }

            let name = nameLength > 0
                ? String(cString: nameBuffer)
                : "PID \(pid)"

            var pathBuffer = [CChar](
                repeating: 0,
                count: Int(MAXPATHLEN) * 4
            )

            let pathLength = pathBuffer.withUnsafeMutableBufferPointer {
                proc_pidpath(
                    pid,
                    $0.baseAddress,
                    UInt32($0.count)
                )
            }

            let path = pathLength > 0
                ? String(cString: pathBuffer)
                : ""

            records.append(
                ProcessRecord(
                    pid: pid,
                    parentPID: Int32(bsd.pbi_ppid),
                    name: name,
                    path: path,
                    userID: bsd.pbi_uid,
                    cpuPercent: max(0, cpu),
                    memoryBytes: task.pti_resident_size
                )
            )
        }

        previousCPU = nextCPU
        previousSampleTime = now
        processes = records
        lastUpdated = Date()
    }
}
