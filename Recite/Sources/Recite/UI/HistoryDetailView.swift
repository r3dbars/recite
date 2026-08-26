import SwiftUI
import AppKit

struct HistoryDetailView: View {
    @StateObject private var queue = ReadingQueue.shared

    var body: some View {
        VStack(spacing: 0) {
            if queue.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 44))
                        .foregroundColor(Color.secondary.opacity(0.4))
                    Text("No History Yet")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Items you've listened to will appear here.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(queue.history) { item in
                        HistoryItemRow(item: item)
                            .onTapGesture {
                                let replay = queue.add(text: item.text, source: item.source)
                                queue.play(item: replay)
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("History")
        .navigationSubtitle("Tap any item to read it again.")
        .toolbar {
            if !queue.history.isEmpty {
                ToolbarItem(placement: .automatic) {
                    Button("Clear") { queue.clearHistory() }
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct HistoryItemRow: View {
    let item: ReadingQueue.Item

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.preview)
                .font(.system(size: 13))
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(item.source)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("·")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                Text(Self.dateFormatter.localizedString(for: item.addedAt, relativeTo: Date()))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("·")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                Text("~\(item.estimatedMinutes) min")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
