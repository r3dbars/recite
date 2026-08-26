import SwiftUI
import AppKit

struct SettingsDetailView: View {
    @ObservedObject private var engine = SpeechEngine.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 30, weight: .bold))
                    Text("Voice, speed, and local model")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4)

                SettingsPanel {
                    HStack(alignment: .center, spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.16))
                            Image(systemName: "speedometer")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                        .frame(width: 46, height: 46)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Playback Speed")
                                    .font(.system(size: 16, weight: .semibold))
                                Spacer()
                                Text(speedLabel(engine.speed))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.accentColor)
                            }

                            HStack(spacing: 10) {
                                Text("0.5×")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                Slider(
                                    value: Binding(get: { engine.speed }, set: { engine.updateSpeed($0) }),
                                    in: 0.5...2.0, step: 0.25
                                )
                                Text("2×")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                SettingsPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Text-to-Speech Model", systemImage: engine.selectedSpeechModel.systemImage)
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                            modelStatusView
                        }

                        Picker(
                            "Model",
                            selection: Binding(
                                get: { engine.selectedSpeechModelID },
                                set: { engine.selectedSpeechModelID = $0 }
                            )
                        ) {
                            ForEach(SpeechEngine.speechModels) { model in
                                Text(model.pickerTitle).tag(model.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 340, alignment: .leading)

                        HStack(spacing: 8) {
                            Text(engine.selectedSpeechModel.detail)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text(engine.selectedSpeechModel.modelID)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("\(engine.selectedSpeechModel.name) Voices", systemImage: "mic")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        if !engine.selectedSpeechModel.supportsKokoroVoices {
                            StatusPill(
                                title: "Samples",
                                systemImage: "play.circle.fill",
                                color: .blue
                            )
                        }
                        if engine.previewingVoice != nil {
                            Button {
                                engine.stopVoicePreview()
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .controlSize(.small)
                        }
                    }

                    VStack(spacing: 8) {
                        ForEach(SpeechEngine.voicePresets(for: engine.selectedSpeechModel.voiceFamily)) { preset in
                            VoiceChoiceRow(
                                preset: preset,
                                isSelected: engine.selectedVoice == preset.voiceID,
                                isPreviewing: engine.previewingVoice == preset.id,
                                canPreview: engine.canPreview(preset),
                                showsPreview: preset.modelFamily.supportsVoiceSamples,
                                unavailableReason: preset.modelFamily.sampleUnavailableReason,
                                select: { engine.selectVoice(preset) },
                                preview: { engine.previewVoice(preset) }
                            )
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .navigationTitle("")
    }

    @ViewBuilder
    private var modelStatusView: some View {
        switch engine.modelStatus {
        case .ready:
            StatusPill(title: "Ready", systemImage: "checkmark.circle.fill", color: .green)
        case .error:
            Button("Retry") { Task { await engine.loadModel() } }
                .controlSize(.small)
        case .downloading(let p):
            StatusPill(title: "Downloading \(Int(p * 100))%", systemImage: "arrow.down.circle.fill", color: .blue)
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        case .notLoaded:
            StatusPill(title: "Not Loaded", systemImage: "exclamationmark.circle.fill", color: .orange)
        }
    }

    private func speedLabel(_ rate: Double) -> String {
        if rate == 1.0 { return "1×" }
        if rate == floor(rate) { return "\(Int(rate))×" }
        return String(format: "%.2g×", rate)
    }
}

private struct SettingsPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
            )
    }
}

private struct VoiceChoiceRow: View {
    let preset: VoicePreset
    let isSelected: Bool
    let isPreviewing: Bool
    let canPreview: Bool
    let showsPreview: Bool
    let unavailableReason: String?
    let select: () -> Void
    let preview: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: select) {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(isSelected ? .accentColor : Color(NSColor.quaternaryLabelColor))
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(preset.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(voiceDescription)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("\"\(preset.sampleText)\"")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.9))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsPreview {
                Button(action: preview) {
                    Label(isPreviewing ? "Stop" : "Sample",
                          systemImage: isPreviewing ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 84)
                }
                .controlSize(.small)
                .disabled(!canPreview && !isPreviewing)
            } else if let unavailableReason {
                Text(unavailableReason)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 112, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color(NSColor.separatorColor), lineWidth: 0.7)
        )
    }

    private var rowBackground: Color {
        if isSelected { return Color.accentColor.opacity(0.1) }
        return Color(NSColor.controlBackgroundColor)
    }

    private var voiceDescription: String {
        preset.detail
    }
}

private struct StatusPill: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Settings View (used by Settings scene in ReciteApp)
typealias SettingsView = SettingsDetailView
