import Testing
import Foundation
@testable import EverClipCore

@Suite final class ExportTests {
    let tempDir: URL
    let store: ClipStore

    init() throws {
        tempDir = TestSupport.makeTempDir()
        let blobStore = try BlobStore(root: tempDir.appendingPathComponent("store"))
        store = try ClipStore.inMemory(blobStore: blobStore)
        try store.store(ClipDraft(kind: .text, text: "note one"))
        try store.store(ClipDraft(kind: .image, imageData: TestSupport.onePixelPNG, imageFileExtension: "png"))
    }

    deinit { TestSupport.remove(tempDir) }

    @Test func archiveBuilderWritesManifest() throws {
        let out = tempDir.appendingPathComponent("out")
        let archive = try ArchiveBuilder().build(
            items: try store.allItems(),
            blobURLProvider: { self.store.blobURL(for: $0) },
            includeBlobs: true,
            into: out,
            zip: false
        )
        #expect(archive.itemCount == 2)

        let manifestURL = archive.directoryURL.appendingPathComponent("manifest.json")
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(ArchiveManifest.self, from: Data(contentsOf: manifestURL))
        #expect(manifest.itemCount == 2)
        #expect(manifest.application == "EverClip")

        let imageItem = manifest.items.first { $0.kind == "image" }
        #expect(imageItem?.blobPath != nil)
    }

    @Test func archiveBuilderCanZip() throws {
        let out = tempDir.appendingPathComponent("outzip")
        let archive = try ArchiveBuilder().build(
            items: try store.allItems(),
            blobURLProvider: { self.store.blobURL(for: $0) },
            includeBlobs: true,
            into: out,
            zip: true
        )
        let zipURL = try #require(archive.zipURL)
        #expect(FileManager.default.fileExists(atPath: zipURL.path))
        #expect(zipURL.pathExtension == "zip")
    }

    @Test func localFolderExporterCopiesArchive() async throws {
        let out = tempDir.appendingPathComponent("staging")
        let archive = try ArchiveBuilder().build(
            items: try store.allItems(),
            blobURLProvider: { self.store.blobURL(for: $0) },
            includeBlobs: false,
            into: out,
            zip: true
        )
        let destination = tempDir.appendingPathComponent("backups")
        let exporter = LocalFolderExporter(destinationFolder: destination)
        try await exporter.export(archive)

        let copied = destination.appendingPathComponent(archive.preferredFileURL.lastPathComponent)
        #expect(FileManager.default.fileExists(atPath: copied.path))
    }

    @Test func gmailMIMEIncludesHeadersAndAttachment() {
        let mime = GmailExporter.buildMIME(
            to: "me@example.com",
            attachmentName: "backup.zip",
            zip: TestSupport.onePixelPNG,
            date: Date(timeIntervalSince1970: 0)
        )
        #expect(mime.contains("To: me@example.com"))
        #expect(mime.contains("Subject: EverClip clipboard backup"))
        #expect(mime.contains("Content-Disposition: attachment; filename=\"backup.zip\""))
        #expect(mime.contains("Content-Transfer-Encoding: base64"))
        #expect(mime.contains("multipart/mixed"))
    }

    @Test func exportDisabledByDefault() {
        #expect(!AppSettings.default.export.isEnabled)
        #expect(AppSettings.default.export.schedule == .off)
        #expect(AppSettings.default.export.targets.isEmpty)
    }
}
