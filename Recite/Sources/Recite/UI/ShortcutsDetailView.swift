import SwiftUI
import AppKit

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
