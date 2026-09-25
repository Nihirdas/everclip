import Testing
import Foundation
@testable import EverClipCore

@Suite struct RetentionTests {

    private func candidate(_ id: Int64, ageDays: Double, bytes: Int = 100, favorite: Bool = false, now: Date) -> RetentionCandidate {
        RetentionCandidate(id: id, updatedAt: now.addingTimeInterval(-ageDays * 86_400), byteSize: bytes, isFavorite: favorite)
    }

    @Test func unlimitedPrunesNothing() {
        let now = Date()
        let candidates = [candidate(1, ageDays: 1000, now: now), candidate(2, ageDays: 5, now: now)]
        #expect(RetentionPolicy.unlimited.idsToPrune(from: candidates, now: now).isEmpty)
    }

    @Test func maxItemsKeepsNewest() {
        let now = Date()
        let candidates = [
            candidate(1, ageDays: 1, now: now),
            candidate(2, ageDays: 2, now: now),
            candidate(3, ageDays: 3, now: now),
            candidate(4, ageDays: 4, now: now)
        ]
        #expect(RetentionPolicy(maxItems: 2).idsToPrune(from: candidates, now: now) == [3, 4])
    }

    @Test func maxDaysPrunesOld() {
        let now = Date()
        let candidates = [
            candidate(1, ageDays: 2, now: now),
            candidate(2, ageDays: 10, now: now),
            candidate(3, ageDays: 40, now: now)
        ]
        #expect(RetentionPolicy(maxDays: 7).idsToPrune(from: candidates, now: now) == [2, 3])
    }

    @Test func maxDiskBytesPrunesOverflow() {
        let now = Date()
        let candidates = [
            candidate(1, ageDays: 1, bytes: 400, now: now),
            candidate(2, ageDays: 2, bytes: 400, now: now),
            candidate(3, ageDays: 3, bytes: 400, now: now)
        ]
        // Budget 900: newest two (800) fit, third overflows.
        #expect(RetentionPolicy(maxDiskBytes: 900).idsToPrune(from: candidates, now: now) == [3])
    }

    @Test func favoritesAreNeverPruned() {
        let now = Date()
        let candidates = [
            candidate(1, ageDays: 100, favorite: true, now: now),
            candidate(2, ageDays: 2, now: now),
            candidate(3, ageDays: 3, now: now),
            candidate(4, ageDays: 4, now: now)
        ]
        let victims = RetentionPolicy(maxDays: 7, maxItems: 1).idsToPrune(from: candidates, now: now)
        #expect(!victims.contains(1))
    }

    @Test func storeApplyRetentionByCount() throws {
        let store = try ClipStore.inMemory()
        var ids: [Int64] = []
        for i in 0..<5 {
            let item = try #require(try store.store(ClipDraft(kind: .text, text: "n\(i)")).item)
            ids.append(item.id!)
            usleep(3_000)
        }
        try store.setFavorite(id: ids[0], isFavorite: true)

        let pruned = try store.applyRetention(RetentionPolicy(maxItems: 2))
        #expect(pruned.count == 2)          // 4 non-favorites, keep newest 2
        #expect(try store.count() == 3)     // 2 non-favorites + 1 favorite
        #expect(!pruned.contains(ids[0]))   // favorite untouched
    }
}
