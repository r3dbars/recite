struct SpeechModelPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let modelID: String
    let badge: String
    let detail: String
    let systemImage: String
    let language: String?
    let voicePrompt: String?
    let supportsKokoroVoices: Bool
    let requiresEspeakTextProcessor: Bool
    let voiceFamily: VoiceModelFamily

    var pickerTitle: String {
        "\(name) (\(badge))"
    }

    static let kokoro = SpeechModelPreset(
        id: "kokoro",
        name: "Kokoro 82M",
        modelID: "mlx-community/Kokoro-82M-bf16",
        badge: "bf16",
        detail: "Fast default voice model",
        systemImage: "brain",
        language: "en-us",
        voicePrompt: nil,
        supportsKokoroVoices: true,
        requiresEspeakTextProcessor: true,
        voiceFamily: .kokoro
    )

    static let qwen3 = SpeechModelPreset(
        id: "qwen3-tts",
        name: "Qwen3-TTS",
        modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit",
        badge: "8-bit",
        detail: "MLX multilingual model",
        systemImage: "waveform",
        language: "English",
        voicePrompt: nil,
        supportsKokoroVoices: false,
        requiresEspeakTextProcessor: false,
        voiceFamily: .qwen
    )

    static let chatterbox = SpeechModelPreset(
        id: "chatterbox",
        name: "Chatterbox Turbo",
        modelID: "mlx-community/chatterbox-turbo-4bit",
        badge: "4-bit",
        detail: "MLX expressive English model",
        systemImage: "quote.bubble",
        language: nil,
        voicePrompt: nil,
        supportsKokoroVoices: false,
        requiresEspeakTextProcessor: false,
        voiceFamily: .chatterbox
    )

    static let all: [SpeechModelPreset] = [
        .kokoro,
        .qwen3,
        .chatterbox,
    ]
}
