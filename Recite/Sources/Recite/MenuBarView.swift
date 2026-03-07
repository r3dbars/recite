import SwiftUI

struct MenuBarView: View {
    @StateObject private var engine = SpeechEngine.shared
    @StateObject private var queue = ReadingQueue.shared
    @StateObject private var grabber = TextGrabber.shared
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            playerSection
            Divider()
            queueSection
            Divider()
            footerSection
        }
        .frame(width: 300)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "headphones")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.accentColor)
            Text("Recite")
                .font(.system(size: 16, weight: .bold))
            Spacer()
            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: "gear")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingSettings) {
                SettingsView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Player

    private var playerSection: some View {
        VStack(spacing: 8) {
            // Now playing text
            if let item = queue.currentItem {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                        Text(item.source.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    Text(item.preview)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 8)

                // Progress bar
                ProgressView(value: engine.progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .padding(.horizontal, 14)

            } else {
                Text(queue.isEmpty ? "Select text and press ⌘⇧R" : "Tap play to start")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }

            // Playback controls
            HStack(spacing: 16) {
                // Skip back
                Button {
                    // Restart current or go to previous
                    if engine.progress > 0.1, let item = queue.currentItem {
                        queue.play(item: item)
                    }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .disabled(queue.currentItem == nil)

                // Play / Pause
                Button {
                    if engine.state == .idle && !queue.isEmpty {
                        queue.playNext()
                    } else {
                        engine.togglePlayPause()
                    }
                } label: {
                    Image(systemName: engine.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(queue.isEmpty && engine.state == .idle ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(queue.isEmpty && engine.state == .idle)

                // Skip forward
                Button {
                    engine.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .disabled(queue.currentIndex == nil)

                Spacer()

                // Speed control
                Menu {
                    ForEach([0.4, 0.5, 0.6, 0.7, 0.8, 1.0], id: \.self) { spd in
                        Button(speedLabel(spd)) {
                            engine.updateRate(Float(spd))
                        }
                    }
                } label: {
                    Text(speedLabel(Double(engine.rate)))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Queue

    private var queueSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if !queue.items.isEmpty {
                    Button("Clear") {
                        queue.clear()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            if queue.items.isEmpty {
                Text("Nothing queued")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 10)
            } else {
                List {
                    ForEach(queue.items) { item in
                        QueueItemRow(item: item,
                                     isCurrent: queue.currentItem?.id == item.id)
                        .onTapGesture {
                            queue.play(item: item)
                        }
                    }
                    .onDelete { queue.remove(at: $0) }
                    .onMove { queue.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain)
                .frame(maxHeight: 160)
                .environment(\.editMode, .constant(.active))
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            // Add clipboard button
            Button {
                if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                    queue.add(text: text, source: "Clipboard")
                }
            } label: {
                Label("Add Clipboard", systemImage: "clipboard")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func speedLabel(_ rate: Double) -> String {
        let pct = Int((rate / Double(AVSpeechUtteranceDefaultSpeechRate)) * 100)
        return "\(pct)%"
    }
}

// MARK: - Queue Row

struct QueueItemRow: View {
    let item: ReadingQueue.Item
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isCurrent {
                Image(systemName: "waveform")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundColor(isCurrent ? .primary : .secondary)
                Text("~\(item.estimatedMinutes) min · \(item.source)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .background(isCurrent ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(4)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @StateObject private var engine = SpeechEngine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Voice")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Picker("Voice", selection: $engine.selectedVoiceIdentifier) {
                    ForEach(engine.availableVoices, id: \.identifier) { voice in
                        Text("\(voice.name) (\(voice.language))")
                            .tag(voice.identifier)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Speed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                HStack {
                    Text("Slow")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Slider(value: $engine.rate, in: 0.3...0.9)
                    Text("Fast")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Text("Global hotkey: ⌘⇧R\nRequires Accessibility permission.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 260)
    }
}
