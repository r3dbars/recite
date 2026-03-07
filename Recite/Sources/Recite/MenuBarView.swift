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
            modelStatusBanner
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

    // MARK: - Model Status

    @ViewBuilder
    private var modelStatusBanner: some View {
        switch engine.modelStatus {
        case .notLoaded:
            statusRow(icon: "arrow.down.circle", text: "Model not loaded", color: .orange)
        case .downloading(let progress):
            VStack(spacing: 4) {
                statusRow(icon: "arrow.down.circle", text: "Downloading model…", color: .blue)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
        case .loading:
            statusRow(icon: "circle.dotted", text: "Loading Qwen3-TTS…", color: .blue)
        case .ready:
            EmptyView()
        case .error(let msg):
            VStack(spacing: 4) {
                statusRow(icon: "exclamationmark.triangle", text: "Model error", color: .red)
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                Button("Retry") {
                    Task { await engine.loadModel() }
                }
                .font(.system(size: 11))
                .padding(.bottom, 6)
            }
        }
    }

    private func statusRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
    }

    // MARK: - Player

    private var playerSection: some View {
        VStack(spacing: 8) {
            if let item = queue.currentItem {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if engine.state == .generating {
                            ProgressView()
                                .controlSize(.mini)
                            Text("GENERATING…")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.orange)
                        } else {
                            Image(systemName: "waveform")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                            Text(item.source.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
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

                ProgressView(value: engine.progress)
                    .progressViewStyle(.linear)
                    .tint(engine.state == .generating ? .orange : .accentColor)
                    .padding(.horizontal, 14)

            } else {
                VStack(spacing: 4) {
                    Text(queue.isEmpty ? "Select text and press ⌘⇧R" : "Tap play to start")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    if engine.modelStatus == .ready {
                        Text("Qwen3-TTS ready")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            }

            // Playback controls
            HStack(spacing: 16) {
                Button {
                    if engine.progress > 0.1, let item = queue.currentItem {
                        queue.play(item: item)
                    }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .disabled(queue.currentItem == nil || engine.state == .generating)

                Button {
                    if engine.state == .idle && !queue.isEmpty {
                        queue.playNext()
                    } else {
                        engine.togglePlayPause()
                    }
                } label: {
                    Image(systemName: playButtonIcon)
                        .font(.system(size: 32))
                        .foregroundColor(playButtonColor)
                }
                .buttonStyle(.plain)
                .disabled((queue.isEmpty && engine.state == .idle) || engine.modelStatus != .ready)

                Button {
                    engine.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .disabled(queue.currentIndex == nil || engine.state == .generating)

                Spacer()

                // Speed control
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { spd in
                        Button(speedLabel(spd)) {
                            engine.updateSpeed(spd)
                        }
                    }
                } label: {
                    Text(speedLabel(engine.speed))
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

    private var playButtonIcon: String {
        switch engine.state {
        case .playing: return "pause.circle.fill"
        case .generating: return "hourglass.circle.fill"
        default: return "play.circle.fill"
        }
    }

    private var playButtonColor: Color {
        if engine.state == .generating { return .orange }
        if queue.isEmpty && engine.state == .idle { return .secondary }
        return .accentColor
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
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
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
        if rate == 1.0 { return "1x" }
        if rate == floor(rate) { return "\(Int(rate))x" }
        return String(format: "%.2gx", rate)
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

            // Model info
            VStack(alignment: .leading, spacing: 4) {
                Text("Voice Model")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                HStack {
                    Image(systemName: "brain")
                        .font(.system(size: 12))
                    Text("Qwen3-TTS 0.6B (8-bit)")
                        .font(.system(size: 12))
                }
                Text("Multilingual neural TTS via MLX")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Playback Speed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                HStack {
                    Text("0.5x")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Slider(value: Binding(
                        get: { engine.speed },
                        set: { engine.updateSpeed($0) }
                    ), in: 0.5...2.0, step: 0.25)
                    Text("2x")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Text("Global hotkey: ⌘⇧R\nRequires Accessibility permission.\n\nPowered by mlx-audio-swift\n100% on-device · Apple Silicon")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 260)
    }
}
