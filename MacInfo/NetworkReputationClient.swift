import Foundation

actor NetworkReputationClient {

    static let shared = NetworkReputationClient()

    private let session: URLSession

    private var database: NetworkThreatDatabase?

    private var ranges: [NetworkThreatRange] = []

    private var asnCache:
        [String: NetworkASNInformation] = [:]

    private var lastUpdateAttempt: Date?

    private var isUpdating = false

    private var nextLookupAt =
        ContinuousClock.now

    private let updateInterval: TimeInterval = 3600

    private let maximumFeedAge:
        TimeInterval = 48 * 3600

    private static var databaseURL: URL {

        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/MacInfo",
                isDirectory: true
            )
            .appendingPathComponent(
                "network-threat-database.json"
            )
    }

    init() {

        let configuration =
            URLSessionConfiguration.ephemeral

        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60

        configuration.httpCookieStorage = nil
        configuration.urlCache = nil

        session = URLSession(
            configuration: configuration
        )
    }

    // MARK: - Load saved database

    func loadDatabase() throws {

        if database != nil {
            return
        }

        let url = Self.databaseURL

        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return
        }

        let data = try Data(contentsOf: url)

        let saved = try JSONDecoder().decode(
            NetworkThreatDatabase.self,
            from: data
        )

        let parsed = try Self.parseDatabase(saved)

        database = saved
        ranges = parsed
    }

    func databaseInformation() -> (
        count: Int,
        date: Date?
    ) {

        (
            count: ranges.count,
            date: database?.downloadedAt
        )
    }

    // MARK: - Update feeds

    func updateDatabase() async throws {

        guard !isUpdating else {
            return
        }

        let previousAttempt = UserDefaults.standard
            .object(forKey: "NetworkReputation.LastAttempt")
            as? Date

        let mostRecent = [
            lastUpdateAttempt,
            previousAttempt,
            database?.downloadedAt
        ]
        .compactMap { $0 }
        .max()

        if let mostRecent,
           Date().timeIntervalSince(mostRecent) <
            updateInterval {

            throw NetworkReputationError.updateTooSoon
        }

        isUpdating = true

        lastUpdateAttempt = Date()

        UserDefaults.standard.set(
            lastUpdateAttempt,
            forKey: "NetworkReputation.LastAttempt"
        )

        defer {
            isUpdating = false
        }

        let ipv4 = try await download(
            "https://www.spamhaus.org/drop/drop_v4.json"
        )

        let ipv6 = try await download(
            "https://www.spamhaus.org/drop/drop_v6.json"
        )

        try Task.checkCancellation()

        let newDatabase = NetworkThreatDatabase(
            downloadedAt: Date(),
            ipv4Data: ipv4,
            ipv6Data: ipv6
        )

        let parsed = try Self.parseDatabase(
            newDatabase
        )

        try saveDatabase(newDatabase)

        database = newDatabase

        ranges = parsed
    }

    // MARK: - Download

    private func download(
        _ address: String
    ) async throws -> Data {

        guard let url = URL(string: address) else {
            throw NetworkReputationError.invalidResponse
        }

        var request = URLRequest(url: url)

        request.setValue(
            "MacInfo/3.3",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) =
            try await session.data(for: request)

        guard let response =
            response as? HTTPURLResponse else {

            throw NetworkReputationError.invalidResponse
        }

        guard response.statusCode == 200 else {

            throw NetworkReputationError.httpError(
                response.statusCode
            )
        }

        guard !data.isEmpty,
              data.count <= 20 * 1024 * 1024 else {

            throw NetworkReputationError.invalidFeed
        }

        return data
    }

    // MARK: - Parse feed

    private static func parseFeed(
        _ data: Data,
        expectedAddressBytes: Int
    ) throws -> [NetworkThreatRange] {

        guard let text = String(
            data: data,
            encoding: .utf8
        ) else {
            throw NetworkReputationError.invalidFeed
        }

        let decoder = JSONDecoder()

        var items: [NetworkThreatRange] = []

        var hasMetadata = false

        for rawLine in text.split(
            whereSeparator: \.isNewline
        ) {

            let line = rawLine.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !line.isEmpty else {
                continue
            }

            let lineData = Data(line.utf8)

            guard let object = try JSONSerialization
                .jsonObject(with: lineData)
                as? [String: Any] else {

                throw NetworkReputationError.invalidFeed
            }

            // Preserve metadata in the original raw feed.
            if object["type"] != nil &&
                object["cidr"] == nil {

                if object["timestamp"] != nil,
                   object["copyright"] != nil {

                    hasMetadata = true
                }

                continue
            }

            let item = try decoder.decode(
                NetworkThreatRange.self,
                from: lineData
            )

            let network = item.cidr
                .split(separator: "/")
                .first
                .map(String.init) ?? ""

            guard IPAddressUtilities.isValidCIDR(
                item.cidr
            ),
            IPAddressUtilities.parse(network)?.count ==
                expectedAddressBytes else {

                throw NetworkReputationError.invalidFeed
            }

            items.append(item)
        }

        guard !items.isEmpty, hasMetadata else {
            throw NetworkReputationError.invalidFeed
        }

        return items
    }

    private static func parseDatabase(
        _ database: NetworkThreatDatabase
    ) throws -> [NetworkThreatRange] {

        let ipv4 = try parseFeed(
            database.ipv4Data,
            expectedAddressBytes: 4
        )

        let ipv6 = try parseFeed(
            database.ipv6Data,
            expectedAddressBytes: 16
        )

        return ipv4 + ipv6
    }

    // MARK: - Local reputation check

    func check(
        _ item: NetworkReputationItem
    ) -> NetworkReputationItem {

        var result = item

        result.matchedRanges = []
        result.errorMessage = nil
        result.checkedAt = Date()

        if IPAddressUtilities.isLocalOrReserved(
            item.address
        ) {

            result.status = .local

            return result
        }

        guard let database else {

            result.status = .unavailable

            return result
        }

        let age = Date().timeIntervalSince(
            database.downloadedAt
        )

        let matches = ranges.filter {

            IPAddressUtilities.contains(
                address: item.address,
                cidr: $0.cidr
            )
        }

        result.matchedRanges = matches

        if age < 0 || age > maximumFeedAge {

            result.status = .stale

            result.errorMessage =
                "Threat database is out of date."

        } else if !matches.isEmpty {

            result.status = .threatMatch

        } else {

            result.status = .noMatch
        }

        return result
    }

    // MARK: - ASN lookup

    func lookupASN(
        address: String
    ) async throws -> NetworkASNInformation {

        guard let normalized =
            IPAddressUtilities.normalized(address),
              !IPAddressUtilities.isLocalOrReserved(
                normalized
              ) else {

            throw NetworkReputationError.invalidAddress
        }

        if let cached = asnCache[normalized] {
            return cached
        }

        let slot = max(
            ContinuousClock.now,
            nextLookupAt
        )

        nextLookupAt = slot.advanced(
            by: .seconds(2)
        )

        try await ContinuousClock().sleep(
            until: slot
        )

        try Task.checkCancellation()

        var components = URLComponents(
            string:
                "https://stat.ripe.net/data/network-info/data.json"
        )!

        components.queryItems = [

            URLQueryItem(
                name: "resource",
                value: normalized
            ),

            URLQueryItem(
                name: "sourceapp",
                value: "MacInfo"
            )
        ]

        guard let url = components.url else {
            throw NetworkReputationError.invalidAddress
        }

        let (data, response) =
            try await session.data(from: url)

        guard let response =
            response as? HTTPURLResponse else {

            throw NetworkReputationError.invalidResponse
        }

        guard response.statusCode == 200 else {

            throw NetworkReputationError.httpError(
                response.statusCode
            )
        }

        let decoded = try JSONDecoder().decode(
            RIPEStatResponse.self,
            from: data
        )

        asnCache[normalized] = decoded.data

        return decoded.data
    }

    // MARK: - Persistence

    private func saveDatabase(
        _ database: NetworkThreatDatabase
    ) throws {

        let url = Self.databaseURL

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [
                .posixPermissions: 0o700
            ]
        )

        let data = try JSONEncoder().encode(
            database
        )

        try data.write(
            to: url,
            options: .atomic
        )
    }
}
