import SwiftUI
import AppKit

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
