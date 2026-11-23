
import Foundation
import Security

struct PersistenceAnalysis: Sendable {
    let modifiedAt: Date?
    let signingStatus: String
    let teamIdentifier: String?
    let reviewReasons: [String]
}

enum PersistenceAnalyzer {
    static func analyze(
        plistURL: URL,
        executablePath: String,
        programExists: Bool?,
        type: StartupItemType
    ) -> PersistenceAnalysis {
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: plistURL.path
        )

        let modifiedAt = attributes?[.modificationDate] as? Date

        var reasons: [String] = []

        if programExists == false {
            reasons.append("Executable target does not exist")
        }

        if let modifiedAt,
           Date().timeIntervalSince(modifiedAt) < 7 * 86400 {
            reasons.append("Startup configuration modified recently")
        }

        let signing = inspectSigning(executablePath)

        if signing.status == "Unsigned" {
            reasons.append("Executable is unsigned")
        }

        if signing.status == "Invalid Signature" {
            reasons.append("Executable signature is invalid")
        }

        let lowerPath = executablePath.lowercased()

        if lowerPath.hasPrefix("/tmp/") ||
           lowerPath.hasPrefix("/private/tmp/") ||
           lowerPath.hasPrefix("/var/tmp/") ||
           lowerPath.hasPrefix("/private/var/tmp/") {
            reasons.append("Executable located in a temporary directory")
        }

        if lowerPath.contains("/downloads/") {
            reasons.append("Executable launched from Downloads")
        }

        return PersistenceAnalysis(
            modifiedAt: modifiedAt,
            signingStatus: signing.status,
            teamIdentifier: signing.teamID,
            reviewReasons: reasons
        )
    }

    private static func inspectSigning(
        _ path: String
    ) -> (status: String, teamID: String?) {
        guard path.hasPrefix("/"),
              FileManager.default.fileExists(atPath: path) else {
            return ("Unavailable", nil)
        }

        var code: SecStaticCode?

        let createStatus = SecStaticCodeCreateWithPath(
            URL(fileURLWithPath: path) as CFURL,
            SecCSFlags(),
            &code
        )

        guard createStatus == errSecSuccess,
              let code else {
            return ("Unsigned", nil)
        }

        let valid = SecStaticCodeCheckValidity(
            code,
            SecCSFlags(),
            nil
        ) == errSecSuccess

        var info: CFDictionary?

        let infoStatus = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        )

        guard infoStatus == errSecSuccess,
              let dictionary = info as? [String: Any] else {
            return (
                valid ? "Signed" : "Invalid Signature",
                nil
            )
        }

        let teamID = dictionary[
            kSecCodeInfoTeamIdentifier as String
        ] as? String

        let flags = dictionary[
            kSecCodeInfoFlags as String
        ] as? UInt32 ?? 0

        guard valid else {
            return ("Invalid Signature", teamID)
        }

        if flags & 0x2 != 0 {
            return ("Ad-hoc", teamID)
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
            return ("Developer ID", teamID)
        }

        if names.contains(where: {
            $0.contains("Apple")
        }) {
            return ("Apple Signed", teamID)
        }

        return ("Other Signed", teamID)
    }
}
