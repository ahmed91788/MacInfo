
import Foundation
import CryptoKit


enum FileHashStatus: String, Codable, Sendable {
    case success
    case missing
    case unreadable
    case notRegularFile
    case changedDuringRead

    // MacInfo 2.4
    case skippedTooLarge
    case cancelled
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
        chunkSize: Int = 1024 * 1024,
        maximumFileSize: UInt64 = UInt64.max
    ) -> FileHashResult {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default

        func failure(
            _ status: FileHashStatus,
            size: UInt64? = nil
        ) -> FileHashResult {
            FileHashResult(
                path: path,
                status: status,
                sha256: nil,
                size: size,
                modifiedAt: nil
            )
        }

        if Task<Never, Never>.isCancelled {
            return failure(.cancelled)
        }

        let attributes: [FileAttributeKey: Any]

        do {
            attributes = try fm.attributesOfItem(
                atPath: path
            )
        } catch {
            let nsError = error as NSError

            if nsError.domain == NSCocoaErrorDomain &&
                (nsError.code == NSFileNoSuchFileError ||
                 nsError.code == NSFileReadNoSuchFileError) {
                return failure(.missing)
            }

            return failure(.unreadable)
        }

        guard attributes[.type] as? FileAttributeType
                == .typeRegular else {
            return failure(.notRegularFile)
        }

        let initialSize =
            (attributes[.size] as? NSNumber)?
                .uint64Value ?? 0

        let initialDate =
            attributes[.modificationDate] as? Date

        let initialFileID =
            attributes[.systemFileNumber] as? NSNumber

        let initialDeviceID =
            attributes[.systemNumber] as? NSNumber

        guard initialSize <= maximumFileSize else {
            return failure(
                .skippedTooLarge,
                size: initialSize
            )
        }

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
                if Task<Never, Never>.isCancelled {
                    return failure(.cancelled)
                }

                let data = try handle.read(
                    upToCount: max(
                        4096,
                        min(chunkSize, 8 * 1024 * 1024)
                    )
                ) ?? Data()

                if data.isEmpty {
                    break
                }

                bytesRead += UInt64(data.count)

                guard bytesRead <= maximumFileSize else {
                    return failure(
                        .skippedTooLarge,
                        size: bytesRead
                    )
                }

                hasher.update(data: data)
            }
        } catch {
            return failure(.unreadable)
        }

        guard let finalAttributes = try? fm.attributesOfItem(
            atPath: path
        ) else {
            return failure(.changedDuringRead)
        }

        let finalSize =
            (finalAttributes[.size] as? NSNumber)?
                .uint64Value ?? 0

        let finalDate =
            finalAttributes[.modificationDate] as? Date

        let finalFileID =
            finalAttributes[.systemFileNumber] as? NSNumber

        let finalDeviceID =
            finalAttributes[.systemNumber] as? NSNumber

        guard bytesRead == initialSize,
              initialSize == finalSize,
              initialDate == finalDate,
              initialFileID == finalFileID,
              initialDeviceID == finalDeviceID else {
            return failure(.changedDuringRead)
        }

        if Task<Never, Never>.isCancelled {
            return failure(.cancelled)
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

