import Testing
import Foundation
@testable import EverClipCore

@Suite struct ClipClassifierTests {
    let classifier = ClipClassifier()

    @Test func concealedIsNeverStored() {
        var snapshot = TestSupport.textSnapshot("hunter2")
        snapshot.isConcealed = true
        #expect(classifier.makeDraft(from: snapshot) == nil)
    }

    @Test func transientIsSkipped() {
        var snapshot = TestSupport.textSnapshot("temporary")
        snapshot.isTransient = true
        #expect(classifier.makeDraft(from: snapshot) == nil)
    }

    @Test func emptyTextIsSkipped() {
        #expect(classifier.makeDraft(from: TestSupport.textSnapshot("   \n  ")) == nil)
        #expect(classifier.makeDraft(from: PasteboardSnapshot()) == nil)
    }

    @Test func plainText() {
        let draft = classifier.makeDraft(from: TestSupport.textSnapshot("hello world"))
        #expect(draft?.kind == .text)
        #expect(draft?.text == "hello world")
    }

    @Test func textIsTrimmed() {
        #expect(classifier.makeDraft(from: TestSupport.textSnapshot("  spaced  "))?.text == "spaced")
    }

    @Test func urlFromText() {
        #expect(classifier.makeDraft(from: TestSupport.textSnapshot("https://example.com"))?.kind == .url)
        #expect(classifier.makeDraft(from: TestSupport.textSnapshot("example.com"))?.kind == .url)
    }

    @Test func sentenceContainingURLIsNotAURL() {
        #expect(classifier.makeDraft(from: TestSupport.textSnapshot("see example.com for details"))?.kind == .text)
    }

    @Test func urlFromPasteboardField() {
        var snapshot = PasteboardSnapshot(types: ["public.url"])
        snapshot.urlString = "https://swift.org"
        #expect(classifier.makeDraft(from: snapshot)?.kind == .url)
    }

    @Test func richText() {
        var snapshot = TestSupport.textSnapshot("styled")
        snapshot.rtf = Data("{\\rtf1}".utf8)
        let draft = classifier.makeDraft(from: snapshot)
        #expect(draft?.kind == .richText)
        #expect(draft?.text == "styled")
        #expect(draft?.rtfData != nil)
    }

    @Test func image() {
        var snapshot = PasteboardSnapshot(types: ["public.png"])
        snapshot.imageData = TestSupport.onePixelPNG
        snapshot.imageFileExtension = "png"
        #expect(classifier.makeDraft(from: snapshot)?.kind == .image)
    }

    @Test func screenshotDetectedByType() {
        var snapshot = PasteboardSnapshot(types: ["public.png", "com.apple.screencapture"])
        snapshot.imageData = TestSupport.onePixelPNG
        #expect(classifier.makeDraft(from: snapshot)?.kind == .screenshot)
    }

    @Test func fileURLs() {
        let snapshot = PasteboardSnapshot(types: ["public.file-url"], fileURLs: ["/tmp/a.txt", "/tmp/b.txt"])
        let draft = classifier.makeDraft(from: snapshot)
        #expect(draft?.kind == .file)
        #expect(draft?.fileURLs.count == 2)
    }

    @Test func fileURLsWinOverText() {
        var snapshot = PasteboardSnapshot(types: ["public.file-url"], fileURLs: ["/tmp/a.txt"])
        snapshot.plainText = "some caption"
        #expect(classifier.makeDraft(from: snapshot)?.kind == .file)
    }
}
