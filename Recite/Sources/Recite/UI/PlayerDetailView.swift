import SwiftUI
import AppKit

struct PlayerDetailView: View {
    @StateObject private var engine = SpeechEngine.shared
    @StateObject private var queue  = ReadingQueue.shared

    var body: some View {
        Group {
            if queue.currentItem != nil {
                nowPlayingBox
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Home")
        .navigationSubtitle("Read any text aloud, on-device.")
    }

    // MARK: - Now Playing Box (fills remaining window space)

    private var nowPlayingBox: some View {
        VStack(spacing: 10) {
            if let item = queue.currentItem {
                HStack(alignment: .top, spacing: 10) {
                    Label(item.source, systemImage: engine.state == .generating ? "hourglass" : "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())

                    Spacer()

                    if engine.state == .generating {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.mini)
                            Text("Generating…")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                ScrollView {
                    Text(item.text)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.bottom, 4)
                }
                .frame(maxHeight: .infinity)
            }

            ProgressView(value: engine.progress)
                .tint(engine.state == .generating ? .orange : .accentColor)

            HStack(spacing: 24) {
                Button {
                    engine.stop()
                    queue.clear()
                } label: {
                    Text("Clear")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)

                Spacer()

                Button { engine.skipBackward() } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(engine.state != .playing && engine.state != .paused)

                if engine.state == .generating {
                    Button { engine.stop() } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { engine.togglePlayPause() } label: {
                        Image(systemName: playIcon)
                            .font(.system(size: 34))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(engine.modelStatus != .ready)
                }

                Button { engine.skipForward() } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(engine.state != .playing && engine.state != .paused)

                Spacer()

                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { spd in
                        Button(speedLabel(spd)) { engine.updateSpeed(spd) }
                    }
                } label: {
                    Text(speedLabel(engine.speed))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Action cards
                sectionHeader("Read Text", subtitle: "Select text and read it aloud.")
                    .padding(.top, 24)

                VStack(spacing: 1) {
                    ActionCard(
                        icon: "text.cursor",
                        iconColor: .accentColor,
                        title: "Read Selection",
                        subtitle: "Read the selected text from your last app."
                    ) {
                        (NSApp.delegate as? AppDelegate)?.readSelection()
                    }

                    ActionCard(
                        icon: "doc.on.clipboard",
                        iconColor: .accentColor,
                        title: "Paste & Read",
                        subtitle: "Read text from your clipboard."
                    ) {
                        guard let text = NSPasteboard.general.string(forType: .string),
                              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        let item = queue.add(text: text, source: "Clipboard")
                        if engine.state == .idle { queue.play(item: item) }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
                .padding(.top, 10)

                // Ready Check
                sectionHeader("Ready Check", subtitle: "Green is ready. Orange needs attention.")
                    .padding(.top, 28)

                VStack(spacing: 0) {
                    ReadyCheckRow(
                        icon: "brain",
                        label: "TTS model",
                        detail: engine.selectedSpeechModel.name,
                        status: modelReadyStatus
                    )
                    Divider().padding(.leading, 44)
                    ReadyCheckRow(
                        icon: "hand.raised",
                        label: "Accessibility",
                        detail: "Required for ⌃⌥R hotkey",
                        status: AXIsProcessTrusted() ? .ready("Ready") : .warning("Permission needed")
                    )
                    Divider().padding(.leading, 44)
                    ReadyCheckRow(
                        icon: "terminal",
                        label: "espeak-ng",
                        detail: espeakReadyDetail,
                        status: espeakReadyStatus
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
                .padding(.top, 10)

                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private var modelReadyStatus: ReadyCheckRow.Status {
        switch engine.modelStatus {
        case .ready:                return .ready("Ready")
        case .downloading(let p):   return .warning("Downloading \(Int(p * 100))%")
        case .loading:              return .warning("Loading…")
        case .error(let msg):       return .error(String(msg.prefix(30)))
        case .notLoaded:            return .warning("Not loaded")
        }
    }

    private var espeakReadyDetail: String {
        if EspeakTextProcessor.isUsingBundledRuntime {
            return "Text helper bundled with Recite"
        }
        return "Text helper for source builds"
    }

    private var espeakReadyStatus: ReadyCheckRow.Status {
        if EspeakTextProcessor.isUsingBundledRuntime {
            return .ready("Bundled")
        }
        if EspeakTextProcessor.installedExecutablePath != nil {
            return .ready("Installed")
        }
        return .warning("Missing for source build")
    }

    private var playIcon: String {
        switch engine.state {
        case .playing:    return "pause.circle.fill"
        case .generating: return "hourglass.circle.fill"
        default:          return "play.circle.fill"
        }
    }

    private func speedLabel(_ rate: Double) -> String {
        if rate == 1.0 { return "1×" }
        if rate == floor(rate) { return "\(Int(rate))×" }
        return String(format: "%.2g×", rate)
    }
}

// MARK: - Action Card

struct ActionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var disabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 32, height: 32)
                    .background(iconColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(disabled ? .secondary : .primary)
                        if disabled {
                            Text("SOON")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !disabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isHovered && !disabled ? Color(NSColor.controlBackgroundColor).opacity(0.7) : Color(NSColor.controlBackgroundColor))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Ready Check Row

struct ReadyCheckRow: View {
    enum Status {
        case ready(String)
        case warning(String)
        case error(String)
    }

    let icon: String
    let label: String
    let detail: String
    let status: Status

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(statusColor)
                .frame(width: 32, height: 32)
                .background(statusColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var statusColor: Color {
        switch status {
        case .ready:   return .green
        case .warning: return .orange
        case .error:   return .red
        }
    }

    private var statusText: String {
        switch status {
        case .ready(let s), .warning(let s), .error(let s): return s
        }
    }
}
