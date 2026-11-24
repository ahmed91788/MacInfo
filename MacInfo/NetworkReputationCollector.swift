import Foundation

nonisolated enum NetworkReputationCollector {

    static func scan() throws
        -> [NetworkReputationItem] {

        let result = ExtensionCommandRunner.run(

            executable: "/usr/sbin/lsof",

            arguments: [
                "-nP",
                "-iTCP",
                "-sTCP:ESTABLISHED",
                "-Fpcn"
            ],

            timeout: 30
        )

        try Task.checkCancellation()

        guard !result.timedOut else {

            throw NSError(
                domain: "MacInfo.NetworkReputation",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Connection collection timed out."
                ]
            )
        }

        // lsof can return 1 when no files match.
        guard result.exitCode == 0 ||
              (
                result.exitCode == 1 &&
                result.errorOutput.isEmpty
              ) else {

            throw NSError(
                domain: "MacInfo.NetworkReputation",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Unable to collect network connections."
                ]
            )
        }

        var items: [
            String: NetworkReputationItem
        ] = [:]

        var processName = "Unknown"

        for rawLine in result.output.split(
            whereSeparator: \.isNewline
        ) {

            try Task.checkCancellation()

            let line = String(rawLine)

            guard let field = line.first else {
                continue
            }

            let value = String(line.dropFirst())

            switch field {

            case "p":

                processName = "PID \(value)"

            case "c":

                processName = value

            case "n":

                guard let endpoint =
                    parseRemoteEndpoint(value) else {

                    continue
                }

                guard !IPAddressUtilities
                    .isLocalOrReserved(
                        endpoint.address
                    ) else {

                    continue
                }

                var item =
                    items[endpoint.address] ??
                    NetworkReputationItem(
                        address: endpoint.address
                    )

                if !item.processes.contains(
                    processName
                ) {

                    item.processes.append(
                        processName
                    )
                }

                if let port = endpoint.port,
                   !item.ports.contains(port) {

                    item.ports.append(port)
                }

                item.connectionCount += 1

                items[endpoint.address] = item

            default:

                break
            }
        }

        return items.values.map { item in

            var normalized = item

            normalized.processes.sort()
            normalized.ports.sort()

            return normalized

        }.sorted {

            $0.connectionCount >
                $1.connectionCount
        }
    }

    // MARK: - Parse remote endpoint

    private static func parseRemoteEndpoint(
        _ value: String
    ) -> (
        address: String,
        port: Int?
    )? {

        let endpoints = value.components(
            separatedBy: "->"
        )

        guard endpoints.count == 2 else {
            return nil
        }

        let remote = endpoints[1]

        if remote.hasPrefix("[") {

            guard let closing = remote.firstIndex(
                of: "]"
            ) else {
                return nil
            }

            let start = remote.index(after: remote.startIndex)
            let rawAddress = String(remote[start..<closing])

            let remainder = remote[
                remote.index(after: closing)...
            ]

            let port = Int(
                remainder.hasPrefix(":")
                    ? String(remainder.dropFirst())
                    : ""
            )

            guard let address =
                IPAddressUtilities.normalized(
                    rawAddress
                ) else {

                return nil
            }

            return (address, port)
        }

        guard let separator = remote.lastIndex(
            of: ":"
        ) else {

            return nil
        }

        let rawAddress = String(
            remote[..<separator]
        )

        let port = Int(
            remote[
                remote.index(after: separator)...
            ]
        )

        guard let address =
            IPAddressUtilities.normalized(
                rawAddress
            ) else {

            return nil
        }

        return (address, port)
    }
}
