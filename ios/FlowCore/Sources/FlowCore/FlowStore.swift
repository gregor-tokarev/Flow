import Foundation

@MainActor
public final class FlowStore {
    public private(set) var library: Library
    public private(set) var isRestoring = false
    /// Records whose files were absent at startup. Keep the metadata for recovery.
    public private(set) var missingAttachments: [Attachment] = []
    public var onChange: (() -> Void)?
    public var undoActionName: String? { history.last?.name }
    public let directory: URL
    private let fileManager = FileManager.default
    private var history: [(name: String, library: Library)] = []
    private var libraryURL: URL { directory.appendingPathComponent("library.json") }
    private var attachmentsURL: URL { directory.appendingPathComponent("attachments", isDirectory: true) }

    public init(directory: URL) throws {
        self.directory = directory
        library = Library()
        try fileManager.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: libraryURL.path) {
            library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: libraryURL))
            try library.validate()
            for attachment in library.attachments {
                if !fileManager.fileExists(atPath: try attachmentURL(attachment).path) {
                    missingAttachments.append(attachment)
                }
            }
        } else {
            try persist(library)
        }
        // Deleted files survive during the session so deletion can be undone.
        let referenced = Set(library.attachments.compactMap(\.storageName))
        for url in try fileManager.contentsOfDirectory(at: attachmentsURL, includingPropertiesForKeys: nil)
            where !referenced.contains(url.lastPathComponent) {
            try? fileManager.removeItem(at: url)
        }
    }

    public var folders: [Folder] {
        library.folders.sorted { ($0.position, $0.id) < ($1.position, $1.id) }
    }

    public func entries(in folderID: String? = nil) -> [Entry] {
        library.entries.filter { folderID == nil || $0.folderId == folderID }
            .sorted { ($0.position, $0.createdAt, $0.id) < ($1.position, $1.createdAt, $1.id) }
    }

    public func attachments(for entryID: String) -> [Attachment] {
        library.attachments.filter { $0.entryId == entryID }
    }

    public func entry(_ id: String) -> Entry? { library.entries.first { $0.id == id } }

    public func save(_ entry: Entry) throws {
        try change { library in
            guard library.folders.contains(where: { $0.id == entry.folderId }) else {
                throw FlowError.invalid("The folder no longer exists.")
            }
            if let index = library.entries.firstIndex(where: { $0.id == entry.id }) {
                library.entries[index] = entry
            } else {
                let ordered = library.entries.filter { $0.folderId == entry.folderId }
                    .sorted { ($0.position, $0.id) < ($1.position, $1.id) }
                for (position, old) in ordered.enumerated() {
                    if let index = library.entries.firstIndex(where: { $0.id == old.id }) {
                        library.entries[index].position = Int64(position + 1)
                    }
                }
                var newEntry = entry
                newEntry.position = 0
                library.entries.append(newEntry)
            }
        }
    }

    public func toggleCompleted(_ id: String) throws {
        guard var entry = entry(id), entry.type == .task else { return }
        entry.completed.toggle()
        try save(entry)
    }

    public func deleteEntry(_ id: String) throws {
        try change(undoName: "Delete entry") { library in
            library.entries.removeAll { $0.id == id }
            library.attachments.removeAll { $0.entryId == id }
        }
    }

    public func saveFolder(_ folder: Folder) throws {
        var folder = folder
        folder.name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folder.name.isEmpty else { throw FlowError.invalid("Enter a folder name.") }
        try change { library in
            if let index = library.folders.firstIndex(where: { $0.id == folder.id }) {
                library.folders[index] = folder
            } else {
                let ordered = library.folders.sorted { ($0.position, $0.id) < ($1.position, $1.id) }
                for (position, old) in ordered.enumerated() {
                    if let index = library.folders.firstIndex(where: { $0.id == old.id }) {
                        library.folders[index].position = Int64(position)
                    }
                }
                folder.position = Int64(library.folders.count)
                library.folders.append(folder)
            }
        }
    }

    public func deleteFolder(_ id: String) throws {
        guard id != Folder.masterID else { throw FlowError.invalid("The Master folder cannot be deleted.") }
        try change(undoName: "Delete folder") { library in
            let removedIDs = Set(library.entries.filter { $0.folderId == id }.map(\.id))
            library.attachments.removeAll { removedIDs.contains($0.entryId) }
            library.entries.removeAll { $0.folderId == id }
            library.folders.removeAll { $0.id == id }
        }
    }

    public func moveEntry(_ id: String, to folderID: String) throws {
        guard var entry = entry(id), entry.folderId != folderID else { return }
        entry.folderId = folderID
        try change { library in
            guard library.folders.contains(where: { $0.id == folderID }) else {
                throw FlowError.invalid("The folder no longer exists.")
            }
            let ordered = library.entries.filter { $0.folderId == folderID }
                .sorted { ($0.position, $0.id) < ($1.position, $1.id) }
            for (position, old) in ordered.enumerated() {
                if let index = library.entries.firstIndex(where: { $0.id == old.id }) {
                    library.entries[index].position = Int64(position + 1)
                }
            }
            entry.position = 0
            if let index = library.entries.firstIndex(where: { $0.id == id }) { library.entries[index] = entry }
        }
    }

    public func reorderEntries(_ ids: [String], in folderID: String?) throws {
        guard Set(ids) == Set(entries(in: folderID).map(\.id)), Set(ids).count == ids.count else {
            throw FlowError.invalid("The entry list has changed. Try again.")
        }
        try change { library in
            for (position, id) in ids.enumerated() {
                if let index = library.entries.firstIndex(where: { $0.id == id }) {
                    library.entries[index].position = Int64(position)
                }
            }
        }
    }

    public func reorderFolders(_ ids: [String]) throws {
        guard Set(ids) == Set(library.folders.map(\.id)), Set(ids).count == ids.count else {
            throw FlowError.invalid("The folder list has changed. Try again.")
        }
        try change { library in
            for (position, id) in ids.enumerated() {
                if let index = library.folders.firstIndex(where: { $0.id == id }) {
                    library.folders[index].position = Int64(position)
                }
            }
        }
    }

    public func addAttachment(from url: URL, to entryID: String, mimeType: String?) throws {
        try requireWritable()
        let name = UUID().uuidString + "." + url.pathExtension
        let destination = attachmentsURL.appendingPathComponent(name)
        try fileManager.copyItem(at: url, to: destination)
        do {
            let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let attachment = Attachment(entryId: entryID, fileName: url.lastPathComponent,
                                        mimeType: mimeType, size: Int64(size), storageName: name)
            try change { $0.attachments.append(attachment) }
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    public func deleteAttachment(_ id: String) throws {
        try change(undoName: "Delete attachment") { $0.attachments.removeAll { $0.id == id } }
    }

    public func attachmentURL(_ attachment: Attachment) throws -> URL {
        guard let name = attachment.storageName, !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\") else {
            throw FlowError.invalid("Invalid attachment path.")
        }
        return attachmentsURL.appendingPathComponent(name)
    }

    public func undoDeletion() throws {
        try requireWritable()
        guard let snapshot = history.last else { return }
        // Restore only deleted objects. Preserve edits made after the deletion.
        var restored = library
        let folderIDs = Set(restored.folders.map(\.id))
        restored.folders += snapshot.library.folders.filter { !folderIDs.contains($0.id) }
        let entryIDs = Set(restored.entries.map(\.id))
        restored.entries += snapshot.library.entries.filter { !entryIDs.contains($0.id) }
        let attachmentIDs = Set(restored.attachments.map(\.id))
        restored.attachments += snapshot.library.attachments.filter { !attachmentIDs.contains($0.id) }
        try persist(restored)
        library = restored
        history.removeLast()
        onChange?()
    }

    /// Copies and commits a prepared backup off the main actor. Concurrent mutations
    /// are rejected until the disk commit and in-memory publication have both finished.
    /// A confirmed restore runs to completion even if the awaiting task is cancelled.
    public func restore(_ backup: PreparedBackup) async throws {
        try await restore(backup, write: Self.writeRestore)
    }

    // The writer can be controlled by package tests to exercise concurrent mutations.
    func restore(_ backup: PreparedBackup, write: @escaping @Sendable (PreparedBackup, URL) throws -> Library) async throws {
        try requireWritable()
        isRestoring = true
        defer { isRestoring = false }
        let directory = self.directory
        let restored = try await Task.detached(priority: .userInitiated) {
            try write(backup, directory)
        }.value
        library = restored
        missingAttachments = []
        history.removeAll()
        onChange?()
    }

    nonisolated static func writeRestore(_ backup: PreparedBackup, directory: URL) throws -> Library {
        let fileManager = FileManager.default
        let attachmentsURL = directory.appendingPathComponent("attachments", isDirectory: true)
        var restored = backup.library
        var copied: [URL] = []
        do {
            for index in restored.attachments.indices {
                let attachment = restored.attachments[index]
                guard let source = backup.files[attachment.id] else {
                    throw FlowError.invalid("An attachment is missing from the backup.")
                }
                let name = UUID().uuidString + "." + URL(fileURLWithPath: attachment.fileName).pathExtension
                let destination = attachmentsURL.appendingPathComponent(name)
                copied.append(destination)
                try fileManager.copyItem(at: source, to: destination)
                restored.attachments[index].storageName = name
            }
            try writeLibrary(restored, to: directory.appendingPathComponent("library.json"))
        } catch {
            copied.forEach { try? fileManager.removeItem(at: $0) }
            throw error
        }
        return restored
    }

    private func change(undoName: String? = nil, _ mutation: (inout Library) throws -> Void) throws {
        try requireWritable()
        var updated = library
        try mutation(&updated)
        try persist(updated)
        if let undoName {
            // Keep only what this operation deleted; undo must not resurrect earlier deletions.
            let remainingFolders = Set(updated.folders.map(\.id))
            let remainingEntries = Set(updated.entries.map(\.id))
            let remainingAttachments = Set(updated.attachments.map(\.id))
            let deleted = Library(folders: library.folders.filter { !remainingFolders.contains($0.id) },
                                  entries: library.entries.filter { !remainingEntries.contains($0.id) },
                                  attachments: library.attachments.filter { !remainingAttachments.contains($0.id) })
            history.append((undoName, deleted))
            if history.count > 20 { history.removeFirst() }
        }
        library = updated
        onChange?()
    }

    private func persist(_ library: Library) throws {
        try Self.writeLibrary(library, to: libraryURL)
    }

    private func requireWritable() throws {
        guard !isRestoring else { throw FlowError.invalid("A backup is being restored. Please wait until it finishes.") }
    }

    nonisolated private static func writeLibrary(_ library: Library, to url: URL) throws {
        try library.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(library).write(to: url, options: .atomic)
    }

    /// Preserves an unreadable library by moving it beside the original directory.
    /// If creating the new library fails, attempts to put the original back.
    public static func startNewLibrary(at directory: URL) throws -> (store: FlowStore, preservedDirectory: URL?) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else {
            return (try FlowStore(directory: directory), nil)
        }
        let timestamp = FlowDate.string().replacingOccurrences(of: ":", with: "-")
        let preserved = directory.deletingLastPathComponent()
            .appendingPathComponent("\(directory.lastPathComponent)-recovery-\(timestamp)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.moveItem(at: directory, to: preserved)
        do {
            return (try FlowStore(directory: directory), preserved)
        } catch {
            // Only the fresh, failed initialization is removed. Never delete the preserved copy.
            try? fileManager.removeItem(at: directory)
            try? fileManager.moveItem(at: preserved, to: directory)
            throw error
        }
    }
}
