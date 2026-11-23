
import Foundation
import CryptoKit

enum FileHashStatus: String, Codable, Sendable {
    case success
    case missing
    case unreadable
    case notRegularFile
    case changedDuringRead
}

struct FileHashResult: Codable, Sendable {
    let path: String
    let status: FileHashStatus
    let sha256: String?
    let size: UInt64?
    let modifiedAt: Date?
}

enum FileIntegrityHasher {
    static func hash(
        path: String,
        chunkSize: Int = 1024 * 1024
    ) -> FileHashResult {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default

        func failure(_ status: FileHashStatus) -> FileHashResult {
            FileHashResult(
                path: path,
                status: status,
                sha256: nil,
                size: nil,
                modifiedAt: nil
            )
        }

        guard fm.fileExists(atPath: path) else {
            return failure(.missing)
        }

        guard let attributes = try? fm.attributesOfItem(
            atPath: path
        ) else {
            return failure(.unreadable)
        }

        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            return failure(.notRegularFile)
        }

        let initialSize = (attributes[.size] as? NSNumber)?
            .uint64Value ?? 0

        let initialDate = attributes[.modificationDate] as? Date

        guard let handle = try? FileHandle(
            forReadingFrom: url
        ) else {
            return failure(.unreadable)
        }

        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        var bytesRead: UInt64 = 0

        do {
            while true {
                let data = try handle.read(
                    upToCount: max(4096, chunkSize)
                ) ?? Data()

                if data.isEmpty {
                    break
                }

                hasher.update(data: data)
                bytesRead += UInt64(data.count)
            }
        } catch {
            return failure(.unreadable)
        }

        guard let finalAttributes = try? fm.attributesOfItem(
            atPath: path
        ) else {
            return failure(.unreadable)
        }

        let finalSize = (finalAttributes[.size] as? NSNumber)?
            .uint64Value ?? 0

        let finalDate = finalAttributes[.modificationDate] as? Date

        guard bytesRead == initialSize,
              initialSize == finalSize,
              initialDate == finalDate else {
            return failure(.changedDuringRead)
        }

        let digest = hasher.finalize()

        let hex = digest.map {
            String(format: "%02x", $0)
        }.joined()

        return FileHashResult(
            path: path,
            status: .success,
            sha256: hex,
            size: bytesRead,
            modifiedAt: finalDate
        )
    }
}
