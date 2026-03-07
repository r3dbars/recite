import AppKit
import ApplicationServices
import Combine

/// Grabs selected text from the frontmost application.
/// Strategy:
///   1. Try Accessibility API (AXSelectedText) — fast, no clipboard side-effects
///   2. Fall back to simulated ⌘C — works in any app that supports copy
@MainActor
class TextGrabber: ObservableObject {
    static let shared = TextGrabber()

    // MARK: - Public

    func getSelectedText() async -> String? {
        // Try Accessibility first
        if let text = getTextViaAccessibility(), !text.isEmpty {
            return text
        }
        // Fall back to clipboard simulation
        return await getTextViaClipboard()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Accessibility

    private func getTextViaAccessibility() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString,
                                             &focusedElement) == .success,
              let element = focusedElement else { return nil }

        var selectedText: AnyObject?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement,
                                             kAXSelectedTextAttribute as CFString,
                                             &selectedText) == .success else { return nil }

        return selectedText as? String
    }

    // MARK: - Clipboard Simulation

    private func getTextViaClipboard() async -> String? {
        let pasteboard = NSPasteboard.general

        // Save current clipboard state
        let savedChangeCount = pasteboard.changeCount
        let savedStrings = pasteboard.pasteboardItems?.compactMap {
            $0.string(forType: .string)
        }

        // Clear and trigger ⌘C in frontmost app
        pasteboard.clearContents()

        let src = CGEventSource(stateID: .hidSystemState)
        // Key code 8 = C
        let cDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        cDown?.flags = .maskCommand
        cDown?.post(tap: .cghidEventTap)

        let cUp = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        cUp?.flags = .maskCommand
        cUp?.post(tap: .cghidEventTap)

        // Poll for clipboard update (max 300ms)
        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 30_000_000) // 30ms
            if pasteboard.changeCount != savedChangeCount {
                break
            }
        }

        let grabbed = pasteboard.string(forType: .string)

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
