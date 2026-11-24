import Foundation
import Darwin

nonisolated enum IPAddressUtilities {

    static func parse(_ address: String) -> [UInt8]? {

        let cleaned = address
            .split(separator: "%")
            .first
            .map(String.init) ?? address

        var ipv4 = in_addr()

        if cleaned.withCString({
            inet_pton(AF_INET, $0, &ipv4)
        }) == 1 {

            return withUnsafeBytes(of: &ipv4) {
                Array($0)
            }
        }

        var ipv6 = in6_addr()

        if cleaned.withCString({
            inet_pton(AF_INET6, $0, &ipv6)
        }) == 1 {

            let bytes = withUnsafeBytes(of: &ipv6) {
                Array($0)
            }

            // Normalize IPv4-mapped IPv6 addresses.
            if bytes.prefix(10).allSatisfy({ $0 == 0 }),
               bytes[10] == 0xff,
               bytes[11] == 0xff {

                return Array(bytes.suffix(4))
            }

            return bytes
        }

        return nil
    }

    // MARK: - CIDR matching

    static func contains(
        address: String,
        cidr: String
    ) -> Bool {

        guard let addressBytes = parse(address) else {
            return false
        }

        return contains(
            addressBytes: addressBytes,
            cidr: cidr
        )
    }

    static func contains(
        addressBytes: [UInt8],
        cidr: String
    ) -> Bool {

        let parts = cidr.split(separator: "/")

        guard parts.count == 2,
              let networkBytes = parse(String(parts[0])),
              let prefixLength = Int(parts[1]),
              networkBytes.count == addressBytes.count,
              prefixLength >= 0,
              prefixLength <= networkBytes.count * 8 else {

            return false
        }

        let fullBytes = prefixLength / 8
        let remainingBits = prefixLength % 8

        for index in 0..<fullBytes {

            if addressBytes[index] != networkBytes[index] {
                return false
            }
        }

        if remainingBits > 0 {

            let mask = UInt8(
                truncatingIfNeeded:
                    0xff << (8 - remainingBits)
            )

            if addressBytes[fullBytes] & mask !=
                networkBytes[fullBytes] & mask {

                return false
            }
        }

        return true
    }

    static func isValidCIDR(_ cidr: String) -> Bool {

        let parts = cidr.split(separator: "/")

        guard parts.count == 2,
              let bytes = parse(String(parts[0])),
              let prefix = Int(parts[1]) else {

            return false
        }

        return prefix >= 0 &&
               prefix <= bytes.count * 8
    }

    // MARK: - Private and reserved addresses

    private static let excludedRanges = [

        // IPv4
        "0.0.0.0/8",
        "10.0.0.0/8",
        "100.64.0.0/10",
        "127.0.0.0/8",
        "169.254.0.0/16",
        "172.16.0.0/12",
        "192.0.0.0/24",
        "192.0.2.0/24",
        "192.168.0.0/16",
        "198.18.0.0/15",
        "198.51.100.0/24",
        "203.0.113.0/24",
        "224.0.0.0/4",
        "240.0.0.0/4",

        // IPv6
        "::/128",
        "::1/128",
        "fc00::/7",
        "fe80::/10",
        "ff00::/8",
        "2001:db8::/32",
        "100::/64"
    ]

    static func isLocalOrReserved(
        _ address: String
    ) -> Bool {

        guard let bytes = parse(address) else {
            return true
        }

        return excludedRanges.contains {
            contains(
                addressBytes: bytes,
                cidr: $0
            )
        }
    }

    // MARK: - Address normalization

    static func normalized(
        _ address: String
    ) -> String? {

        guard let bytes = parse(address) else {
            return nil
        }

        var buffer = [CChar](
            repeating: 0,
            count: Int(INET6_ADDRSTRLEN)
        )

        let family = bytes.count == 4
            ? AF_INET
            : AF_INET6

        let success = bytes.withUnsafeBytes { raw in

            buffer.withUnsafeMutableBufferPointer {
                output in

                inet_ntop(
                    family,
                    raw.baseAddress,
                    output.baseAddress,
                    socklen_t(output.count)
                ) != nil
            }
        }

        guard success else {
            return nil
        }

        return String(
            decoding: buffer.prefix { $0 != 0 }.map {
                UInt8(bitPattern: $0)
            },
            as: UTF8.self
        )
    }
}
