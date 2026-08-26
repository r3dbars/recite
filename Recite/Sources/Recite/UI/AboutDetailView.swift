import SwiftUI
import AppKit

struct AboutDetailView: View {
    private var espeakRequirementText: String {
        if EspeakTextProcessor.isUsingBundledRuntime {
            return "espeak-ng bundled with Recite"
        }
        if EspeakTextProcessor.installedExecutablePath != nil {
            return "espeak-ng installed locally"
        }
        return "espeak-ng needed for source builds"
    }

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
                        Text("Recite reads any text aloud using local MLX text-to-speech models. It defaults to Kokoro 82M. No cloud voice API. No subscriptions. Select text in any app, press ⌃⌥R, and Recite speaks it back to you.")
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
                                ("brain", "Kokoro, Qwen3, Chatterbox"),
                                ("cpu", "Apple MLX"),
                                ("lock.shield", "100% on-device"),
                            ])
                            AboutBadgeRow(items: [
                                ("waveform", "24 kHz audio"),
                                ("speedometer", "0.5× – 2× speed"),
                                ("mic", "Kokoro voice presets"),
                            ])
                        }
                    }

                    AboutSection(title: "Requirements") {
                        VStack(alignment: .leading, spacing: 6) {
                            AboutRequirement(met: true, text: "Apple Silicon Mac (M1 or later)")
                            AboutRequirement(met: true, text: "macOS 14 Sonoma or later")
                            AboutRequirement(
                                met: EspeakTextProcessor.installedExecutablePath != nil,
                                text: espeakRequirementText
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
