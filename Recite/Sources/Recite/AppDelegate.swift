import AppKit
import SwiftUI
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private let engine = SpeechEngine.shared
    private let queue = ReadingQueue.shared
    private let grabber = TextGrabber.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        setupGlobalHotKey()
        subscribeToEngine()

        // Load Qwen3-TTS model in background
        Task {
            await engine.loadModel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            engine.stop()
        }
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Recite")
        button.image?.isTemplate = true
        button.action = #selector(handleStatusItemClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func subscribeToEngine() {
        engine.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateStatusItemIcon(state)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItemIcon(_ state: SpeechEngine.State) {
        let iconName: String
        switch state {
        case .playing:    iconName = "play.circle.fill"
        case .paused:     iconName = "pause.circle.fill"
        case .generating: iconName = "ellipsis.circle.fill"
        case .loading:    iconName = "arrow.down.circle"
        case .idle:       iconName = "headphones"
        }
        statusItem.button?.image = NSImage(systemSymbolName: iconName,
                                           accessibilityDescription: "Recite")
        statusItem.button?.image?.isTemplate = (state == .idle)
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 420)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuBarView())
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Read Selection  ⌘⇧R",
                                action: #selector(readSelection), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Read Clipboard",
                                action: #selector(readClipboard), keyEquivalent: ""))
        menu.addItem(.separator())

        // Model status
        let statusTitle: String
        switch engine.modelStatus {
        case .ready: statusTitle = "Qwen3-TTS Ready"
        case .loading: statusTitle = "Loading Model…"
        case .downloading: statusTitle = "Downloading Model…"
        case .notLoaded: statusTitle = "Model Not Loaded"
        case .error: statusTitle = "Model Error"
        }
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Recite",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        self.statusItem.menu = menu
        self.statusItem.button?.performClick(nil)
        self.statusItem.menu = nil
    }

    // MARK: - Global Hot Key (⌘⇧R)

    private func setupGlobalHotKey() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // ⌘⇧R — keyCode 15 = R
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 15 {
                self?.readSelection()
            }
        }
    }

    // MARK: - Actions

    @objc func readSelection() {
        Task {
            if let text = await grabber.getSelectedText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run {
                    queue.add(text: text, source: "Selection")
                    if engine.state == .idle {
                        engine.playNext()
                    }
                }
            }
        }
    }

    @objc func readClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task { @MainActor in
            queue.add(text: text, source: "Clipboard")
            if engine.state == .idle {
                engine.playNext()
            }
        }
    }
}
