import Foundation
import Combine

/// Manages a queue of text items to be read aloud.
@MainActor
class ReadingQueue: ObservableObject {
    static let shared = ReadingQueue()

    struct Item: Identifiable {
        let id = UUID()
        let text: String
        let source: String      // "Selection", "Clipboard", "File", etc.
        let addedAt: Date
        var preview: String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.prefix(80)) + (trimmed.count > 80 ? "…" : "")
        }
        var wordCount: Int {
            text.split(separator: " ").count
        }
        var estimatedMinutes: Int {
            max(1, wordCount / 180) // ~180 wpm reading speed
        }
    }

    @Published var items: [Item] = []
    @Published var currentIndex: Int? = nil

    var currentItem: Item? {
        guard let idx = currentIndex, items.indices.contains(idx) else { return nil }
        return items[idx]
    }

    var isEmpty: Bool { items.isEmpty }

    // MARK: - Queue Management

    func add(text: String, source: String = "Unknown") {
        let item = Item(text: text, source: source, addedAt: Date())
        items.append(item)
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        if let idx = currentIndex {
            if offsets.contains(idx) {
                SpeechEngine.shared.stop()
                currentIndex = nil
            } else {
                let removed = offsets.filter { $0 < idx }.count
                currentIndex = idx - removed
            }
        }
    }

    func clear() {
        SpeechEngine.shared.stop()
        items.removeAll()
        currentIndex = nil
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        items.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    // MARK: - Playback Control

    func playNext() {
        guard !items.isEmpty else { return }

        if let idx = currentIndex {
            let next = idx + 1
            if next < items.count {
                currentIndex = next
                SpeechEngine.shared.speak(items[next].text)
            } else {
                currentIndex = nil
            }
        } else {
            currentIndex = 0
            SpeechEngine.shared.speak(items[0].text)
        }
    }

    func play(item: Item) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        currentIndex = idx
        SpeechEngine.shared.speak(item.text)
    }

    func didFinishCurrent() {
        guard let idx = currentIndex else { return }
        let next = idx + 1
        if next < items.count {
            currentIndex = next
            SpeechEngine.shared.speak(items[next].text)
        } else {
            currentIndex = nil
        }
    }
}
