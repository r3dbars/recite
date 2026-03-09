import AppKit
import ApplicationServices
import Combine
import os.log

private let log = Logger(subsystem: "com.r3dbars.recite", category: "TextGrabber")

/// Grabs selected text from the frontmost application.
/// Strategy:
///   1. Try Accessibility API (AXSelectedText) — fast, no clipboard side-effects
///   2. Fall back to simulated ⌘C — works in any app that supports copy
@MainActor
class TextGrabber: ObservableObject {
    static let shared = TextGrabber()

    // MARK: - Public

    /// Call this synchronously from the hotkey handler to capture the source app
    /// before any async work or focus changes.
    func captureSourceApp() -> pid_t? {
        let app = NSWorkspace.shared.frontmostApplication
        log.info("Captured source app: \(app?.localizedName ?? "none") (pid \(app?.processIdentifier ?? 0))")
        return app?.processIdentifier
    }

    func getSelectedText(fromPID pid: pid_t?) async -> String? {
        log.info("getSelectedText(fromPID: \(pid ?? 0)) called")
        log.info("AXIsProcessTrusted: \(AXIsProcessTrusted())")

        // Try Accessibility first
        if let pid, let text = getTextViaAccessibility(pid: pid), !text.isEmpty {
            log.info("Got text via accessibility (\(text.count) chars)")
            return text
        }
        log.info("Accessibility returned nothing, falling back to clipboard simulation")

        // Fall back to clipboard simulation
        let clipText = await getTextViaClipboard()
        if let clipText, !clipText.isEmpty {
            log.info("Got text via clipboard (\(clipText.count) chars)")
            return clipText
        }

        // Last resort: read whatever is already on the clipboard
        // (user may have manually copied before pressing hotkey)
        let existing = readClipboardText()
        if let existing, !existing.isEmpty {
            log.info("Using existing clipboard content (\(existing.count) chars)")
            return existing
        }

        log.warning("No text found from any method")
        return nil
    }

    /// Read plain text from the current clipboard contents
    private func readClipboardText() -> String? {
        let pasteboard = NSPasteboard.general
        return pasteboard.string(forType: .string)
            ?? pasteboard.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        log.info("requestAccessibilityPermission: trusted=\(trusted)")
    }

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Accessibility

    private func getTextViaAccessibility(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else {
            log.warning("AX not trusted, skipping accessibility grab")
            return nil
        }

        log.info("Querying AX for pid \(pid)")
        let axApp = AXUIElementCreateApplication(pid)

        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString,
                                                         &focusedElement)
        guard focusResult == .success, let element = focusedElement else {
            log.warning("Failed to get focused element: AXError code \(focusResult.rawValue)")
            return nil
        }

        // Log the role of the focused element
        var role: AnyObject?
        AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &role)
        log.info("Focused element role: \(role as? String ?? "unknown")")

        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(element as! AXUIElement,
                                                        kAXSelectedTextAttribute as CFString,
                                                        &selectedText)
        guard textResult == .success else {
            log.warning("Failed to get selected text: AXError code \(textResult.rawValue)")
            return nil
        }

        let text = selectedText as? String
        log.info("AX selected text: \(text ?? "nil") (\(text?.count ?? 0) chars)")
        return text
    }

    // MARK: - Clipboard Simulation

    private func getTextViaClipboard() async -> String? {
        let pasteboard = NSPasteboard.general
        log.info("Starting clipboard simulation")

        // Save current clipboard content for restoration later
        let savedStrings = pasteboard.pasteboardItems?.compactMap {
            $0.string(forType: .string)
        }
        log.info("Saved clipboard items=\(savedStrings?.count ?? 0)")

        // Clear clipboard FIRST, then save the changeCount.
        // clearContents() itself increments changeCount, so we must save AFTER
        // to avoid detecting our own clear as a "change" from the ⌘C.
        pasteboard.clearContents()
        let savedChangeCount = pasteboard.changeCount
        log.info("Cleared clipboard, changeCount=\(savedChangeCount)")

        let src = CGEventSource(stateID: .hidSystemState)
        log.info("CGEventSource created: \(src != nil)")

        // Key code 8 = C
        let cDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        cDown?.flags = .maskCommand
        cDown?.post(tap: .cghidEventTap)
        log.info("Posted ⌘C keyDown")

        let cUp = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        cUp?.flags = .maskCommand
        cUp?.post(tap: .cghidEventTap)
        log.info("Posted ⌘C keyUp")

        // Give the source app a moment to process the ⌘C
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Poll for clipboard update (max 1s — Chrome can be slow)
        let deadline = Date().addingTimeInterval(1.0)
        var pollCount = 0
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            pollCount += 1
            if pasteboard.changeCount != savedChangeCount {
                log.info("Clipboard changed after \(pollCount) polls")
                break
            }
        }

        // Check all common text types — Chrome often copies as rich text without plain text
        let types = pasteboard.types ?? []
        let typeNames = types.map(\.rawValue).joined(separator: ", ")
        log.warning("Clipboard types: \(typeNames, privacy: .public)")

        // Try multiple pasteboard types in order of preference
        let textTypes: [NSPasteboard.PasteboardType] = [
            .string,
            NSPasteboard.PasteboardType("public.utf8-plain-text"),
            NSPasteboard.PasteboardType("public.utf16-plain-text"),
            .rtf,
        ]

        var grabbed: String? = nil
        for type in textTypes {
            if let text = pasteboard.string(forType: type), !text.isEmpty {
                log.info("Found text via type '\(type.rawValue)' (\(text.count) chars)")
                grabbed = text
                break
            }
        }

        // Last resort: try reading from pasteboard items directly
        if grabbed == nil {
            if let items = pasteboard.pasteboardItems {
                for item in items {
                    let itemTypeNames = item.types.map(\.rawValue).joined(separator: ", ")
                    log.warning("Pasteboard item types: \(itemTypeNames, privacy: .public)")
                    for type in item.types {
                        if let text = item.string(forType: type), !text.isEmpty {
                            // Skip HTML markup, prefer plain text
                            if type.rawValue.contains("html") || type.rawValue.contains("rtf") {
                                // Strip HTML tags as last resort
                                let stripped = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !stripped.isEmpty {
                                    log.info("Stripped HTML/RTF from type '\(type.rawValue)' (\(stripped.count) chars)")
                                    grabbed = stripped
                                    break
                                }
                            } else {
                                log.info("Found text via item type '\(type.rawValue)' (\(text.count) chars)")
                                grabbed = text
                                break
                            }
                        }
                    }
                    if grabbed != nil { break }
                }
            }
        }

        let grabSummary = grabbed != nil ? "\(grabbed!.count) chars: \(String(grabbed!.prefix(80)))" : "nil"
        log.warning("Grabbed from clipboard: \(grabSummary, privacy: .public) (changeCount=\(pasteboard.changeCount), polls=\(pollCount))")

        // Restore original clipboard
        pasteboard.clearContents()
        if let strings = savedStrings, !strings.isEmpty {
            for s in strings {
                pasteboard.setString(s, forType: .string)
            }
        }

        return grabbed
    }
}
