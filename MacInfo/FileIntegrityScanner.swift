
import Foundation

enum FileIntegrityScanner {
    static func scan(
        applications: [InstalledApplication],
        startupItems: [StartupItem]
    ) -> [BaselineFileHash] {
        var targets: [String: (category: String, name: String)] = [:]

        // Application main executables
        for app in applications {
            let bundleURL = URL(fileURLWithPath: app.path)

            guard let bundle = Bundle(url: bundleURL),
                  let executableURL = bundle.executableURL else {
                continue
            }

            let path = executableURL.standardizedFileURL.path

            targets[path] = (
                category: "Application",
                name: app.name
            )
        }

        // Startup executable targets
        for item in startupItems {
            let path = item.executablePath

            guard path.hasPrefix("/") else {
                continue
            }

            let normalized = URL(
                fileURLWithPath: path
            ).standardizedFileURL.path

            if targets[normalized] == nil {
                targets[normalized] = (
                    category: "Startup",
                    name: item.label
                )
            }
        }

        return targets.keys.sorted().compactMap { path in
            guard let target = targets[path] else {
                return nil
            }

            return BaselineFileHash(
                path: path,
                category: target.category,
                name: target.name,
                result: FileIntegrityHasher.hash(path: path)
            )
        }
    }
}
