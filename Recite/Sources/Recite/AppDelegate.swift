import AppKit
import SwiftUI
import Combine
import ApplicationServices
import Carbon.HIToolbox
import os.log

private let log = Logger(subsystem: "com.r3dbars.recite", category: "AppDelegate")
private let didShowFirstLaunchWindowKey = "didShowFirstLaunchWindow"
private let reciteHotKeySignature: OSType = 0x52435445

private func sourcePIDFromFrontmostApp() -> pid_t? {
    let frontmost = NSWorkspace.shared.frontmostApplication
    if frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier {
        return nil
    }
    return frontmost?.processIdentifier
}

private func selectedTextFromFocusedElement(pid: pid_t) -> String? {
    guard AXIsProcessTrusted() else { return nil }

    let axApp = AXUIElementCreateApplication(pid)
    var focusedElement: AnyObject?
    let focusResult = AXUIElementCopyAttributeValue(
        axApp,
        kAXFocusedUIElementAttribute as CFString,
        &focusedElement
    )
    guard focusResult == .success, let element = focusedElement else {
        return nil
    }
    guard CFGetTypeID(element) == AXUIElementGetTypeID() else {
        return nil
    }

    var selectedText: AnyObject?
    let selectedResult = AXUIElementCopyAttributeValue(
        element as! AXUIElement,
        kAXSelectedTextAttribute as CFString,
        &selectedText
    )
    guard selectedResult == .success else {
        return nil
    }
    return selectedText as? String
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var carbonHotKeyRef: EventHotKeyRef?
    private var carbonEventHandlerRef: EventHandlerRef?
    private var localEventMonitor: Any?
    private var workspaceObserver: Any?
    private var mainWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    private let engine = SpeechEngine.shared
    private let queue = ReadingQueue.shared
    private let grabber = TextGrabber.shared

    // Last non-Recite frontmost app — used by the Read Selection button
    private var lastExternalApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupStatusItem()
        setupPopover()
        requestAccessibilityAndSetupHotKey()
        subscribeToEngine()
        trackFrontmostApp()
        showMainWindowOnFirstLaunch()

        // Load Kokoro TTS model in background
        Task {
            await engine.loadModel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            engine.stop()
        }
        if let ref = carbonHotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let handler = carbonEventHandlerRef {
            RemoveEventHandler(handler)
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    private func trackFrontmostApp() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                Task { @MainActor in self.lastExternalApp = app }
            }
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = menuBarIdleImage()
        button.action = #selector(handleStatusItemClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func menuBarIdleImage() -> NSImage {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = true
            return img
        }
        let fallback = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Recite")!
        fallback.isTemplate = true
        return fallback
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
        let button = statusItem.button
        switch state {
        case .idle:
            button?.image = menuBarIdleImage()
        case .playing:
            button?.image = sfIcon("play.circle.fill")
        case .paused:
            button?.image = sfIcon("pause.circle.fill")
        case .generating:
            button?.image = sfIcon("ellipsis.circle.fill")
        case .loading:
            button?.image = sfIcon("arrow.down.circle")
        }
    }

    private func sfIcon(_ name: String) -> NSImage {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Recite")!
        img.isTemplate = true
        return img
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 10)
        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView: MenuBarPopoverView())
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            if window.title == "Recite" || window.contentViewController is NSHostingController<ReciteWindowView> {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Recite"
        window.center()
        window.setFrameAutosaveName("ReciteMainWindow")
        window.contentViewController = NSHostingController(rootView: ReciteWindowView())
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func showMainWindowOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: didShowFirstLaunchWindowKey) else {
            return
        }
        UserDefaults.standard.set(true, forKey: didShowFirstLaunchWindowKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let hasVisibleWindow = NSApp.windows.contains { window in
                window.isVisible && !window.isMiniaturized
            }
            if !hasVisibleWindow {
                self?.showMainWindow()
            }
        }
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
        menu.addItem(NSMenuItem(title: "Read Selection  ⌃⌥R",
                                action: #selector(readSelectionFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Read Clipboard",
                                action: #selector(readClipboard), keyEquivalent: ""))
        menu.addItem(.separator())

        // Model status
        let statusTitle: String
        switch engine.modelStatus {
        case .ready: statusTitle = "Kokoro TTS Ready"
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

    // MARK: - Accessibility & Global Hot Key (⌃⌥R)

    private func requestAccessibilityAndSetupHotKey() {
        grabber.requestAccessibilityPermission()
        setupGlobalHotKey()
    }

    private func setupGlobalHotKey() {
        guard carbonHotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard hotKeyID.signature == reciteHotKeySignature, hotKeyID.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }

                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                let sourcePID = sourcePIDFromFrontmostApp()
                let axText = sourcePID.flatMap(selectedTextFromFocusedElement(pid:))

                Task { @MainActor in
                    delegate.hotkeyFired(sourcePID: sourcePID, axText: axText)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &carbonEventHandlerRef
        )
        guard handlerStatus == noErr else {
            log.error("Failed to install Carbon hotkey handler: \(handlerStatus)")
            return
        }

        let hotKeyID = EventHotKeyID(signature: reciteHotKeySignature, id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &carbonHotKeyRef
        )
        guard registerStatus == noErr else {
            log.error("Failed to register Carbon hotkey: \(registerStatus)")
            return
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard event.keyCode == 15, flags == [.control, .option] else {
                return event
            }
            Task { @MainActor in
                self.hotkeyFired(sourcePID: self.lastExternalApp?.processIdentifier, axText: nil)
            }
            return nil
        }
        log.info("Carbon hotkey registered: ⌃⌥R")
    }

    @MainActor
    private func hotkeyFired(sourcePID: pid_t?, axText: String?) {
        let trimmedAXText = axText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedAXText.isEmpty {
            log.info("Hotkey used synchronous AX text (\(trimmedAXText.count) chars)")
            showPopover()
            let item = queue.add(text: trimmedAXText, source: "Selection")
            if engine.state == .idle {
                queue.play(item: item)
            }
            return
        }

        log.info("Hotkey falling back to clipboard simulation for pid \(sourcePID ?? 0)")
        readSelection(sourcePID: sourcePID)
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

        // If called from hotkey, use provided PID.
        // If called from the app window (sourcePID nil), use last known external app.
        let currentPID = NSRunningApplication.current.processIdentifier
        let pid = sourcePID == currentPID ? nil : (sourcePID ?? lastExternalApp?.processIdentifier)

        Task {
            log.info("Grabbing selected text from pid \(pid ?? 0)...")
            // Grab text BEFORE activating Recite — activating steals focus and
            // makes the source app's AX element unreachable.
            let text = await grabber.getSelectedText(fromPID: pid)

            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                log.info("Got text (\(text.count) chars), adding to queue and speaking")
                await MainActor.run {
                    showPopover()
                    let item = queue.add(text: text, source: "Selection")
                    if engine.state == .idle {
                        queue.play(item: item)
                    }
                }
            } else {
                log.warning("No text found from selection")
                await MainActor.run { showPopover() }
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
            let item = queue.add(text: text, source: "Clipboard")
            if engine.state == .idle {
                queue.play(item: item)
            }
        }
    }
}
