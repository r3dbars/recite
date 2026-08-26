import SwiftUI
import AppKit

struct QueueDetailView: View {
    @StateObject private var queue  = ReadingQueue.shared

    var body: some View {
        VStack(spacing: 0) {
            if queue.items.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(queue.items) { item in
                        QueueItemRow(item: item, isCurrent: queue.currentItem?.id == item.id)
                            .onTapGesture { queue.play(item: item) }
                    }
                    .onDelete { queue.remove(at: $0) }
                    .onMove { queue.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Queue")
        .toolbar {
            if !queue.items.isEmpty {
                ToolbarItem(placement: .automatic) {
                    Button("Clear All") { queue.clear() }
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.circle")
                .font(.system(size: 44))
                .foregroundColor(Color.secondary.opacity(0.5))
            Text("Queue is Empty")
                .font(.system(size: 17, weight: .semibold))
            Text("Add text from your clipboard or the Paste & Read button.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Queue Item Row

struct QueueItemRow: View {
    let item: ReadingQueue.Item
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isCurrent ? "waveform" : "doc.text")
                .font(.system(size: 12))
                .foregroundColor(isCurrent ? .accentColor : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.preview)
                    .font(.system(size: 13))
                    .foregroundColor(isCurrent ? .primary : .primary)
                    .lineLimit(2)
                Text("~\(item.estimatedMinutes) min · \(item.source)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.07) : Color.clear)
    }
}
