
import Foundation

struct PerformanceSample: Identifiable {
    let timestamp: Date
    let cpuUsage: Double
    let memoryUsed: UInt64

    var id: Date { timestamp }
}

enum PerformanceRange: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .oneMinute: "1 min"
        case .fiveMinutes: "5 min"
        case .tenMinutes: "10 min"
        }
    }
}
