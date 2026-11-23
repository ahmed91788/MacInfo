
import Foundation

enum SecurityBaselineEngine {
    
    static func capture() -> SecurityBaseline {
        let apps = ApplicationScanner.scan()
        let startup = StartupScanner.scan()

        let hashes = FileIntegrityScanner.scan(
            applications: apps,
            startupItems: startup
        )

        return SecurityBaseline(
            id: UUID(),
            createdAt: Date(),
            applications: apps.map {
                BaselineApplication(
                    path: $0.path,
                    name: $0.name,
                    bundleIdentifier: $0.bundleIdentifier,
                    version: $0.version,
                    signature: $0.signature.rawValue,
                    teamIdentifier: $0.teamIdentifier
                )
            },
            startupItems: startup.map {
                BaselineStartupItem(
                    plistPath: $0.plistPath,
                    label: $0.label,
                    executablePath: $0.executablePath,
                    arguments: $0.arguments,
                    signingStatus: $0.signingStatus,
                    teamIdentifier: $0.teamIdentifier,
                    runAtLoad: $0.runAtLoad,
                    keepAlive: $0.keepAlive,
                    disabledInPlist: $0.disabledInPlist
                )
            },
            fileHashes: hashes
        )
    }


    static func compare(
        baseline: SecurityBaseline,
        current: SecurityBaseline
    ) -> BaselineComparison {
        var changes: [BaselineChange] = []

        let oldApps = Dictionary(
            uniqueKeysWithValues: baseline.applications.map {
                ($0.path, $0)
            }
        )

        let newApps = Dictionary(
            uniqueKeysWithValues: current.applications.map {
                ($0.path, $0)
            }
        )

        for (path, app) in newApps {
            if let previous = oldApps[path] {
                var differences: [String] = []

                if previous.version != app.version {
                    differences.append("Version changed")
                }

                if previous.signature != app.signature {
                    differences.append("Signature classification changed")
                }

                if previous.teamIdentifier != app.teamIdentifier {
                    differences.append("Signing Team ID changed")
                }

                if !differences.isEmpty {
                    changes.append(
                        BaselineChange(
                            id: "app.modified.\(path)",
                            type: .modified,
                            category: "Application",
                            name: app.name,
                            details: differences.joined(separator: ", ")
                        )
                    )
                }
            } else {
                changes.append(
                    BaselineChange(
                        id: "app.added.\(path)",
                        type: .added,
                        category: "Application",
                        name: app.name,
                        details: path
                    )
                )
            }
        }

        for (path, app) in oldApps where newApps[path] == nil {
            changes.append(
                BaselineChange(
                    id: "app.removed.\(path)",
                    type: .removed,
                    category: "Application",
                    name: app.name,
                    details: path
                )
            )
        }

        let oldStartup = Dictionary(
            uniqueKeysWithValues: baseline.startupItems.map {
                ($0.plistPath, $0)
            }
        )

        let newStartup = Dictionary(
            uniqueKeysWithValues: current.startupItems.map {
                ($0.plistPath, $0)
            }
        )

        for (path, item) in newStartup {
            if let previous = oldStartup[path] {
                var differences: [String] = []

                if previous.executablePath != item.executablePath {
                    differences.append("Executable changed")
                }

                if previous.arguments != item.arguments {
                    differences.append("Arguments changed")
                }

                if previous.signingStatus != item.signingStatus {
                    differences.append("Signature changed")
                }

                if previous.teamIdentifier != item.teamIdentifier {
                    differences.append("Signing Team ID changed")
                }

                if previous.runAtLoad != item.runAtLoad {
                    differences.append("RunAtLoad changed")
                }

                if previous.keepAlive != item.keepAlive {
                    differences.append("KeepAlive changed")
                }

                if previous.disabledInPlist != item.disabledInPlist {
                    differences.append("Disabled setting changed")
                }

                if !differences.isEmpty {
                    changes.append(
                        BaselineChange(
                            id: "startup.modified.\(path)",
                            type: .modified,
                            category: "Startup",
                            name: item.label,
                            details: differences.joined(separator: ", ")
                        )
                    )
                }
            } else {
                changes.append(
                    BaselineChange(
                        id: "startup.added.\(path)",
                        type: .added,
                        category: "Startup",
                        name: item.label,
                        details: path
                    )
                )
            }
        }

        for (path, item) in oldStartup where newStartup[path] == nil {
            changes.append(
                BaselineChange(
                    id: "startup.removed.\(path)",
                    type: .removed,
                    category: "Startup",
                    name: item.label,
                    details: path
                )
            )
        }
        
        
        let oldHashes = Dictionary(
            uniqueKeysWithValues: baseline.fileHashes.map {
                ($0.path, $0)
            }
        )

        let newHashes = Dictionary(
            uniqueKeysWithValues: current.fileHashes.map {
                ($0.path, $0)
            }
        )

        for (path, file) in newHashes {
            guard let previous = oldHashes[path] else {
                // A new hash target may already be represented by
                // an added application or startup entry.
                continue
            }

            let oldResult = previous.result
            let newResult = file.result

            if oldResult.status == .success &&
               newResult.status == .success {

                if oldResult.sha256 != newResult.sha256 {
                    
                    changes.append(
                        BaselineChange(
                            id: "hash.modified.\(path)",
                            type: .modified,
                            category: "File Integrity",
                            name: file.name,
                            details: "SHA-256 changed: \(path)",
                            oldHash: oldResult.sha256,
                            newHash: newResult.sha256
                        )
                    )

                }

            } else if oldResult.status == .success &&
                      newResult.status == .missing {

                changes.append(
                    BaselineChange(
                        id: "hash.missing.\(path)",
                        type: .removed,
                        category: "File Integrity",
                        name: file.name,
                        details:
                            "Previously hashed executable is missing: \(path)"
                    )
                )

            } else if newResult.status != .success {
                changes.append(
                    BaselineChange(
                        id: "hash.unavailable.\(path)",
                        type: .modified,
                        category: "File Integrity",
                        name: file.name,
                        details:
                            "Unable to verify executable: " +
                            newResult.status.rawValue
                    )
                )
            }
        }


        changes.sort {
            if $0.type.rawValue != $1.type.rawValue {
                return $0.type.rawValue < $1.type.rawValue
            }

            return $0.name < $1.name
        }

        return BaselineComparison(changes: changes)
    }
}
