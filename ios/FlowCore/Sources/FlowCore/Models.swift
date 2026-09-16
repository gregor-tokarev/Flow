import Foundation

public enum EntryKind: String, Codable, CaseIterable {
    case note, task
}

public struct Folder: Codable, Equatable, Identifiable {
    public static let masterID = "master"
    public var id: String
    public var name: String
    public var position: Int64

    public init(id: String = UUID().uuidString, name: String, position: Int64 = 0) {
        self.id = id
        self.name = name
        self.position = position
    }
}

public struct Entry: Codable, Equatable, Identifiable {
    public var id: String
    public var text: String
    public var createdAt: String
    public var position: Int64
    public var type: EntryKind
    public var completed: Bool
    public var folderId: String

    public init(id: String = UUID().uuidString, text: String = "", createdAt: String = FlowDate.string(),
                position: Int64 = 0, type: EntryKind = .note, completed: Bool = false,
                folderId: String = Folder.masterID) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.position = position
        self.type = type
        self.completed = completed
        self.folderId = folderId
    }
}

public struct Attachment: Codable, Equatable, Identifiable {
    public var id: String
    public var entryId: String
    public var fileName: String
    public var mimeType: String?
    public var size: Int64
    public var createdAt: String
    // Only used by the local store. Omitted from exported Android-compatible metadata.
    public var storageName: String?

    public init(id: String = UUID().uuidString, entryId: String, fileName: String, mimeType: String?,
                size: Int64, createdAt: String = FlowDate.string(), storageName: String? = nil) {
        self.id = id
        self.entryId = entryId
        self.fileName = fileName
        self.mimeType = mimeType
        self.size = size
        self.createdAt = createdAt
        self.storageName = storageName
    }

    private enum CodingKeys: String, CodingKey {
        case id, entryId, fileName, mimeType, size, createdAt, storageName
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(entryId, forKey: .entryId)
        try values.encode(fileName, forKey: .fileName)
        // Kotlin's nullable field is still required in the Android backup schema.
        if let mimeType { try values.encode(mimeType, forKey: .mimeType) }
        else { try values.encodeNil(forKey: .mimeType) }
        try values.encode(size, forKey: .size)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encodeIfPresent(storageName, forKey: .storageName)
    }
}

public struct Library: Codable, Equatable {
    public var schemaVersion = 1
    public var folders: [Folder]
    public var entries: [Entry]
    public var attachments: [Attachment]

    public init(folders: [Folder] = [Folder(id: Folder.masterID, name: "Master")],
                entries: [Entry] = [], attachments: [Attachment] = []) {
        self.folders = folders
        self.entries = entries
        self.attachments = attachments
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw FlowError.invalid("This library version is not supported.") }
        try validateIDs(folders.map(\.id))
        try validateIDs(entries.map(\.id))
        try validateIDs(attachments.map(\.id))
        let folderIDs = Set(folders.map(\.id))
        let entryIDs = Set(entries.map(\.id))
        guard !folders.isEmpty, entries.allSatisfy({ folderIDs.contains($0.folderId) }),
              attachments.allSatisfy({ entryIDs.contains($0.entryId) && $0.size >= 0 }) else {
            throw FlowError.invalid("The backup contains missing folders, missing entries, or invalid attachments.")
        }
        guard entries.allSatisfy({ FlowDate.date($0.createdAt) != nil }),
              attachments.allSatisfy({ FlowDate.date($0.createdAt) != nil }) else {
            throw FlowError.invalid("The backup contains an invalid date.")
        }
    }

    private func validateIDs(_ ids: [String]) throws {
        guard ids.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(ids).count == ids.count else {
            throw FlowError.invalid("The backup contains empty or duplicate IDs.")
        }
    }
}

public enum FlowDate {
    public static func string(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    public static func date(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

public enum FlowError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}
