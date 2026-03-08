import AppKit
import SwiftUI
import Combine
import os.log

private let log = Logger(subsystem: "com.r3dbars.recite", category: "AppDelegate")

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
        requestAccessibilityAndSetupHotKey()
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
                                action: #selector(readSelectionFromMenu), keyEquivalent: ""))
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

    // MARK: - Accessibility & Global Hot Key (⌘⇧R)

    private func requestAccessibilityAndSetupHotKey() {
        // Prompt the user for accessibility permission if not already granted
        grabber.requestAccessibilityPermission()

        if grabber.hasAccessibilityPermission {
            log.info("Accessibility already granted, registering hotkey")
            setupGlobalHotKey()
        } else {
            log.info("Waiting for accessibility permission...")
            // Poll until the user grants permission (checked every 2s)
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                Task { @MainActor in
                    guard let self else { timer.invalidate(); return }
                    if self.grabber.hasAccessibilityPermission {
                        timer.invalidate()
                        log.info("Accessibility granted, registering hotkey")
                        self.setupGlobalHotKey()
                    }
                }
            }
        }
    }

    private func setupGlobalHotKey() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // ⌘⇧R — keyCode 15 = R
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 15 {
                log.info("⌘⇧R pressed — hotkey triggered")
                // Capture source app PID immediately, before any async dispatch
                let sourcePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                log.info("Source app PID: \(sourcePID ?? 0)")
                Task { @MainActor in
                    self?.readSelection(sourcePID: sourcePID)
                }
            }
        }
        log.info("Global hotkey registered (eventMonitor=\(self.eventMonitor != nil))")
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Actions

    func readSelection(sourcePID: pid_t? = nil) {
        log.info("readSelection(sourcePID=\(sourcePID ?? 0)), engine.state=\(String(describing: self.engine.state)), modelStatus=\(String(describing: self.engine.modelStatus))")

        // Use provided PID, or capture now as fallback
        let pid = sourcePID ?? grabber.captureSourceApp()

        Task {
            log.info("Grabbing selected text from pid \(pid ?? 0)...")
            let text = await grabber.getSelectedText(fromPID: pid)

            await MainActor.run {
                showPopover()
            }

            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                log.info("Got text (\(text.count) chars), adding to queue and speaking")
                await MainActor.run {
                    queue.add(text: text, source: "Selection")
                    if engine.state == .idle {
                        engine.playNext()
                    }
                }
            } else {
                log.warning("No text found from selection (text=\(text ?? "nil"))")
            }
        }
    }

    @objc func readSelectionFromMenu() {
        readSelection()
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
