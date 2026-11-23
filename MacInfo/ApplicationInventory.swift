
import Foundation
import Combine
import Security

enum ApplicationSignature: String, Sendable, CaseIterable {
    case apple = "Apple Signed"
    case developerID = "Developer ID"
    case other = "Other Signed"
    case adHoc = "Ad-hoc"
    case unsigned = "Unsigned"
    case invalid = "Invalid"
    case unknown = "Unknown"
}

struct InstalledApplication: Identifiable, Sendable {
    let path: String
    let name: String
    let version: String
    let bundleIdentifier: String
    let signature: ApplicationSignature
    let teamIdentifier: String?

    var id: String { path }
}

enum ApplicationScanner {
    static func scan() -> [InstalledApplication] {
        let home = FileManager.default.homeDirectoryForCurrentUser

        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            home.appendingPathComponent("Applications")
        ]

        var visited = Set<String>()
        var results: [InstalledApplication] = []

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles],
                errorHandler: nil
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else {
                    continue
                }

                enumerator.skipDescendants()

                let path = url.standardizedFileURL.path
                guard visited.insert(path).inserted else {
                    continue
                }

                let bundle = Bundle(url: url)

                let name =
                    bundle?.object(
                        forInfoDictionaryKey: "CFBundleDisplayName"
                    ) as? String
                    ?? bundle?.object(
                        forInfoDictionaryKey: "CFBundleName"
                    ) as? String
                    ?? url.deletingPathExtension().lastPathComponent

                let version =
                    bundle?.object(
                        forInfoDictionaryKey: "CFBundleShortVersionString"
                    ) as? String
                    ?? "Unknown"

                let identifier = bundle?.bundleIdentifier ?? "Unknown"

                let signing = inspectSignature(url)

                results.append(
                    InstalledApplication(
                        path: path,
                        name: name,
                        version: version,
                        bundleIdentifier: identifier,
                        signature: signing.signature,
                        teamIdentifier: signing.teamID
                    )
                )
            }
        }

        return results.sorted {
            $0.name.localizedStandardCompare($1.name)
                == .orderedAscending
        }
    }

    private static func inspectSignature(
        _ url: URL
    ) -> (
        signature: ApplicationSignature,
        teamID: String?
    ) {
        var staticCode: SecStaticCode?

        let status = SecStaticCodeCreateWithPath(
            url as CFURL,
            SecCSFlags(),
            &staticCode
        )

        guard status == errSecSuccess,
              let staticCode else {
            return (.unsigned, nil)
        }

        var info: CFDictionary?

        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        )

        guard infoStatus == errSecSuccess,
              let dictionary = info as? [String: Any] else {
            return (.unknown, nil)
        }

        let teamID = dictionary[
            kSecCodeInfoTeamIdentifier as String
        ] as? String

        let flags = dictionary[
            kSecCodeInfoFlags as String
        ] as? UInt32 ?? 0

        let valid = SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(),
            nil
        ) == errSecSuccess

        guard valid else {
            return (.invalid, teamID)
        }

        // CS_ADHOC flag
        if (flags & 0x00000002) != 0 {
            return (.adHoc, teamID)
        }

        let certificates = dictionary[
            kSecCodeInfoCertificates as String
        ] as? [SecCertificate] ?? []

        let names = certificates.compactMap {
            SecCertificateCopySubjectSummary($0) as String?
        }

        if names.contains(where: {
            $0.contains("Developer ID Application")
        }) {
            return (.developerID, teamID)
        }

        if names.contains(where: {
            $0.contains("Apple")
        }) {
            return (.apple, teamID)
        }

        return (.other, teamID)
    }
}

@MainActor
final class ApplicationInventory: ObservableObject {
    @Published private(set) var applications: [InstalledApplication] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanned: Date?

    func scan() {
        guard !isScanning else { return }

        isScanning = true

        Task {
            let result = await Task.detached(
                priority: .userInitiated
            ) {
                await ApplicationScanner.scan()
            }.value

            applications = result
            lastScanned = Date()
            isScanning = false
        }
    }
}
