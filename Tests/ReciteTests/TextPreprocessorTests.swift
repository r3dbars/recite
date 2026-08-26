import XCTest
@testable import Recite

final class TextPreprocessorTests: XCTestCase {
    func testPreprocessStripsMarkdown() {
        let raw = """
        # Heading
        This is **bold** and *italic* plus `code`.
        [Docs](https://example.com/path)
        """

        let cleaned = TextPreprocessor.preprocessText(raw)

        XCTAssertFalse(cleaned.contains("#"))
        XCTAssertFalse(cleaned.contains("**"))
        XCTAssertFalse(cleaned.contains("`"))
        XCTAssertTrue(cleaned.contains("Heading"))
        XCTAssertTrue(cleaned.contains("bold"))
        XCTAssertTrue(cleaned.contains("italic"))
        XCTAssertTrue(cleaned.contains("code"))
        XCTAssertTrue(cleaned.contains("Docs"))
        XCTAssertFalse(cleaned.contains("https://example.com/path"))
    }

    func testPreprocessStripsSlackEmojiAndTimestamps() {
        let raw = "Thanks :thankyoured: for the note [9:19 AM]"
        let cleaned = TextPreprocessor.preprocessText(raw)

        XCTAssertFalse(cleaned.contains(":thankyoured:"))
        XCTAssertFalse(cleaned.contains("[9:19 AM]"))
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("Thanks"))
        XCTAssertTrue(cleaned.localizedCaseInsensitiveContains("note"))
    }

    func testPreprocessReplacesURLsWithLink() {
        let raw = "See https://example.com/docs and also github.com/r3dbars/recite."
        let cleaned = TextPreprocessor.preprocessText(raw)

        XCTAssertFalse(cleaned.contains("https://"))
        XCTAssertFalse(cleaned.contains("github.com/r3dbars/recite"))
        XCTAssertTrue(cleaned.contains("link"))
    }

    func testSplitIntoSentencesChunksLongSentence() {
        let word = "word"
        let long = Array(repeating: word, count: 200).joined(separator: " ")
        XCTAssertGreaterThan(long.count, TextPreprocessor.maxChunkChars)

        let chunks = TextPreprocessor.splitIntoSentences(long)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= TextPreprocessor.maxChunkChars })
        XCTAssertEqual(chunks.joined(separator: " ").replacingOccurrences(of: ".", with: ""), long)
    }

    func testSplitIntoSentencesEmpty() {
        XCTAssertEqual(TextPreprocessor.splitIntoSentences(""), [])
        XCTAssertEqual(TextPreprocessor.splitIntoSentences("   \n\n  "), [])
        XCTAssertEqual(TextPreprocessor.preprocessText(""), "")
    }
}
