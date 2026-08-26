import XCTest
@testable import Recite

@MainActor
final class ReadingQueueTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var queue: ReadingQueue!

    override func setUp() {
        super.setUp()
        suiteName = "ReciteTests.ReadingQueue.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        queue = ReadingQueue(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        suiteName = nil
        defaults = nil
        queue = nil
        super.tearDown()
    }

    func testPreviewTruncatesLongText() {
        let short = ReadingQueue.Item(text: "Hello world", source: "Test", addedAt: Date())
        XCTAssertEqual(short.preview, "Hello world")

        let longText = String(repeating: "a", count: 100)
        let long = ReadingQueue.Item(text: longText, source: "Test", addedAt: Date())
        XCTAssertEqual(long.preview.count, 81)
        XCTAssertTrue(long.preview.hasSuffix("…"))
        XCTAssertEqual(String(long.preview.dropLast()), String(repeating: "a", count: 80))
    }

    func testWordCountSplitsOnSpaces() {
        let item = ReadingQueue.Item(
            text: "one two three four",
            source: "Clipboard",
            addedAt: Date()
        )
        XCTAssertEqual(item.wordCount, 4)
        XCTAssertEqual(item.estimatedMinutes, 1)
    }

    func testHistoryCapsAtMaxAndPersistsInSuite() {
        for index in 0..<(ReadingQueue.maxHistory + 5) {
            let item = ReadingQueue.Item(
                text: "item \(index)",
                source: "Test",
                addedAt: Date()
            )
            queue.addToHistory(item)
        }

        XCTAssertEqual(queue.history.count, ReadingQueue.maxHistory)
        XCTAssertEqual(queue.history.first?.text, "item \(ReadingQueue.maxHistory + 4)")
        XCTAssertEqual(queue.history.last?.text, "item 5")

        let reloaded = ReadingQueue(defaults: defaults)
        XCTAssertEqual(reloaded.history.count, ReadingQueue.maxHistory)
        XCTAssertEqual(reloaded.history.first?.text, queue.history.first?.text)
    }
}
