import Testing
import Foundation
@testable import EverClipCore

@Suite final class ClipStoreTests {
    let store: ClipStore
    let tempDir: URL

    init() throws {
        tempDir = TestSupport.makeTempDir()
        let blobStore = try BlobStore(root: tempDir)
        store = try ClipStore.inMemory(blobStore: blobStore)
    }

    deinit { TestSupport.remove(tempDir) }

    private func textDraft(_ text: String) -> ClipDraft { ClipDraft(kind: .text, text: text) }

    @Test func storeAndFetchRecent() throws {
        let outcome = try store.store(textDraft("first"))
        let item = try #require(outcome.item)
        #expect(item.id != nil)
        #expect(item.preview == "first")

        let recent = try store.recent()
        #expect(recent.count == 1)
        #expect(recent.first?.text == "first")
    }

    @Test func count() throws {
        try store.store(textDraft("a"))
        try store.store(textDraft("b"))
        #expect(try store.count() == 2)
    }

    @Test func favoriteToggle() throws {
        let item = try #require(try store.store(textDraft("fav")).item)
        #expect(try store.favorites().isEmpty)

        try store.setFavorite(id: item.id!, isFavorite: true)
        let favs = try store.favorites()
        #expect(favs.count == 1)
        #expect(favs.first?.id == item.id)

        try store.setFavorite(id: item.id!, isFavorite: false)
        #expect(try store.favorites().isEmpty)
    }

    @Test func delete() throws {
        let item = try #require(try store.store(textDraft("bye")).item)
        try store.delete(id: item.id!)
        #expect(try store.count() == 0)
    }

    @Test func clearKeepsFavorites() throws {
        let keep = try #require(try store.store(textDraft("keep me")).item)
        try store.store(textDraft("drop me"))
        try store.setFavorite(id: keep.id!, isFavorite: true)

        try store.clear(keepFavorites: true)

        let remaining = try store.recent()
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == keep.id)
    }

    @Test func clearAll() throws {
        let keep = try #require(try store.store(textDraft("keep me")).item)
        try store.setFavorite(id: keep.id!, isFavorite: true)
        try store.store(textDraft("other"))

        try store.clear(keepFavorites: false)
        #expect(try store.count() == 0)
    }

    @Test func topRecentLimit() throws {
        for i in 0..<15 { try store.store(textDraft("item \(i)")) }
        #expect(try store.topRecent(limit: 10).count == 10)
    }

    @Test func imageBlobIsWrittenToDisk() throws {
        let draft = ClipDraft(kind: .image, imageData: TestSupport.onePixelPNG, imageFileExtension: "png")
        let item = try #require(try store.store(draft).item)

        #expect(item.kind == .image)
        let blobURL = try #require(store.blobURL(for: item))
        #expect(FileManager.default.fileExists(atPath: blobURL.path))
        #expect(item.thumbnailPath != nil)
        #expect(item.byteSize > 0)
    }

    @Test func deleteRemovesBlobFromDisk() throws {
        let draft = ClipDraft(kind: .image, imageData: TestSupport.onePixelPNG, imageFileExtension: "png")
        let item = try #require(try store.store(draft).item)
        let blobURL = try #require(store.blobURL(for: item))
        #expect(FileManager.default.fileExists(atPath: blobURL.path))

        try store.delete(id: item.id!)
        #expect(!FileManager.default.fileExists(atPath: blobURL.path))
    }
}
