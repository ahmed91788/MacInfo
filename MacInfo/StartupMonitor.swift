
import Foundation
import Combine

enum StartupItemType: String, CaseIterable, Sendable {
    case userAgent = "User Agent"
    case globalAgent = "Global Agent"
    case globalDaemon = "Global Daemon"
    case systemAgent = "System Agent"
    case systemDaemon = "System Daemon"
}

struct StartupItem: Identifiable, Sendable {
    let id: String
    let label: String
    let type: StartupItemType

    let plistPath: String
    let executablePath: String
    let arguments: [String]

    let runAtLoad: Bool
    let keepAlive: Bool
    let disabledInPlist: Bool
    let programExists: Bool?

    // MacInfo 1.9 additions
    let modifiedAt: Date?
    let signingStatus: String
    let teamIdentifier: String?
    let isRunning: Bool?
    let reviewReasons: [String]

    var needsReview: Bool {
        !reviewReasons.isEmpty
    }
}

private enum StartupScanner {
    static func scan() -> [StartupItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser

        let locations: [(URL, StartupItemType)] = [
            (
                home.appendingPathComponent("Library/LaunchAgents"),
                .userAgent
            ),
            (
                URL(fileURLWithPath: "/Library/LaunchAgents"),
                .globalAgent
            ),
            (
                URL(fileURLWithPath: "/Library/LaunchDaemons"),
                .globalDaemon
            ),
            (
                URL(fileURLWithPath: "/System/Library/LaunchAgents"),
                .systemAgent
            ),
            (
                URL(fileURLWithPath: "/System/Library/LaunchDaemons"),
                .systemDaemon
            )
        ]

        var results: [StartupItem] = []

        for (directory, type) in locations {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for url in files where url.pathExtension.lowercased() == "plist" {
                guard let item = parse(url, type: type) else {
                    continue
                }

                results.append(item)
            }
        }

        return results.sorted {
            $0.label.localizedStandardCompare($1.label)
                == .orderedAscending
        }
    }

    private static func parse(
        _ url: URL,
        type: StartupItemType
    ) -> StartupItem? {
        guard let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ),
              let plist = object as? [String: Any] else {
            return nil
        }

        let label = plist["Label"] as? String
            ?? url.deletingPathExtension().lastPathComponent

        let arguments = plist["ProgramArguments"] as? [String] ?? []

        let executablePath =
            plist["Program"] as? String
            ?? arguments.first
            ?? ""

        let runAtLoad = plist["RunAtLoad"] as? Bool ?? false

        let keepAlive: Bool
        if let value = plist["KeepAlive"] as? Bool {
            keepAlive = value
        } else if plist["KeepAlive"] is [String: Any] {
            // Conditional KeepAlive configuration.
            keepAlive = true
        } else {
            keepAlive = false
        }

        let disabled = plist["Disabled"] as? Bool ?? false

        let programExists: Bool?
        if executablePath.hasPrefix("/") {
            programExists = FileManager.default.fileExists(
                atPath: executablePath
            )
        } else {
            programExists = nil
        }

        
        let analysis = PersistenceAnalyzer.analyze(
            plistURL: url,
            executablePath: executablePath,
            programExists: programExists,
            type: type
        )

        return StartupItem(
            id: url.path,
            label: label,
            type: type,
            plistPath: url.path,
            executablePath: executablePath,
            arguments: arguments,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            disabledInPlist: disabled,
            programExists: programExists,
            modifiedAt: analysis.modifiedAt,
            signingStatus: analysis.signingStatus,
            teamIdentifier: analysis.teamIdentifier,
            isRunning: nil,
            reviewReasons: analysis.reviewReasons
        )
    }
}

@MainActor
final class StartupMonitor: ObservableObject {
    @Published private(set) var items: [StartupItem] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanned: Date?

    func scan() {
        guard !isScanning else { return }

        isScanning = true

        Task {
            let result = await Task.detached(
                priority: .userInitiated
            ) {
                await StartupScanner.scan()
            }.value

            items = result
            lastScanned = Date()
            isScanning = false
        }
    }
}
