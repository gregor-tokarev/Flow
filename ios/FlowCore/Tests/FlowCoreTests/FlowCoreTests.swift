import XCTest
import ZIPFoundation
@testable import FlowCore

final class FlowCoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    @MainActor
    func testPersistsEntriesCompletionFoldersAndOrdering() async throws {
        let store = try FlowStore(directory: directory)
        let first = Entry(text: "First")
        let second = Entry(text: "Second", type: .task)
        try store.save(first)
        try store.save(second)
        XCTAssertEqual(store.entries().map(\.id), [second.id, first.id])
        try store.toggleCompleted(second.id)
        try store.reorderEntries([first.id, second.id], in: Folder.masterID)
        let folder = Folder(name: "Work")
        try store.saveFolder(folder)
        try store.moveEntry(second.id, to: folder.id)
        let reopened = try FlowStore(directory: directory)
        XCTAssertEqual(reopened.entries(in: folder.id).map(\.id), [second.id])
        XCTAssertEqual(reopened.entry(second.id)?.completed, true)
        XCTAssertEqual(reopened.entries(in: Folder.masterID).map(\.id), [first.id])
    }

    @MainActor
    func testNewFolderAppendsAfterDeletionLeavesPositionGaps() async throws {
        let store = try FlowStore(directory: directory)
        let first = Folder(name: "First")
        let last = Folder(name: "Last")
        let added = Folder(name: "Added")
        try store.saveFolder(first)
        try store.saveFolder(last)
        try store.deleteFolder(first.id)
        try store.saveFolder(added)
        XCTAssertEqual(store.folders.map(\.id), [Folder.masterID, last.id, added.id])
    }

    @MainActor
    func testUndoRestoresOnlyDeletedObjectsAndKeepsLaterEdits() async throws {
        let store = try FlowStore(directory: directory)
        let removed = Entry(text: "Deleted")
        var kept = Entry(text: "Original")
        try store.save(removed)
        try store.save(kept)
        try store.deleteEntry(removed.id)
        kept.text = "Edited after deletion"
        try store.save(kept)
        try store.undoDeletion()
        XCTAssertEqual(store.entry(kept.id)?.text, "Edited after deletion")
        XCTAssertEqual(store.entry(removed.id)?.text, "Deleted")
        XCTAssertNil(store.undoActionName)
    }

    @MainActor
    func testFolderDeletionAndUndoRestoresAttachmentBytes() async throws {
        let store = try FlowStore(directory: directory)
        let folder = Folder(name: "Files")
        try store.saveFolder(folder)
        let entry = Entry(text: "Document", folderId: folder.id)
        try store.save(entry)
        let source = directory.appendingPathComponent("hello.txt")
        try Data("Hello, Flow".utf8).write(to: source)
        try store.addAttachment(from: source, to: entry.id, mimeType: "text/plain")
        let attachment = try XCTUnwrap(store.attachments(for: entry.id).first)
        try store.deleteFolder(folder.id)
        XCTAssertTrue(store.library.attachments.isEmpty)
        try store.undoDeletion()
        XCTAssertEqual(try Data(contentsOf: store.attachmentURL(attachment)), Data("Hello, Flow".utf8))
        XCTAssertEqual(store.entry(entry.id), entry)
        XCTAssertTrue(store.folders.contains { $0.id == folder.id })
    }

    @MainActor
    func testAttachmentUndoAndCleanupOnNextLaunch() async throws {
        let store = try FlowStore(directory: directory)
        let entry = Entry(text: "Files")
        try store.save(entry)
        let source = directory.appendingPathComponent("source.txt")
        try Data("content".utf8).write(to: source)
        try store.addAttachment(from: source, to: entry.id, mimeType: "text/plain")
        let attachment = try XCTUnwrap(store.attachments(for: entry.id).first)
        let file = try store.attachmentURL(attachment)
        try store.deleteAttachment(attachment.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        try store.undoDeletion()
        XCTAssertEqual(store.attachments(for: entry.id), [attachment])
        try store.deleteAttachment(attachment.id)
        _ = try FlowStore(directory: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    @MainActor
    func testInvalidMutationsLeaveLibraryAndDiskUnchanged() async throws {
        let store = try FlowStore(directory: directory)
        let original = store.library
        XCTAssertThrowsError(try store.save(Entry(text: "Orphan", folderId: "missing")))
        XCTAssertThrowsError(try store.deleteFolder(Folder.masterID))
        XCTAssertThrowsError(try store.saveFolder(Folder(name: "   ")))
        XCTAssertThrowsError(try store.reorderEntries(["missing"], in: nil))
        XCTAssertEqual(store.library, original)
        XCTAssertEqual(try FlowStore(directory: directory).library, original)
    }

    @MainActor
    func testCorruptLibraryIsNotReplaced() async throws {
        let file = directory.appendingPathComponent("library.json")
        let bytes = Data("not valid JSON".utf8)
        try bytes.write(to: file)
        XCTAssertThrowsError(try FlowStore(directory: directory))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    @MainActor
    func testAndroidFixtureImportAndExportRoundTrip() async throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "android-v1", withExtension: "flow", subdirectory: "Fixtures"))
        let prepared = try FlowBackup.prepare(from: fixture)
        let store = try FlowStore(directory: directory.appendingPathComponent("library"))
        try store.save(Entry(text: "Replaced"))
        try await store.restore(prepared)
        XCTAssertEqual(store.library.entries.count, 2)
        XCTAssertEqual(store.entry("task-1")?.completed, true)
        XCTAssertEqual(store.entry("note-1")?.text, "Hello from Android\nПривет 👋")
        let attachment = try XCTUnwrap(store.library.attachments.first)
        XCTAssertEqual(try String(contentsOf: store.attachmentURL(attachment), encoding: .utf8), "Attachment from Android\n")
        let output = directory.appendingPathComponent("export.flow")
        var exportedLibrary = store.library
        exportedLibrary.attachments[0].mimeType = nil
        try FlowBackup.export(library: exportedLibrary, attachmentURLs: [attachment.id: try store.attachmentURL(attachment)], to: output)
        let reimported = try FlowBackup.prepare(from: output)
        XCTAssertEqual(reimported.library.entries, prepared.library.entries)
        XCTAssertEqual(reimported.library.folders, prepared.library.folders)
        let archive = try Archive(url: output, accessMode: .read)
        XCTAssertEqual(Set(archive.map(\.path)), ["manifest.json", "data/folders.json", "data/entries.json", "data/attachments.json", "attachments/file-1"])
        var metadata = Data()
        _ = try archive.extract(try XCTUnwrap(archive["data/attachments.json"])) { metadata.append($0) }
        XCTAssertFalse(String(decoding: metadata, as: UTF8.self).contains("storageName"))
        let attachmentJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: metadata) as? [[String: Any]])
        XCTAssertTrue(attachmentJSON[0]["mimeType"] is NSNull, "Android requires the nullable mimeType key to be present.")
    }

    func testReadsAndroidLegacyVersionFiveDates() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "android-v5", withExtension: "json", subdirectory: "Fixtures"))
        let prepared = try FlowBackup.prepare(from: fixture)
        let date = try XCTUnwrap(FlowDate.date(prepared.library.entries[0].createdAt))
        XCTAssertEqual(date.timeIntervalSince1970, 1_700_000_000.123, accuracy: 0.001)
    }

    func testAndroidAttachmentWithUnknownSizeUsesArchiveSize() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "android-v1", withExtension: "flow", subdirectory: "Fixtures"))
        let file = directory.appendingPathComponent("unknown-size.flow")
        try FileManager.default.copyItem(at: fixture, to: file)
        let archive = try Archive(url: file, accessMode: .update)
        let old = try XCTUnwrap(archive["data/attachments.json"])
        var data = Data()
        _ = try archive.extract(old) { data.append($0) }
        var metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        metadata[0]["size"] = -1
        metadata[0]["mimeType"] = NSNull()
        let changed = try JSONSerialization.data(withJSONObject: metadata)
        try archive.remove(old)
        try archive.addEntry(with: "data/attachments.json", type: .file, uncompressedSize: Int64(changed.count)) { offset, size in
            changed.subdata(in: Int(offset)..<(Int(offset) + size))
        }
        let prepared = try FlowBackup.prepare(from: file)
        XCTAssertEqual(prepared.library.attachments[0].size, 24)
        XCTAssertNil(prepared.library.attachments[0].mimeType)
    }

    func testRejectsMalformedBackups() throws {
        let cases: [(String, (inout [String: Any]) -> Void)] = [
            ("unsupported", { $0["manifest.json"] = ["format": "flow", "formatVersion": 99, "flowVersion": "1", "createdAt": "2026-01-01T00:00:00Z"] }),
            ("duplicate", { $0["data/folders.json"] = [["id": "master", "name": "Master", "position": 0], ["id": "master", "name": "Duplicate", "position": 1]] }),
            ("orphan", { $0["data/entries.json"] = [["id": "e", "text": "x", "createdAt": "2026-01-01T00:00:00Z", "position": 0, "type": "note", "completed": false, "folderId": "missing"]] }),
            ("bad-date", { $0["data/entries.json"] = [["id": "e", "text": "x", "createdAt": "yesterday", "position": 0, "type": "note", "completed": false, "folderId": "master"]] }),
            ("missing-file", { $0["data/attachments.json"] = [["id": "a", "entryId": "e", "fileName": "file.txt", "size": 1, "createdAt": "2026-01-01T00:00:00Z"]] }),
            ("traversal", { $0["data/attachments.json"] = [["id": "../escape", "entryId": "e", "fileName": "file.txt", "size": 1, "createdAt": "2026-01-01T00:00:00Z"]] })
        ]
        for (name, mutate) in cases {
            var files: [String: Any] = [
                "manifest.json": ["format": "flow", "formatVersion": 1, "flowVersion": "1", "createdAt": "2026-01-01T00:00:00Z"],
                "data/folders.json": [["id": "master", "name": "Master", "position": 0]],
                "data/entries.json": [["id": "e", "text": "x", "createdAt": "2026-01-01T00:00:00Z", "position": 0, "type": "note", "completed": false, "folderId": "master"]],
                "data/attachments.json": []
            ]
            mutate(&files)
            let url = directory.appendingPathComponent(name + ".flow")
            let archive = try Archive(url: url, accessMode: .create)
            for (path, value) in files {
                let data = try JSONSerialization.data(withJSONObject: value)
                try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { offset, size in
                    data.subdata(in: Int(offset)..<(Int(offset) + size))
                }
            }
            XCTAssertThrowsError(try FlowBackup.prepare(from: url), name)
        }
    }

    @MainActor
    func testFailedRestorePreservesExistingLibrary() async throws {
        let store = try FlowStore(directory: directory.appendingPathComponent("store"))
        let existing = Entry(text: "Keep me")
        try store.save(existing)
        let library = Library(entries: [Entry(id: "new", text: "Incoming")], attachments: [Attachment(entryId: "new", fileName: "missing.txt", mimeType: nil, size: 1)])
        let backup = PreparedBackup(library: library, createdAt: FlowDate.string(), files: [:], directory: directory.appendingPathComponent("staging"))
        do {
            try await store.restore(backup)
            XCTFail("A backup with a missing file must not replace the library.")
        } catch {}
        XCTAssertFalse(store.isRestoring)
        XCTAssertEqual(store.library.entries, [existing])
        XCTAssertEqual(try FlowStore(directory: store.directory).library.entries, [existing])
    }

    @MainActor
    func testMissingAttachmentKeepsLibraryAndMetadataUsable() async throws {
        let store = try FlowStore(directory: directory)
        let entry = Entry(text: "Keep my note")
        try store.save(entry)
        let source = directory.appendingPathComponent("document.txt")
        try Data("content".utf8).write(to: source)
        try store.addAttachment(from: source, to: entry.id, mimeType: "text/plain")
        let attachment = try XCTUnwrap(store.attachments(for: entry.id).first)
        try FileManager.default.removeItem(at: store.attachmentURL(attachment))
        let original = try Data(contentsOf: directory.appendingPathComponent("library.json"))
        let reopened = try FlowStore(directory: directory)
        XCTAssertEqual(reopened.entry(entry.id), entry)
        XCTAssertEqual(reopened.missingAttachments, [attachment])
        XCTAssertEqual(reopened.attachments(for: entry.id), [attachment])
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("library.json")), original)
        try reopened.save(Entry(text: "Still usable"))
        XCTAssertEqual(reopened.library.entries.count, 2)
    }

    @MainActor
    func testRecoveryPreservesOriginalLibraryAndAttachmentBytes() async throws {
        let file = directory.appendingPathComponent("library.json")
        let corruptData = Data("corrupt library".utf8)
        try corruptData.write(to: file)
        let attachments = directory.appendingPathComponent("attachments")
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        try Data("irreplaceable file".utf8).write(to: attachments.appendingPathComponent("file.txt"))
        let recovery = try FlowStore.startNewLibrary(at: directory)
        let preserved = try XCTUnwrap(recovery.preservedDirectory)
        defer { try? FileManager.default.removeItem(at: preserved) }
        XCTAssertEqual(try Data(contentsOf: preserved.appendingPathComponent("library.json")), corruptData)
        XCTAssertEqual(try String(contentsOf: preserved.appendingPathComponent("attachments/file.txt"), encoding: .utf8), "irreplaceable file")
        XCTAssertTrue(recovery.store.library.entries.isEmpty)
        try recovery.store.save(Entry(text: "Recovered"))
        XCTAssertEqual(try FlowStore(directory: directory).library.entries.first?.text, "Recovered")
    }

    @MainActor
    func testRestoreLeavesMainActorResponsiveAndRejectsConcurrentWrites() async throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "android-v1", withExtension: "flow", subdirectory: "Fixtures"))
        let backup = try FlowBackup.prepare(from: fixture)
        let store = try FlowStore(directory: directory)
        let original = store.library
        let started = expectation(description: "Background restore started")
        let gate = DispatchSemaphore(value: 0)
        let restore = Task {
            try await store.restore(backup) { backup, directory in
                XCTAssertFalse(Thread.isMainThread)
                started.fulfill()
                guard gate.wait(timeout: .now() + 10) == .success else {
                    throw FlowError.invalid("The main actor did not resume during restore.")
                }
                return try FlowStore.writeRestore(backup, directory: directory)
            }
        }
        await fulfillment(of: [started], timeout: 5)
        XCTAssertTrue(store.isRestoring)
        XCTAssertEqual(store.library, original)
        XCTAssertThrowsError(try store.save(Entry(text: "Conflicting write")))
        XCTAssertThrowsError(try store.undoDeletion())
        gate.signal()
        try await restore.value
        XCTAssertFalse(store.isRestoring)
        XCTAssertEqual(store.library.entries, backup.library.entries)
        XCTAssertEqual(try FlowStore(directory: directory).library, store.library)
    }

    func testLegacyImportRejectsOversizedFileBeforeDecoding() throws {
        let file = directory.appendingPathComponent("oversized.json")
        try Data("{".utf8).write(to: file)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 32 * 1024 * 1024 + 1)
        try handle.close()
        XCTAssertThrowsError(try FlowBackup.prepare(from: file)) { error in
            XCTAssertTrue(error.localizedDescription.contains("too large"))
        }
    }

    func testCachedDatesPreserveBothFormatsAcrossConcurrentCalls() {
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            let date = Date(timeIntervalSince1970: 1_700_000_000.123)
            XCTAssertEqual(FlowDate.string(date), "2023-11-14T22:13:20.123Z")
            XCTAssertEqual(FlowDate.date("2023-11-14T22:13:20.123Z")!.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertEqual(FlowDate.date("2023-11-14T22:13:20Z")!.timeIntervalSince1970, 1_700_000_000)
            XCTAssertNil(FlowDate.date("invalid"))
        }
    }
}
