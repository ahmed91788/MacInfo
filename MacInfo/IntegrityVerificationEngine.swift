
import Foundation

enum IntegrityVerificationEngine {
    static func verify(
        baseline: SecurityBaseline,
        options: IntegrityScanOptions,
        progress: @Sendable (IntegrityScanProgress) -> Void
    ) -> [IntegrityVerificationResult] {

        var targets: [String: IntegrityTarget] = [:]

        let baselineHashes = Dictionary(
            baseline.fileHashes.map {
                ($0.path, $0)
            },
            uniquingKeysWith: { first, _ in first }
        )

        func addTarget(
            path: String,
            name: String,
            category: String
        ) {
            guard path.hasPrefix("/") else {
                return
            }

            if category == "Application" &&
                !options.includeApplications {
                return
            }

            if category == "Startup" &&
                !options.includeStartupItems {
                return
            }

            if !options.includeSystemFiles &&
                (path.hasPrefix("/System/") ||
                 path.hasPrefix("/usr/bin/") ||
                 path.hasPrefix("/usr/sbin/") ||
                 path.hasPrefix("/bin/") ||
                 path.hasPrefix("/sbin/")) {
                return
            }

            targets[path] = IntegrityTarget(
                path: path,
                name: name,
                category: category
            )
        }

        // MARK: Existing baseline targets

        for file in baseline.fileHashes {
            addTarget(
                path: file.path,
                name: file.name,
                category: file.category
            )
        }

        // MARK: Current applications

        if options.includeApplications &&
            !Task<Never, Never>.isCancelled {

            for app in ApplicationScanner.scan() {
                guard let bundle = Bundle(
                    url: URL(fileURLWithPath: app.path)
                ),
                let executable = bundle.executableURL else {
                    continue
                }

                addTarget(
                    path: executable.standardizedFileURL.path,
                    name: app.name,
                    category: "Application"
                )
            }
        }

        // MARK: Current startup targets

        if options.includeStartupItems &&
            !Task<Never, Never>.isCancelled {

            for item in StartupScanner.scan() {
                guard item.executablePath.hasPrefix("/") else {
                    continue
                }

                let path = URL(
                    fileURLWithPath: item.executablePath
                ).standardizedFileURL.path

                addTarget(
                    path: path,
                    name: item.label,
                    category: "Startup"
                )
            }
        }

        let sortedTargets = targets.values.sorted {
            $0.path < $1.path
        }

        var results: [IntegrityVerificationResult] = []

        // MARK: File verification

        for (index, target) in sortedTargets.enumerated() {
            if Task<Never, Never>.isCancelled {
                break
            }

            progress(
                IntegrityScanProgress(
                    completed: index,
                    total: sortedTargets.count,
                    currentPath: target.path
                )
            )

            let previous = baselineHashes[target.path]?.result

            let current = FileIntegrityHasher.hash(
                path: target.path,
                maximumFileSize: options.maximumFileSize
            )

            let status: IntegrityVerificationStatus
            let message: String?

            switch current.status {
            case .success:
                if let previous,
                   previous.status == .success,
                   let oldHash = previous.sha256,
                   let newHash = current.sha256 {

                    status = oldHash == newHash
                        ? .matched
                        : .changed

                    message = nil

                } else if previous == nil {
                    status = .newFile
                    message = "No hash recorded in the baseline."
                } else {
                    status = .unverified
                    message = "Baseline hash unavailable."
                }

            case .missing:
                status = .missing
                message = "File does not exist."

            case .skippedTooLarge:
                status = .skipped
                message = "File exceeds the configured size limit."

            case .cancelled:
                status = .cancelled
                message = "Verification cancelled."

            default:
                status = .unverified
                message = current.status.rawValue
            }

            results.append(
                IntegrityVerificationResult(
                    path: target.path,
                    name: target.name,
                    category: target.category,
                    status: status,
                    baselineHash: previous?.sha256,
                    currentHash: current.sha256,
                    size: current.size,
                    message: message
                )
            )
        }

        progress(
            IntegrityScanProgress(
                completed: results.count,
                total: sortedTargets.count,
                currentPath: ""
            )
        )

        return results
    }
}
