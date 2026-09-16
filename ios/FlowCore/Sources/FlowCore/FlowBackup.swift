import Foundation
import ZIPFoundation

public final class PreparedBackup {
    public let library: Library
    public let createdAt: String
    let files: [String: URL]
    private let temporaryDirectory: URL

    init(library: Library, createdAt: String, files: [String: URL], directory: URL) {
        self.library = library
        self.createdAt = createdAt
        self.files = files
        temporaryDirectory = directory
    }

    deinit { try? FileManager.default.removeItem(at: temporaryDirectory) }
}

public enum FlowBackup {
    // Bounds apply before extraction, including ZIP files with extreme compression ratios.
    private static let metadataLimit: UInt64 = 32 * 1024 * 1024
    private static let attachmentLimit: UInt64 = 512 * 1024 * 1024
    private static let totalLimit: UInt64 = 2 * 1024 * 1024 * 1024

    private struct Manifest: Codable {
        let format: String
        let formatVersion: Int
        let flowVersion: String
        let createdAt: String
    }

    public static func export(library: Library, attachmentURLs: [String: URL], to url: URL) throws {
        try library.validate()
        let archive = try Archive(url: url, accessMode: .create)
        do {
            let manifest = Manifest(format: "flow", formatVersion: 1, flowVersion: "iOS 1.0", createdAt: FlowDate.string())
            try add(manifest, path: "manifest.json", to: archive)
            try add(library.folders, path: "data/folders.json", to: archive)
            try add(library.entries, path: "data/entries.json", to: archive)
            let metadata = library.attachments.map { attachment -> Attachment in
                var copy = attachment
                copy.storageName = nil
                return copy
            }
            try add(metadata, path: "data/attachments.json", to: archive)
            for attachment in library.attachments {
                try validateAttachmentID(attachment.id)
                guard let source = attachmentURLs[attachment.id] else {
                    throw FlowError.invalid("An attachment is missing. The backup was not created.")
                }
                try archive.addEntry(with: "attachments/" + attachment.id, fileURL: source, compressionMethod: .deflate)
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    public static func prepare(from url: URL) throws -> PreparedBackup {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let handle = try FileHandle(forReadingFrom: url)
            let prefix = try handle.read(upToCount: 64) ?? Data()
            try handle.close()
            if prefix.first(where: { ![9, 10, 13, 32].contains($0) }) == 123 {
                return try prepareLegacy(url, directory: directory)
            }
            let archive = try Archive(url: url, accessMode: .read)
            let paths = archive.map(\.path)
            guard Set(paths).count == paths.count else { throw FlowError.invalid("The archive contains duplicate file paths.") }
            let manifest: Manifest = try read("manifest.json", from: archive)
            guard manifest.format == "flow", manifest.formatVersion == 1 else {
                throw FlowError.invalid("This Flow backup format is not supported.")
            }
            var library = Library(folders: try read("data/folders.json", from: archive),
                                  entries: try read("data/entries.json", from: archive),
                                  attachments: try read("data/attachments.json", from: archive))
            ensureMaster(in: &library)
            // Android uses -1 when a document provider cannot report a file's size.
            for index in library.attachments.indices where library.attachments[index].size == -1 {
                let attachment = library.attachments[index]
                guard let entry = archive["attachments/" + attachment.id], entry.type == .file,
                      entry.uncompressedSize <= attachmentLimit else {
                    throw FlowError.invalid("An attachment is missing or too large.")
                }
                library.attachments[index].size = Int64(entry.uncompressedSize)
            }
            try library.validate()
            var total: UInt64 = 0
            var files: [String: URL] = [:]
            for index in library.attachments.indices {
                let attachment = library.attachments[index]
                try validateAttachmentID(attachment.id)
                guard let entry = archive["attachments/" + attachment.id], entry.type == .file,
                      entry.uncompressedSize <= attachmentLimit,
                      entry.uncompressedSize == UInt64(attachment.size) else {
                    throw FlowError.invalid("An attachment is missing, too large, or has the wrong size.")
                }
                total += entry.uncompressedSize
                guard total <= totalLimit else { throw FlowError.invalid("The backup exceeds the 2 GB import limit.") }
                // Never use an archive path or imported ID as a destination path.
                let destination = directory.appendingPathComponent(UUID().uuidString)
                let checksum = try archive.extract(entry, to: destination)
                guard checksum == entry.checksum else { throw FlowError.invalid("An attachment is damaged.") }
                files[attachment.id] = destination
                library.attachments[index].storageName = nil
            }
            return PreparedBackup(library: library, createdAt: manifest.createdAt, files: files, directory: directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func add<T: Encodable>(_ value: T, path: String, to archive: Archive) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { offset, size in
            data.subdata(in: Int(offset)..<(Int(offset) + size))
        }
    }

    private static func read<T: Decodable>(_ path: String, from archive: Archive) throws -> T {
        guard let entry = archive[path], entry.type == .file, entry.uncompressedSize <= metadataLimit else {
            throw FlowError.invalid("Missing or oversized backup metadata: \(path)")
        }
        var data = Data()
        let checksum = try archive.extract(entry) { chunk in
            guard UInt64(data.count + chunk.count) <= metadataLimit else {
                throw FlowError.invalid("Backup metadata is too large.")
            }
            data.append(chunk)
        }
        guard checksum == entry.checksum else { throw FlowError.invalid("The backup metadata is damaged.") }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func validateAttachmentID(_ id: String) throws {
        guard !id.isEmpty, id != ".", id != "..", !id.contains("/"), !id.contains("\\"), !id.contains("\0") else {
            throw FlowError.invalid("Invalid attachment ID.")
        }
    }

    private static func ensureMaster(in library: inout Library) {
        if !library.folders.contains(where: { $0.id == Folder.masterID }) {
            library.folders.insert(Folder(id: Folder.masterID, name: "Master", position: -1), at: 0)
        }
    }

    private struct LegacyBackup: Decodable {
        let version: Int
        let folders: [Folder]
        let notes: [LegacyEntry]
    }

    private struct LegacyEntry: Decodable {
        let id: String
        let text: String
        let createdAt: Int64
        let position: Int64
        let type: EntryKind
        let completed: Bool
        let folderId: String
    }

    private static func prepareLegacy(_ url: URL, directory: URL) throws -> PreparedBackup {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= metadataLimit else { throw FlowError.invalid("The legacy backup is too large.") }
        let legacy = try JSONDecoder().decode(LegacyBackup.self, from: Data(contentsOf: url))
        guard legacy.version == 5 else { throw FlowError.invalid("Only version 5 legacy backups are supported.") }
        var library = Library(folders: legacy.folders, entries: legacy.notes.map {
            Entry(id: $0.id, text: $0.text, createdAt: FlowDate.string(Date(timeIntervalSince1970: Double($0.createdAt) / 1000)),
                  position: $0.position, type: $0.type, completed: $0.completed, folderId: $0.folderId)
        })
        ensureMaster(in: &library)
        try library.validate()
        return PreparedBackup(library: library, createdAt: "", files: [:], directory: directory)
    }
}
