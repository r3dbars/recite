import SwiftUI
import AppKit

// MARK: - Menu Bar Popover

struct MenuBarPopoverView: View {
    @StateObject private var engine = SpeechEngine.shared
    @StateObject private var queue  = ReadingQueue.shared

    var body: some View {
        VStack(spacing: 0) {
            popoverHeader
            popoverDivider

            if queue.currentItem != nil || engine.state == .generating {
                popoverNowPlaying
                popoverDivider
            }

            popoverPrimaryActions
            popoverDivider
            popoverSecondaryActions
        }
        .frame(width: 300)
        .background(Color(red: 0.12, green: 0.12, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Header

    private var popoverHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 17))
                .foregroundColor(.accentColor)
            Text("Recite")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            modelStatusPill
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var modelStatusPill: some View {
        switch engine.modelStatus {
        case .ready:
            statusTag("Ready", color: .green)
        case .downloading(let p):
            statusTag("↓ \(Int(p * 100))%", color: .blue)
        case .loading:
            statusTag("Loading…", color: .orange)
        case .error:
            statusTag("Error", color: .red)
        case .notLoaded:
            statusTag("Not loaded", color: Color(white: 0.4))
        }
    }

    private func statusTag(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(white: 1.0, opacity: 0.5))
        }
    }

    // MARK: Now Playing

    @ViewBuilder
    private var popoverNowPlaying: some View {
        if let item = queue.currentItem {
            PopoverRow(
                icon: engine.state == .generating ? "hourglass" : "waveform",
                iconColor: engine.state == .generating ? .orange : .accentColor,
                title: engine.state == .generating ? "Generating audio…" : "Now Playing",
                subtitle: item.preview,
                shortcut: nil,
                action: nil
            )
        }
    }

    // MARK: Primary Actions

    private var popoverPrimaryActions: some View {
        VStack(spacing: 0) {
            PopoverRow(
                icon: "text.cursor",
                iconColor: popoverIconGray,
                title: "Read Selection",
                subtitle: nil,
                shortcut: "⌃⌥R"
            ) {
                (NSApp.delegate as? AppDelegate)?.readSelection()
            }

            PopoverRow(
                icon: "doc.on.clipboard",
                iconColor: popoverIconGray,
                title: "Add Clipboard",
                subtitle: nil,
                shortcut: nil
            ) {
                guard let text = NSPasteboard.general.string(forType: .string),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let item = queue.add(text: text, source: "Clipboard")
                if engine.state == .idle { queue.play(item: item) }
            }

            if engine.state == .playing || engine.state == .paused || engine.state == .generating {
                PopoverRow(
                    icon: engine.state == .paused ? "play.fill" : "pause.fill",
                    iconColor: popoverIconGray,
                    title: engine.state == .paused ? "Resume" : (engine.state == .generating ? "Cancel" : "Pause"),
                    subtitle: nil,
                    shortcut: nil
                ) {
                    if engine.state == .generating { engine.stop() }
                    else { engine.togglePlayPause() }
                }
            }
        }
    }

    // MARK: Secondary Actions

    private var popoverSecondaryActions: some View {
        VStack(spacing: 0) {
            PopoverRow(
                icon: "macwindow",
                iconColor: popoverIconGray,
                title: "Open Recite",
                subtitle: nil,
                shortcut: nil
            ) {
                (NSApp.delegate as? AppDelegate)?.showMainWindow()
            }

            PopoverRow(
                icon: "power",
                iconColor: popoverIconGray,
                title: "Quit Recite",
                subtitle: nil,
                shortcut: "⌘Q"
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var popoverDivider: some View {
        Rectangle()
            .fill(Color(white: 1.0, opacity: 0.07))
            .frame(height: 0.5)
    }

    private var popoverIconGray: Color { Color(white: 0.55) }
}

// MARK: - Popover Row

struct PopoverRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let shortcut: String?
    let action: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 18, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 1.0, opacity: 0.42))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 1.0, opacity: 0.3))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, subtitle != nil ? 9 : 10)
            .background(isHovered && action != nil ? Color(white: 1.0, opacity: 0.07) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .disabled(action == nil)
    }
}

// MARK: - Main Window

struct ReciteWindowView: View {
    @State private var selectedPanel: RecitePanel = .player

    var body: some View {
        NavigationSplitView {
            ReciteSidebar(selection: $selectedPanel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            switch selectedPanel {
            case .player:    PlayerDetailView()
            case .queue:     QueueDetailView()
            case .history:   HistoryDetailView()
            case .shortcuts: ShortcutsDetailView()
            case .settings:  SettingsDetailView()
            case .about:     AboutDetailView()
            }
        }
        .frame(minWidth: 700, minHeight: 480)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Sidebar

enum RecitePanel: String, Hashable, CaseIterable {
    case player    = "Home"
    case queue     = "Queue"
    case history   = "History"
    case shortcuts = "Shortcuts"
    case settings  = "Settings"
    case about     = "About"

    var icon: String {
        switch self {
        case .player:    return "house"
        case .queue:     return "list.bullet"
        case .history:   return "clock.arrow.circlepath"
        case .shortcuts: return "keyboard"
        case .settings:  return "gearshape"
        case .about:     return "info.circle"
        }
    }
}

struct ReciteSidebar: View {
    @Binding var selection: RecitePanel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Playback") {
                    ForEach([RecitePanel.player, .queue, .history], id: \.self) { panel in
                        Label(panel.rawValue, systemImage: panel.icon).tag(panel)
                    }
                }
                Section("Preferences") {
                    ForEach([RecitePanel.shortcuts, .settings, .about], id: \.self) { panel in
                        Label(panel.rawValue, systemImage: panel.icon).tag(panel)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Player Detail

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

                Button {
                    if let item = queue.currentItem { queue.play(item: item) }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(engine.state == .generating)

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

                Button { engine.playNext() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

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
                        label: "Kokoro TTS model",
                        detail: "On-device neural text-to-speech",
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
                        detail: "Text preprocessing — brew install espeak-ng",
                        status: EspeakTextProcessor.installedExecutablePath != nil
                            ? .ready("Ready") : .warning("Not installed")
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

// MARK: - History Detail

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

// MARK: - Shortcuts Detail

struct ShortcutsDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                shortcutSection("Reading", subtitle: "System-wide reading shortcut.") {
                    ShortcutRow(keys: ["⌃", "⌥", "R"], label: "Read Selection", detail: "Read selected text in the frontmost app system-wide.")
                }

                shortcutSection("Playback", subtitle: "Control audio while Recite is focused.") {
                    ShortcutRow(keys: ["Space"], label: "Play / Pause", detail: "Toggle playback.")
                }

                shortcutSection("How ⌃⌥R Works", subtitle: nil) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            Text("1")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                            Text("Select text in any app — Mail, Safari, Notes, Slack, Terminal, anywhere.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Text("2")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                            Text("Press ⌃⌥R. Recite captures the selection without stealing focus from your app.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        HStack(alignment: .top, spacing: 10) {
                            Text("3")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                            Text("Audio generates on-device and begins playing. The menu bar icon changes to show playback state.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor))
                }

                shortcutSection("Requirement", subtitle: nil) {
                    HStack(spacing: 14) {
                        Image(systemName: AXIsProcessTrusted() ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AXIsProcessTrusted() ? .green : .orange)
                            .frame(width: 32, height: 32)
                            .background((AXIsProcessTrusted() ? Color.green : Color.orange).opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility Permission")
                                .font(.system(size: 13, weight: .medium))
                            Text(AXIsProcessTrusted()
                                 ? "Granted — global hotkey is active."
                                 : "Not granted — open System Settings › Privacy & Security › Accessibility and add Recite.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor))
                }

                Spacer().frame(height: 32)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .navigationTitle("Shortcuts")
        .navigationSubtitle("Keyboard triggers for Recite.")
    }

    private func shortcutSection<Content: View>(_ title: String, subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if let sub = subtitle {
                    Text(sub).font(.system(size: 12)).foregroundColor(.secondary)
                }
            }
            content()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
        }
        .padding(.bottom, 28)
    }
}

struct ShortcutRow: View {
    let keys: [String]
    let label: String
    let detail: String
    var comingSoon: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(comingSoon ? .secondary : .primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(NSColor.windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
                        .opacity(comingSoon ? 0.5 : 1)
                }
            }
            .frame(minWidth: 90, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(comingSoon ? .secondary : .primary)
                    if comingSoon {
                        Text("SOON")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(detail).font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - About Detail

struct AboutDetailView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // App identity header
                VStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.accentColor)
                    Text("Recite")
                        .font(.system(size: 26, weight: .bold))
                    Text("On-device text-to-speech for your Mac")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)

                Divider()

                // What it does
                VStack(alignment: .leading, spacing: 20) {
                    AboutSection(title: "What Recite Does") {
                        Text("Recite reads any text aloud using Kokoro 82M, a fast neural text-to-speech model that runs entirely on your Mac — no internet, no cloud, no subscriptions. Select text in any app, press ⌃⌥R, and Recite speaks it back to you.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    AboutSection(title: "How to Use") {
                        VStack(alignment: .leading, spacing: 10) {
                            AboutStep(number: "1", text: "Select text in any app — Mail, Safari, Notes, Slack, anywhere.")
                            AboutStep(number: "2", text: "Press ⌃⌥R. Recite grabs the selection and queues it up.")
                            AboutStep(number: "3", text: "Audio generates on-device and plays immediately. Pause, skip, or clear from the Home tab or the menu bar icon.")
                        }
                    }

                    AboutSection(title: "Under the Hood") {
                        VStack(alignment: .leading, spacing: 8) {
                            AboutBadgeRow(items: [
                                ("brain", "Kokoro 82M (bf16)"),
                                ("cpu", "Apple MLX"),
                                ("lock.shield", "100% on-device"),
                            ])
                            AboutBadgeRow(items: [
                                ("waveform", "24 kHz audio"),
                                ("speedometer", "0.5× – 2× speed"),
                                ("mic", "13 voice presets"),
                            ])
                        }
                    }

                    AboutSection(title: "Requirements") {
                        VStack(alignment: .leading, spacing: 6) {
                            AboutRequirement(met: true, text: "Apple Silicon Mac (M1 or later)")
                            AboutRequirement(met: true, text: "macOS 14 Sonoma or later")
                            AboutRequirement(
                                met: EspeakTextProcessor.installedExecutablePath != nil,
                                text: "espeak-ng  —  brew install espeak-ng"
                            )
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)

                Divider()

                // Footer
                VStack(spacing: 4) {
                    Text("Recite  ·  MIT License  ·  Built with mlx-audio-swift")
                        .font(.system(size: 11))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
                .padding(.vertical, 20)
            }
        }
        .navigationTitle("About")
    }
}

private struct AboutSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content()
        }
    }
}

private struct AboutStep: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AboutBadgeRow: View {
    let items: [(String, String)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                HStack(spacing: 5) {
                    Image(systemName: item.0)
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    Text(item.1)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
            }
            Spacer()
        }
    }
}

private struct AboutRequirement: View {
    let met: Bool
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(met ? .green : .orange)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(met ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Queue Detail

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

// MARK: - Settings Detail

struct SettingsDetailView: View {
    @ObservedObject private var engine = SpeechEngine.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                // Speed
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("0.5×").font(.system(size: 11)).foregroundColor(.secondary)
                            Slider(
                                value: Binding(get: { engine.speed }, set: { engine.updateSpeed($0) }),
                                in: 0.5...2.0, step: 0.25
                            )
                            Text("2×").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        Text("Current speed: \(speedLabel(engine.speed))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Playback Speed", systemImage: "speedometer")
                        .font(.system(size: 13, weight: .semibold))
                }

                // Voice
                GroupBox {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(SpeechEngine.voicePresets) { preset in
                            Button {
                                engine.selectedVoice = preset.kokoroVoice
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: engine.selectedVoice == preset.kokoroVoice
                                          ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(engine.selectedVoice == preset.kokoroVoice
                                                         ? .accentColor : Color(NSColor.quaternaryLabelColor))
                                        .font(.system(size: 14))

                                    Text(preset.name)
                                        .font(.system(size: 13))
                                        .foregroundColor(.primary)

                                    Text(preset.kokoroVoice)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)

                                    Spacer()
                                }
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if preset.id != SpeechEngine.voicePresets.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Voice", systemImage: "mic")
                        .font(.system(size: 13, weight: .semibold))
                }

                // Model info
                GroupBox {
                    HStack {
                        Label("Kokoro 82M (bf16)", systemImage: "brain")
                            .font(.system(size: 13))
                        Spacer()
                        switch engine.modelStatus {
                        case .ready:
                            Label("Ready", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                        case .error:
                            Button("Retry") { Task { await engine.loadModel() } }
                                .font(.system(size: 12))
                        default:
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Model", systemImage: "cpu")
                        .font(.system(size: 13, weight: .semibold))
                }

                Text("100% on-device  ·  Apple Silicon  ·  MIT License")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }
            .padding(24)
        }
        .navigationTitle("Settings")
    }

    private func speedLabel(_ rate: Double) -> String {
        if rate == 1.0 { return "1×" }
        if rate == floor(rate) { return "\(Int(rate))×" }
        return String(format: "%.2g×", rate)
    }
}

// MARK: - Settings View (used by Settings scene in ReciteApp)
typealias SettingsView = SettingsDetailView
