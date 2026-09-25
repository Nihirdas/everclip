import Testing
import Foundation
@testable import EverClipCore

@Suite struct DedupeTests {

    @Test func identicalTextCollapses() throws {
        let store = try ClipStore.inMemory()
        let first = try store.store(ClipDraft(kind: .text, text: "same"))
        let second = try store.store(ClipDraft(kind: .text, text: "same"))

        if case .inserted = first {} else { Issue.record("first should insert") }
        if case .duplicateBumped(let bumped) = second {
            #expect(bumped.id == first.item?.id)
        } else {
            Issue.record("second should be a duplicate")
        }
        #expect(try store.count() == 1)
    }

    @Test func differentTextDoesNotCollapse() throws {
        let store = try ClipStore.inMemory()
        try store.store(ClipDraft(kind: .text, text: "one"))
        try store.store(ClipDraft(kind: .text, text: "two"))
        #expect(try store.count() == 2)
    }

    @Test func duplicateFloatsToTop() throws {
        let store = try ClipStore.inMemory()
        let a = try #require(try store.store(ClipDraft(kind: .text, text: "alpha")).item)
        usleep(10_000)
        try store.store(ClipDraft(kind: .text, text: "beta"))
        usleep(10_000)

        // Re-copying alpha should bump it above beta.
        try store.store(ClipDraft(kind: .text, text: "alpha"))
        let recent = try store.recent()
        #expect(recent.first?.id == a.id)
        #expect(recent.count == 2)
    }

    @Test func sameBytesImageCollapses() throws {
        let tempDir = TestSupport.makeTempDir()
        defer { TestSupport.remove(tempDir) }
        let blobStore = try BlobStore(root: tempDir)
        let imageStore = try ClipStore.inMemory(blobStore: blobStore)

        try imageStore.store(ClipDraft(kind: .image, imageData: TestSupport.onePixelPNG, imageFileExtension: "png"))
        try imageStore.store(ClipDraft(kind: .image, imageData: TestSupport.onePixelPNG, imageFileExtension: "png"))
        #expect(try imageStore.count() == 1)
    }

    @Test func hashDistinguishesKinds() {
        let textHash = ContentHasher.hash(for: ClipDraft(kind: .text, text: "https://x.com"))
        let urlHash = ContentHasher.hash(for: ClipDraft(kind: .url, text: "https://x.com"))
        #expect(textHash != urlHash)
    }
}
