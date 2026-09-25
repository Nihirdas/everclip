import Testing
import Foundation
@testable import EverClipCore

@Suite final class SearchTests {
    let store: ClipStore

    init() throws {
        store = try ClipStore.inMemory()
        try store.store(ClipDraft(kind: .text, text: "hello world"))
        try store.store(ClipDraft(kind: .text, text: "goodbye world"))
        try store.store(ClipDraft(kind: .url, text: "https://example.com/search"))
    }

    @Test func fullTextSingleToken() throws {
        let results = try store.search(SearchQuery(text: "hello"))
        #expect(results.count == 1)
        #expect(results.first?.text == "hello world")
    }

    @Test func fullTextSharedToken() throws {
        #expect(try store.search(SearchQuery(text: "world")).count == 2)
    }

    @Test func prefixMatch() throws {
        #expect(try store.search(SearchQuery(text: "wor")).count == 2)
    }

    @Test func multiTokenIsAnd() throws {
        #expect(try store.search(SearchQuery(text: "hello world")).count == 1)
        #expect(try store.search(SearchQuery(text: "hello goodbye")).count == 0)
    }

    @Test func typeFilter() throws {
        let results = try store.search(SearchQuery(text: "", kinds: [.url]))
        #expect(results.count == 1)
        #expect(results.first?.kind == .url)
    }

    @Test func emptyQueryReturnsAll() throws {
        #expect(try store.search(SearchQuery()).count == 3)
    }

    @Test func favoritesOnly() throws {
        let item = try #require(try store.recent().first)
        try store.setFavorite(id: item.id!, isFavorite: true)
        let results = try store.search(SearchQuery(favoritesOnly: true))
        #expect(results.count == 1)
        #expect(results.first?.id == item.id)
    }

    @Test func searchWithinURL() throws {
        let results = try store.search(SearchQuery(text: "example"))
        #expect(results.count == 1)
        #expect(results.first?.kind == .url)
    }

    @Test func noMatch() throws {
        #expect(try store.search(SearchQuery(text: "zzznotfound")).isEmpty)
    }
}
