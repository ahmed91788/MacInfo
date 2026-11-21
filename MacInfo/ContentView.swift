import SwiftUI
import AppKit

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MacInfo")
                .font(.largeTitle)
                .bold()

            Text("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")

            Text("Computer: \(Host.current().localizedName ?? "Unknown")")

            Text("CPU: \(cpuArchitecture)")

            Text("RAM: \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB")

            Text("Date: \(Date().formatted())")

            Button("Copy System Information") {
                let info = """
                macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
                Computer: \(Host.current().localizedName ?? "Unknown")
                CPU: \(cpuArchitecture)
                RAM: \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB
                """
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(info, forType: .string)
            }
        }
        .padding(24)
        .frame(width: 450)
    }

    var cpuArchitecture: String {
        #if arch(arm64)
        return "Apple Silicon"
        #elseif arch(x86_64)
        return "Intel"
        #else
        return "Unknown"
        #endif
    }
}
