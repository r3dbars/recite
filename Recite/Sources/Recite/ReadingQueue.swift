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
            max(1, (wordCount + 179) / 180) // ~180 wpm reading speed
        }
    }

    @Published var items: [Item] = []
    @Published var currentIndex: Int? = nil
    @Published var history: [Item] = []

    static let historyKey = "readingHistory"
    static let maxHistory = 50

    private let defaults: UserDefaults

    var currentItem: Item? {
        guard let idx = currentIndex, items.indices.contains(idx) else { return nil }
        return items[idx]
    }

    var isEmpty: Bool { items.isEmpty }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadHistory()
    }

    // MARK: - Queue Management

    @discardableResult
    func add(text: String, source: String = "Unknown") -> Item {
        let item = Item(text: text, source: source, addedAt: Date())
        items.append(item)
        return item
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
        let currentID = currentItem?.id
        items.move(fromOffsets: fromOffsets, toOffset: toOffset)
        if let currentID {
            currentIndex = items.firstIndex { $0.id == currentID }
        }
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
        // Save to history before advancing
        addToHistory(items[idx])
        let next = idx + 1
        if next < items.count {
            currentIndex = next
            SpeechEngine.shared.speak(items[next].text)
        } else {
            currentIndex = nil
        }
    }

    func clearHistory() {
        history.removeAll()
        defaults.removeObject(forKey: Self.historyKey)
    }

    // MARK: - History Persistence

    func addToHistory(_ item: Item) {
        // Deduplicate by text
        history.removeAll { $0.text == item.text }
        history.insert(item, at: 0)
        if history.count > Self.maxHistory {
            history = Array(history.prefix(Self.maxHistory))
        }
        saveHistory()
    }

    private func saveHistory() {
        let data = history.compactMap { item -> [String: String]? in
            ["text": item.text, "source": item.source, "addedAt": ISO8601DateFormatter().string(from: item.addedAt)]
        }
        defaults.set(data, forKey: Self.historyKey)
    }

    private func loadHistory() {
        guard let data = defaults.array(forKey: Self.historyKey) as? [[String: String]] else { return }
        let fmt = ISO8601DateFormatter()
        history = data.compactMap { dict in
            guard let text = dict["text"], let source = dict["source"],
                  let dateStr = dict["addedAt"], let date = fmt.date(from: dateStr) else { return nil }
            return Item(text: text, source: source, addedAt: date)
        }
    }
}
