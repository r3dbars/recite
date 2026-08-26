import SwiftUI
import AppKit


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
